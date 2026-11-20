// Generates Ribbon's app icon from the "Hybrid" mark.
//
//   swift design/make-icons.swift      (run from the project root)
//
// Writes Resources/AppIcon.icns (bundled by build.sh) and design/ribbon-icon-1024.png.
// The mark is defined on a 64×64 grid (y down), the same geometry as design/ribbon-mark.svg
// and the menu bar icon drawn in Sources/Ribbon/AppDelegate.swift.

import AppKit

let accent = NSColor(srgbRed: 0x3D / 255.0, green: 0x5A / 255.0, blue: 0xFE / 255.0, alpha: 1)
let tileColor = NSColor(srgbRed: 0x16 / 255.0, green: 0x17 / 255.0, blue: 0x1B / 255.0, alpha: 1)
let sideColor = NSColor(srgbRed: 0xF5 / 255.0, green: 0xF4 / 255.0, blue: 0xF0 / 255.0, alpha: 1)

/// Draws the mark into `rect` (a square), in an unflipped (y-up) context.
func drawMark(in rect: CGRect) {
    let unit = rect.width / 64
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: rect.minX + x * unit, y: rect.maxY - y * unit)
    }
    func polygon(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: p(points[0].0, points[0].1))
        for pt in points.dropFirst() { path.line(to: p(pt.0, pt.1)) }
        path.close()
        return path
    }
    sideColor.setFill()
    polygon([(3, 20), (14, 15), (14, 49), (3, 44)]).fill()
    polygon([(50, 15), (61, 20), (61, 44), (50, 49)]).fill()

    accent.setFill()
    let center = NSRect(x: rect.minX + 17 * unit, y: rect.maxY - 56 * unit, width: 30 * unit, height: 48 * unit)
    NSBezierPath(roundedRect: center, xRadius: 5 * unit, yRadius: 5 * unit).fill()
}

/// One square PNG of the full app icon: macOS icon grid (824pt tile on a 1024pt canvas).
func renderIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixels) / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.set()
    tileColor.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let markSize = tile.width * 0.62
    drawMark(in: NSRect(x: tile.midX - markSize / 2, y: tile.midY - markSize / 2, width: markSize, height: markSize))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = fm.temporaryDirectory.appending(path: "AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try renderIcon(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try renderIcon(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
try renderIcon(pixels: 1024).write(to: root.appending(path: "design/ribbon-icon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Resources/AppIcon.icns and design/ribbon-icon-1024.png")
