#!/usr/bin/env bash
set -euo pipefail
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for v in A B C; do
  svg="$DIR/icon$v.svg"
  html="$DIR/_render$v.html"
  png="$DIR/icon$v-1024.png"
  small="$DIR/icon$v-80.png"
  {
    printf '<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0}svg{display:block}</style></head><body>'
    cat "$svg"
    printf '</body></html>'
  } > "$html"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --screenshot="$png" --window-size=1024,1024 "file://$html" >/dev/null 2>&1
  sips -z 80 80 "$png" --out "$small" >/dev/null 2>&1
  rm -f "$html"
  echo "rendered icon$v: $(sips -g pixelWidth -g pixelHeight "$png" | tail -2 | tr '\n' ' ')"
done
