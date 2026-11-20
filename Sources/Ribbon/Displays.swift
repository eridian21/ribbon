import AppKit

/// A connected display, in Accessibility coordinates (origin at the top-left of the
/// primary display, y pointing down).
struct Display {
    /// Stable per-monitor ID (survives unplugging/replugging and reboots).
    let id: String
    let name: String
    let isBuiltIn: Bool
    let frame: CGRect
    let visible: CGRect

    /// All connected displays, ordered left to right (then top to bottom).
    static func all() -> [Display] {
        guard let primary = NSScreen.screens.first else { return [] }
        let height = primary.frame.height
        func toAX(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height)
        }
        return NSScreen.screens.map { screen in
            Display(id: stableID(of: screen), name: screen.localizedName,
                    isBuiltIn: CGDisplayIsBuiltin(cgDisplayID(of: screen)) != 0,
                    frame: toAX(screen.frame), visible: toAX(screen.visibleFrame))
        }
        .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    private static func cgDisplayID(of screen: NSScreen) -> CGDirectDisplayID {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return CGDirectDisplayID(number?.uint32Value ?? 0)
    }

    private static func stableID(of screen: NSScreen) -> String {
        let displayID = cgDisplayID(of: screen)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) {
            return string as String
        }
        return "display-\(displayID)"
    }

    /// Where windows in this display's ribbon are parked when not focused. macOS won't let
    /// a window go fully off-screen, so it sits in a bottom corner with a 1pt sliver showing.
    /// Picks a corner that doesn't spill onto another display.
    func parkingFrame(size: CGSize, among displays: [Display]) -> CGRect {
        func spillsOntoOther(_ r: CGRect, from d: Display) -> Bool {
            displays.contains { $0.id != d.id && $0.frame.intersects(r) }
        }
        func corners(of d: Display) -> [CGRect] {
            [CGRect(origin: CGPoint(x: d.frame.maxX - 1, y: d.frame.maxY - 1), size: size),
             CGRect(origin: CGPoint(x: d.frame.minX - size.width + 1, y: d.frame.maxY - 1), size: size)]
        }
        if let r = corners(of: self).first(where: { !spillsOntoOther($0, from: self) }) {
            return r
        }
        // Unusual arrangement where both of this display's bottom corners border another
        // display: park at a free corner of some other display instead.
        for d in displays {
            if let r = corners(of: d).first(where: { !spillsOntoOther($0, from: d) }) {
                return r
            }
        }
        return corners(of: self)[0]
    }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
