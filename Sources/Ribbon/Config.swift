import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// User settings, read from ~/.config/ribbon/config.json. Any field left out of the
/// file keeps its default, so the file only needs the settings you want to change.
struct RibbonConfig: Equatable {
    /// Padding in points between the focused window and the screen edges.
    var gap: CGFloat = 12
    /// Apps Ribbon leaves alone, by name ("Calculator") or bundle ID ("com.apple.calculator").
    var floatingApps: [String] = ["Calculator"]
    var keys = Keys()
    /// App shortcuts. `app` is a name, a bundle ID, "browser" (the default browser) or
    /// "terminal" (see Launcher.terminalURL).
    /// `newWindow` opens a new window if the app is already running; otherwise the
    /// shortcut focuses the app (launching it if needed).
    var launch: [LaunchBinding] = [
        LaunchBinding(keys: "cmd+shift+return", app: "terminal", newWindow: true),
        LaunchBinding(keys: "cmd+shift+b", app: "browser"),
        LaunchBinding(keys: "cmd+shift+f", app: "Finder"),
    ]

    struct LaunchBinding: Equatable {
        var keys: String
        var app: String
        var newWindow = false
    }

    /// Shortcuts like "cmd+shift+left". Modifiers: cmd/super, shift, ctrl, opt/alt.
    /// Use "" to disable a shortcut.
    struct Keys: Equatable {
        var focusLeft = "cmd+left"
        var focusRight = "cmd+right"
        var moveLeft = "cmd+shift+left"
        var moveRight = "cmd+shift+right"
        var focusFirst = "cmd+home"
        var focusLast = "cmd+end"
        var pause = "cmd+shift+p"
        var resume = "cmd+shift+r"
        var focusDisplayLeft = "cmd+opt+left"
        var focusDisplayRight = "cmd+opt+right"
        /// Off by default (moveToDisplayByNumber is used instead); e.g. "cmd+opt+shift+left".
        var moveToDisplayLeft = ""
        var moveToDisplayRight = ""
        /// Focus display 1, 2, … (built-in first, then external displays left to right).
        var focusDisplayByNumber = ["cmd+1", "cmd+2"]
        /// Send the focused window to display 1, 2, … (same numbering).
        var moveToDisplayByNumber = ["cmd+shift+1", "cmd+shift+2"]
    }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/ribbon/config.json")

    /// Loads the config, writing a default file first if none exists.
    /// On error, returns nil and a message describing what's wrong.
    static func load() -> (config: RibbonConfig?, error: String?) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            let defaults = RibbonConfig()
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(defaults).write(to: url)
            } catch {
                NSLog("Ribbon: couldn't write default config: \(error)")
            }
            return (defaults, nil)
        }
        do {
            let config = try JSONDecoder().decode(RibbonConfig.self, from: Data(contentsOf: url))
            return (config, nil)
        } catch let DecodingError.dataCorrupted(ctx) {
            let detail = (ctx.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return (nil, "\(url.path) isn't valid JSON. \(detail ?? ctx.debugDescription)")
        } catch let DecodingError.typeMismatch(_, ctx) {
            let field = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return (nil, "\(url.path): \"\(field)\" has the wrong type. \(ctx.debugDescription)")
        } catch {
            return (nil, "Couldn't read \(url.path): \(error)")
        }
    }
}

extension RibbonConfig: Codable {
    private enum CodingKeys: String, CodingKey { case gap, floatingApps, keys, launch }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gap = try c.decodeIfPresent(CGFloat.self, forKey: .gap) ?? gap
        floatingApps = try c.decodeIfPresent([String].self, forKey: .floatingApps) ?? floatingApps
        keys = try c.decodeIfPresent(Keys.self, forKey: .keys) ?? keys
        launch = try c.decodeIfPresent([LaunchBinding].self, forKey: .launch) ?? launch
    }
}

extension RibbonConfig.LaunchBinding: Codable {
    private enum CodingKeys: String, CodingKey { case keys, app, newWindow }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = try c.decode(String.self, forKey: .keys)
        app = try c.decode(String.self, forKey: .app)
        newWindow = try c.decodeIfPresent(Bool.self, forKey: .newWindow) ?? false
    }
}

extension RibbonConfig.Keys: Codable {
    private enum CodingKeys: String, CodingKey {
        case focusLeft, focusRight, moveLeft, moveRight, focusFirst, focusLast, pause, resume
        case focusDisplayLeft, focusDisplayRight, moveToDisplayLeft, moveToDisplayRight
        case focusDisplayByNumber, moveToDisplayByNumber
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusLeft = try c.decodeIfPresent(String.self, forKey: .focusLeft) ?? focusLeft
        focusRight = try c.decodeIfPresent(String.self, forKey: .focusRight) ?? focusRight
        moveLeft = try c.decodeIfPresent(String.self, forKey: .moveLeft) ?? moveLeft
        moveRight = try c.decodeIfPresent(String.self, forKey: .moveRight) ?? moveRight
        focusFirst = try c.decodeIfPresent(String.self, forKey: .focusFirst) ?? focusFirst
        focusLast = try c.decodeIfPresent(String.self, forKey: .focusLast) ?? focusLast
        pause = try c.decodeIfPresent(String.self, forKey: .pause) ?? pause
        resume = try c.decodeIfPresent(String.self, forKey: .resume) ?? resume
        focusDisplayLeft = try c.decodeIfPresent(String.self, forKey: .focusDisplayLeft) ?? focusDisplayLeft
        focusDisplayRight = try c.decodeIfPresent(String.self, forKey: .focusDisplayRight) ?? focusDisplayRight
        moveToDisplayLeft = try c.decodeIfPresent(String.self, forKey: .moveToDisplayLeft) ?? moveToDisplayLeft
        moveToDisplayRight = try c.decodeIfPresent(String.self, forKey: .moveToDisplayRight) ?? moveToDisplayRight
        focusDisplayByNumber = try c.decodeIfPresent([String].self, forKey: .focusDisplayByNumber) ?? focusDisplayByNumber
        moveToDisplayByNumber = try c.decodeIfPresent([String].self, forKey: .moveToDisplayByNumber) ?? moveToDisplayByNumber
    }
}

/// A parsed shortcut such as "cmd+shift+left".
struct KeyCombo {
    let keyCode: Int
    let modifiers: Int

    init?(_ string: String) {
        var modifiers = 0
        var keyCode: Int?
        for part in string.lowercased().split(separator: "+") {
            switch part.trimmingCharacters(in: .whitespaces) {
            case "cmd", "command", "super", "⌘": modifiers |= cmdKey
            case "shift", "⇧": modifiers |= shiftKey
            case "ctrl", "control", "⌃": modifiers |= controlKey
            case "opt", "option", "alt", "⌥": modifiers |= optionKey
            case let key:
                guard keyCode == nil, let code = KeyCombo.keyCodes[key] else { return nil }
                keyCode = code
            }
        }
        guard let keyCode else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private static let keyCodes: [String: Int] = {
        var map: [String: Int] = [
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab,
            "escape": kVK_Escape, "esc": kVK_Escape, "delete": kVK_Delete, "backspace": kVK_Delete,
            "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
            ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
            "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
        ]
        let letters = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
                       kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
                       kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
                       kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z]
        for (i, code) in letters.enumerated() {
            map[String(UnicodeScalar(UInt8(97 + i)))] = code
        }
        let digits = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                      kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (i, code) in digits.enumerated() {
            map[String(i)] = code
        }
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                     kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (i, code) in fKeys.enumerated() {
            map["f\(i + 1)"] = code
        }
        return map
    }()
}
