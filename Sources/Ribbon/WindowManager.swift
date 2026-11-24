import AppKit
import ApplicationServices

/// One ribbon entry: a window, or a group of macOS native tabs (Ghostty, Finder, Terminal…).
///
/// Each native tab is its own AX window, but only the selected tab is listed in the app's
/// kAXWindowsAttribute, and switching tabs posts no notification. So an entry remembers
/// every tab it has seen and `element` points at whichever one was last seen selected.
final class ManagedWindow {
    private(set) var element: AXUIElement
    private(set) var tabs: [AXUIElement]
    let pid: pid_t
    /// The display this window belongs on. If that display is unplugged the window is
    /// moved elsewhere, and it returns here when the display is reconnected.
    var home: String
    /// The frame Ribbon last gave this entry. Tabs in a group share one frame, which is
    /// how a newly selected, previously unseen tab is matched to its group.
    var lastFrame: CGRect?

    init(_ element: AXUIElement, pid: pid_t, home: String) {
        self.element = element
        self.tabs = [element]
        self.pid = pid
        self.home = home
        self.lastFrame = element.frame
    }

    func contains(_ el: AXUIElement) -> Bool {
        tabs.contains { CFEqual($0, el) }
    }

    /// Records `el` as one of this entry's tabs and makes it the selected one.
    func select(_ el: AXUIElement) {
        if !contains(el) { tabs.append(el) }
        element = el
    }

    func removeTab(_ el: AXUIElement) {
        tabs.removeAll { CFEqual($0, el) }
    }
}

/// One display's strip of windows. As many whole windows as fit the display's column width
/// are on screen, starting at `firstVisible`; the rest are parked off-screen.
final class Ribbon {
    var windows: [ManagedWindow] = []
    private(set) var focused = 0
    /// Index of the leftmost window on screen. The view only scrolls when focus moves
    /// outside the windows already shown (like Niri).
    private(set) var firstVisible = 0

    /// Adjusts `firstVisible` so the focused window is on screen and, near the end of the
    /// ribbon, the screen stays filled. Returns the range of windows to show.
    func scrollToFocus(perScreen: Int) -> Range<Int> {
        let k = max(perScreen, 1)
        if focused < firstVisible { firstVisible = focused }
        if focused >= firstVisible + k { firstVisible = focused - k + 1 }
        firstVisible = max(0, min(firstVisible, windows.count - k))
        return firstVisible..<min(firstVisible + k, windows.count)
    }
    /// The window focused before the current one; focus returns here when the current
    /// window closes (so closing a window you just opened takes you back where you were).
    private weak var previous: ManagedWindow?

    var current: ManagedWindow? { windows.indices.contains(focused) ? windows[focused] : nil }

    func setFocus(_ i: Int) {
        if i != focused, let current { previous = current }
        focused = i
    }

    /// Moves the focused window to slot `i`; focus stays on it (not a focus change).
    func swapFocused(with i: Int) {
        windows.swapAt(focused, i)
        focused = i
    }
    /// New windows go right after the focused one (like Niri).
    var insertionPoint: Int { windows.isEmpty ? 0 : focused + 1 }

    func index(of el: AXUIElement) -> Int? {
        windows.firstIndex { $0.contains(el) }
    }

    func insert(_ w: ManagedWindow, at position: Int) {
        let i = min(position, windows.count)
        windows.insert(w, at: i)
        if i <= focused, windows.count > 1 { focused += 1 }
    }

    func remove(at i: Int) {
        let removed = windows.remove(at: i)
        let wasFocused = i == focused
        if i < focused { focused -= 1 }
        focused = min(focused, max(windows.count - 1, 0))
        if wasFocused, let previous, let p = windows.firstIndex(where: { $0 === previous }) {
            focused = p
        }
        if previous === removed { previous = nil }
    }
}

private let axCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let wm = Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue()
    wm.handle(notification as String, element: element)
}

/// Keeps one horizontal strip of windows per display. On each display exactly one window
/// (that ribbon's focused one) fills the screen; the rest are parked off-screen.
final class WindowManager {
    var config: RibbonConfig
    /// Called whenever ribbons or focus may have changed (for the menu bar indicator).
    var onChange: (() -> Void)?
    private(set) var isRunning = false

    private var displays: [Display] = []          // left to right
    private var ribbons: [String: Ribbon] = [:]   // keyed by Display.id
    private var activeID: String?                  // display the user is working on
    private var observers: [pid_t: AXObserver] = [:]
    private var appElements: [pid_t: AXUIElement] = [:]
    private var workspaceObserversInstalled = false
    private var pendingDisplayChange: DispatchWorkItem?
    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    init(config: RibbonConfig) {
        self.config = config
    }

    private var active: Ribbon? { activeID.flatMap { ribbons[$0] } }

    // MARK: State for the UI

    struct Entry {
        let title: String
        let isOnScreen: Bool
        let displayID: String
        let index: Int
    }

    struct Section {
        let displayName: String
        let isActive: Bool
        let entries: [Entry]
    }

    var sections: [Section] {
        displays.compactMap { d in
            guard let r = ribbons[d.id] else { return nil }
            let entries = r.windows.enumerated().map { i, w in
                refreshSelectedTab(w)
                let app = NSRunningApplication(processIdentifier: w.pid)?.localizedName ?? "Unknown"
                let title = w.element.string(kAXTitleAttribute) ?? ""
                return Entry(title: title.isEmpty || title == app ? app : "\(app) — \(title)",
                             isOnScreen: i == r.focused, displayID: d.id, index: i)
            }
            return Section(displayName: d.name, isActive: d.id == activeID, entries: entries)
        }
    }

    /// 1-based position of the focused window on the active display, and its window count.
    var position: (index: Int, count: Int)? {
        guard let r = active, !r.windows.isEmpty else { return nil }
        return (r.focused + 1, r.windows.count)
    }

    // MARK: Lifecycle

    /// Starts managing windows. Each window joins the ribbon of the display it's on.
    /// Windows found in `preferredOrder` keep that order; others follow, left to right.
    func start(preferredOrder: [AXUIElement] = []) {
        guard !isRunning else { return }
        isRunning = true
        // Don't let one hung app freeze the window manager.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        installWorkspaceObservers()

        displays = Display.all()
        ribbons = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, Ribbon()) })
        activeID = displays.first?.id

        for app in NSWorkspace.shared.runningApplications {
            track(app, initialScan: true)
        }
        func rank(_ w: ManagedWindow) -> Int {
            preferredOrder.firstIndex { w.contains($0) } ?? Int.max
        }
        for r in ribbons.values {
            r.windows.sort { (rank($0), $0.element.position?.x ?? 0) < (rank($1), $1.element.position?.x ?? 0) }
            r.setFocus(0)
        }
        syncFocusFromSystem()
        layout()
        onChange?()
    }

    /// Stops managing windows and puts each back on screen on its display.
    /// Returns the ribbon order so a later `start` can restore it.
    @discardableResult
    func stop() -> [AXUIElement] {
        guard isRunning else { return [] }
        var order: [AXUIElement] = []
        for d in displays {
            guard let r = ribbons[d.id] else { continue }
            order += r.windows.flatMap(\.tabs)
            for w in r.windows {
                refreshSelectedTab(w)
                setFrame(w, visibleFrame(of: d))
            }
        }
        if let w = active?.current {
            focusWindow(w)
        }
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        appElements.removeAll()
        ribbons.removeAll()
        displays.removeAll()
        activeID = nil
        isRunning = false
        onChange?()
        return order
    }

    private func installWorkspaceObservers() {
        guard !workspaceObserversInstalled else { return }
        workspaceObserversInstalled = true
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, isRunning,
                  let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            track(app)
        }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, isRunning,
                  let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            untrack(app.processIdentifier)
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.syncFocusFromSystem()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleDisplayReconcile()
        }
    }

    // MARK: Navigation within the active display

    func focusLeft() { focusRelative(-1) }
    func focusRight() { focusRelative(1) }

    func focusFirst() {
        guard let id = activeID else { return }
        focus(displayID: id, at: 0)
    }

    func focusLast() {
        guard let id = activeID, let r = active else { return }
        focus(displayID: id, at: r.windows.count - 1)
    }

    func focus(displayID: String, at index: Int) {
        guard isRunning, let r = ribbons[displayID], r.windows.indices.contains(index) else { return }
        r.setFocus(index)
        activeID = displayID
        layout()
        focusWindow(r.windows[index])
    }

    private func focusRelative(_ delta: Int) {
        guard isRunning else { return }
        syncFocusFromSystem()
        guard let id = activeID, let r = active else { return }
        focus(displayID: id, at: r.focused + delta)
    }

    func moveWindowLeft() { moveWindow(by: -1) }
    func moveWindowRight() { moveWindow(by: 1) }

    /// Swaps the focused window with its neighbour; focus stays on the moved window.
    private func moveWindow(by delta: Int) {
        guard isRunning else { return }
        syncFocusFromSystem()
        guard let r = active else { return }
        let target = r.focused + delta
        guard r.windows.indices.contains(r.focused), r.windows.indices.contains(target) else { return }
        r.swapFocused(with: target)
        layout()
    }

    // MARK: Navigation between displays

    func focusDisplayLeft() { focusDisplay(by: -1) }
    func focusDisplayRight() { focusDisplay(by: 1) }
    func moveWindowToDisplayLeft() { moveWindowToDisplay(by: -1) }
    func moveWindowToDisplayRight() { moveWindowToDisplay(by: 1) }

    private func neighbourDisplay(_ delta: Int) -> Display? {
        guard let i = displays.firstIndex(where: { $0.id == activeID }) else { return nil }
        let j = i + delta
        return displays.indices.contains(j) ? displays[j] : nil
    }

    /// Focuses display `number` (see `numberedDisplay`).
    func focusDisplay(number: Int) {
        guard isRunning, let target = numberedDisplay(number) else { return }
        activateDisplay(target)
    }

    private func focusDisplay(by delta: Int) {
        guard isRunning else { return }
        syncFocusFromSystem()
        guard let target = neighbourDisplay(delta) else { return }
        activateDisplay(target)
    }

    private func activateDisplay(_ target: Display) {
        activeID = target.id
        if let w = ribbons[target.id]?.current {
            focusWindow(w)
        }
        onChange?()
    }

    /// Displays by number (1-based index): the built-in display first, then external
    /// displays left to right. The numbering doesn't depend on how displays are arranged.
    private func numberedDisplay(_ number: Int) -> Display? {
        let numbered = displays.filter(\.isBuiltIn) + displays.filter { !$0.isBuiltIn }
        return numbered.indices.contains(number - 1) ? numbered[number - 1] : nil
    }

    /// Sends the focused window to display `number`'s ribbon and follows it there.
    func moveWindowToDisplay(number: Int) {
        guard isRunning else { return }
        syncFocusFromSystem()
        guard let target = numberedDisplay(number) else { return }
        moveFocusedWindow(to: target)
    }

    /// Sends the focused window to the neighbouring display's ribbon and follows it there.
    private func moveWindowToDisplay(by delta: Int) {
        guard isRunning else { return }
        syncFocusFromSystem()
        guard let target = neighbourDisplay(delta) else { return }
        moveFocusedWindow(to: target)
    }

    private func moveFocusedWindow(to target: Display) {
        guard let source = active, let w = source.current,
              target.id != activeID, let dest = ribbons[target.id] else { return }
        source.remove(at: source.focused)
        dest.insert(w, at: dest.insertionPoint)
        dest.setFocus(dest.index(of: w.element) ?? dest.focused)
        w.home = target.id
        activeID = target.id
        layout()
        focusWindow(w)
    }

    // MARK: Layout

    private func visibleFrame(of d: Display) -> CGRect {
        d.visible.insetBy(dx: config.gap, dy: config.gap)
    }

    /// Window width on a display (its `width` fraction of the usable area, accounting for
    /// the gaps between windows) and how many whole windows fit side by side.
    private func columns(on d: Display) -> (width: CGFloat, perScreen: Int) {
        let area = visibleFrame(of: d)
        let gap = config.gap
        let fraction = config.windowWidth(for: d)
        let width = min(area.width, max(200, (fraction * (area.width + gap) - gap).rounded(.down)))
        let perScreen = max(1, Int((area.width + gap) / (width + gap) + 0.001))
        return (width, perScreen)
    }

    func layout() {
        guard isRunning else { return }
        for d in displays {
            guard let r = ribbons[d.id] else { continue }
            r.windows.forEach { refreshSelectedTab($0) }
            let area = visibleFrame(of: d)
            let (width, perScreen) = columns(on: d)
            let shown = r.scrollToFocus(perScreen: perScreen)

            // Lay the shown windows out left to right; centre them if they don't fill the screen.
            let total = CGFloat(shown.count) * width + CGFloat(max(shown.count - 1, 0)) * config.gap
            let startX = area.minX + ((area.width - total) / 2).rounded(.down)
            func frame(at i: Int) -> CGRect {
                let slot = CGFloat(i - shown.lowerBound)
                return CGRect(x: startX + slot * (width + config.gap), y: area.minY, width: width, height: area.height)
            }

            // Show the focused window first, then its visible neighbours, then park the rest
            // (avoids a flash of desktop).
            if let current = r.current {
                setFrame(current, frame(at: r.focused))
            }
            for i in shown where i != r.focused {
                setFrame(r.windows[i], frame(at: i))
            }
            let parked = d.parkingFrame(size: CGSize(width: width, height: area.height), among: displays)
            for (i, w) in r.windows.enumerated() where !shown.contains(i) {
                setFrame(w, parked)
            }
        }
        onChange?()
    }

    private func setFrame(_ w: ManagedWindow, _ target: CGRect, attempt: Int = 0) {
        w.lastFrame = target
        let el = w.element
        if let current = el.frame,
           abs(current.minX - target.minX) < 1, abs(current.minY - target.minY) < 1,
           abs(current.width - target.width) < 1, abs(current.height - target.height) < 1 {
            return
        }
        // Apps with "enhanced user interface" on (often set by accessibility tools)
        // animate every AX resize, which makes moves slow and racy. Turn it off briefly.
        let app = appElements[w.pid]
        let enhanced = app?.bool("AXEnhancedUserInterface") == true
        if enhanced { app?.set("AXEnhancedUserInterface", false) }

        // Size → position → size: some apps clamp the size against the old position,
        // and moving between displays of different sizes needs the second resize.
        el.setSize(target.size)
        el.setPosition(target.origin)
        el.setSize(target.size)

        if enhanced { app?.set("AXEnhancedUserInterface", true) }

        // Moving a window to another display takes effect asynchronously, and a resize
        // made in the meantime is clamped to the old display (e.g. a window sent from the
        // laptop to a taller monitor ends up laptop-height). Check shortly and re-apply.
        guard attempt < 4 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, isRunning, framesMatch(w.lastFrame, target) else { return }
            setFrame(w, target, attempt: attempt + 1) // returns early once the frame is right
        }
    }

    private func focusWindow(_ w: ManagedWindow) {
        refreshSelectedTab(w)
        if let app = appElements[w.pid] {
            app.set(kAXFrontmostAttribute, true)
        }
        w.element.set(kAXMainAttribute, true)
        w.element.perform(kAXRaiseAction)
    }

    // MARK: Display changes

    /// Plugging/unplugging fires several notifications in a row; wait for them to settle.
    private func scheduleDisplayReconcile() {
        pendingDisplayChange?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcileDisplays() }
        pendingDisplayChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func reconcileDisplays() {
        guard isRunning else { return }
        let current = Display.all()
        guard !current.isEmpty else { return } // mid-transition (e.g. closing the lid); wait
        let ids = Set(current.map(\.id))
        displays = current

        for d in current where ribbons[d.id] == nil {
            ribbons[d.id] = Ribbon()
        }
        if activeID == nil || !ids.contains(activeID!) {
            activeID = current.first?.id
        }

        // Unplugged displays: their windows join the end of the active display's ribbon,
        // keeping their `home` so they can go back later.
        for (id, r) in ribbons where !ids.contains(id) {
            ribbons.removeValue(forKey: id)
            if let fallback = active {
                fallback.windows.append(contentsOf: r.windows)
            }
        }

        // Reconnected displays: send windows whose home is back to it, in order.
        for (id, r) in ribbons {
            let returning = r.windows.filter { $0.home != id && ribbons[$0.home] != nil }
            for w in returning {
                if let i = r.index(of: w.element) { r.remove(at: i) }
                ribbons[w.home]?.windows.append(w)
            }
        }

        layout()
    }

    // MARK: Tracking apps and windows

    private func isFloating(_ app: NSRunningApplication) -> Bool {
        let floating = Set(config.floatingApps.map { $0.lowercased() })
        return [app.bundleIdentifier, app.localizedName]
            .compactMap { $0?.lowercased() }
            .contains(where: floating.contains)
    }

    /// The display a window is currently (mostly) on.
    private func displayID(containing el: AXUIElement) -> String? {
        guard let frame = el.frame,
              let best = displays.max(by: { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }),
              best.frame.intersection(frame).area > 0 else { return activeID }
        return best.id
    }

    /// Starts managing an app. During the initial scan each window joins the ribbon of the
    /// display it's on. For apps launched later, windows join the active display's ribbon
    /// and take focus like any other new window.
    private func track(_ app: NSRunningApplication, attempt: Int = 0, initialScan: Bool = false) {
        let pid = app.processIdentifier
        guard isRunning, app.activationPolicy == .regular, pid != getpid(),
              observers[pid] == nil, !app.isTerminated, !isFloating(app) else { return }

        let appEl = AXUIElementCreateApplication(pid)
        var created: AXObserver?
        guard AXObserverCreate(pid, axCallback, &created) == .success, let observer = created else { return }

        // Freshly launched apps often aren't ready for AX yet; retry for a few seconds.
        guard AXObserverAddNotification(observer, appEl, kAXWindowCreatedNotification as CFString, refcon) == .success else {
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.track(app, attempt: attempt + 1, initialScan: initialScan)
                }
            }
            return
        }
        AXObserverAddNotification(observer, appEl, kAXFocusedWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        appElements[pid] = appEl

        if initialScan {
            for window in appEl.windows {
                if let id = displayID(containing: window), let r = ribbons[id] {
                    adopt(window, pid: pid, into: id, at: r.windows.count)
                }
            }
            return
        }

        // A freshly launched app's first window usually exists before AX is ready, so we
        // pick it up here rather than via kAXWindowCreatedNotification. Insert the app's
        // windows in order, right after the focused window of the display macOS opened
        // them on.
        let listed = appEl.windows
        guard let first = appEl.focusedWindow ?? listed.first,
              let id = displayID(containing: first), let r = ribbons[id] else { return }
        var insertAt = r.insertionPoint
        var adopted: [AXUIElement] = []
        for window in listed where adopt(window, pid: pid, into: id, at: insertAt) {
            insertAt += 1
            adopted.append(window)
        }
        if !adopted.isEmpty {
            let preferred = appEl.focusedWindow.flatMap { fw in adopted.first { CFEqual($0, fw) } }
            if let i = r.index(of: preferred ?? adopted[0]) {
                focus(displayID: id, at: i)
                return
            }
        }
        layout()
    }

    private func untrack(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        appElements.removeValue(forKey: pid)
        let hadFocus = active?.current?.pid == pid
        for r in ribbons.values {
            while let i = r.windows.firstIndex(where: { $0.pid == pid }) {
                r.remove(at: i)
            }
        }
        layout()
        if hadFocus, let w = active?.current { focusWindow(w) }
    }

    private func isManageable(_ el: AXUIElement) -> Bool {
        el.role == kAXWindowRole
            && el.subrole == kAXStandardWindowSubrole
            && !el.isMinimized
            && !el.isFullScreen
            && el.isSettable(kAXSizeAttribute)   // fixed-size windows (e.g. System Settings) float
            && el.isSettable(kAXPositionAttribute)
    }

    /// Adds a window to a display's ribbon. Returns true if added.
    @discardableResult
    private func adopt(_ el: AXUIElement, pid: pid_t, into displayID: String, at position: Int) -> Bool {
        guard locate(el) == nil, isManageable(el), observers[pid] != nil,
              let r = ribbons[displayID] else { return false }
        r.insert(ManagedWindow(el, pid: pid, home: displayID), at: position)
        observeWindow(el, pid: pid)
        return true
    }

    private func observeWindow(_ el: AXUIElement, pid: pid_t) {
        guard let observer = observers[pid] else { return }
        for n in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observer, el, n as CFString, refcon) // "already registered" is fine
        }
    }

    // MARK: Native tabs

    private func framesMatch(_ a: CGRect?, _ b: CGRect?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2
            && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }

    /// Points the entry at whichever of its tabs is currently selected. A selected window
    /// we've never seen (e.g. a tab that was in the background when Ribbon started) is
    /// claimed if it sits exactly where this entry was put. Returns false if no tab of
    /// this entry is currently listed.
    @discardableResult
    private func refreshSelectedTab(_ w: ManagedWindow) -> Bool {
        guard let appEl = appElements[w.pid] else { return false }
        let listed = appEl.windows
        if listed.contains(where: { CFEqual($0, w.element) }) { return true }
        if let tab = listed.first(where: { w.contains($0) }) {
            w.select(tab)
            return true
        }
        if let tab = listed.first(where: { locate($0) == nil && isManageable($0) && framesMatch($0.frame, w.lastFrame) }) {
            w.select(tab)
            observeWindow(tab, pid: w.pid)
            return true
        }
        return false
    }

    /// If `el` is a new tab in an existing group, returns that group's entry. A new tab
    /// replaces its group's selected tab in the window list and takes the group's frame.
    private func tabGroup(for el: AXUIElement) -> ManagedWindow? {
        guard let appEl = appElements[el.pid] else { return nil }
        let listed = appEl.windows
        let frame = el.frame
        for r in ribbons.values {
            for w in r.windows where w.pid == el.pid {
                let selectedStillListed = listed.contains { CFEqual($0, w.element) }
                if !selectedStillListed, framesMatch(frame, w.lastFrame) || framesMatch(frame, w.element.frame) {
                    return w
                }
            }
        }
        return nil
    }

    private func locate(_ el: AXUIElement) -> (displayID: String, ribbon: Ribbon, index: Int)? {
        for (id, r) in ribbons {
            if let i = r.index(of: el) { return (id, r, i) }
        }
        return nil
    }

    /// If the user changed focus some other way (click, ⌘-Tab, Dock), follow it,
    /// including onto another display.
    private func syncFocusFromSystem() {
        guard isRunning,
              let app = NSWorkspace.shared.frontmostApplication,
              let appEl = appElements[app.processIdentifier],
              let window = appEl.focusedWindow else { return }
        if locate(window) == nil {
            // Possibly a tab we haven't seen yet; let its group claim it.
            for r in ribbons.values {
                for w in r.windows where w.pid == app.processIdentifier { refreshSelectedTab(w) }
            }
        }
        guard let (id, r, i) = locate(window) else { return }
        guard id != activeID || i != r.focused else { return }
        activeID = id
        r.setFocus(i)
        layout()
    }

    // MARK: AX notifications

    func handle(_ notification: String, element: AXUIElement) {
        guard isRunning else { return }
        switch notification {
        case kAXWindowCreatedNotification, kAXWindowDeminiaturizedNotification:
            windowAppeared(element, retries: 3)

        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            guard let (id, r, i) = locate(element) else { return }
            let wasFocused = id == activeID && i == r.focused
            let entry = r.windows[i]
            entry.removeTab(element)
            // Closing one tab of a group selects another tab; keep the entry for it.
            if refreshSelectedTab(entry), !CFEqual(entry.element, element) {
                layout()
                if wasFocused { focusWindow(entry) }
                return
            }
            r.remove(at: i)
            layout()
            if wasFocused, let w = r.current { focusWindow(w) }

        case kAXFocusedWindowChangedNotification:
            syncFocusFromSystem()

        default:
            break
        }
    }

    private func windowAppeared(_ el: AXUIElement, retries: Int) {
        // New windows join the ribbon of the display macOS opened them on (falls back to
        // the active display if the window isn't on any display yet).
        guard isRunning, let id = displayID(containing: el), let r = ribbons[id] else { return }
        if locate(el) == nil, isManageable(el), let group = tabGroup(for: el),
           let (groupID, groupRibbon, i) = locate(group.element) {
            // A new tab (⌘T) in an existing group: same ribbon entry, not a new window.
            group.select(el)
            observeWindow(el, pid: el.pid)
            focus(displayID: groupID, at: groupRibbon.index(of: el) ?? i)
            return
        }
        if adopt(el, pid: el.pid, into: id, at: r.insertionPoint) {
            focus(displayID: id, at: r.index(of: el) ?? r.focused)
        } else if retries > 0, locate(el) == nil {
            // Some apps post "created" before the window's role/subrole are populated.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.windowAppeared(el, retries: retries - 1)
            }
        }
    }
}
