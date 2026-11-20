import AppKit
import ApplicationServices
import Carbon.HIToolbox
import UniformTypeIdentifiers

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

    /// Resolves "browser" (the default web browser), "terminal" (the user's terminal),
    /// a bundle ID, or an app name.
    static func appURL(for app: String) -> URL? {
        let ws = NSWorkspace.shared
        if app.lowercased() == "browser" {
            return ws.urlForApplication(toOpen: URL(string: "https://example.com")!)
        }
        if app.lowercased() == "terminal" {
            return terminalURL()
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

    private static let appleTerminal = "com.apple.Terminal"
    private static let thirdPartyTerminals = [
        "com.mitchellh.ghostty", "com.googlecode.iterm2", "com.github.wez.wezterm",
        "net.kovidgoyal.kitty", "org.alacritty", "dev.warp.Warp-Stable", "co.zeit.hyper",
    ]

    /// macOS has no "default terminal" setting. The closest is the app that opens shell
    /// scripts, which terminals like iTerm2 claim when made the default — but many
    /// (Ghostty included) don't, leaving Terminal.app. So prefer, in order: a non-Apple
    /// handler for shell scripts, a known terminal that's running, one that's installed,
    /// and finally Terminal.app.
    static func terminalURL() -> URL? {
        let ws = NSWorkspace.shared
        if let type = UTType("com.apple.terminal.shell-script"),
           let handler = ws.urlForApplication(toOpen: type),
           Bundle(url: handler)?.bundleIdentifier != appleTerminal {
            return handler
        }
        let running = Set(ws.runningApplications.compactMap(\.bundleIdentifier))
        if let id = thirdPartyTerminals.first(where: running.contains),
           let url = ws.urlForApplication(withBundleIdentifier: id) {
            return url
        }
        for id in thirdPartyTerminals {
            if let url = ws.urlForApplication(withBundleIdentifier: id) { return url }
        }
        return ws.urlForApplication(withBundleIdentifier: appleTerminal)
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
