#!/usr/bin/env bash
# analyze.sh — the reproducible analyzer baseline for the whole repo.
#
# Runs `flutter pub get` in the repo root AND in every sub-package that has a
# pubspec.yaml, THEN runs `flutter analyze` once across the tree.
#
# WHY THIS SCRIPT EXISTS: on 2026-07-19 four agents were briefed with an
# analyzer baseline of 616 issues. The real number was 7. The other 609 were
# phantoms — `packages/net_quality` had never had `flutter pub get` run in it,
# so it had no .dart_tool/package_config.json, so every `import 'package:test/
# test.dart'` in that package resolved to nothing and the analyzer reported
# uri_does_not_exist on each one. The tree looked catastrophically broken and
# was in fact clean. A baseline that depends on undocumented local state is not
# a baseline; it is a rumor.
#
# The fix is NOT "remember to pub get first." A wrapper you still have to know a
# secret about is the same defect wearing a hat. This script establishes the
# preconditions itself, every time, so the wrong number is not reachable.
#
# The package list is DISCOVERED from the filesystem, never hardcoded — adding a
# new package under packages/ must not silently reintroduce the phantom-issue
# failure. A package added tomorrow is covered without editing this file.
#
# Usage:
#   scripts/analyze.sh              # bootstrap deps, then analyze
#   scripts/analyze.sh --no-pub-get # analyze only (fast re-run; you own the risk)
#
# Exit 0 = zero issues. Exit 1 = at least one issue, or a pub get failed.
# There is no "acceptable number of issues" here. The baseline is 0.
#
# Portable to macOS bash 3.2 (no mapfile / associative arrays).

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

RUN_PUB_GET=1
for arg in "$@"; do
  case "$arg" in
    --no-pub-get) RUN_PUB_GET=0 ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "analyze.sh: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

# --- Discover every pubspec in the repo (root + sub-packages) ----------------
# Sorted for deterministic output. Excludes build/ and ephemeral Flutter plugin
# scaffolding, which contain generated pubspecs that are not ours to resolve.
PUBSPEC_DIRS="$(
  find "$ROOT" -name pubspec.yaml -type f \
    -not -path "*/build/*" \
    -not -path "*/.dart_tool/*" \
    -not -path "*/ephemeral/*" \
    -not -path "*/.symlinks/*" \
    -print 2>/dev/null | sed 's|/pubspec.yaml$||' | sort
)"

if [ -z "$PUBSPEC_DIRS" ]; then
  echo "analyze.sh: FATAL — no pubspec.yaml found under $ROOT" >&2
  exit 1
fi

if [ "$RUN_PUB_GET" -eq 1 ]; then
  echo "==> Resolving dependencies for every package (discovered from filesystem)"
  FAILED=""
  # Word-splitting on newlines only, so paths containing spaces survive.
  OLD_IFS="$IFS"; IFS='
'
  for dir in $PUBSPEC_DIRS; do
    printf '    pub get: %s\n' "${dir#"$ROOT"/}"
    if ! (cd "$dir" && flutter pub get >/dev/null 2>&1); then
      echo "    !! FAILED: ${dir#"$ROOT"/}" >&2
      FAILED="$FAILED $dir"
    fi
  done
  IFS="$OLD_IFS"

  if [ -n "$FAILED" ]; then
    echo "" >&2
    echo "analyze.sh: FATAL — 'flutter pub get' failed in:$FAILED" >&2
    echo "Analyzing now would report phantom uri_does_not_exist issues." >&2
    echo "Refusing to produce a baseline that cannot be trusted." >&2
    exit 1
  fi
else
  echo "==> Skipping pub get (--no-pub-get); baseline is only valid if deps are current"
fi

# --- Analyze ----------------------------------------------------------------
echo "==> flutter analyze"
OUT="$(flutter analyze 2>&1)"
ANALYZE_STATUS=$?
echo "$OUT"

# Belt and braces: trust neither signal alone. `flutter analyze` exits 1 on
# info-severity issues today, but the exit code has shifted across Flutter
# versions, so we also read the reported issue count out of the output. If
# EITHER says there is a problem, this script fails.
COUNT_LINE="$(printf '%s\n' "$OUT" | grep -E '^[0-9]+ issue(s)? found' | tail -1)"
ISSUE_COUNT="$(printf '%s\n' "$COUNT_LINE" | grep -oE '^[0-9]+')"

echo ""
if [ "$ANALYZE_STATUS" -eq 0 ] && [ -z "$ISSUE_COUNT" ]; then
  echo "analyze.sh: CLEAN — 0 issues."
  exit 0
fi

if [ -n "$ISSUE_COUNT" ] && [ "$ISSUE_COUNT" -gt 0 ]; then
  echo "analyze.sh: FAIL — $ISSUE_COUNT issue(s). The baseline is 0; fix them." >&2
  exit 1
fi

if [ "$ANALYZE_STATUS" -ne 0 ]; then
  echo "analyze.sh: FAIL — flutter analyze exited $ANALYZE_STATUS." >&2
  exit 1
fi

echo "analyze.sh: CLEAN — 0 issues."
exit 0
