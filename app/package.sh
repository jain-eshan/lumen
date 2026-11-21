#!/bin/zsh
# Packs Lumen.app into a disk image people can open and drag to Applications.
set -euo pipefail
LAB="${0:A:h:h}"
STAGE=$(mktemp -d)
mkdir -p "$LAB/dist"
ditto "$LAB/Lumen.app" "$STAGE/Lumen.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$LAB/dist/Lumen.dmg"
hdiutil create -volname "Lumen" -srcfolder "$STAGE" -fs APFS -format ULMO -o "$LAB/dist/Lumen.dmg" >/dev/null
rm -rf "$STAGE"
echo "Packed $LAB/dist/Lumen.dmg ($(du -h "$LAB/dist/Lumen.dmg" | cut -f1))"
