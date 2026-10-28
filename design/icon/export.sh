#!/usr/bin/env bash
# Regenerates every app icon PNG in the asset catalog from the SVG sources.
set -euo pipefail
cd "$(dirname "$0")"
SET=../../Theo/Resources/Assets.xcassets/AppIcon.appiconset
TMP=$(mktemp -d)
python3 make_icon.py
node render.js icon-light.svg "$TMP/light.png" 1024 icon-dark.svg "$TMP/dark.png" 1024 icon-tinted.svg "$TMP/tinted.png" 1024 \
  icon-mac.svg "$TMP/mac-1024.png" 1024 icon-mac.svg "$TMP/mac-512.png" 512 icon-mac.svg "$TMP/mac-256.png" 256 \
  icon-mac.svg "$TMP/mac-128.png" 128 icon-mac.svg "$TMP/mac-64.png" 64 icon-mac.svg "$TMP/mac-32.png" 32 icon-mac.svg "$TMP/mac-16.png" 16
mkdir -p "$SET"
python3 - "$TMP" "$SET" <<'PY'
import sys, shutil
from PIL import Image
tmp, out = sys.argv[1], sys.argv[2]
# iOS icons must be opaque.
for src, dst in [("light", "AppIcon-1024.png"), ("dark", "AppIcon-1024-dark.png"), ("tinted", "AppIcon-1024-tinted.png")]:
    im = Image.open(f"{tmp}/{src}.png").convert("RGBA")
    bg = Image.new("RGB", im.size, (0, 0, 0))
    bg.paste(im, mask=im.split()[3])
    bg.save(f"{out}/{dst}", optimize=True)
for size, names in {16: ["mac-16"], 32: ["mac-16@2x", "mac-32"], 64: ["mac-32@2x"], 128: ["mac-128"],
                    256: ["mac-128@2x", "mac-256"], 512: ["mac-256@2x", "mac-512"], 1024: ["mac-512@2x"]}.items():
    for name in names:
        shutil.copy(f"{tmp}/mac-{size}.png", f"{out}/{name}.png")
PY
cp "$TMP/light.png" ../../design/icon/preview-ios.png
cp "$TMP/mac-1024.png" ../../design/icon/preview-mac.png
rm -rf "$TMP"
echo "icons exported"
