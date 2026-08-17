# OptTab

Tiny native macOS window switcher. **Option+Tab** lists every window, not every app, so two Chrome profiles show up as two entries.

No Electron, no Swift packages, no screen recording, no Pro tier. Swift and AppKit only.

```
⌥ Tab

  [ Chrome ] [ Chrome ] [ VS Code ]
    Gmail      GitHub     opttab
  [ Terminal ] [ Finder ]
     zsh        Documents
```

Release Option to focus the selected window. macOS `⌘ Tab` still switches apps; OptTab switches windows.

## Why

`⌘ Tab` is an application switcher. Two browser profiles are still one Chrome. Apple's window cycle is `⌘ ``.

OptTab uses **Option+Tab** so it does not fight the system switcher.

## Install

Needs macOS 14+ and Xcode or the Command Line Tools.

```bash
git clone https://github.com/mmdmcy/opttab.git
cd opttab
./install.sh
```

That builds `OptTab.app`, copies it to `/Applications`, and launches it.

If a yellow line appears in the overlay, click it to open **System Settings → Privacy & Security → Accessibility** and enable OptTab. OptTab does not keep asking with system popups.

Optional: menu bar icon → Launch at Login.

## Use

| Key | Action |
| --- | --- |
| `⌥ Tab` | Open switcher / next window |
| `⌥ ⇧ Tab` | Previous window |
| arrows | Move in the grid |
| click | Focus that window |
| release `⌥` | Focus selected window |
| `esc` | Cancel |

## Scope

- Visible windows on the current space
- Square grid of app icon + title, no live previews
- Focus that window, not merely its app
- Skips Finder Desktop, menu-bar extras, and itself

No tiling WM, no `⌘ Tab` replacement, no Screen Recording.

## Build without installing

```bash
./build.sh
open dist/OptTab.app
```

The binary is a small arm64 AppKit executable. Zero third-party dependencies.

## License

MIT. See [LICENSE](LICENSE).
