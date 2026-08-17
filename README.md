# OptTab

Tiny native macOS window switcher. **Option+Tab** lists every window, not every app, so two Chrome profiles show up as two entries.

No Electron, no Swift packages, no Pro tier. Swift and AppKit only.

```
⌥ Tab

  Chrome          Inbox — Gmail
  Chrome          GitHub
  VS Code         opttab
  Terminal        zsh
```

Release Option to focus the selected window. That is the whole point: macOS `⌘ Tab` still switches apps; OptTab switches windows.

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

Grant **Accessibility** when asked (System Settings → Privacy & Security → Accessibility). Window switchers need it to read and focus other apps' windows. After granting, OptTab relaunches itself.

Optional: click the menu bar icon → Launch at Login.

## Use

| Key | Action |
| --- | --- |
| `⌥ Tab` | Open switcher / next window |
| `⌥ ⇧ Tab` | Previous window |
| arrows | Move selection |
| release `⌥` | Focus selected window |
| `esc` | Cancel |

## Scope (v1)

- Visible windows on the current space
- App icon + window title
- Focus that window, not merely its app
- Skips Finder Desktop, menu-bar extras, and itself

No thumbnails, no tiling WM, no `⌘ Tab` replacement.

## Build without installing

```bash
./build.sh
open dist/OptTab.app
```

The binary is a small arm64 AppKit executable. Zero third-party dependencies.

## License

MIT. See [LICENSE](LICENSE).
