import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func drawIcon(_ pixels: Int, to path: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
    let c = graphics.cgContext
    c.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    NSColor(calibratedRed: 0.055, green: 0.43, blue: 0.91, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 198, yRadius: 198).fill()
    // An original folder silhouette, split into two working panes.
    let folder = NSBezierPath()
    folder.move(to: NSPoint(x: 244, y: 688)); folder.line(to: NSPoint(x: 426, y: 688))
    folder.line(to: NSPoint(x: 478, y: 638)); folder.line(to: NSPoint(x: 780, y: 638))
    folder.curve(to: NSPoint(x: 812, y: 606), controlPoint1: NSPoint(x: 801, y: 638), controlPoint2: NSPoint(x: 812, y: 627))
    folder.line(to: NSPoint(x: 812, y: 346))
    folder.curve(to: NSPoint(x: 780, y: 314), controlPoint1: NSPoint(x: 812, y: 325), controlPoint2: NSPoint(x: 801, y: 314))
    folder.line(to: NSPoint(x: 244, y: 314))
    folder.curve(to: NSPoint(x: 212, y: 346), controlPoint1: NSPoint(x: 223, y: 314), controlPoint2: NSPoint(x: 212, y: 325))
    folder.line(to: NSPoint(x: 212, y: 656))
    folder.curve(to: NSPoint(x: 244, y: 688), controlPoint1: NSPoint(x: 212, y: 677), controlPoint2: NSPoint(x: 223, y: 688))
    folder.close(); NSColor.white.setFill(); folder.fill()
    NSColor(calibratedRed: 0.055, green: 0.43, blue: 0.91, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 492, y: 352, width: 34, height: 244), xRadius: 17, yRadius: 17).fill()
    NSColor(calibratedRed: 0.055, green: 0.43, blue: 0.91, alpha: 0.3).setFill()
    for x in [286.0, 584.0] { for y in [421.0, 491.0, 561.0] { NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 150, height: 20), xRadius: 10, yRadius: 10).fill() } }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: path)
}
for size in [16, 32, 128, 256, 512] {
    try drawIcon(size, to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size * 2, to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
