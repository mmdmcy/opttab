#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dist="$root/dist"
app="$dist/OptTab.app"
macos="$app/Contents/MacOS"
resources="$app/Contents/Resources"

rm -rf "$app"
mkdir -p "$macos" "$resources"

cp "$root/Info.plist" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
if [ -f "$root/opttab.svg" ]; then
    cp "$root/opttab.svg" "$resources/opttab.svg"
fi

xcrun swiftc \
    -O \
    -parse-as-library \
    -whole-module-optimization \
    -target arm64-apple-macosx14.0 \
    -framework AppKit \
    -framework ApplicationServices \
    -framework Carbon \
    -framework ServiceManagement \
    -o "$macos/OptTab" \
    "$root"/Sources/*.swift

strip "$macos/OptTab"

. "$root/scripts/sign.sh"
sign_opttab "$app"

printf '%s\n' "Built $app"
ls -lh "$macos/OptTab"
codesign -d -r - "$app" 2>&1 | sed -n 's/^.*designated => /signed: /p'
