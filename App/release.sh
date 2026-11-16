#!/usr/bin/env bash
# İki sürümü derler ve GitHub Release için iki DMG üretir:
#   dist/SpoofDPIPlus-<sürüm>-macOS14-Universal.dmg
#   dist/SpoofDPIPlus-<sürüm>-macOS10.15-Intel.dmg
# DMG penceresi: arka plan görseli, uygulama → Applications oku, cilt ikonu.
# Not: Pencere düzeni Finder'a AppleScript ile verilir; ilk çalıştırmada macOS
# Terminal'in Finder'ı kontrol etmesi için izin isteyebilir.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 1.0.0)"
DIST="$ROOT/dist"
mkdir -p "$DIST"
TOOLS="$(mktemp -d)"; trap 'rm -rf "$TOOLS"' EXIT
swiftc -O "$ROOT/App/Icon/make_dmg_background.swift" -o "$TOOLS/make_bg"

make_dmg() {  # <app> <dmg> <cilt-adı> <arka-plan-alt-başlığı>
  local app="$1" dmg="$2" vol="$3" subtitle="$4"
  local stage rw dev mnt
  stage="$(mktemp -d)"; rw="$TOOLS/rw.dmg"

  # 1) İçerik: uygulama, Applications kısayolu, gizli arka plan ve cilt ikonu
  cp -R "$app" "$stage/"
  ln -s /Applications "$stage/Applications"
  mkdir "$stage/.background"
  "$TOOLS/make_bg" "$TOOLS/bg.png" 1 "$subtitle"
  "$TOOLS/make_bg" "$TOOLS/bg@2x.png" 2 "$subtitle"
  tiffutil -cathidpicheck "$TOOLS/bg.png" "$TOOLS/bg@2x.png" -out "$stage/.background/background.tiff" >/dev/null
  cp "$app/Contents/Resources/AppIcon.icns" "$stage/.VolumeIcon.icns"

  # 2) Yazılabilir imaj oluştur ve bağla
  rm -f "$rw"
  hdiutil create -quiet -volname "$vol" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$rw"
  rm -rf "$stage"
  dev="$(hdiutil attach -readwrite -noverify -noautoopen "$rw" | awk '/Apple_HFS/{print $1}')"
  mnt="/Volumes/$vol"

  # 3) Cilt ikonunu etkinleştir (SetFile varsa)
  if command -v SetFile >/dev/null; then SetFile -a C "$mnt"; fi

  # 4) Finder pencere düzeni
  local app_name; app_name="$(basename "$app")"
  osascript <<EOF || echo "⚠ Finder düzeni uygulanamadı (Otomasyon izni yok). DMG çalışır ama arka plan/ikon yerleşimi olmaz. Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon'dan Terminal'e Finder izni verin." >&2
tell application "Finder"
  tell disk "$vol"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "$app_name" of container window to {170, 200}
    set position of item "Applications" of container window to {470, 200}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
  sync
  hdiutil detach -quiet "$dev" || { sleep 2; hdiutil detach -force -quiet "$dev"; }

  # 5) Sıkıştırılmış, salt okunur DMG
  rm -f "$dmg"
  hdiutil convert -quiet "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg"
  rm -f "$rw"
  echo "✔ $dmg ($(du -h "$dmg" | cut -f1))"
}

"$ROOT/App/build.sh" modern
"$ROOT/App/build.sh" legacy

make_dmg "$ROOT/build/SpoofDPI+.app" "$DIST/SpoofDPIPlus-$VERSION-macOS14-Universal.dmg" \
  "SpoofDPI+ $VERSION" "macOS 14+ · Apple Silicon & Intel"
make_dmg "$ROOT/build/Legacy/SpoofDPI+.app" "$DIST/SpoofDPIPlus-$VERSION-macOS10.15-Intel.dmg" \
  "SpoofDPI+ $VERSION Legacy" "macOS 10.15+ · Intel"
