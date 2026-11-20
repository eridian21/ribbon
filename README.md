<img src="design/ribbon-icon-1024.png" alt="" width="128">

# Ribbon

A minimal Niri-style scrolling window manager for macOS. Uses only public APIs, so SIP stays on.

- Each display has its own ribbon: a horizontal strip of full-width windows, one on screen at a time.
- New windows open on the active display, to the right of the focused one, and take focus.
- Clicking, ⌘-Tab and the Dock also work; Ribbon follows the focus, including across displays.
- The menu bar icon shows your position on the active display (e.g. `3/7`); its menu lists each
  display's windows in ribbon order.

## Install

Requires macOS 14 (Sonoma) or later, on Apple Silicon or Intel.

1. Download **Ribbon-x.y.z.dmg** from the [latest release](https://github.com/eridian21/ribbon/releases/latest).
2. Open the downloaded file and drag **Ribbon** into the **Applications** folder.
3. Open Ribbon from Applications. macOS will say it can't verify Ribbon; click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down to the message saying Ribbon was
   blocked, and click **Open Anyway**. Confirm with your password or Touch ID.
5. Ribbon asks for **Accessibility** access, which it needs to move and resize windows. Turn on
   Ribbon in **System Settings → Privacy & Security → Accessibility**. Ribbon starts as soon as
   it's allowed, and its icon appears in the menu bar.

To start Ribbon automatically, choose **Launch at Login** from its menu bar menu.

**Why the warning?** Apple only skips it for apps signed through its paid developer program.
Ribbon isn't, so macOS asks you to approve it once. The full source code is in this repository.

**Updating:** quit Ribbon from its menu, then drag the new version into Applications and choose
**Replace**. You may need to click **Open Anyway** again; the Accessibility permission carries over.

## Default shortcuts

| Keys | Action |
| --- | --- |
| ⌘← / ⌘→ | Focus previous / next window |
| ⌘⇧← / ⌘⇧→ | Move the focused window left / right |
| ⌘Home / ⌘End (⌘fn← / ⌘fn→ on a MacBook) | Focus first / last window |
| ⌘⇧P | Pause: put every window back on screen and stop tiling |
| ⌘⇧R | Resume tiling (keeps the previous order) |
| ⌘⌥← / ⌘⌥→ | Focus the display to the left / right |
| ⌘1 / ⌘2 | Focus the built-in display / the external display |
| ⌘⇧1 / ⌘⇧2 | Send the focused window to the built-in / external display |
| ⌘⇧Return | New terminal window (opens your terminal if it isn't running) |
| ⌘⇧B | Focus the default browser (opens it if needed) |
| ⌘⇧F | Focus Finder |

⌘←/→ stop at the ends of a ribbon; use ⌘⌥←/→ to switch displays.

## Config

`~/.config/ribbon/config.json` is created with defaults on first launch. Use **Edit Config…**
and **Reload Config** in Ribbon's menu bar menu. Leave out any setting to keep its default.

```json
{
  "gap": 12,
  "floatingApps": ["Calculator", "com.1password.1password"],
  "keys": {
    "focusLeft": "cmd+left",
    "focusRight": "cmd+right",
    "moveLeft": "cmd+shift+left",
    "moveRight": "cmd+shift+right",
    "focusFirst": "cmd+home",
    "focusLast": "cmd+end",
    "pause": "cmd+shift+p",
    "resume": "cmd+shift+r",
    "focusDisplayLeft": "cmd+opt+left",
    "focusDisplayRight": "cmd+opt+right",
    "moveToDisplayLeft": "",
    "moveToDisplayRight": "",
    "focusDisplayByNumber": ["cmd+1", "cmd+2"],
    "moveToDisplayByNumber": ["cmd+shift+1", "cmd+shift+2"]
  },
  "launch": [
    { "keys": "cmd+shift+return", "app": "terminal", "newWindow": true },
    { "keys": "cmd+shift+b", "app": "browser" },
    { "keys": "cmd+shift+f", "app": "Finder" }
  ]
}
```

- `gap`: padding in points around the focused window.
- `floatingApps`: apps Ribbon ignores, by name or bundle ID (`osascript -e 'id of app "Name"'`).
- `keys`: modifiers `cmd`/`super`, `shift`, `ctrl`, `opt`/`alt`; keys are letters, digits,
  `left`/`right`/`up`/`down`, `home`/`end`, `pageup`/`pagedown`, `f1`–`f12`, `space`, `tab`,
  `return`, `escape`, and punctuation. `""` disables a shortcut.
- `focusDisplayByNumber`: one shortcut per display number. Display 1 is the built-in screen,
  then external displays left to right. Add `"cmd+3"` for a third display; `[]` disables them.
- `moveToDisplayByNumber`: the same, for sending the focused window to a display.
- `launch`: app shortcuts; see [App shortcuts](#app-shortcuts) below.
- `moveToDisplayLeft` / `moveToDisplayRight`: arrow-based alternative, off by default
  (e.g. `"cmd+opt+shift+left"`).

## App shortcuts

The `launch` list in the config holds shortcuts that open apps. The three defaults are only a
starting point: add as many entries as you like, change them, or remove them, then choose
**Reload Config** from Ribbon's menu bar menu.

```json
"launch": [
  { "keys": "cmd+shift+return", "app": "terminal", "newWindow": true },
  { "keys": "cmd+shift+b", "app": "browser" },
  { "keys": "cmd+shift+f", "app": "Finder" },
  { "keys": "cmd+shift+m", "app": "Mail" },
  { "keys": "cmd+shift+n", "app": "com.apple.Notes" }
]
```

Each entry has:

- `keys`: the shortcut, in the same format as the other shortcuts.
- `app`: an app name ("Mail"), a bundle ID ("com.apple.Notes"), or one of two special values:
  - `"browser"`: your default web browser.
  - `"terminal"`: your terminal. macOS has no real "default terminal" setting, so Ribbon picks
    the app you've made the handler for shell scripts (if it isn't Terminal.app), otherwise a
    known terminal that's running, otherwise one that's installed (Ghostty, iTerm2, WezTerm, kitty,
    Alacritty, Warp, Hyper), otherwise Terminal.app. Name the app directly if it picks the wrong one.
- `newWindow` (optional, default `false`): when the app is already running, open a new window
  (by pressing the app's own ⌘N menu item) instead of just switching to it.

Without `newWindow`, a shortcut switches to the app, launching it if needed, like clicking it in
the Dock.

The `launch` list is used as a whole: if your config has one, it replaces the defaults, so keep
any of the three you still want. To find an app's name and bundle ID, run this while it's open:

```sh
osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSWorkspace.sharedWorkspace.runningApplications.js.filter(a => a.activationPolicy == 0).map(a => a.localizedName.js + "  →  " + a.bundleIdentifier.js).join("\n")'
```

## How it works

On each display only the focused window is on screen; the others are parked in a bottom
corner with a 1pt sliver visible (macOS doesn't let windows go fully off-screen). Ribbon picks
a corner that doesn't border another display. Ignored: dialogs/panels, minimized and
native-fullscreen windows, fixed-size windows, and floating apps.

**Monitors:** each window remembers its display. Unplugging a display moves its windows to the
end of the active display's ribbon; plugging it back in sends them home. Sending a window to
another display with ⌘⇧1/⌘⇧2 makes that its new home.

## Limitations

- Dragging a window to another display with the mouse doesn't move it between ribbons (it snaps
  back); use ⌘⇧1/⌘⇧2.
- Built for a single Space per display; switching Spaces isn't handled.
- If Ribbon crashes, parked windows stay in the corner. Relaunching and quitting Ribbon restores them.

## Transparency (per app)

| App | Setting |
| --- | --- |
| Ghostty | `background-opacity = 0.85` |
| kitty | `background_opacity 0.85` |
| Alacritty | `[window] opacity = 0.85` |
| WezTerm | `config.window_background_opacity = 0.85` |
| iTerm2 | Settings → Profiles → Window → Transparency |
| Terminal.app | Settings → Profiles → Background color → Opacity |
| VS Code | no native option (needs an extension that patches VS Code) |
