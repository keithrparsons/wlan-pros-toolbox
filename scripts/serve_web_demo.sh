#!/usr/bin/env bash
#
# serve_web_demo.sh - Run the web-only WLAN Pros Toolbox locally in a browser.
#
# Serves the calculators + reference web build at http://localhost:8088
# with the correct MIME types (.wasm, .mjs) that Flutter web and the
# self-hosted pdf.js engine need.
#
# Usage:
#   ./scripts/serve_web_demo.sh          # serve (builds first if needed)
#   ./scripts/serve_web_demo.sh --build  # force a fresh build, then serve
#
# Stop it with Ctrl-C.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$REPO/build/web"
PORT=8088

cd "$REPO"

# Rebuild if asked, or if the build is missing (e.g. after `flutter clean`).
if [[ "${1:-}" == "--build" || ! -f "$WEB_DIR/index.html" ]]; then
  echo "Building web (calculators + reference)..."
  flutter build web --release
fi

echo
echo "WLAN Pros Toolbox (web) -> http://localhost:$PORT"
echo "Press Ctrl-C to stop."
echo

python3 -c "
import http.server, mimetypes, functools
mimetypes.add_type('text/javascript', '.mjs')
mimetypes.add_type('text/javascript', '.js')
mimetypes.add_type('application/wasm', '.wasm')
H = functools.partial(http.server.SimpleHTTPRequestHandler, directory='$WEB_DIR')
http.server.test(HandlerClass=H, port=$PORT, bind='127.0.0.1')
"
