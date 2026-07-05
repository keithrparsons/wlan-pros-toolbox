#!/usr/bin/env bash
# version-guard.sh — pre-ship check that no hardcoded app-version literal in
# shipped prose has drifted from pubspec.yaml.
#
# Thin wrapper over scripts/version_guard.py (the real scanner). Kept as a shell
# entrypoint to mirror leakage-guard.sh so both guards run the same way from a
# pre-push hook, a CI step, or the flutter test that wraps it
# (test/consistency/version_consistency_guard_test.dart).
#
# WHY: the "How this app works" guide once shipped `app v1.5.4` while the build
# was 1.7.0 — a hand-typed version rotted across releases. Guides now render
# `app v{{app_version}}` (filled at runtime from the actual package version).
# This guard fails the build if any literal app-version claim disagrees with
# pubspec, so that drift can never ship again.
#
# Usage:
#   scripts/version-guard.sh                 # scans the default prose globs
#   scripts/version-guard.sh <file> [file..] # scan explicit files
#
# Exit 0 = clean. Exit 1 = a drifted app-version literal (fix before shipping).

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "version-guard: python3 not found on PATH" >&2
  exit 1
fi

exec python3 "$ROOT/scripts/version_guard.py" "$@"
