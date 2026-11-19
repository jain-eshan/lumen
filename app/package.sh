#!/bin/zsh
# Packs Narrator.app into a disk image people can open and drag to Applications.
set -euo pipefail
LAB="${0:A:h:h}"
STAGE=$(mktemp -d)
mkdir -p "$LAB/dist"
ditto "$LAB/Narrator.app" "$STAGE/Narrator.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$LAB/dist/Narrator.dmg"
hdiutil create -volname "Narrator" -srcfolder "$STAGE" -fs APFS -format ULMO -o "$LAB/dist/Narrator.dmg" >/dev/null
rm -rf "$STAGE"
echo "Packed $LAB/dist/Narrator.dmg ($(du -h "$LAB/dist/Narrator.dmg" | cut -f1))"
