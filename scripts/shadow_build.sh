#!/usr/bin/env bash
#
# shadow_build.sh: rebuild web, WLAN Pi web and Android from one commit and
# compare them with the artifacts that were actually released.
#
# This is a CHECK, not a release. It never uploads, deploys, publishes or
# signs with a real key, and it refuses to run if any real signing or store
# credential file is present on this machine (see refuse_if_keys below).
#
# Usage:
#   scripts/shadow_build.sh <commit> [options]
#
# Options:
#   --ref-web DIR     released web folder to compare with, e.g. the /app
#                     folder of a read-only clone of the site repo
#   --ref-pi PATH|URL released WLAN Pi bundle (wlanpi-toolbox-web-bundle.tar.gz,
#                     a local path or a public release download URL)
#   --out DIR         work folder (default: /tmp/shadow-<short commit>)
#   --no-android      skip the Android app bundle
#
# Builds, matching the release commands:
#   web      flutter build web --release --base-href /app/   (toolbox.wlanpros.com/app/)
#   wlanpi   flutter build web --release --base-href /       (.github/workflows/wlanpi-web-bundle.yml)
#   android  flutter build appbundle --release                (debug signed here by design)
#
# Exit 0 = every comparison that ran found only expected differences.
# Exit 1 = a real difference, a failed build, or a refused run.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_FLUTTER="$(sed -n "s/.*flutter-version: '\([0-9.]*\)'.*/\1/p" "$ROOT/.github/workflows/ci.yml" | head -1)"

COMMIT=""; REF_WEB=""; REF_PI=""; OUT=""; ANDROID=1
while [ $# -gt 0 ]; do
  case "$1" in
    --ref-web) REF_WEB="$2"; shift 2 ;;
    --ref-pi) REF_PI="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --no-android) ANDROID=0; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) if [ -z "$COMMIT" ]; then COMMIT="$1"; else echo "Unknown argument: $1" >&2; exit 1; fi; shift ;;
  esac
done
[ -n "$COMMIT" ] || { echo "Usage: scripts/shadow_build.sh <commit> [options]" >&2; exit 1; }

# ── Refuse to run near real keys ────────────────────────────────────────────
# A shadow build must not be able to produce a really-signed artifact, so it
# refuses when any real signing or store credential is reachable.
refuse_if_keys() {
  local found=()
  local f
  for f in \
    "$ROOT/android/key.properties" \
    "$ROOT/android/fastlane/play-service-account.json" \
    "$ROOT/ios/fastlane/.env" \
    "$ROOT/ios/ExportOptions.plist" \
    "$HOME/.wpt-keys" \
    "$HOME/.appstoreconnect"; do
    [ -e "$f" ] && found+=("$f")
  done
  while IFS= read -r f; do found+=("$f"); done < <(
    find "$ROOT" "$HOME" -maxdepth 4 \
      \( -path '*/build' -o -path '*/.dart_tool' -o -path '*/.pub-cache' -o -path '*/.android' -o -path '*/sdk' \) -prune -o \
      -type f \( -name '*.jks' -o -name '*.keystore' -o -name '*.p8' -o -name '*.p12' -o -name '*.pfx' -o -name '*.mobileprovision' \) \
      -print 2>/dev/null)
  if [ ${#found[@]} -gt 0 ]; then
    echo "REFUSED: real signing or store credential files are present:" >&2
    printf '  %s\n' "${found[@]}" >&2
    echo "Run shadow builds only on a machine that has no release keys." >&2
    exit 1
  fi
}
refuse_if_keys

command -v flutter >/dev/null || { echo "flutter is not on PATH" >&2; exit 1; }
HAVE_FLUTTER="$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9.]*\).*/\1/p' | head -1)"
if [ -n "$CI_FLUTTER" ] && [ "$HAVE_FLUTTER" != "$CI_FLUTTER" ]; then
  echo "WARNING: Flutter $HAVE_FLUTTER here, CI pins $CI_FLUTTER. Output will differ." >&2
fi

SHORT="$(git -C "$ROOT" rev-parse --short=8 "$COMMIT^{commit}")"
OUT="${OUT:-/tmp/shadow-$SHORT}"
SRC="$OUT/src"
mkdir -p "$OUT"
if [ ! -d "$SRC" ]; then
  git -C "$ROOT" worktree add --detach "$SRC" "$COMMIT" >/dev/null
fi
refuse_if_keys   # the new worktree must not carry keys either

SUMMARY="$OUT/summary.txt"
: > "$SUMMARY"
say() { echo "$*" | tee -a "$SUMMARY"; }
STATUS=0

say "Shadow build of $SHORT ($(git -C "$SRC" log -1 --format='%ci %s' | cut -c1-90))"
say "Flutter $HAVE_FLUTTER (CI pins ${CI_FLUTTER:-unknown})"
say "Version in pubspec: $(sed -n 's/^version: //p' "$SRC/pubspec.yaml")"
say ""

build_web() {  # $1 = base href, $2 = output folder name
  ( cd "$SRC" && flutter build web --release --base-href "$1" ) > "$OUT/build-$2.log" 2>&1 \
    || { say "$2: BUILD FAILED, see $OUT/build-$2.log"; return 1; }
  rm -rf "${OUT:?}/$2"
  cp -R "$SRC/build/web" "$OUT/$2"
}

compare_web() {  # $1 = label, $2 = reference dir, $3 = shadow dir
  say "── $1 ──"
  if python3 "$ROOT/scripts/shadow_webdiff.py" "$2" "$3" | tee -a "$SUMMARY"; then :; else STATUS=1; fi
  say ""
}

# ── Web (toolbox.wlanpros.com/app/) ─────────────────────────────────────────
if build_web /app/ web; then
  if [ -n "$REF_WEB" ]; then compare_web "web /app/" "$REF_WEB" "$OUT/web"
  else say "web: built, no --ref-web given, not compared"; say ""; fi
else STATUS=1; fi

# ── WLAN Pi web bundle ──────────────────────────────────────────────────────
if build_web / wlanpi; then
  if [ -n "$REF_PI" ]; then
    mkdir -p "$OUT/ref-pi"
    if [[ "$REF_PI" =~ ^https:// ]]; then
      curl -sSfL "$REF_PI" -o "$OUT/ref-pi.tar.gz"   # public read-only download
      REF_PI="$OUT/ref-pi.tar.gz"
    fi
    tar -xzf "$REF_PI" -C "$OUT/ref-pi"
    [ -f "$OUT/ref-pi/web/BUNDLE-INFO.txt" ] && sed 's/^/  reference /' "$OUT/ref-pi/web/BUNDLE-INFO.txt" | tee -a "$SUMMARY"
    compare_web "WLAN Pi web /" "$OUT/ref-pi/web" "$OUT/wlanpi"
  else say "wlanpi: built, no --ref-pi given, not compared"; say ""; fi
else STATUS=1; fi

# ── Android app bundle (debug signed by design) ─────────────────────────────
if [ "$ANDROID" = 1 ]; then
  say "── Android ──"
  if ( cd "$SRC" && flutter build appbundle --release ) > "$OUT/build-android.log" 2>&1; then
    AAB="$SRC/build/app/outputs/bundle/release/app-release.aab"
    SIGNER="$(keytool -printcert -jarfile "$AAB" 2>/dev/null | sed -n 's/^Owner: //p' | head -1)"
    if [ "$SIGNER" != "C=US, O=Android, CN=Android Debug" ]; then
      say "android: STOP, the bundle is not debug signed ($SIGNER). Delete it; it must not exist."
      rm -f "$AAB"; exit 1
    fi
    cp "$AAB" "$OUT/app-release-debugsigned.aab"
    say "android: built, $(du -h "$AAB" | cut -f1), signer: Android Debug (expected, cannot be uploaded)"
    PUB="$(sed -n 's/^version: //p' "$SRC/pubspec.yaml")"
    VC="${PUB#*+}"
    if [ -n "${BUNDLETOOL_JAR:-}" ] && [ -f "$BUNDLETOOL_JAR" ]; then
      java -jar "$BUNDLETOOL_JAR" dump manifest --bundle="$AAB" > "$OUT/android-manifest.xml"
      MV="$(grep -oE 'versionCode="[0-9]+"' "$OUT/android-manifest.xml" | head -1 | tr -dc 0-9)"
      MN="$(grep -oE 'versionName="[^"]+"' "$OUT/android-manifest.xml" | head -1 | cut -d'"' -f2)"
      say "android: versionCode $MV, versionName $MN (pubspec $PUB)"
      if [ "$MV" != "$VC" ] || [ "$MN" != "${PUB%+*}" ]; then
        say "android: REAL version mismatch with pubspec"; STATUS=1
      fi
      say "android: permissions:"
      grep -oE 'uses-permission[^>]*name="[^"]+"' "$OUT/android-manifest.xml" | sed 's/.*name="/    /;s/"$//' | sort | tee -a "$SUMMARY"
    else
      say "android: set BUNDLETOOL_JAR to a bundletool jar to read versionCode and permissions"
    fi
    if [ -f "$SRC/android/fastlane/metadata/android/en-US/changelogs/$VC.txt" ]; then
      say "android: What's New for versionCode $VC exists ($(wc -c < "$SRC/android/fastlane/metadata/android/en-US/changelogs/$VC.txt") chars, Play limit 500)"
    else
      say "android: REAL gap, no changelogs/$VC.txt, Play would ship with no What's New"; STATUS=1
    fi
  else
    say "android: BUILD FAILED, see $OUT/build-android.log"; STATUS=1
  fi
  say ""
fi

say "Summary written to $SUMMARY. Nothing was uploaded or signed with a real key."
say "Remove the worktree when done: git worktree remove --force $SRC"
exit $STATUS
