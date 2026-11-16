#!/usr/bin/env bash
# SpoofDPI+ uygulamasını derler.
#   ./App/build.sh          → build/SpoofDPI+.app          (macOS 14+, Universal: Apple Silicon + Intel)
#   ./App/build.sh legacy   → build/Legacy/SpoofDPI+.app   (macOS 10.15+, Intel, SpoofDPI gömülü)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${1:-modern}"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 1.0.0)"

case "$VARIANT" in
  modern) APP="$ROOT/build/SpoofDPI+.app"; MIN_OS="14.0" ;;
  legacy) APP="$ROOT/build/Legacy/SpoofDPI+.app"; MIN_OS="10.15" ;;
  *) echo "Kullanım: $0 [modern|legacy]" >&2; exit 1 ;;
esac

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
RES="$APP/Contents/Resources"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- Uygulama ikili dosyası ---
if [[ "$VARIANT" == modern ]]; then
  for arch in arm64 x86_64; do
    swiftc -O -parse-as-library -target "$arch-apple-macos14" \
      "$ROOT/App/SpoofDPIPlusApp.swift" -o "$TMP/SpoofDPIPlus-$arch"
  done
  lipo -create "$TMP/SpoofDPIPlus-arm64" "$TMP/SpoofDPIPlus-x86_64" -output "$APP/Contents/MacOS/SpoofDPIPlus"
else
  swiftc -O -target x86_64-apple-macos10.15 \
    "$ROOT/Legacy/SpoofDPIPlusLegacy.swift" -o "$APP/Contents/MacOS/SpoofDPIPlus"

  # Buton ikonları (10.15'te SF Symbols yok → PNG)
  swiftc -O "$ROOT/Legacy/make_symbols.swift" -o "$TMP/make_symbols"
  "$TMP/make_symbols" "$RES/Symbols"

  # Gömülü SpoofDPI v0.12.0 (Go 1.21/1.22 ile derlenir; Go 1.23+ macOS 11 ister)
  "$ROOT/Legacy/build-spoofdpi.sh" "$RES/spoofdpi-legacy"
fi

# --- Uygulama ikonu: Apple ızgarasına oturt, .icns üret ---
SET="$TMP/AppIcon.iconset"; mkdir "$SET"
swiftc -O "$ROOT/App/Icon/make_icon.swift" -o "$TMP/make_icon"
"$TMP/make_icon" "$ROOT/AppIcon-1024.png" "$TMP/base.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/base.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/base.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$RES/AppIcon.icns"

# --- Menü çubuğu template ikonu (18pt @1x/@2x) ---
swiftc -O "$ROOT/App/Icon/make_menubar.swift" -o "$TMP/make_menubar"
"$TMP/make_menubar" "$ROOT/App/Icon/menubar-source.png" "$RES/MenuBarIcon.png" 18
"$TMP/make_menubar" "$ROOT/App/Icon/menubar-source.png" "$RES/MenuBarIcon@2x.png" 36

# --- Yerelleştirme ve script ---
cp -R "$ROOT/App/Resources/"*.lproj "$RES/"
cp "$ROOT/spoofdpi-plus.sh" "$RES/spoofdpi-plus.sh"
chmod +x "$RES/spoofdpi-plus.sh"

cat >"$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SpoofDPI+</string>
  <key>CFBundleDisplayName</key><string>SpoofDPI+</string>
  <key>CFBundleIdentifier</key><string>com.spoofdpiplus.app</string>
  <key>CFBundleExecutable</key><string>SpoofDPIPlus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDevelopmentRegion</key><string>tr</string>
  <key>CFBundleLocalizations</key><array><string>tr</string><string>en</string></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
EOF

[[ -f "$RES/spoofdpi-legacy" ]] && codesign --force -s - "$RES/spoofdpi-legacy"
codesign --force -s - "$APP"
echo "Hazır ($VARIANT, macOS $MIN_OS+, $(lipo -archs "$APP/Contents/MacOS/SpoofDPIPlus")): $APP"
