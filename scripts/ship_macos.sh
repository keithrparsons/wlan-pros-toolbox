#!/usr/bin/env bash
#
# ship_macos.sh — build, sign, notarize, staple, and package the macOS WLAN Pros
# Toolbox into a distributable .dmg for beta testers (notarized DIRECT
# distribution, NOT the App Store / TestFlight). Testers double-click the .dmg
# and the app opens — Gatekeeper trusts notarized Developer ID apps.
#
# Signed WITHOUT the App Sandbox (so all tools work, including Traceroute that
# the sandbox blocks) but WITH the hardened runtime (required for notarization).
#
# Usage (from anywhere in the repo):
#     ./scripts/ship_macos.sh
# Then send testers the .dmg path it prints.
#
# One-time prerequisite (done 2026-06-01): a "Developer ID Application" cert +
# private key in the login keychain. Only the Account Holder can create it
# (Xcode -> Settings -> Accounts -> Manage Certificates -> +, or a portal CSR).
#
set -euo pipefail

export PATH="/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ID="Developer ID Application: Keith Parsons (MNMCTY7YZT)"
APP="build/macos/Build/Products/Release/wlan_pros_toolbox.app"
ZIP="build/macos/wlan_pros_toolbox_notarize.zip"
DMG="build/macos/WLAN-Pros-Toolbox.dmg"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_DS2DH6R6P4.p8"
KEY_ID="DS2DH6R6P4"
ISSUER="a5ea7e74-39c4-442b-a431-fcf98e0cc5fd"

echo "==> Building macOS release"
flutter build macos --release

echo "==> Signing (Developer ID, hardened runtime, no sandbox)"
# Inside-out: nested frameworks first, then the app bundle.
for fw in "$APP"/Contents/Frameworks/*.framework; do
  codesign --force --options runtime --timestamp --sign "$ID" "$fw"
done
codesign --force --options runtime --timestamp --sign "$ID" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Notarizing (waits for Apple, usually a few minutes)"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" --wait

echo "==> Stapling the notarization ticket"
xcrun stapler staple "$APP"

echo "==> Packaging .dmg (staged with a drag-to-Applications alias)"
rm -f "$DMG"
# Stage the signed+stapled .app next to an /Applications alias so the mounted
# volume shows the usual "drag the app onto Applications" install layout. ditto
# preserves the code signature and the stapled notarization ticket; hdiutil then
# packs the whole staging folder instead of the bare .app.
STAGE="build/macos/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "WLAN Pros Toolbox" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> Verifying Gatekeeper acceptance"
spctl -a -vvv -t install "$APP" || true

echo ""
echo "==> Done. Built + notarized .dmg (with drag-to-Applications alias):"
echo "    $ROOT/$DMG"
echo ""
echo "    Beta testers: send them this file directly."
echo "    PUBLIC SITE DOWNLOAD (Matthew's workflow, 2026-07-07): do NOT commit the .dmg."
echo "    Publish it as a GitHub Release on the toolbox-wlanpros-site repo — the site"
echo "    download link auto-picks the newest release, no page edits:"
echo "      gh release create v<VERSION> \"$ROOT/$DMG\" --title v<VERSION> --notes \"...\""
echo "    (the .dmg is already named WLAN-Pros-Toolbox.dmg, exactly as required). See that repo's README."
