# OptTab

Tiny native macOS window switcher. **Option+Tab** lists every window, not every app, so two Chrome profiles show up as two entries.

No Electron, no Swift packages, no Pro tier. Swift and AppKit only. The unfinished taskbar is separate and not part of the active app.

```
⌥ Tab

  [ Chrome ] [ Chrome ] [ VS Code ]
    Gmail      GitHub     opttab
  [ Terminal ] [ Finder ]
     zsh        Documents
```

Click a tile while Option+Tab is open, or release Option, to focus that window. macOS `⌘ Tab` still switches apps; OptTab switches windows.

## Why

`⌘ Tab` is an application switcher. Two browser profiles are still one Chrome. Apple's window cycle is `⌘ ``.

OptTab uses **Option+Tab** so it does not fight the system switcher. The switcher is independent of the optional taskbar, so it never hides or replaces the macOS Dock.

## Install

Needs macOS 14+ and Xcode or the Command Line Tools.

```bash
git clone https://github.com/mmdmcy/opttab.git
cd opttab
./install.sh
```

That builds `OptTab.app`, copies it to `/Applications`, and launches it.

If a previous OptTab row is already enabled in Accessibility, turn it off and on once after install, then choose **Relaunch OptTab** from the menu bar. Rebuilds keep the same signature, so you should not have to do that again.

The switcher needs Accessibility to inspect and focus individual windows. Screen Recording is not needed for Alt-Tab. Input Monitoring is optional: Carbon handles the shortcut without it; enabling it adds more reliable keyboard navigation and release detection on newer macOS versions. Relaunch after changing either permission.

Optional: menu bar icon → Launch at Login.

## Use

| Key | Action |
| --- | --- |
| `⌥ Tab` | Open switcher / next window |
| `⌥ ⇧ Tab` | Previous window |
| arrows | Move in the grid |
| click a tile | Focus that window |
| release `⌥` | Focus selected window |

The taskbar is intentionally not enabled in this build.

## Scope

- Visible, minimized, and full-screen windows across Spaces
- Square grid switcher
- Focus that window, not merely its app
- Does not change the Dock or require Screen Recording
- Skips Finder Desktop, menu-bar extras, and itself
- The unfinished taskbar is not started or consulted

No tiling WM, no `⌘ Tab` replacement.

## Build without installing

```bash
./build.sh
open dist/OptTab.app
```

The binary is a small arm64 AppKit executable. Zero third-party dependencies.

## License

MIT. See [LICENSE](LICENSE).
