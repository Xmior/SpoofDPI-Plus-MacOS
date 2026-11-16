// SF Symbols'ü renkli PNG'ye çevirir (macOS 10.15'te SF Symbols API'si yok).
// Derleme makinesinde (macOS 11+) çalışır. Kullanım: make_symbols <çıktı-klasörü>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let symbols: [(String, String, NSColor)] = [
    ("install", "square.and.arrow.down", .systemGreen),
    ("uninstall", "trash", .systemRed),
    ("start", "play.fill", .systemGreen),
    ("running", "checkmark.circle.fill", .systemGreen),
    ("stop", "stop.fill", .systemRed),
    ("restart", "arrow.clockwise", .systemOrange),
    ("proxyOn", "network", .systemBlue),
    ("proxyOff", "network.slash", .systemGray),
    ("discord", "bubble.left.and.bubble.right.fill", .systemIndigo),
    ("logs", "doc.text.magnifyingglass", .systemTeal),
    ("refresh", "arrow.triangle.2.circlepath", .secondaryLabelColor),
    ("window", "macwindow", .secondaryLabelColor),
]

let px = 64
for (file, name, color) in symbols {
    let cfg = NSImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else {
        print("eksik sembol: \(name)"); exit(1)
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = sym.size
    let scale = CGFloat(px - 6) / max(s.width, s.height)
    let w = s.width * scale, h = s.height * scale
    sym.draw(in: NSRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(file).png"))
}
