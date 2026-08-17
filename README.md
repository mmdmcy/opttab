# OptTab

Tiny native macOS window switcher. **Option+Tab** lists every window, not every app, so two Chrome profiles show up as two entries.

No Electron, no Swift packages, no Pro tier. Swift and AppKit only.

```
⌥ Tab

  [ Chrome preview ]  [ Chrome preview ]  [ VS Code ]  [ Terminal ]
      Gmail               GitHub            opttab         zsh
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

Grant these when asked (System Settings → Privacy & Security):

- **Accessibility** — list and focus other apps' windows
- **Input Monitoring** — see Option+Tab while another app is focused
- **Screen Recording** — live window previews in the switcher

After granting, use the menu bar icon → **Show Switcher** to confirm the overlay, then press **Option+Tab**.

Optional: click the menu bar icon → Launch at Login.

## Use

| Key | Action |
| --- | --- |
| `⌥ Tab` | Open switcher / next window |
| `⌥ ⇧ Tab` | Previous window |
| arrows | Move selection |
| release `⌥` | Focus selected window |
| `esc` | Cancel |

## Scope

- Visible windows on the current space
- Horizontal Windows-style switcher with live previews
- Focus that window, not merely its app
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
