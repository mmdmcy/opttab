#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$root/build.sh"

app="$root/dist/OptTab.app"
if [ ! -d "$app" ]; then
    printf '%s\n' "Build failed: $app missing" >&2
    exit 1
fi

if pgrep -x OptTab >/dev/null 2>&1; then
    pkill -x OptTab || true
    sleep 0.3
fi

# Releases before 1.9 hid the Dock for the experimental taskbar. Restore
# whatever they saved before installing the Alt-Tab-only build.
saved_autohide=$(/usr/bin/defaults read com.mmdmcy.opttab opttab.savedDockAutohide 2>/dev/null || true)
saved_delay=$(/usr/bin/defaults read com.mmdmcy.opttab opttab.savedDockDelay 2>/dev/null || true)
if [ -n "$saved_autohide" ]; then
    case "$saved_autohide" in
        1|true|TRUE|True) dock_autohide=true ;;
        *) dock_autohide=false ;;
    esac
    /usr/bin/defaults write com.apple.dock autohide -bool "$dock_autohide"
    if [ -n "$saved_delay" ]; then
        /usr/bin/defaults write com.apple.dock autohide-delay -float "$saved_delay"
    fi
    /usr/bin/defaults delete com.mmdmcy.opttab opttab.savedDockAutohide >/dev/null 2>&1 || true
    /usr/bin/defaults delete com.mmdmcy.opttab opttab.savedDockDelay >/dev/null 2>&1 || true
    /usr/bin/killall Dock >/dev/null 2>&1 || true
fi

rm -rf /Applications/OptTab.app
cp -R "$app" /Applications/OptTab.app
xattr -cr /Applications/OptTab.app 2>/dev/null || true

. "$root/scripts/sign.sh"
sign_opttab /Applications/OptTab.app

open /Applications/OptTab.app

printf '%s\n' "Installed /Applications/OptTab.app (Alt-Tab only; taskbar disabled)"
printf '%s\n' "This build uses a stable signature. In Accessibility, turn OptTab off and on once, then Relaunch from the menu bar."
