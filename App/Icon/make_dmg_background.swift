// DMG penceresi arka planı: uygulamadan Applications'a ok ve iki dilde kısa yönerge.
// Kullanım: make_dmg_background <çıktı.png> <ölçek: 1|2> [alt başlık]
import AppKit

let args = CommandLine.arguments
let out = args[1]
let scale = CGFloat(Double(args[2]) ?? 1)
let subtitle = args.count > 3 ? args[3] : ""
let W: CGFloat = 640, H: CGFloat = 400

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Açık maviden beyaza geçiş (uygulama ikonunun renkleri)
let gradient = NSGradient(starting: NSColor(deviceRed: 0.86, green: 0.93, blue: 1.0, alpha: 1),
                          ending: NSColor(deviceRed: 0.98, green: 0.99, blue: 1.0, alpha: 1))!
gradient.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                            .foregroundColor: color, .paragraphStyle: p]
    NSAttributedString(string: s, attributes: a).draw(in: NSRect(x: 0, y: y, width: W, height: size + 8))
}

let blue = NSColor(deviceRed: 0.16, green: 0.52, blue: 0.96, alpha: 1)
text("SpoofDPI+", size: 26, weight: .bold, color: NSColor(deviceWhite: 0.15, alpha: 1), y: H - 58)
if !subtitle.isEmpty {
    text(subtitle, size: 12, weight: .medium, color: NSColor(deviceWhite: 0.4, alpha: 1), y: H - 82)
}

// Ok: uygulama ikonu (x=170) → Applications (x=470), ikon merkezleri y=200 (Finder koordinatı, üstten)
let arrowY = H - 200
let path = NSBezierPath()
path.move(to: NSPoint(x: 250, y: arrowY))
path.line(to: NSPoint(x: 385, y: arrowY))
path.lineWidth = 6
path.lineCapStyle = .round
blue.withAlphaComponent(0.85).setStroke()
path.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 395, y: arrowY))
head.line(to: NSPoint(x: 375, y: arrowY + 14))
head.line(to: NSPoint(x: 375, y: arrowY - 14))
head.close()
blue.withAlphaComponent(0.85).setFill()
head.fill()

text("Uygulamayı Applications klasörüne sürükleyin", size: 14, weight: .semibold,
     color: NSColor(deviceWhite: 0.25, alpha: 1), y: 62)
text("Drag the app to the Applications folder", size: 12, weight: .regular,
     color: NSColor(deviceWhite: 0.45, alpha: 1), y: 40)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
