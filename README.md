<p align="center">
  <img src="AppIcon-1024.png" width="128" alt="SpoofDPI+">
</p>

<h1 align="center">SpoofDPI+ MacOS</h1>

<p align="center">
  <a href="https://github.com/xvzc/SpoofDPI">SpoofDPI</a> için macOS menü çubuğu uygulaması · A macOS menu bar app for <a href="https://github.com/xvzc/SpoofDPI">SpoofDPI</a>
</p>

<p align="center">
  <a href="#türkçe">Türkçe</a> · <a href="#english">English</a> · <a href="../../releases">Releases</a>
</p>

> SpoofDPI+ is not affiliated with the SpoofDPI project. It is an independent app that installs and manages SpoofDPI.
> SpoofDPI+, SpoofDPI projesinin resmi bir parçası değildir; SpoofDPI'ı kuran ve yöneten bağımsız bir uygulamadır.

---

## Türkçe

### Ne işe yarar?

SpoofDPI+, Türkiye'deki DPI (Derin Paket İnceleme) engellerini aşmak için [SpoofDPI](https://github.com/xvzc/SpoofDPI)'ı tek tıkla kurar, bilgisayar açılınca kendiliğinden başlayan bir servis olarak çalıştırır ve menü çubuğundan yönetmenizi sağlar. VPN değildir: trafiğiniz başka bir sunucuya gitmez ve bağlantı hızınız düşmez.

- **Tek tıkla kurulum:** SpoofDPI'ı kurar, `launchd` servisi oluşturur, sistem proxy'sini ayarlar.
- **Durum paneli:** Servis, SpoofDPI portu, sistem proxy'si ve discord.com erişimi 10 saniyede bir kontrol edilir.
- **Düğmeler:** Kur, Kaldır, Başlat, Durdur, Yeniden Başlat, Proxy Aç/Kapat, Discord, Günlükler.
- **Menü çubuğu:** Durum, ikonlu Başlat/Durdur/Yeniden Başlat düğmeleri ve proxy anahtarı. İkon açık/koyu temaya uyar.
- **Arka planda çalışma:** Pencereyi kapatıp Dock'tan gizleyebilirsiniz; uygulama menü çubuğunda çalışmaya devam eder.
- **Discord:** Discord'u doğrudan proxy ile başlatır.
- **Türkçe / İngilizce** arayüz (macOS sistem diline göre).
- **Komut satırı aracı:** `spoofdpi-plus.sh` ile arayüz olmadan da her şey yapılabilir.

**Yapmadıkları:** Discord **sesli kanalları** çalışmayabilir; ses UDP ile gider ve HTTP proxy UDP taşıyamaz. ByeDPI, Zapret, WireGuard/WARP gibi başka yöntemler yoktur. Bunlara ihtiyacınız varsa [Çalışmazsa](#çalışmazsa) bölümüne bakın.

### İndirme

Her sürümde iki DMG yayınlanır. [Releases](../../releases) sayfasından Mac'inize uygun olanı indirin:

| | **SpoofDPI+** (önerilen) | **SpoofDPI+ Legacy** |
|---|---|---|
| Dosya | `SpoofDPIPlus-<sürüm>-macOS14-Universal.dmg` | `SpoofDPIPlus-<sürüm>-macOS10.15-Intel.dmg` |
| macOS | **14 Sonoma** veya üstü | **10.15 Catalina** veya üstü |
| İşlemci | Apple Silicon + Intel | Yalnızca Intel |
| SpoofDPI | Güncel sürüm, Homebrew ile kurulur | 0.12.0, uygulamanın içinde gelir |
| Homebrew | Gerekli ([brew.sh](https://brew.sh)) | Gerekmez |

macOS 13 veya daha eski bir Intel Mac kullanıyorsanız **Legacy** sürümünü indirin. Engeli aşma yöntemi iki sürümde de aynıdır.

> Legacy sürümü henüz gerçek bir macOS 10.15 bilgisayarda denenmedi. Sorun yaşarsanız lütfen bir issue açın.

### Kurulum

1. DMG'yi açın ve `SpoofDPI+.app` dosyasını **Applications** klasörüne sürükleyin.
2. Uygulamayı açın. Uygulama Apple tarafından onaylanmadığı (notarize edilmediği) için macOS uyarı verir:
   - **macOS 14:** Uygulamaya sağ tıklayın → **Aç** → **Aç**.
   - **macOS 15 ve sonrası:** Uygulamayı bir kez açmayı deneyin, uyarıyı kapatın. **Sistem Ayarları → Gizlilik ve Güvenlik** bölümünün altındaki **Yine de Aç** düğmesine basın.
   - Ya da Terminal'de:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/SpoofDPI+.app"
     ```
3. **Kur** düğmesine basın. Sistem proxy'sini ayarlamak için yönetici şifresi istenir.
4. Durum panelindeki dört satırın da yeşil olduğunu kontrol edin.

Uygulamanın her açılışta başlamasını isterseniz **Sistem Ayarları → Genel → Giriş Öğeleri** bölümüne ekleyin. Uygulama kapalıyken de servis çalışmaya devam eder.

### Nasıl çalışır?

```
Uygulama (Discord, tarayıcı...)
        │  HTTP/HTTPS
        ▼
Sistem proxy'si ──► SpoofDPI (127.0.0.1:8080, launchd servisi)
                        │  1. DNS'i DNS-over-HTTPS ile çözer (1.1.1.1)
                        │  2. TLS ClientHello paketini 1 baytlık parçalara böler
                        ▼
                     İnternet
```

Engelleme iki aşamada yapılır:

1. **DNS zehirleme:** ISS'nin DNS sunucusu engelli siteler için sahte bir adres döndürür. SpoofDPI bunun yerine şifreli DNS (DNS-over-HTTPS) kullanır.
2. **SNI filtreleme:** HTTPS bağlantısının ilk paketinde sitenin adı şifresiz yer alır. DPI bu adı görünce bağlantıyı keser. SpoofDPI paketi küçük parçalara böler; DPI adı okuyamaz, sunucu ise parçaları birleştirip normal yanıt verir.

Kurulumun oluşturduğu dosyalar:

| Dosya | Görevi |
|---|---|
| `~/Library/LaunchAgents/com.spoofdpiplus.agent.plist` | Açılışta başlayan servis |
| `~/.config/spoofdpi-plus/config.toml` | SpoofDPI ayarları (Legacy'de yok) |
| `~/Library/Application Support/SpoofDPIPlus/` | Gömülü SpoofDPI (yalnızca Legacy) |
| `~/Library/Logs/SpoofDPIPlus/` | Günlükler |

### Komut satırı

Uygulama olmadan, depodaki script ile de kurabilirsiniz (Homebrew gerekir):

```bash
./spoofdpi-plus.sh install
```

| Komut | Açıklama |
|---|---|
| `install [--no-proxy]` | SpoofDPI'ı kurar, servisi başlatır, sistem proxy'sini açar |
| `uninstall` | Proxy'yi kapatır ve servisi kaldırır |
| `start` / `stop` / `restart` | Servisi yönetir |
| `status` | Servis ve proxy durumunu gösterir, discord.com'a erişimi test eder |
| `proxy-on` / `proxy-off` | Sistem proxy'sini açar veya kapatır |
| `discord` | Discord'u proxy ile başlatır |
| `logs` | Günlükleri canlı izler |

### Sorun giderme

**Site hâlâ açılmıyor.** `~/.config/spoofdpi-plus/config.toml` dosyasındaki `[https]` bölümünü değiştirip **Yeniden Başlat**'a basın. Denenebilecek ayarlar:

```toml
split-mode = "random"
```

```toml
split-mode = "chunk"
chunk-size = 1
disorder = true
```

**İnternet tamamen kesildi.** Servis durmuş ama sistem proxy'si açık kalmış olabilir. **Proxy Kapat** düğmesine basın ya da:

```bash
./spoofdpi-plus.sh proxy-off
```

**Başka bir VPN kullanıyorum.** VPN'ler proxy ayarıyla çakışabilir. Aynı anda yalnızca birini kullanın.

**Eskiden "SplitWire" adıyla kurmuştum.** Uygulamada herhangi bir işlem yaptığınızda (ör. **Yeniden Başlat**) eski servis kendiliğinden yeni ada taşınır, ayarlarınız korunur.

### Çalışmazsa

Daha fazla yöntem sunan (ByeDPI, WARP ile Discord sesi) başka bir macOS uygulamasını deneyebilirsiniz: **[a-mertdincer/SplitWire-Turkey-macOS](https://github.com/a-mertdincer/SplitWire-Turkey-macOS)**. İkisini aynı anda çalıştırmayın; önce SpoofDPI+'da **Kaldır**'a basın.

### Kaldırma

Uygulamada **Kaldır**'a basın ve uygulamayı Çöp Sepeti'ne taşıyın. Geriye kalan dosyaları da silmek için:

```bash
rm -rf ~/.config/spoofdpi-plus ~/Library/Logs/SpoofDPIPlus "$HOME/Library/Application Support/SpoofDPIPlus"
```

SpoofDPI'ı Homebrew'dan da silmek için:

```bash
brew uninstall spoofdpi
```

### Kaynaktan derleme

Gerekenler: macOS 14+ ve Xcode Command Line Tools (`xcode-select --install`). Xcode projesi gerekmez. Legacy sürümü için ayrıca **Go 1.21 veya 1.22** gerekir (Go 1.23+ ile derlenen programlar macOS 11 ister; farklı bir Go için `GO=/yol/go`).

| Komut | Çıktı |
|---|---|
| `./App/build.sh` | `build/SpoofDPI+.app` (macOS 14+, Universal) |
| `./App/build.sh legacy` | `build/Legacy/SpoofDPI+.app` (macOS 10.15+, Intel) |
| `./App/release.sh` | İkisini derler, `dist/` klasörüne iki DMG üretir |

Sürüm numarası `VERSION` dosyasından okunur.

---

## English

### What is it?

SpoofDPI+ installs [SpoofDPI](https://github.com/xvzc/SpoofDPI) with one click, runs it as a background service that starts at login, and lets you control it from the menu bar. It is built to get around DPI (Deep Packet Inspection) blocking in Türkiye. It is not a VPN: your traffic does not go through another server and your connection speed is not affected.

- **One-click setup:** installs SpoofDPI, creates a `launchd` service and sets the system proxy.
- **Status panel:** the service, the SpoofDPI port, the system proxy and access to discord.com are checked every 10 seconds.
- **Buttons:** Install, Uninstall, Start, Stop, Restart, Proxy On/Off, Discord, Logs.
- **Menu bar:** status, icon-only Start/Stop/Restart buttons and a proxy switch. The icon adapts to light and dark mode.
- **Run in background:** close the window and hide the Dock icon; the app keeps running in the menu bar.
- **Discord:** launches Discord directly through the proxy.
- **Turkish / English** interface (follows the macOS system language).
- **Command-line tool:** everything also works without the app through `spoofdpi-plus.sh`.

**What it doesn't do:** Discord **voice channels** may not work; voice uses UDP and an HTTP proxy cannot carry UDP. Other methods such as ByeDPI, Zapret or WireGuard/WARP are not included. If you need them, see [If it doesn't work](#if-it-doesnt-work).

### Download

Every release ships two DMGs. Download the one for your Mac from the [Releases](../../releases) page:

| | **SpoofDPI+** (recommended) | **SpoofDPI+ Legacy** |
|---|---|---|
| File | `SpoofDPIPlus-<version>-macOS14-Universal.dmg` | `SpoofDPIPlus-<version>-macOS10.15-Intel.dmg` |
| macOS | **14 Sonoma** or later | **10.15 Catalina** or later |
| CPU | Apple Silicon + Intel | Intel only |
| SpoofDPI | Latest version, installed with Homebrew | 0.12.0, bundled in the app |
| Homebrew | Required ([brew.sh](https://brew.sh)) | Not needed |

If you have an Intel Mac on macOS 13 or older, download **Legacy**. Both versions use the same bypass method.

> The Legacy version has not been tested on a real macOS 10.15 machine yet. If you run into problems, please open an issue.

### Installation

1. Open the DMG and drag `SpoofDPI+.app` into **Applications**.
2. Open the app. Because it is not notarized by Apple, macOS will show a warning:
   - **macOS 14:** right-click the app → **Open** → **Open**.
   - **macOS 15 and later:** try to open the app once and dismiss the warning, then click **Open Anyway** under **System Settings → Privacy & Security**.
   - Or in Terminal:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/SpoofDPI+.app"
     ```
3. Click **Install**. Your administrator password is required to set the system proxy.
4. Check that all four lines in the status panel are green.

To start the app at login, add it under **System Settings → General → Login Items**. The service keeps running even when the app is closed.

### How it works

```
App (Discord, browser...)
        │  HTTP/HTTPS
        ▼
System proxy ──► SpoofDPI (127.0.0.1:8080, launchd service)
                     │  1. Resolves DNS over HTTPS (1.1.1.1)
                     │  2. Splits the TLS ClientHello into 1-byte chunks
                     ▼
                  Internet
```

Blocking happens in two steps:

1. **DNS poisoning:** the ISP's DNS server returns a fake address for blocked sites. SpoofDPI uses encrypted DNS (DNS over HTTPS) instead.
2. **SNI filtering:** the first packet of an HTTPS connection contains the site name in plain text. When the DPI sees it, it resets the connection. SpoofDPI splits that packet into small pieces so the DPI can't read the name, while the server reassembles them and answers normally.

Files created by the installation:

| File | Purpose |
|---|---|
| `~/Library/LaunchAgents/com.spoofdpiplus.agent.plist` | Service that starts at login |
| `~/.config/spoofdpi-plus/config.toml` | SpoofDPI settings (not used by Legacy) |
| `~/Library/Application Support/SpoofDPIPlus/` | Bundled SpoofDPI (Legacy only) |
| `~/Library/Logs/SpoofDPIPlus/` | Logs |

### Command line

You can also install without the app, using the script in this repository (requires Homebrew):

```bash
./spoofdpi-plus.sh install
```

| Command | Description |
|---|---|
| `install [--no-proxy]` | Installs SpoofDPI, starts the service, turns on the system proxy |
| `uninstall` | Turns off the proxy and removes the service |
| `start` / `stop` / `restart` | Controls the service |
| `status` | Shows service and proxy status, tests access to discord.com |
| `proxy-on` / `proxy-off` | Turns the system proxy on or off |
| `discord` | Launches Discord through the proxy |
| `logs` | Follows the logs |

### Troubleshooting

**A site still doesn't open.** Change the `[https]` section in `~/.config/spoofdpi-plus/config.toml` and click **Restart**. Settings to try:

```toml
split-mode = "random"
```

```toml
split-mode = "chunk"
chunk-size = 1
disorder = true
```

**The internet stopped working completely.** The service may have stopped while the system proxy is still on. Click **Proxy Off**, or run:

```bash
./spoofdpi-plus.sh proxy-off
```

**I'm using another VPN.** VPNs can conflict with the proxy setting. Use only one at a time.

**I installed it earlier under the name "SplitWire".** The first action you take in the app (e.g. **Restart**) moves the old service over automatically and keeps your settings.

### If it doesn't work

You can try another macOS app that offers more methods (ByeDPI, Discord voice via WARP): **[a-mertdincer/SplitWire-Turkey-macOS](https://github.com/a-mertdincer/SplitWire-Turkey-macOS)**. Don't run both at the same time; click **Uninstall** in SpoofDPI+ first.

### Uninstalling

Click **Uninstall** in the app and move the app to the Trash. To remove the remaining files:

```bash
rm -rf ~/.config/spoofdpi-plus ~/Library/Logs/SpoofDPIPlus "$HOME/Library/Application Support/SpoofDPIPlus"
```

To also remove SpoofDPI from Homebrew:

```bash
brew uninstall spoofdpi
```

### Building from source

Requirements: macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`). No Xcode project is needed. The Legacy build also needs **Go 1.21 or 1.22** (programs built with Go 1.23+ require macOS 11; use `GO=/path/to/go` to pick another Go).

| Command | Output |
|---|---|
| `./App/build.sh` | `build/SpoofDPI+.app` (macOS 14+, Universal) |
| `./App/build.sh legacy` | `build/Legacy/SpoofDPI+.app` (macOS 10.15+, Intel) |
| `./App/release.sh` | Builds both and creates two DMGs in `dist/` |

The version number is read from the `VERSION` file.

---

## Proje yapısı · Project layout

```
spoofdpi-plus.sh                 Komut satırı aracı / CLI tool (used by the app too)
App/SpoofDPIPlusApp.swift        SwiftUI uygulaması / app (macOS 14+)
App/build.sh                     Derleme / build (modern | legacy)
App/release.sh                   İki DMG / both DMGs
App/Icon/                        İkon araçları / icon tools
App/Resources/{tr,en}.lproj      Türkçe / English strings
Legacy/SpoofDPIPlusLegacy.swift  AppKit uygulaması / app (macOS 10.15+)
Legacy/build-spoofdpi.sh         SpoofDPI 0.12.0 derleme / build
Legacy/make_symbols.swift        SF Symbols → PNG
AppIcon-1024.png                 Uygulama ikonu / app icon
VERSION                          Sürüm / version
```

## Teşekkürler · Credits

- [xvzc/SpoofDPI](https://github.com/xvzc/SpoofDPI): DPI aşımını yapan asıl araç · the tool that does the actual bypass
- [cagritaskn/SplitWire-Turkey](https://github.com/cagritaskn/SplitWire-Turkey): İlham kaynağı olan Windows projesi · the Windows project that inspired this one
- [a-mertdincer/SplitWire-Turkey-macOS](https://github.com/a-mertdincer/SplitWire-Turkey-macOS): Başka bir macOS uygulaması · another macOS app

## Uyarı · Disclaimer

Bu araç bilgiye erişim özgürlüğü amacıyla sunulmaktadır; kullanımından doğan sorumluluk kullanıcıya aittir.
This tool is provided for free access to information. You are responsible for how you use it.
