import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var config = RibbonConfig()
    private lazy var wm = WindowManager(config: config)
    private var hotKeys: HotKeys!
    private var statusItem: NSStatusItem!
    private var signalSources: [DispatchSourceSignal] = []
    private var hasAccess = false
    private var isPaused = false
    private var pausedOrder: [AXUIElement] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKeys = HotKeys()
        setUpStatusItem()
        setUpSignalHandlers()

        let (loaded, error) = RibbonConfig.load()
        if let loaded { config = loaded }
        if let error { showAlert("Ribbon is using default settings", error) }
        wm.config = config
        wm.onChange = { [weak self] in self?.updateTitle() }

        waitForAccessibilityThenStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wm.stop() // no-op if paused or never started
    }

    private func waitForAccessibilityThenStart() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            start()
            return
        }
        updateTitle()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.start()
        }
    }

    private func start() {
        hasAccess = true
        registerHotKeys()
        wm.start()
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        let k = config.keys
        var bindings: [(name: String, keys: String, action: () -> Void)] = [
            ("focusLeft", k.focusLeft, { [weak self] in self?.wm.focusLeft() }),
            ("focusRight", k.focusRight, { [weak self] in self?.wm.focusRight() }),
            ("moveLeft", k.moveLeft, { [weak self] in self?.wm.moveWindowLeft() }),
            ("moveRight", k.moveRight, { [weak self] in self?.wm.moveWindowRight() }),
            ("focusFirst", k.focusFirst, { [weak self] in self?.wm.focusFirst() }),
            ("focusLast", k.focusLast, { [weak self] in self?.wm.focusLast() }),
            ("pause", k.pause, { [weak self] in self?.pause() }),
            ("resume", k.resume, { [weak self] in self?.resume() }),
            ("focusDisplayLeft", k.focusDisplayLeft, { [weak self] in self?.wm.focusDisplayLeft() }),
            ("focusDisplayRight", k.focusDisplayRight, { [weak self] in self?.wm.focusDisplayRight() }),
            ("moveToDisplayLeft", k.moveToDisplayLeft, { [weak self] in self?.wm.moveWindowToDisplayLeft() }),
            ("moveToDisplayRight", k.moveToDisplayRight, { [weak self] in self?.wm.moveWindowToDisplayRight() }),
        ]
        for (i, keys) in k.focusDisplayByNumber.enumerated() {
            bindings.append(("focusDisplayByNumber[\(i + 1)]", keys, { [weak self] in self?.wm.focusDisplay(number: i + 1) }))
        }
        for launch in config.launch {
            bindings.append(("launch \(launch.app)", launch.keys, { [weak self] in
                do {
                    try Launcher.run(launch)
                } catch {
                    self?.showAlert("Couldn't open \(launch.app)",
                                    "No app named \"\(launch.app)\" was found. Use the app's exact name or bundle ID in config.json.")
                }
            }))
        }
        for (i, keys) in k.moveToDisplayByNumber.enumerated() {
            bindings.append(("moveToDisplayByNumber[\(i + 1)]", keys, { [weak self] in self?.wm.moveWindowToDisplay(number: i + 1) }))
        }
        var problems: [String] = []
        for b in bindings where !b.keys.isEmpty {
            guard let combo = KeyCombo(b.keys) else {
                problems.append("\(b.name): \"\(b.keys)\" isn't a shortcut Ribbon understands")
                continue
            }
            if !hotKeys.register(combo, action: b.action) {
                problems.append("\(b.name): \"\(b.keys)\" couldn't be registered (already in use?)")
            }
        }
        if !problems.isEmpty {
            showAlert("Some shortcuts weren't set", problems.joined(separator: "\n"))
        }
    }

    // MARK: Pause / resume

    @objc private func pause() {
        guard hasAccess, !isPaused else { return }
        pausedOrder = wm.stop()
        isPaused = true
        updateTitle()
    }

    @objc private func resume() {
        guard hasAccess, isPaused else { return }
        isPaused = false
        wm.start(preferredOrder: pausedOrder)
        pausedOrder = []
        updateTitle()
    }

    // MARK: Config

    @objc private func editConfig() {
        if !FileManager.default.fileExists(atPath: RibbonConfig.url.path) {
            _ = RibbonConfig.load() // writes the default file
        }
        // Open in TextEdit-style plain text editor rather than whatever owns .json (often Xcode).
        let config = NSWorkspace.OpenConfiguration()
        if let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([RibbonConfig.url], withApplicationAt: editor, configuration: config)
        } else {
            NSWorkspace.shared.open(RibbonConfig.url)
        }
    }

    @objc private func reloadConfig() {
        let (loaded, error) = RibbonConfig.load()
        guard let loaded else {
            showAlert("Config not reloaded", error ?? "Unknown error")
            return
        }
        let floatingChanged = loaded.floatingApps != config.floatingApps
        config = loaded
        wm.config = loaded
        guard hasAccess else { return }
        registerHotKeys()
        if isPaused { return }
        if floatingChanged {
            // Re-scan apps so newly floating apps are released and others picked up.
            let order = wm.stop()
            wm.start(preferredOrder: order)
        } else {
            wm.layout()
        }
    }

    // MARK: Launch at login

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showAlert("Couldn't change Launch at Login", error.localizedDescription)
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.menuBarIcon
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.setAccessibilityLabel("Ribbon")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateTitle()
    }

    /// The Ribbon mark (same geometry as design/ribbon-mark.svg) as a template image,
    /// so macOS tints it to match a light or dark menu bar.
    private static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            let unit = rect.width / 64
            func polygon(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: points[0].0 * unit, y: points[0].1 * unit))
                for p in points.dropFirst() { path.line(to: NSPoint(x: p.0 * unit, y: p.1 * unit)) }
                path.close()
                return path
            }
            NSColor.black.withAlphaComponent(0.45).setFill()
            polygon([(3, 20), (14, 15), (14, 49), (3, 44)]).fill()
            polygon([(50, 15), (61, 20), (61, 44), (50, 49)]).fill()
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 17 * unit, y: 8 * unit, width: 30 * unit, height: 48 * unit),
                         xRadius: 5 * unit, yRadius: 5 * unit).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    private func updateTitle() {
        let title: String
        if !hasAccess {
            title = " needs Accessibility"
        } else if isPaused {
            title = " paused"
        } else if let p = wm.position {
            title = " \(p.index)/\(p.count)"
        } else {
            title = ""
        }
        if statusItem.button?.title != title {
            statusItem.button?.title = title
        }
    }

    /// Rebuilt each time the menu opens so the window list is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if hasAccess, !isPaused {
            let sections = wm.sections
            let showHeaders = sections.count > 1
            for section in sections {
                if showHeaders {
                    menu.addItem(.sectionHeader(title: section.displayName + (section.isActive ? " (active)" : "")))
                }
                if section.entries.isEmpty {
                    menu.addItem(disabled("No windows"))
                }
                for entry in section.entries {
                    let item = NSMenuItem(title: truncate(entry.title), action: #selector(jumpToWindow(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = MenuTarget(displayID: entry.displayID, index: entry.index)
                    item.state = entry.isOnScreen ? .on : .off
                    menu.addItem(item)
                }
            }
            menu.addItem(.separator())
        }

        if hasAccess {
            menu.addItem(item(isPaused ? "Resume Ribbon" : "Pause Ribbon",
                              isPaused ? #selector(resume) : #selector(pause)))
        }
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Edit Config…", #selector(editConfig)))
        menu.addItem(item("Reload Config", #selector(reloadConfig)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ribbon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private struct MenuTarget {
        let displayID: String
        let index: Int
    }

    @objc private func jumpToWindow(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget else { return }
        wm.focus(displayID: target.displayID, at: target.index)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func truncate(_ s: String, max: Int = 70) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: Signals

    /// On Ctrl-C / kill, bring parked windows back before exiting.
    private func setUpSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.wm.stop()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
