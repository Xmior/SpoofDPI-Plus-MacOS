// SpoofDPI+ (Legacy) — macOS 10.15+ / Intel için AppKit sürümü.
// SwiftUI, SF Symbols ve Swift Concurrency 10.15'te yok/eksik olduğu için saf AppKit + GCD kullanır.
import AppKit

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Derleme sırasında üretilen buton ikonları (Resources/Symbols/<ad>.png)
func symbol(_ name: String) -> NSImage? {
    guard let path = Bundle.main.path(forResource: name, ofType: "png", inDirectory: "Symbols") else { return nil }
    let img = NSImage(contentsOfFile: path)
    img?.size = NSSize(width: 26, height: 26)
    return img
}

// MARK: - Shell

struct ShellResult {
    let code: Int32
    let out: String
    var lastLine: String {
        let line = out.split(separator: "\n").last.map(String.init) ?? ""
        return line.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }
}

func shell(_ exe: String, _ args: [String]) -> ShellResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return ShellResult(code: -1, out: error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return ShellResult(code: p.terminationStatus, out: String(decoding: data, as: UTF8.self))
}

// MARK: - Model

final class Model {
    var serviceLoaded = false
    var running = false
    var proxyOn = false
    var discordOK: Bool? = nil
    var busy = false
    var message = ""
    var onChange: (() -> Void)?

    let script = Bundle.main.path(forResource: "spoofdpi-plus", ofType: "sh") ?? ""
    let logDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/SpoofDPIPlus")
    static let discordPath = "/Applications/Discord.app"
    let discordIcon: NSImage? = FileManager.default.fileExists(atPath: Model.discordPath)
        ? NSWorkspace.shared.icon(forFile: Model.discordPath) : nil

    private let queue = DispatchQueue(label: "spoofdpi-plus.shell")
    private var timer: Timer?

    init() {
        refresh(testDiscord: true)
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func changed() { onChange?() }

    func refresh(testDiscord: Bool = false) {
        queue.async {
            let loaded = shell("/bin/launchctl", ["print", "gui/\(getuid())/com.spoofdpiplus.agent"]).code == 0
            let port = shell("/usr/bin/nc", ["-z", "127.0.0.1", "8080"]).code == 0
            let proxy = shell("/usr/sbin/scutil", ["--proxy"]).out.contains("HTTPSEnable : 1")
            var discord: Bool? = nil
            if testDiscord && port {
                let code = shell("/usr/bin/curl", ["-s", "-o", "/dev/null", "-m", "8", "-w", "%{http_code}",
                                                   "-x", "http://127.0.0.1:8080", "https://discord.com"]).out
                discord = code.hasPrefix("2") || code.hasPrefix("3")
            }
            DispatchQueue.main.async {
                self.serviceLoaded = loaded
                self.running = port
                self.proxyOn = proxy
                if testDiscord { self.discordOK = port ? discord : false }
                self.changed()
            }
        }
    }

    private func perform(_ label: String, _ work: @escaping () -> ShellResult) {
        busy = true
        message = "\(label)…"
        changed()
        queue.async {
            let r = work()
            DispatchQueue.main.async { self.finish(label, r) }
        }
    }

    private func finish(_ label: String, _ r: ShellResult) {
        busy = false
        message = r.code == 0 ? "\(label): \(L("msg.ok"))" : "\(label): \(L("msg.error")) — \(r.lastLine)"
        changed()
        refresh(testDiscord: true)
    }

    private func adminScript(_ arg: String) -> String {
        "do shell script \"'\(script)' \(arg)\" with administrator privileges"
    }

    func run(_ args: [String], label: String) {
        let s = script
        perform(label) { shell("/bin/bash", [s] + args) }
    }

    func runAdmin(_ arg: String, label: String) {
        let a = adminScript(arg)
        perform(label) { shell("/usr/bin/osascript", ["-e", a]) }
    }

    func install() {
        let s = script, a = adminScript("proxy-on")
        perform(L("act.install")) {
            let r = shell("/bin/bash", [s, "install", "--no-proxy"])
            return r.code == 0 ? shell("/usr/bin/osascript", ["-e", a]) : r
        }
    }

    func uninstall() {
        let s = script, a = adminScript("proxy-off")
        perform(L("act.uninstall")) {
            _ = shell("/usr/bin/osascript", ["-e", a])
            return shell("/bin/bash", [s, "uninstall-service"])
        }
    }

    func logs() -> String {
        let text = ["spoofdpi.log", "spoofdpi.err.log"].compactMap { name -> String? in
            guard let s = try? String(contentsOf: logDir.appendingPathComponent(name), encoding: .utf8) else { return nil }
            return s.split(separator: "\n").suffix(200).joined(separator: "\n")
        }.joined(separator: "\n")
        let clean = text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
        return clean.isEmpty ? L("logs.empty") : clean
    }
}

// MARK: - Küçük yardımcılar

final class ClosureTarget: NSObject {
    let fn: () -> Void
    init(_ fn: @escaping () -> Void) { self.fn = fn }
    @objc func fire() { fn() }
}

/// Hedef nesneleri canlı tutmak için
var closureTargets: [ClosureTarget] = []

func makeButton(_ title: String, image: NSImage?, _ action: @escaping () -> Void) -> NSButton {
    let t = ClosureTarget(action)
    closureTargets.append(t)
    let b = NSButton(title: title, target: t, action: #selector(ClosureTarget.fire))
    b.bezelStyle = .regularSquare
    b.image = image
    b.imagePosition = image == nil ? .noImage : .imageAbove
    b.font = NSFont.systemFont(ofSize: 12, weight: .medium)
    b.translatesAutoresizingMaskIntoConstraints = false
    b.heightAnchor.constraint(equalToConstant: 72).isActive = true
    b.widthAnchor.constraint(equalToConstant: 118).isActive = true
    return b
}

func label(_ text: String, size: CGFloat = 13, bold: Bool = false, secondary: Bool = false) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    if secondary { f.textColor = .secondaryLabelColor }
    return f
}

final class StatusLineView: NSStackView {
    private let dot = NSTextField(labelWithString: "●")
    private let value = label("", secondary: true)
    init(title: String) {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 6
        dot.font = NSFont.systemFont(ofSize: 11)
        addArrangedSubview(dot)
        addArrangedSubview(label(title))
        addArrangedSubview(value)
    }
    required init?(coder: NSCoder) { fatalError() }
    func set(_ on: Bool, _ text: String) {
        dot.textColor = on ? .systemGreen : .systemRed
        value.stringValue = text
    }
}

// MARK: - Ana pencere

final class MainWindowController: NSWindowController {
    let model: Model
    private let lines = (launchd: StatusLineView(title: L("status.launchd")),
                         port: StatusLineView(title: "SpoofDPI 127.0.0.1:8080"),
                         proxy: StatusLineView(title: L("status.proxy")),
                         discord: StatusLineView(title: "discord.com"))
    private var startButton: NSButton!
    private var stopButton: NSButton!
    private var allButtons: [NSButton] = []
    private let spinner = NSProgressIndicator()
    private let messageLabel = label(" ", size: 12, secondary: true)

    init(model: Model) {
        self.model = model
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "SpoofDPI+"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        build()
        w.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func section(_ title: String, _ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.spacing = 10
        let s = NSStackView(views: [label(title, size: 12, bold: true, secondary: true), row])
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 6
        return s
    }

    private func build() {
        let m = model
        // Durum (sol üst)
        let refresh = makeButton("", image: symbol("refresh")) { m.refresh(testDiscord: true) }
        refresh.bezelStyle = .inline
        refresh.isBordered = false
        refresh.constraints.forEach { $0.isActive = false }
        let header = NSStackView(views: [label(L("status.title"), size: 20, bold: true), refresh])
        header.spacing = 8
        let status = NSStackView(views: [header, lines.launchd, lines.port, lines.proxy, lines.discord])
        status.orientation = .vertical
        status.alignment = .leading
        status.spacing = 5

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let top = NSStackView(views: [status, spacer, icon])
        top.alignment = .top

        startButton = makeButton(L("btn.start"), image: symbol("start")) { m.run(["start"], label: L("act.start")) }
        stopButton = makeButton(L("btn.stop"), image: symbol("stop")) { m.run(["stop"], label: L("act.stop")) }
        let restart = makeButton(L("btn.restart"), image: symbol("restart")) { m.run(["restart"], label: L("act.restart")) }
        let install = makeButton(L("btn.install"), image: symbol("install")) { m.install() }
        let uninstall = makeButton(L("btn.uninstall"), image: symbol("uninstall")) { m.uninstall() }
        let pOn = makeButton(L("btn.proxyOn"), image: symbol("proxyOn")) { m.runAdmin("proxy-on", label: L("act.proxyOn")) }
        let pOff = makeButton(L("btn.proxyOff"), image: symbol("proxyOff")) { m.runAdmin("proxy-off", label: L("act.proxyOff")) }
        let discordImg = m.discordIcon.map { img -> NSImage in
            let c = img.copy() as! NSImage; c.size = NSSize(width: 28, height: 28); return c
        } ?? symbol("discord")
        let discord = makeButton(L("btn.discord"), image: discordImg) { m.run(["discord"], label: "Discord") }
        let logs = makeButton(L("btn.logs"), image: symbol("logs")) { [weak self] in self?.showLogs() }
        allButtons = [startButton, stopButton, restart, install, uninstall, pOn, pOff, discord, logs]

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        let msg = NSStackView(views: [spinner, messageLabel])
        msg.spacing = 6

        let bg = makeButton(L("btn.background"), image: nil) { AppDelegate.shared.runInBackground() }
        let quit = makeButton(L("menu.quit"), image: nil) { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = .command
        for b in [bg, quit] {
            b.bezelStyle = .rounded
            b.constraints.forEach { $0.isActive = false }
        }
        bg.toolTip = L("help.background")
        let bottomSpacer = NSView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bottom = NSStackView(views: [bg, bottomSpacer, quit])

        let root = NSStackView(views: [
            top,
            section(L("sec.setup"), [install, uninstall]),
            section(L("sec.service"), [startButton, stopButton, restart]),
            section(L("sec.tools"), [pOn, pOff, discord, logs]),
            msg, bottom,
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)
        root.translatesAutoresizingMaskIntoConstraints = false
        for v in [top, bottom] { v.translatesAutoresizingMaskIntoConstraints = false }

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            top.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -44),
            bottom.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -44),
        ])
        window?.contentView = content
        update()
    }

    func update() {
        let m = model
        lines.launchd.set(m.serviceLoaded, m.serviceLoaded ? L("status.loaded") : L("status.notLoaded"))
        lines.port.set(m.running, m.running ? L("status.listening") : L("status.off"))
        lines.proxy.set(m.proxyOn, m.proxyOn ? L("status.on") : L("status.off"))
        lines.discord.set(m.discordOK ?? false, m.discordOK == true ? L("status.reachable")
                          : (m.discordOK == nil ? L("status.testing") : L("status.unreachable")))

        startButton.title = m.running ? L("btn.running") : L("btn.start")
        startButton.image = symbol(m.running ? "running" : "start")
        allButtons.forEach { $0.isEnabled = !m.busy }
        startButton.isEnabled = !m.busy && !m.running
        stopButton.isEnabled = !m.busy && (m.running || m.serviceLoaded)

        messageLabel.stringValue = m.message.isEmpty ? " " : m.message
        m.busy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    private func showLogs() {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 380))
        tv.isEditable = false
        tv.font = NSFont.userFixedPitchFont(ofSize: 11)
        tv.string = model.logs()
        let sv = NSScrollView(frame: tv.frame)
        sv.hasVerticalScroller = true
        sv.documentView = tv
        let alert = NSAlert()
        alert.messageText = L("logs.title")
        alert.accessoryView = sv
        alert.addButton(withTitle: L("logs.close"))
        alert.addButton(withTitle: L("logs.finder"))
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(model.logDir) }
    }
}

// MARK: - Uygulama

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate!
    let model = Model()
    var window: MainWindowController!
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        buildMainMenu()
        window = MainWindowController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        model.onChange = { [weak self] in self?.update() }
        update()
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    func update() {
        if let btn = statusItem.button {
            let img = Bundle.main.image(forResource: "MenuBarIcon")
            img?.isTemplate = true
            img?.size = NSSize(width: 18, height: 18)
            btn.image = img
            btn.alphaValue = model.running ? 1 : 0.45
        }
        window.update()
    }

    // Menü çubuğu menüsü her açılışta güncel durumla yeniden kurulur
    func menuNeedsUpdate(_ menu: NSMenu) {
        let m = model
        menu.removeAllItems()
        func info(_ on: Bool, _ title: String, _ value: String) {
            let item = NSMenuItem(title: "\(on ? "🟢" : "🔴")  \(title): \(value)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        info(m.serviceLoaded, L("status.launchd"), m.serviceLoaded ? L("status.loaded") : L("status.notLoaded"))
        info(m.running, "SpoofDPI", m.running ? L("status.listening") : L("status.off"))
        info(m.proxyOn, L("status.proxy"), m.proxyOn ? L("status.on") : L("status.off"))
        menu.addItem(.separator())

        func action(_ title: String, _ img: String, enabled: Bool, _ fn: @escaping () -> Void) {
            let t = ClosureTarget(fn); closureTargets.append(t)
            let item = NSMenuItem(title: title, action: enabled ? #selector(ClosureTarget.fire) : nil, keyEquivalent: "")
            item.target = t
            let i = symbol(img); i?.size = NSSize(width: 16, height: 16)
            item.image = i
            menu.addItem(item)
        }
        if m.running {
            action(L("btn.running"), "running", enabled: false) {}
        } else {
            action(L("btn.start"), "start", enabled: !m.busy) { m.run(["start"], label: L("act.start")) }
        }
        action(L("btn.stop"), "stop", enabled: !m.busy && (m.running || m.serviceLoaded)) { m.run(["stop"], label: L("act.stop")) }
        action(L("btn.restart"), "restart", enabled: !m.busy) { m.run(["restart"], label: L("act.restart")) }
        menu.addItem(.separator())
        let proxy = NSMenuItem(title: L("status.proxy"), action: m.busy ? nil : #selector(ClosureTarget.fire), keyEquivalent: "")
        let pt = ClosureTarget { m.runAdmin(m.proxyOn ? "proxy-off" : "proxy-on",
                                            label: m.proxyOn ? L("act.proxyOff") : L("act.proxyOn")) }
        closureTargets.append(pt)
        proxy.target = pt
        proxy.state = m.proxyOn ? .on : .off
        menu.addItem(proxy)
        menu.addItem(.separator())
        action(L("menu.open"), "window", enabled: true) { [weak self] in self?.showWindow() }
        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        window.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func runInBackground() {
        window.close()
        NSApp.setActivationPolicy(.accessory)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
