#!/usr/bin/env bash
# Build a notarized Developer ID .dmg of QAdrito for internal beta.
# Prerequisites:
#   1. Apple Developer Program membership
#   2. Xcode → Settings → Accounts → add Apple ID → manage certificates →
#      "Developer ID Application" (and install it)
#   3. Export: TEAM_ID=XXXXXXXX  (10-char Team ID from developer.apple.com → Membership)
#   4. Notary key: either
#        - Xcode is signed into the team (notarytool can use keychain profile), or
#        - APP_STORE_CONNECT_API_KEY_P8 / KEY_ID / ISSUER_ID env vars
#
# Usage:
#   TEAM_ID=ABCDE12345 ./scripts/make-beta-dmg.sh
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=QAdritoNotary ./scripts/make-beta-dmg.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Qadrito/Qadrito.xcodeproj"
SCHEME="Qadrito"
DIST="$ROOT/dist"
ARCHIVE="$DIST/QAdrito.xcarchive"
EXPORT_DIR="$DIST/export"
APP_NAME="QAdrito"
DMG_NAME="QAdrito-Beta"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$ROOT/Qadrito/Qadrito/Info.plist" 2>/dev/null || echo "1.0")"
# Prefer MARKETING_VERSION from xcode if Info.plist missing
if [[ "$VERSION" == "1.0" ]]; then
  VERSION=$(grep -m1 'MARKETING_VERSION' "$ROOT/Qadrito/Qadrito.xcodeproj/project.pbxproj" \
    | sed 's/.*= //;s/;//' | tr -d ' ' || echo "1.0")
fi

if [[ -z "${TEAM_ID:-}" ]]; then
  echo "Set TEAM_ID to your 10-character Apple Team ID, e.g.:"
  echo "  TEAM_ID=ABCDE12345 $0"
  exit 1
fi

EXPORT_OPTS="$DIST/ExportOptions-DeveloperID.plist"
sed "s/TEAM_ID_HERE/${TEAM_ID}/" "$ROOT/scripts/ExportOptions-DeveloperID.plist" > "$EXPORT_OPTS"

echo "==> Checking Developer ID identity…"
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "No 'Developer ID Application' identity found in Keychain."
  echo "In Xcode: Settings → Accounts → [your team] → Manage Certificates → + → Developer ID Application"
  exit 1
fi

mkdir -p "$DIST"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
rm -f "$DIST/${DMG_NAME}-"*.dmg

echo "==> Archiving Release…"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates

echo "==> Exporting Developer ID app…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -allowProvisioningUpdates

APP="$EXPORT_DIR/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
  # Target product name may be QAdrito
  APP="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.app' | head -1)"
fi
if [[ ! -d "$APP" ]]; then
  echo "Export produced no .app in $EXPORT_DIR"
  ls -la "$EXPORT_DIR" || true
  exit 1
fi

echo "==> Notarizing…"
# Zip for notarytool
ZIP="$DIST/QAdrito-for-notary.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "${APP_STORE_CONNECT_API_KEY_P8:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  xcrun notarytool submit "$ZIP" \
    --key "$APP_STORE_CONNECT_API_KEY_P8" \
    --key-id "$APP_STORE_CONNECT_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --wait
else
  echo "No notary credentials."
  echo "One-time setup (recommended):"
  echo "  xcrun notarytool store-credentials QAdritoNotary \\"
  echo "    --apple-id YOUR_APPLE_ID@email.com \\"
  echo "    --team-id $TEAM_ID \\"
  echo "    --password <app-specific-password>"
  echo "Then re-run with: NOTARY_PROFILE=QAdritoNotary TEAM_ID=$TEAM_ID $0"
  exit 1
fi

echo "==> Stapling notarization ticket…"
xcrun stapler staple "$APP"

STAGING="$DIST/dmg-root"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="$DIST/${DMG_NAME}-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "QAdrito ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

# Clean staging zip used only for notary
rm -f "$ZIP"
rm -rf "$STAGING"

echo ""
echo "✅ Ready for internal beta:"
echo "   $DMG"
echo "Share that file (Slack/Drive). Teammates drag QAdrito → Applications."
