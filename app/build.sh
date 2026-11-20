#!/bin/zsh
# Builds Narrator.app. The first build, or --full, also packs the voice engine and model inside the app.
set -euo pipefail
APP_SRC="${0:A:h}"
LAB="${APP_SRC:h}"
BUNDLE="$LAB/Narrator.app"
RES="$BUNDLE/Contents/Resources"
SIGNING="$LAB/.signing"
[[ "${1:-}" == "--full" ]] && rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$RES"
swiftc -O "$APP_SRC"/*.swift -o "$BUNDLE/Contents/MacOS/Narrator"
cp "$LAB/scripts/kokoro_server.py" "$RES/kokoro_server.py"
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Narrator</string>
  <key>CFBundleIdentifier</key><string>local.narrator.app</string>
  <key>CFBundleName</key><string>Narrator</string>
  <key>CFBundleDisplayName</key><string>Narrator</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.3</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>NSHumanReadableCopyright</key><string>Narrator, your AI reading agent. Read more, without reading. GPL-3.0.</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
security unlock-keychain -p "$(cat "$SIGNING/keychain-password")" "$SIGNING/narrator.keychain-db"
sign() { codesign --force --sign "$(cat "$SIGNING/identity")" --keychain "$SIGNING/narrator.keychain-db" "$@"; }

# Lumen's poses, made by art/cutout.swift from the generated pose sheet.
rm -rf "$RES/lumen" && cp -R "$APP_SRC/lumen" "$RES/lumen"

if [[ ! -f "$RES/AppIcon.icns" || "$APP_SRC/lumen/read.png" -nt "$RES/AppIcon.icns" ]]; then
  ICONS=$(mktemp -d)
  "$BUNDLE/Contents/MacOS/Narrator" --render-icon="$ICONS/icon.png"
  mkdir "$ICONS/AppIcon.iconset"
  for size in 16 32 128 256 512; do
    sips -z $size $size "$ICONS/icon.png" --out "$ICONS/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$ICONS/icon.png" --out "$ICONS/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONS/AppIcon.iconset" -o "$RES/AppIcon.icns"
  rm -rf "$ICONS"
fi

if [[ ! -x "$RES/python/bin/python3" ]]; then
  echo "Packing the voice engine into the app (first build only)"
  PYTHON_HOME="${$(readlink -f "$LAB/envs/kokoro/bin/python"):h:h}"
  SITE="$RES/python/lib/python3.12/site-packages"
  ditto "$PYTHON_HOME" "$RES/python"
  ditto "$LAB/envs/kokoro/lib/python3.12/site-packages" "$SITE"
  rm -rf "$SITE/_virtualenv.py" "$SITE/_virtualenv.pth" "$RES/python/lib/python3.12/test" "$RES/python/lib/python3.12/idlelib" "$RES/python/lib/python3.12/tkinter"
  # The download cache stores the model as links to shared files, so copy the real files.
  cp -RL "$LAB"/models/hub/models--mlx-community--Kokoro-82M-bf16/snapshots/*/ "$RES/kokoro"
  "$RES/python/bin/python3" -I -m compileall -q -j 0 "$RES/python/lib" >/dev/null 2>&1 || true
  # Every library inside gets the same signature as the app.
  find "$RES/python" -type f \( -name "*.so" -o -name "*.dylib" -o -perm -u+x \) -print0 | while IFS= read -r -d '' file; do
    file "$file" | grep -q "Mach-O" && sign "$file" 2>/dev/null || true
  done
fi
# The voice runs on MLX. PyTorch, and the libraries installed only to support it, are never needed:
# leaving them out saves about 850 MB, starts the voice faster and uses less memory.
SITE="$RES/python/lib/python3.12/site-packages"
for unused in torch sympy mpmath networkx transformers curated_transformers spacy_curated_transformers; do
  rm -rf "$SITE/$unused" "$SITE/$unused"-*.dist-info(N)
done
sign --identifier local.narrator.app "$BUNDLE"
echo "Built $BUNDLE ($(du -sh "$BUNDLE" | cut -f1))"
