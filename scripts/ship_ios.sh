#!/usr/bin/env bash
#
# ship_ios.sh — build a new signed iOS build of WLAN Pros Toolbox and upload it
# to TestFlight. The internal "Field Testers" group has access to all builds,
# so Keith's iPhone and iPad receive each new build automatically after Apple
# finishes processing (usually 5-15 min). No Xcode, no website steps.
#
# Usage (from anywhere in the repo):
#     ./scripts/ship_ios.sh
#
# One-time prerequisites (already done as of 2026-06-01):
#   - App Store Connect API key at ~/.appstoreconnect/private_keys/ + ios/fastlane/.env
#   - Distribution cert + "com.wlanpros.wlanProsToolbox AppStore" profile installed
#   - App record + Field Testers internal group exist in App Store Connect
#
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PBXPROJ="ios/Runner.xcodeproj/project.pbxproj"
PROFILE="com.wlanpros.wlanProsToolbox AppStore"
TEAM="MNMCTY7YZT"
BUNDLE="com.wlanpros.wlanProsToolbox"
# Timestamp build number guarantees a unique, monotonically increasing value,
# which TestFlight requires for every upload under the same version.
BUILD_NUMBER="$(date +%Y%m%d%H%M)"

# Always put the project's signing back to Automatic, even if the build fails,
# so local device runs in Xcode are unaffected.
restore_signing() { git checkout -- "$PBXPROJ" 2>/dev/null || true; }
trap restore_signing EXIT

echo "==> Build ${BUILD_NUMBER}: switching Runner to manual distribution signing"
( cd ios && fastlane run update_code_signing_settings \
    use_automatic_signing:false \
    path:"Runner.xcodeproj" \
    team_id:"${TEAM}" \
    code_sign_identity:"Apple Distribution" \
    profile_name:"${PROFILE}" \
    bundle_identifier:"${BUNDLE}" \
    targets:"Runner" )

echo "==> Building signed App Store IPA (Flutter, clean CocoaPods env)"
# Run Flutter directly (NOT inside fastlane) so CocoaPods uses the correct Ruby.
flutter build ipa --release \
  --build-number="${BUILD_NUMBER}" \
  --export-options-plist=ios/ExportOptions.plist

# ---------------------------------------------------------------------------
# THE IPA IS VERIFIED, NOT ASSUMED.  Added 2026-07-28 after this script shipped
# a SIX-DAY-OLD binary.
#
# `flutter build ipa` EXITS 0 EVEN WHEN THE EXPORT FAILS.  On 2026-07-28 it
# printed "Encountered error while creating the IPA: error: exportArchive Copy
# failed", returned 0, and left the previous run's IPA sitting in
# build/ios/ipa/.  `set -e` cannot see a zero exit, so the script walked on and
# fastlane uploaded the stale file.  App Store Connect happened to reject it as
# a duplicate build number, which is the ONLY reason it was caught — had the
# stale build number been lower than the live one, a 22 July binary would have
# reached TestFlight labelled 1.8.5 and nothing would have said otherwise.
#
# A missing-file check alone is NOT sufficient: the failure mode is a file that
# EXISTS and is WRONG.  So assert the build number inside the IPA matches the
# one we just asked for.
# ---------------------------------------------------------------------------
IPA="build/ios/ipa/wlan_pros_toolbox.ipa"
[ -f "$IPA" ] || { echo "FATAL: $IPA does not exist — the export failed." >&2; exit 1; }

BUILT_NUMBER="$(unzip -p "$IPA" "Payload/Runner.app/Info.plist" \
  | plutil -convert xml1 -o - - \
  | awk '/<key>CFBundleVersion<\/key>/{getline; gsub(/.*<string>|<\/string>.*/,""); print; exit}')"

if [ "$BUILT_NUMBER" != "$BUILD_NUMBER" ]; then
  echo "" >&2
  echo "FATAL: the IPA on disk is NOT the build this run produced." >&2
  echo "  asked for : ${BUILD_NUMBER}" >&2
  echo "  IPA holds : ${BUILT_NUMBER}" >&2
  echo "" >&2
  echo "The export failed and left a previous run's IPA in place. Nothing has" >&2
  echo "been uploaded. Export it by hand, which is known to work when the" >&2
  echo "Flutter wrapper fails:" >&2
  echo "" >&2
  echo "  xcodebuild -exportArchive \\" >&2
  echo "    -archivePath build/ios/archive/Runner.xcarchive \\" >&2
  echo "    -exportOptionsPlist ios/ExportOptions.plist \\" >&2
  echo "    -exportPath build/ios/ipa" >&2
  echo "" >&2
  exit 1
fi
echo "==> IPA verified: version ${BUILT_NUMBER} is this run's build"

echo "==> Restoring automatic signing"
restore_signing
trap - EXIT

echo "==> Uploading to TestFlight"
( cd ios && fastlane upload )

echo ""
echo "==> Done. Build ${BUILD_NUMBER} is uploading."
echo "    After Apple processing, it appears in TestFlight on your iPhone + iPad automatically."
