#!/usr/bin/env bash
# SpoofDPI+ — SpoofDPI için macOS servis ve proxy yöneticisi.
# SpoofDPI'ı arka planda (launchd) çalıştırır ve sistem proxy'sini ona yönlendirir.
# Kullanım: ./spoofdpi-plus.sh {install|uninstall|start|stop|restart|status|proxy-on|proxy-off|discord|logs}
set -euo pipefail

LABEL="com.spoofdpiplus.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONF_DIR="$HOME/.config/spoofdpi-plus"
CONF="$CONF_DIR/config.toml"
LOG_DIR="$HOME/Library/Logs/SpoofDPIPlus"
HOST="127.0.0.1"
PORT="${SPOOFDPI_PLUS_PORT:-8080}"
BYPASS="localhost 127.0.0.1 *.local 169.254/16 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"
GUI_DOMAIN="gui/$(id -u)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPPORT_DIR="$HOME/Library/Application Support/SpoofDPIPlus"

# Eski sürüm (macOS 10.15+, Intel): script'in yanında gömülü "spoofdpi-legacy" varsa
# Homebrew yerine o kullanılır. Bu SpoofDPI v0.12 sürümüdür; TOML yerine parametre alır.
LEGACY_SRC="$SCRIPT_DIR/spoofdpi-legacy"
LEGACY_BIN="$SUPPORT_DIR/spoofdpi-legacy"
is_legacy() { [[ -x "$LEGACY_SRC" || -x "$LEGACY_BIN" && ! -f "$CONF" ]]; }

c_ok()  { printf '\033[32m✔\033[0m %s\n' "$*"; }
c_inf() { printf '\033[36m➜\033[0m %s\n' "$*"; }
c_err() { printf '\033[31m✖\033[0m %s\n' "$*" >&2; }

[[ "$(uname)" == "Darwin" ]] || { c_err "Bu script yalnızca macOS içindir."; exit 1; }

# Eski "SplitWire" adıyla yapılmış kurulumu yeni ada taşır (servis, ayar dosyası).
migrate_old_install() {
  local old_label="com.splitwire.spoofdpi"
  local old_plist="$HOME/Library/LaunchAgents/$old_label.plist"
  [[ -f "$old_plist" ]] || return 0
  c_inf "Eski SplitWire kurulumu SpoofDPI+'ya taşınıyor..."
  launchctl bootout "$GUI_DOMAIN/$old_label" 2>/dev/null || true
  for _ in {1..20}; do launchctl print "$GUI_DOMAIN/$old_label" >/dev/null 2>&1 || break; sleep 0.25; done
  rm -f "$old_plist"
  if [[ -f "$HOME/.config/splitwire/config.toml" && ! -f "$CONF" ]]; then
    mkdir -p "$CONF_DIR"; mv "$HOME/.config/splitwire/config.toml" "$CONF"
    rmdir "$HOME/.config/splitwire" 2>/dev/null || true
  fi
  rm -rf "$HOME/Library/Logs/SplitWire" "$HOME/Library/Application Support/SplitWire"
  mkdir -p "$LOG_DIR"
  write_plist
  launchctl enable "$GUI_DOMAIN/$LABEL"
  launchctl bootstrap "$GUI_DOMAIN" "$PLIST"
  wait_port || true
}

find_spoofdpi() {
  if is_legacy; then [[ -x "$LEGACY_BIN" ]] && { echo "$LEGACY_BIN"; return; }; return 1; fi
  command -v spoofdpi 2>/dev/null && return
  for p in /opt/homebrew/bin/spoofdpi /usr/local/bin/spoofdpi; do
    [[ -x "$p" ]] && { echo "$p"; return; }
  done
  return 1
}

# Aktif (devre dışı olmayan) ağ servisleri: Wi-Fi, Ethernet, USB LAN...
network_services() {
  networksetup -listallnetworkservices | tail -n +2 | grep -v '^\*' || true
}

ensure_spoofdpi() {
  if [[ -x "$LEGACY_SRC" ]]; then
    mkdir -p "$SUPPORT_DIR"
    cp -f "$LEGACY_SRC" "$LEGACY_BIN"; chmod +x "$LEGACY_BIN"
    xattr -d com.apple.quarantine "$LEGACY_BIN" 2>/dev/null || true
    c_ok "Gömülü SpoofDPI kopyalandı: $LEGACY_BIN"
    return
  fi
  if find_spoofdpi >/dev/null; then return; fi
  command -v brew >/dev/null || { c_err "Homebrew bulunamadı. https://brew.sh adresinden kurun ve tekrar deneyin."; exit 1; }
  c_inf "SpoofDPI Homebrew ile kuruluyor..."
  brew install spoofdpi
}

write_config() {
  mkdir -p "$CONF_DIR" "$LOG_DIR"
  is_legacy && return 0   # eski sürüm ayarları parametre olarak alır (bkz. write_plist)
  [[ -f "$CONF" ]] && { c_inf "Mevcut ayar dosyası korunuyor: $CONF"; return; }
  cat >"$CONF" <<EOF
# SpoofDPI+ / SpoofDPI ayarları. Değişiklikten sonra: ./spoofdpi-plus.sh restart
[app]
mode = "http"
listen-addr = "$HOST:$PORT"
no-tui = true

[dns]
# ISS DNS zehirlemesini aşmak için DNS-over-HTTPS
mode = "https"
https-url = "https://1.1.1.1/dns-query"

[https]
# Türk Telekom'da "sni" yetmiyor; chunk-size=1 çalışıyor. Alternatif: split-mode = "random"
split-mode = "chunk"
chunk-size = 1
EOF
  c_ok "Ayar dosyası oluşturuldu: $CONF"
}

write_plist() {
  local bin args; bin="$(find_spoofdpi)"
  if is_legacy; then
    args=""
    for a in -addr "$HOST" -port "$PORT" -enable-doh -dns-addr 1.1.1.1 -window-size 1 -silent -system-proxy=false; do
      args+="    <string>$a</string>"$'\n'
    done
  else
    args="    <string>--config</string><string>$CONF</string>"$'\n'
  fi
  mkdir -p "$(dirname "$PLIST")"
  cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$bin</string>
$args  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>$LOG_DIR/spoofdpi.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/spoofdpi.err.log</string>
</dict>
</plist>
EOF
  plutil -lint "$PLIST" >/dev/null
  c_ok "launchd servisi yazıldı: $PLIST"
}

is_loaded() { launchctl print "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1; }

wait_port() {
  for _ in {1..20}; do nc -z "$HOST" "$PORT" 2>/dev/null && break; sleep 0.5; done
  if nc -z "$HOST" "$PORT" 2>/dev/null; then c_ok "SpoofDPI çalışıyor ($HOST:$PORT)"
  else c_err "SpoofDPI port $PORT'ta yanıt vermiyor. Günlük: $LOG_DIR/spoofdpi.err.log"; return 1; fi
}

# Servis zaten yüklüyse yeniden yüklemez (bootout asenkron olduğu için
# hemen ardından bootstrap "Input/output error" verip servisi kapalı bırakıyordu).
svc_start() {
  [[ -f "$PLIST" ]] || { c_err "Servis kurulu değil. Önce: $0 install"; return 1; }
  if is_loaded; then
    nc -z "$HOST" "$PORT" 2>/dev/null || launchctl kickstart "$GUI_DOMAIN/$LABEL"
  else
    launchctl enable "$GUI_DOMAIN/$LABEL"
    launchctl bootstrap "$GUI_DOMAIN" "$PLIST"
  fi
  wait_port
}

svc_restart() {
  if is_loaded; then launchctl kickstart -k "$GUI_DOMAIN/$LABEL"; wait_port
  else svc_start; fi
}

svc_stop() {
  if ! is_loaded; then c_inf "Servis zaten çalışmıyor"; return 0; fi
  launchctl bootout "$GUI_DOMAIN/$LABEL" 2>/dev/null || true
  for _ in {1..20}; do is_loaded || break; sleep 0.25; done
  c_ok "SpoofDPI durduruldu"
}

proxy_on() {
  c_inf "Sistem proxy'si ayarlanıyor (yönetici şifresi istenebilir)..."
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    sudo networksetup -setwebproxy "$svc" "$HOST" "$PORT" off
    sudo networksetup -setsecurewebproxy "$svc" "$HOST" "$PORT" off
    # shellcheck disable=SC2086
    sudo networksetup -setproxybypassdomains "$svc" $BYPASS
    c_ok "Proxy açık: $svc"
  done < <(network_services)
}

proxy_off() {
  c_inf "Sistem proxy'si kapatılıyor (yönetici şifresi istenebilir)..."
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    sudo networksetup -setwebproxystate "$svc" off
    sudo networksetup -setsecurewebproxystate "$svc" off
    c_ok "Proxy kapalı: $svc"
  done < <(network_services)
}

status() {
  if launchctl print "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1; then c_ok "launchd servisi yüklü"; else c_err "launchd servisi yüklü değil"; fi
  if nc -z "$HOST" "$PORT" 2>/dev/null; then c_ok "SpoofDPI dinliyor: $HOST:$PORT"; else c_err "SpoofDPI dinlemiyor"; fi
  while IFS= read -r svc; do
    [[ -z "$svc" ]] && continue
    local st; st="$(networksetup -getsecurewebproxy "$svc" | awk -F': ' '/^Enabled/{print $2}')"
    printf '   %-28s HTTPS proxy: %s\n' "$svc" "$st"
  done < <(network_services)
  if command -v curl >/dev/null && nc -z "$HOST" "$PORT" 2>/dev/null; then
    local code; code="$(curl -s -o /dev/null -m 8 -w '%{http_code}' -x "http://$HOST:$PORT" https://discord.com || true)"
    [[ "$code" =~ ^[23] ]] && c_ok "discord.com proxy üzerinden erişilebilir (HTTP $code)" || c_err "discord.com testi başarısız (HTTP ${code:-000})"
  fi
}

# Discord'u proxy argümanıyla başlatır (sistem proxy'si kapalıyken de çalışır)
discord() {
  local app="/Applications/Discord.app/Contents/MacOS/Discord"
  [[ -x "$app" ]] || { c_err "Discord bulunamadı: $app"; exit 1; }
  pkill -x Discord 2>/dev/null && sleep 2 || true
  nohup "$app" --proxy-server="http://$HOST:$PORT" >/dev/null 2>&1 &
  c_ok "Discord proxy ile başlatıldı"
}

[[ -n "${1:-}" ]] && migrate_old_install

case "${1:-}" in
  install)
    ensure_spoofdpi; write_config; write_plist; svc_start
    if [[ "${2:-}" != "--no-proxy" ]]; then proxy_on; fi
    c_ok "Kurulum tamamlandı. Durum için: $0 status" ;;
  uninstall)
    proxy_off; svc_stop; rm -f "$PLIST"
    c_ok "Servis kaldırıldı. (Ayarlar: $CONF — SpoofDPI'ı silmek için: brew uninstall spoofdpi)" ;;
  uninstall-service) svc_stop; rm -f "$PLIST"; c_ok "Servis kaldırıldı" ;;
  start)     svc_start ;;
  stop)      svc_stop ;;
  restart)   svc_restart ;;
  status)    status ;;
  proxy-on)  proxy_on ;;
  proxy-off) proxy_off ;;
  discord)   discord ;;
  logs)      tail -n 50 -f "$LOG_DIR"/spoofdpi*.log ;;
  *)
    cat <<EOF
SpoofDPI+
Kullanım: $0 <komut>

  install [--no-proxy]  SpoofDPI kur, açılışta otomatik başlat, sistem proxy'sini aç
  uninstall             Proxy'yi kapat ve servisi kaldır
  start | stop | restart
  status                Servis/proxy durumu ve discord.com testi
  proxy-on | proxy-off  Sistem proxy'sini aç/kapat (servise dokunmaz)
  discord               Discord'u doğrudan proxy ile başlat
  logs                  Günlükleri izle
EOF
    exit 1 ;;
esac
