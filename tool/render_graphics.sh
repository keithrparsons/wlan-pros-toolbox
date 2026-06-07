#!/bin/zsh
# Render each redrawn SVG to a PNG on the #222222 review surface via headless Chrome.
# Usage: render_graphics.sh <outdir> <svg...>
set -e
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="$1"; shift
TMP=$(mktemp -d)
for svg in "$@"; do
  name=$(basename "$svg" .svg)
  # read viewBox dims
  dims=$(grep -o 'viewBox="0 0 [0-9.]* [0-9.]*"' "$svg" | head -1 | sed -E 's/viewBox="0 0 ([0-9.]+) ([0-9.]+)"/\1 \2/')
  w=${dims% *}; h=${dims#* }
  w=${w%.*}; h=${h%.*}
  svgcontent=$(cat "$svg")
  cat > "$TMP/$name.html" <<HTML
<!doctype html><html><head><meta charset="utf8"><style>
html,body{margin:0;padding:0}
.band{width:${w}px;height:${h}px;background:#222222;display:flex;align-items:center;justify-content:center}
svg{width:${w}px;height:${h}px;display:block}
</style></head><body><div class="band">${svgcontent}</div></body></html>
HTML
  "$CHROME" --headless --disable-gpu --no-sandbox --force-device-scale-factor=3 \
    --hide-scrollbars --default-background-color=00000000 \
    --window-size=${w},${h} \
    --screenshot="$OUT/$name.png" "file://$TMP/$name.html" >/dev/null 2>&1
  echo "rendered $name.png (${w}x${h})"
done
rm -rf "$TMP"
