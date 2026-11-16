import SwiftUI
import AppKit

/// Yerelleştirilmiş metin (Resources/{tr,en}.lproj/Localizable.strings)
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

@main
struct SpoofDPIPlusApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        Window("SpoofDPI+", id: "main") {
            MainView().environmentObject(model)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuPanel().environmentObject(model)
        } label: {
            MenuBarIcon(running: model.running)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menü çubuğu ikonu: template görsel, rengi macOS ayarlar.
struct MenuBarIcon: View {
    let running: Bool
    private static let image: NSImage? = {
        guard let img = Bundle.main.image(forResource: "MenuBarIcon") else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()
    var body: some View {
        if let img = Self.image {
            Image(nsImage: img).opacity(running ? 1 : 0.45)
        } else {
            Image(systemName: running ? "shield.lefthalf.filled" : "shield.slash")
        }
    }
}

// MARK: - Model

@MainActor
final class Model: ObservableObject {
    @Published var serviceLoaded = false
    @Published var running = false
    @Published var proxyOn = false
    @Published var discordOK: Bool? = nil
    @Published var busy = false
    @Published var message = ""
    @Published var logText = ""

    static let discordPath = "/Applications/Discord.app"
    let discordIcon: NSImage? = FileManager.default.fileExists(atPath: Model.discordPath)
        ? NSWorkspace.shared.icon(forFile: Model.discordPath) : nil

    private let script = Bundle.main.path(forResource: "spoofdpi-plus", ofType: "sh") ?? ""
    private let label = "com.spoofdpiplus.agent"
    let logDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SpoofDPIPlus")
    private var timer: Timer?

    init() {
        refresh(testDiscord: true)
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(testDiscord: Bool = false) {
        let label = self.label
        Task.detached {
            let loaded = Shell.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]).code == 0
            let port = Shell.run("/usr/bin/nc", ["-z", "127.0.0.1", "8080"]).code == 0
            let proxy = Shell.run("/usr/sbin/scutil", ["--proxy"]).out.contains("HTTPSEnable : 1")
            let discord: Bool?
            if testDiscord && port {
                let code = Shell.run("/usr/bin/curl", ["-s", "-o", "/dev/null", "-m", "8", "-w", "%{http_code}",
                                                       "-x", "http://127.0.0.1:8080", "https://discord.com"]).out
                discord = code.hasPrefix("2") || code.hasPrefix("3")
            } else { discord = nil }
            await MainActor.run {
                self.serviceLoaded = loaded
                self.running = port
                self.proxyOn = proxy
                if testDiscord { self.discordOK = port ? discord : false }
            }
        }
    }

    /// Kullanıcı olarak çalışır (brew, launchctl).
    func run(_ args: [String], label: String) { perform(label) { Shell.run("/bin/bash", [self.script] + args) } }

    /// Yönetici yetkisiyle çalışır (networksetup). macOS şifre penceresi açar.
    func runAdmin(_ arg: String, label: String) {
        let apple = "do shell script \"'\(script)' \(arg)\" with administrator privileges"
        perform(label) { Shell.run("/usr/bin/osascript", ["-e", apple]) }
    }

    private func finish(_ label: String, _ r: Shell.Result) {
        busy = false
        message = r.code == 0 ? "\(label): \(L("msg.ok"))" : "\(label): \(L("msg.error")) — \(r.lastLine)"
        refresh(testDiscord: true)
    }

    private func perform(_ label: String, _ work: @escaping @Sendable () -> Shell.Result) {
        busy = true
        message = "\(label)…"
        Task.detached {
            let r = work()
            await MainActor.run { self.finish(label, r) }
        }
    }

    func install() {
        busy = true
        message = L("msg.installing")
        Task.detached {
            let r = Shell.run("/bin/bash", [self.script, "install", "--no-proxy"])
            await MainActor.run {
                if r.code == 0 { self.busy = false; self.runAdmin("proxy-on", label: L("act.install")) }
                else { self.finish(L("act.install"), r) }
            }
        }
    }

    func uninstall() {
        busy = true
        message = L("msg.uninstalling")
        let apple = "do shell script \"'\(script)' proxy-off\" with administrator privileges"
        Task.detached {
            _ = Shell.run("/usr/bin/osascript", ["-e", apple])
            let r = Shell.run("/bin/bash", [self.script, "uninstall-service"])
            await MainActor.run { self.finish(L("act.uninstall"), r) }
        }
    }

    func loadLogs() {
        let dir = logDir
        Task.detached {
            let text = ["spoofdpi.log", "spoofdpi.err.log"].compactMap { name -> String? in
                guard let s = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { return nil }
                return s.split(separator: "\n").suffix(200).joined(separator: "\n")
            }.joined(separator: "\n")
            let clean = text.replacingOccurrences(of: #"\u{1B}\[[0-9;]*m"#, with: "", options: .regularExpression)
            await MainActor.run { self.logText = clean.isEmpty ? L("logs.empty") : clean }
        }
    }
}

// MARK: - Ana pencere

struct MainView: View {
    @EnvironmentObject var m: Model
    @State private var showLogs = false

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                StatusPanel()
                Spacer()
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 64, height: 64)
                }
            }

            Block(L("sec.setup")) {
                LazyVGrid(columns: cols, spacing: 12) {
                    ActionButton(title: L("btn.install"), icon: .symbol("square.and.arrow.down"), tint: .green) { m.install() }
                    ActionButton(title: L("btn.uninstall"), icon: .symbol("trash"), tint: .red) { m.uninstall() }
                }
            }

            Block(L("sec.service")) {
                LazyVGrid(columns: cols, spacing: 12) {
                    if m.running {
                        ActionButton(title: L("btn.running"), icon: .symbol("checkmark.circle.fill"), tint: .green) {}
                            .disabled(true)
                    } else {
                        ActionButton(title: L("btn.start"), icon: .symbol("play.fill"), tint: .green) {
                            m.run(["start"], label: L("act.start"))
                        }
                    }
                    ActionButton(title: L("btn.stop"), icon: .symbol("stop.fill"), tint: .red) { m.run(["stop"], label: L("act.stop")) }
                        .disabled(!m.running && !m.serviceLoaded)
                    ActionButton(title: L("btn.restart"), icon: .symbol("arrow.clockwise"), tint: .orange) { m.run(["restart"], label: L("act.restart")) }
                }
            }

            Block(L("sec.tools")) {
                LazyVGrid(columns: cols, spacing: 12) {
                    ActionButton(title: L("btn.proxyOn"), icon: .symbol("network"), tint: .blue) { m.runAdmin("proxy-on", label: L("act.proxyOn")) }
                    ActionButton(title: L("btn.proxyOff"), icon: .symbol("network.slash"), tint: .gray) { m.runAdmin("proxy-off", label: L("act.proxyOff")) }
                    ActionButton(title: L("btn.discord"),
                                 icon: m.discordIcon.map { .image($0) } ?? .symbol("bubble.left.and.bubble.right.fill"),
                                 tint: .indigo) { m.run(["discord"], label: "Discord") }
                    ActionButton(title: L("btn.logs"), icon: .symbol("doc.text.magnifyingglass"), tint: .teal) { m.loadLogs(); showLogs = true }
                }
            }

            HStack(spacing: 8) {
                if m.busy { ProgressView().controlSize(.small) }
                Text(m.message.isEmpty ? " " : m.message)
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }

            Divider()

            HStack {
                Button { AppWindow.runInBackground() } label: {
                    Label(L("btn.background"), systemImage: "menubar.arrow.up.rectangle")
                }
                .help(L("help.background"))
                Spacer()
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    Label(L("menu.quit"), systemImage: "power")
                }
                .keyboardShortcut("q")
            }
        }
        .disabled(m.busy)
        .padding(22)
        .frame(width: 540)
        .sheet(isPresented: $showLogs) { LogsView().environmentObject(m) }
    }
}

struct Block<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

struct StatusPanel: View {
    @EnvironmentObject var m: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L("status.title")).font(.title2.bold())
                Button { m.refresh(testDiscord: true) } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.borderless).help(L("status.refresh"))
            }
            StatusLine(title: L("status.launchd"), on: m.serviceLoaded, onText: L("status.loaded"), offText: L("status.notLoaded"))
            StatusLine(title: "SpoofDPI 127.0.0.1:8080", on: m.running, onText: L("status.listening"), offText: L("status.off"))
            StatusLine(title: L("status.proxy"), on: m.proxyOn, onText: L("status.on"), offText: L("status.off"))
            StatusLine(title: "discord.com", on: m.discordOK ?? false, onText: L("status.reachable"),
                       offText: m.discordOK == nil ? L("status.testing") : L("status.unreachable"))
        }
    }
}

struct StatusLine: View {
    let title: String
    let on: Bool
    let onText: String
    let offText: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(on ? Color.green : Color.red).frame(width: 9, height: 9)
            Text(title)
            Text(on ? onText : offText).foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

enum ButtonIcon {
    case symbol(String)
    case image(NSImage)
}

struct ActionButton: View {
    let title: String
    let icon: ButtonIcon
    let tint: Color
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    switch icon {
                    case .symbol(let name):
                        Image(systemName: name).font(.system(size: 22, weight: .medium)).foregroundStyle(tint)
                    case .image(let img):
                        Image(nsImage: img).resizable().interpolation(.high).frame(width: 30, height: 30)
                    }
                }
                .frame(height: 30)
                Text(title).font(.callout.weight(.medium)).multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(hover && enabled ? 0.10 : 0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct LogsView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("logs.title")).font(.headline)
                Spacer()
                Button(L("logs.reload")) { m.loadLogs() }
                Button(L("logs.finder")) { NSWorkspace.shared.open(m.logDir) }
                Button(L("logs.close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(m.logText).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .padding(16)
        .frame(width: 720, height: 420)
    }
}

// MARK: - Menü çubuğu

struct MenuPanel: View {
    @EnvironmentObject var m: Model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusPanel()
            Divider()
            HStack(spacing: 6) {
                if m.running {
                    MenuIconButton(icon: "checkmark.circle.fill", tint: .green, help: L("btn.running")) {}
                        .disabled(true)
                } else {
                    MenuIconButton(icon: "play.fill", tint: .green, help: L("btn.start")) {
                        m.run(["start"], label: L("act.start"))
                    }
                }
                MenuIconButton(icon: "stop.fill", tint: .red, help: L("btn.stop")) {
                    m.run(["stop"], label: L("act.stop"))
                }
                .disabled(!m.running && !m.serviceLoaded)
                MenuIconButton(icon: "arrow.clockwise", tint: .orange, help: L("btn.restart")) {
                    m.run(["restart"], label: L("act.restart"))
                }
                Spacer()
                Image(systemName: m.proxyOn ? "network" : "network.slash")
                    .foregroundStyle(m.proxyOn ? .blue : .secondary)
                    .help(L("status.proxy"))
                Toggle("", isOn: Binding(
                    get: { m.proxyOn },
                    set: { m.runAdmin($0 ? "proxy-on" : "proxy-off", label: $0 ? L("act.proxyOn") : L("act.proxyOff")) }
                ))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
                .help(L("status.proxy"))
            }
            .disabled(m.busy)
            if m.busy || !m.message.isEmpty {
                HStack(spacing: 6) {
                    if m.busy { ProgressView().controlSize(.mini) }
                    Text(m.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Divider()
            HStack {
                Button(L("menu.open")) { AppWindow.show { openWindow(id: "main") } }
                Spacer()
                Button(L("menu.quit")) { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// Dock görünürlüğü: arka planda yalnızca menü çubuğu ikonu kalır.
@MainActor
enum AppWindow {
    static func runInBackground() {
        NSApp.windows.filter { $0.identifier?.rawValue == "main" || $0.title == "SpoofDPI+" }.forEach { $0.close() }
        NSApp.setActivationPolicy(.accessory)
    }

    static func show(_ open: () -> Void) {
        NSApp.setActivationPolicy(.regular)
        open()
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuIconButton: View {
    let icon: String
    let tint: Color
    let help: String
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint.opacity(enabled ? 1 : 0.6))
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hover && enabled ? 0.12 : 0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Shell

enum Shell {
    struct Result: Sendable {
        let code: Int32
        let out: String
        var lastLine: String {
            out.split(separator: "\n").last.map(String.init)?
                .replacingOccurrences(of: #"\u{1B}\[[0-9;]*m"#, with: "", options: .regularExpression) ?? ""
        }
    }

    static func run(_ exe: String, _ args: [String]) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return Result(code: -1, out: error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(code: p.terminationStatus, out: String(decoding: data, as: UTF8.self))
    }
}
