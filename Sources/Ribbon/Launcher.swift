import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Opens or focuses apps for the `launch` shortcuts in the config.
enum Launcher {
    enum Failure: Error {
        case appNotFound(String)
    }

    /// Focuses the app (launching it if needed), or with `newWindow` opens a new window
    /// in it. New windows are picked up and focused by the window manager as usual.
    static func run(_ binding: RibbonConfig.LaunchBinding) throws {
        guard let url = appURL(for: binding.app) else { throw Failure.appNotFound(binding.app) }

        let bundleID = Bundle(url: url)?.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.first {
            ($0.bundleIdentifier != nil && $0.bundleIdentifier == bundleID) || $0.bundleURL == url
        }

        if binding.newWindow, let running {
            newWindow(in: running)
            return
        }
        // Launches the app, or activates it if it's running (like clicking it in the Dock,
        // which also makes apps like Finder open a window if they have none).
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// Resolves "browser" (the default web browser), a bundle ID, or an app name.
    static func appURL(for app: String) -> URL? {
        let ws = NSWorkspace.shared
        if app.lowercased() == "browser" {
            return ws.urlForApplication(toOpen: URL(string: "https://example.com")!)
        }
        if let url = ws.urlForApplication(withBundleIdentifier: app) {
            return url
        }
        if let running = ws.runningApplications.first(where: { $0.localizedName?.lowercased() == app.lowercased() }),
           let url = running.bundleURL {
            return url
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", "\(home)/Applications", "/System/Library/CoreServices"]
        for folder in folders {
            let path = "\(folder)/\(app).app"
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Opens a new window by pressing the app's own plain-⌘N menu item (works in any
    /// language). Falls back to sending ⌘N if the menu can't be read.
    private static func newWindow(in app: NSRunningApplication) {
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        if let menuBar = appEl.element(kAXMenuBarAttribute), let item = findCommandN(in: menuBar, depth: 0) {
            item.perform(kAXPressAction)
            return
        }
        app.activate()
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_N), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.postToPid(app.processIdentifier)
        }
    }

    private static func findCommandN(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 4 else { return nil }
        for child in element.children {
            // Modifiers 0 means ⌘ alone (no ⇧/⌥/⌃), i.e. ⌘N rather than ⌘⇧N.
            if child.role == kAXMenuItemRole,
               child.string(kAXMenuItemCmdCharAttribute)?.uppercased() == "N",
               child.int(kAXMenuItemCmdModifiersAttribute) == 0,
               child.bool(kAXEnabledAttribute) != false {
                return child
            }
            if let found = findCommandN(in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }
}
