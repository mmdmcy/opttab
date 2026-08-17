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
codesign --force --sign - --identifier com.mmdmcy.opttab --timestamp=none /Applications/OptTab.app >/dev/null

open /Applications/OptTab.app

printf '%s\n' "Installed /Applications/OptTab.app"
printf '%s\n' "Press Option+Tab. If a yellow line appears in the overlay, click it to grant Accessibility."
