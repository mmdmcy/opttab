# OptTab

Tiny native macOS window switcher and bottom taskbar. **Option+Tab** lists every window, not every app, so two Chrome profiles show up as two entries. The taskbar at the bottom groups the same app, like Windows and Linux Mint.

No Electron, no Swift packages, no Pro tier. Swift and AppKit only.

```
⌥ Tab

  [ Chrome ] [ Chrome ] [ VS Code ]
    Gmail      GitHub     opttab
  [ Terminal ] [ Finder ]
     zsh        Documents

[ Finder ] [ Apps ] [ Brave 2 ] [ VS Code ] [ Terminal ]          14:41
```

Click a tile while Option+Tab is open, or release Option, to focus that window. The cursor moves to that window, including across monitors. macOS `⌘ Tab` still switches apps; OptTab switches windows.

## Why

`⌘ Tab` is an application switcher. Two browser profiles are still one Chrome. Apple's window cycle is `⌘ ``.

OptTab uses **Option+Tab** so it does not fight the system switcher. A bottom taskbar groups open windows the way Windows and Linux Mint do. Hover a grouped icon to pick a window from live thumbnails. Right-click an app for New Window and browser profiles. The macOS Dock is hidden while that taskbar is on; restore it from the menu bar if you want it back.

## Install

Needs macOS 14+ and Xcode or the Command Line Tools.

```bash
git clone https://github.com/mmdmcy/opttab.git
cd opttab
./install.sh
```

That builds `OptTab.app`, copies it to `/Applications`, and launches it.

If a previous OptTab row is already enabled in Accessibility, turn it off and on once after install, then choose **Relaunch OptTab** from the menu bar. Rebuilds keep the same signature, so you should not have to do that again.

Thumbnails need Screen Recording. macOS will ask once when you first open the switcher or a grouped taskbar picker. After you allow it, relaunch OptTab from the menu bar.

Optional: menu bar icon → Launch at Login.

## Use

| Key | Action |
| --- | --- |
| `⌥ Tab` | Open switcher / next window |
| `⌥ ⇧ Tab` | Previous window |
| arrows | Move in the grid |
| click a tile | Focus that window |
| release `⌥` | Focus selected window |
| click a taskbar icon | Focus that window, or minimize if it is already front |
| hover a grouped icon | Pick which window to raise |
| right-click taskbar icon | Pin, New Window, Profiles, Close, Quit |

## Scope

- Visible and minimized windows
- Square grid switcher plus a grouped bottom taskbar
- Live window thumbnails (Screen Recording)
- Focus that window, not merely its app, and move the cursor there
- Finder and Apps stay on the left; right-click other apps to pin them
- Brave / Chrome / Edge profiles from the right-click menu
- Skips Finder Desktop, menu-bar extras, and itself

No tiling WM, no `⌘ Tab` replacement.

## Build without installing

```bash
./build.sh
open dist/OptTab.app
```

The binary is a small arm64 AppKit executable. Zero third-party dependencies.

## License

MIT. See [LICENSE](LICENSE).
