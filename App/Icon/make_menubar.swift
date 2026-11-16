// Siyah-beyaz kaynak görseli menü çubuğu "template" ikonuna çevirir:
// koyu pikseller opak, açık pikseller şeffaf olur; macOS rengi kendisi ayarlar.
// Kullanım: make_menubar <kaynak.png> <çıktı.png> <piksel>
import AppKit

let a = CommandLine.arguments
let size = Int(a[3])!
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[1])))!

// 1) Kaynağı alfa maskesine çevir.
//    Kaynakta şeffaf alan varsa (ör. şeffaf zemin üzerine beyaz çizim) şekil = opak pikseller.
//    Yoksa (ör. beyaz zemin üzerine siyah çizim) şekil = koyu pikseller.
let w = src.pixelsWide, h = src.pixelsHigh
var transparent = 0, maxAlpha: CGFloat = 0
for y in stride(from: 0, to: h, by: 4) {
    for x in stride(from: 0, to: w, by: 4) {
        let a = src.colorAt(x: x, y: y)!.alphaComponent
        if a < 0.05 { transparent += 1 }
        maxAlpha = max(maxAlpha, a)
    }
}
let useAlpha = transparent > (w / 4) * (h / 4) / 10   // %10'dan fazlası şeffafsa
let mask = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
for y in 0..<h {
    for x in 0..<w {
        let c = src.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        let alpha: CGFloat
        if useAlpha {
            alpha = maxAlpha > 0 ? min(1, c.alphaComponent / maxAlpha) : 0   // yarı opak çizimi tam opak yap
        } else {
            let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
            alpha = (1 - lum) * c.alphaComponent
        }
        mask.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: alpha), atX: x, y: y)
    }
}

// 2) Kare tuvale, en-boy oranını koruyarak ölçekle
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
NSGraphicsContext.current!.imageInterpolation = .high
let s = CGFloat(size) / CGFloat(max(w, h))
let dw = CGFloat(w) * s, dh = CGFloat(h) * s
mask.draw(in: NSRect(x: (CGFloat(size) - dw) / 2, y: (CGFloat(size) - dh) / 2, width: dw, height: dh))
NSGraphicsContext.restoreGraphicsState()
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
