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

rm -rf /Applications/OptTab.app
cp -R "$app" /Applications/OptTab.app
xattr -cr /Applications/OptTab.app 2>/dev/null || true

. "$root/scripts/sign.sh"
sign_opttab /Applications/OptTab.app

open /Applications/OptTab.app

printf '%s\n' "Installed /Applications/OptTab.app"
printf '%s\n' "This build uses a stable signature. In Accessibility, turn OptTab off and on once, then Relaunch from the menu bar."
