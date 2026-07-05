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
CI_PAT='by the team|by our team|reviewed by the team|keith-(reviewed|approved|confirmed)|per a keith decision|transcribed by the team|verified and expanded by|voice-gated|voice-lint|cold-eyes|rendered verbatim|the treatment'

# Case-sensitive: internal machinery. Agent names are matched whole-word to limit
# false positives; SOP/GL/WS refs, wikilinks, repo paths, and session-log mentions
# are hard tells. \[\[(?!:) matches wikilinks but not POSIX [[: character classes.
CS_PAT='SOP-[0-9]|GL-[0-9]|WS-[0-9]|\[\[[^:]|session-log|Deliverables/|Team Knowledge|myPKA|/Developer/|(^|[^A-Za-z])(Larry|Penn|Pax|Nolan|Mack|Silas|Felix|Vera|Iris|Charta|Pixel|Vex)([^A-Za-z]|$)'

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

# Stage 2: shipped Dart string literals. The asset scan above cannot reach
# lib/data/*.dart (typed const datasets like the LED / vendor-model decoders) or
# lib/screens/**, and grepping raw .dart would false-positive on every provenance
# COMMENT. leakage_guard_dart.py strips comments and scans only string-literal
# content — the strings that actually ship. This is the surface the original guard
# missed (the decoder ", Pax <date>." citations lived here, not in tool_help.json).
dart_rc=0
if command -v python3 >/dev/null 2>&1 && [ -f "$ROOT/scripts/leakage_guard_dart.py" ]; then
  DART_TARGETS=""
  [ -d "$ROOT/lib/data" ] && DART_TARGETS="$DART_TARGETS $ROOT/lib/data"
  [ -d "$ROOT/lib/screens" ] && DART_TARGETS="$DART_TARGETS $ROOT/lib/screens"
  if [ -n "$DART_TARGETS" ]; then
    echo ""
    python3 "$ROOT/scripts/leakage_guard_dart.py" $DART_TARGETS || dart_rc=1
  fi
fi

echo ""
if [ "$hits" -gt 0 ] || [ "$dart_rc" -ne 0 ]; then
  if [ "$hits" -gt 0 ]; then
    echo "LEAKAGE GUARD: FAIL — $hits asset file(s) with internal references (scanned $scanned)."
  fi
  [ "$dart_rc" -ne 0 ] && echo "LEAKAGE GUARD: FAIL — internal references in shipped Dart string content (see above)."
  echo "Remove team/process/agent/SOP machinery; keep authorship (Keith Parsons / WLAN Pros)."
  echo "SOP-061 Check 1. A FAIL does not ship."
  exit 1
fi
echo "LEAKAGE GUARD: clean — no internal references in $scanned shipped asset files or scanned Dart strings."
exit 0
