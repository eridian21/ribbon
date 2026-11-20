# Ribbon

A minimal Niri-style scrolling window manager for macOS. Uses only public APIs, so SIP stays on.

- Each display has its own ribbon: a horizontal strip of full-width windows, one on screen at a time.
- New windows open on the active display, to the right of the focused one, and take focus.
- Clicking, ⌘-Tab and the Dock also work; Ribbon follows the focus, including across displays.
- The menu bar shows your position on the active display (`▤ 3/7`); its menu lists each
  display's windows in ribbon order.

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

| ⌘⇧Return | New Ghostty window (opens Ghostty if it isn't running) |
| ⌘⇧B | Focus the default browser (opens it if needed) |
| ⌘⇧F | Focus Finder |

⌘←/→ stop at the ends of a ribbon; use ⌘⌥←/→ to switch displays.

## Config

`~/.config/ribbon/config.json` is created with defaults on first launch. Use **Edit Config…**
and **Reload Config** in the ▤ menu. Leave out any setting to keep its default.

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
    { "keys": "cmd+shift+return", "app": "Ghostty", "newWindow": true },
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
- `launch`: app shortcuts. `app` is an app name, bundle ID, or `"browser"` (your default
  browser). Without `newWindow` the shortcut focuses the app, launching it if needed; with
  `"newWindow": true` it opens a new window (via the app's ⌘N menu item) when it's running.
- `moveToDisplayLeft` / `moveToDisplayRight`: arrow-based alternative, off by default
  (e.g. `"cmd+opt+shift+left"`).

## Build & run

```sh
./build.sh
open build/Ribbon.app
```

On first launch, grant Accessibility in System Settings → Privacy & Security → Accessibility.
`build.sh` signs with the "Ribbon Dev" certificate so the grant survives rebuilds (falls back to
ad-hoc signing, which needs a re-grant per build, if that certificate is missing).

**Launch at Login** is in the ▤ menu. It registers the app at its current path, so if you move
`Ribbon.app` (e.g. into /Applications), toggle it off and on again.

Quitting (or Ctrl-C / `kill`) brings all parked windows back on screen.

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
