#!/usr/bin/env bash
# voice-guard.sh — thin wrapper around scripts/voice_guard.py.
#
# Mirrors scripts/version-guard.sh so both guards are invoked the same way from
# the Dart consistency tests, from CI, and by hand.
#
# Usage:
#   scripts/voice-guard.sh                 # scans the default shipped surfaces
#   scripts/voice-guard.sh <path> [path..] # scan explicit paths
#
# Exit 0 = clean. Exit 1 = a HARD voice rule is broken in shipped user-facing copy.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "voice-guard: FAIL — python3 not found on PATH."
  exit 1
fi

exec python3 "$ROOT/scripts/voice_guard.py" "$@"
