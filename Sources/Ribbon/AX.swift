import ApplicationServices

/// Thin, typed wrappers over the Accessibility C API.
extension AXUIElement {
    private func raw(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ name: String) -> String? { raw(name) as? String }
    func bool(_ name: String) -> Bool? { raw(name) as? Bool }

    func element(_ name: String) -> AXUIElement? {
        guard let v = raw(name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    var pid: pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(self, &pid)
        return pid
    }

    var windows: [AXUIElement] { (raw(kAXWindowsAttribute) as? [AXUIElement]) ?? [] }
    var children: [AXUIElement] { (raw(kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
    func int(_ name: String) -> Int? { (raw(name) as? NSNumber)?.intValue }
    var focusedWindow: AXUIElement? { element(kAXFocusedWindowAttribute) }
    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var isMinimized: Bool { bool(kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { bool("AXFullScreen") ?? false }

    func isSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(self, name as CFString, &settable) == .success && settable.boolValue
    }

    var position: CGPoint? {
        guard let v = raw(kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    var size: CGSize? {
        guard let v = raw(kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    var frame: CGRect? {
        guard let p = position, let s = size else { return nil }
        return CGRect(origin: p, size: s)
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        if let v = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, v)
        }
    }

    func setSize(_ size: CGSize) {
        var s = size
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, v)
        }
    }

    func set(_ name: String, _ value: Bool) {
        AXUIElementSetAttributeValue(self, name as CFString, value ? kCFBooleanTrue : kCFBooleanFalse)
    }

    func perform(_ action: String) {
        AXUIElementPerformAction(self, action as CFString)
    }
}
