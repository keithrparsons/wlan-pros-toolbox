#!/usr/bin/env bash
# leakage-guard.sh — pre-ship scan for internal myPKA references in public Toolbox content.
#
# Operationalizes SOP-061 (Pre-Ship Content Gate), Check 1: nothing about HOW the
# content was made may appear in shipped output. Scans human-readable content that
# ships to users (bundled assets + the built web output) for internal team/process
# language and internal machinery (agent names, SOP/GL/WS refs, wikilinks).
#
# KEEPS authorship on purpose — "Keith Parsons" and "WLAN Pros" are the byline, not
# the machinery. The rule: a reader may know WHO stands behind the work, never HOW
# the sausage was made.
#
# Usage:
#   scripts/leakage-guard.sh                 # scans assets/ (+ build/web if present)
#   scripts/leakage-guard.sh <dir> [dir...]  # scan explicit paths
#
# Exit 0 = clean. Exit 1 = internal references found (fix before shipping).
# Wire as a pre-push hook or run before pushing the web build to the public repo.
#
# Portable to macOS bash 3.2 (no mapfile / associative arrays).

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -gt 0 ]; then
  TARGETS="$*"
else
  TARGETS="$ROOT/assets"
  [ -d "$ROOT/build/web" ] && TARGETS="$TARGETS $ROOT/build/web"
fi

# Case-insensitive: team / process language + internal review stamps (the phrases
# that actually leaked into shipped help + field-manual content).
CI_PAT='by the team|by our team|reviewed by the team|keith-(reviewed|approved|confirmed)|per a keith decision|transcribed by the team|verified and expanded by'

# Case-sensitive: internal machinery. Agent names are matched whole-word to limit
# false positives; SOP/GL/WS refs, wikilinks, and session-log mentions are hard tells.
CS_PAT='SOP-[0-9]|GL-[0-9]|WS-[0-9]|\[\[|session-log|(^|[^A-Za-z])(Larry|Penn|Pax|Nolan|Mack|Silas|Felix|Vera|Iris|Charta|Pixel|Vex)([^A-Za-z]|$)'

hits=0
scanned=0

while IFS= read -r f; do
  scanned=$((scanned + 1))
  m="$( { grep -nEi "$CI_PAT" "$f"; grep -nE "$CS_PAT" "$f"; } 2>/dev/null )"
  if [ -n "$m" ]; then
    echo "── ${f#"$ROOT"/}"
    printf '%s\n' "$m" | sed 's/^/   /'
    hits=$((hits + 1))
  fi
done <<EOF
$(find $TARGETS -type f \( -name '*.json' -o -name '*.md' -o -name '*.txt' -o -name '*.html' -o -name '*.arb' \) 2>/dev/null)
EOF

echo ""
if [ "$hits" -gt 0 ]; then
  echo "LEAKAGE GUARD: FAIL — $hits file(s) with internal references (scanned $scanned)."
  echo "Remove team/process/agent/SOP machinery; keep authorship (Keith Parsons / WLAN Pros)."
  echo "SOP-061 Check 1. A FAIL does not ship."
  exit 1
fi
echo "LEAKAGE GUARD: clean — no internal references in $scanned shipped content files."
exit 0
