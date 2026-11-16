// Kaynak PNG'yi Apple macOS ikon ızgarasına (1024 tuvalde 824x824 gövde) oturtur.
import AppKit
let a = CommandLine.arguments
let src = NSImage(contentsOfFile: a[1])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.imageInterpolation = .high
src.draw(in: NSRect(x: 100, y: 100, width: 824, height: 824))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
