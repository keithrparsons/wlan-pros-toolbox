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

echo "==> Restoring automatic signing"
restore_signing
trap - EXIT

echo "==> Uploading to TestFlight"
( cd ios && fastlane upload )

echo ""
echo "==> Done. Build ${BUILD_NUMBER} is uploading."
echo "    After Apple processing, it appears in TestFlight on your iPhone + iPad automatically."
