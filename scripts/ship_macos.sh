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

echo "==> Packaging .dmg"
rm -f "$DMG"
hdiutil create -volname "WLAN Pros Toolbox" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "==> Verifying Gatekeeper acceptance"
spctl -a -vvv -t install "$APP" || true

echo ""
echo "==> Done. Send testers this file:"
echo "    $ROOT/$DMG"
