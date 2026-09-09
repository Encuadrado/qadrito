#!/usr/bin/env bash
# Build, sign, notarize, and publish a QAdrito release via GitHub Releases with Sparkle.
#
# Prerequisites:
#   1. All beta DMG prerequisites (Developer ID cert, notarization profile)
#   2. Sparkle EdDSA private key at ~/.qadrito/sparkle_eddsa_private.key
#      (Generate once: ./scripts/sparkle-tools/generate_keys)
#   3. GitHub CLI (`gh`) authenticated
#   4. Updated MARKETING_VERSION and CURRENT_PROJECT_VERSION in Xcode project
#
# Usage:
#   TEAM_ID=225N4NNDYX NOTARY_PROFILE=QAdritoNotary ./scripts/make-release.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Qadrito/Qadrito.xcodeproj"
SCHEME="Qadrito"
DIST="$ROOT/dist"
ARCHIVE="$DIST/QAdrito.xcarchive"
EXPORT_DIR="$DIST/export"
APP_NAME="QAdrito"

# Version from Xcode project
VERSION=$(grep -m1 'MARKETING_VERSION' "$PROJECT/project.pbxproj" \
  | sed 's/.*= //;s/;//' | tr -d ' ' || echo "1.0")
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PROJECT/project.pbxproj" \
  | sed 's/.*= //;s/;//' | tr -d ' ' || echo "1")

DMG_NAME="QAdrito-${VERSION}"
ZIP_NAME="QAdrito-${VERSION}.zip"

if [[ -z "${TEAM_ID:-}" ]]; then
  echo "Set TEAM_ID to your Apple Team ID, e.g.:"
  echo "  TEAM_ID=225N4NNDYX $0"
  exit 1
fi

SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-$HOME/.qadrito/sparkle_eddsa_private.key}"

# Security: Ensure private key is NOT stored inside the repository
RESOLVED_KEY_PATH="$(cd "$(dirname "$SPARKLE_PRIVATE_KEY")" 2>/dev/null && pwd)/$(basename "$SPARKLE_PRIVATE_KEY")" || RESOLVED_KEY_PATH="$SPARKLE_PRIVATE_KEY"
GIT_ROOT="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || echo "")"

if [[ -n "$GIT_ROOT" ]]; then
  case "$RESOLVED_KEY_PATH" in
    "$GIT_ROOT"*)
      echo "❌ ERROR: Sparkle private key MUST NOT be stored inside the repository!"
      echo ""
      echo "   Requested path: $SPARKLE_PRIVATE_KEY"
      echo "   Resolved to:    $RESOLVED_KEY_PATH"
      echo "   Repository root: $GIT_ROOT"
      echo ""
      echo "🔒 Security requirement:"
      echo "   Private keys must be stored OUTSIDE the git repository to prevent accidental commits."
      echo ""
      echo "✅ Recommended: Use the default location (outside repo):"
      echo "   TEAM_ID=$TEAM_ID NOTARY_PROFILE=\${NOTARY_PROFILE:-} $0"
      echo ""
      echo "   Default location: ~/.qadrito/sparkle_eddsa_private.key"
      echo ""
      echo "   Or set SPARKLE_PRIVATE_KEY to another path outside the repo:"
      echo "   SPARKLE_PRIVATE_KEY=~/secure-keys/sparkle.key TEAM_ID=$TEAM_ID $0"
      exit 1
      ;;
  esac
fi

if [[ ! -f "$SPARKLE_PRIVATE_KEY" ]]; then
  echo "Sparkle EdDSA private key not found at: $SPARKLE_PRIVATE_KEY"
  echo "Generate keys first:"
  echo "  ./scripts/sparkle-keygen.sh"
  echo "  # Update INFOPLIST_KEY_SUPublicEDKey in Xcode with the public key"
  exit 1
fi

if ! command -v gh &>/dev/null; then
  echo "GitHub CLI 'gh' not found. Install: https://cli.github.com/"
  exit 1
fi

EXPORT_OPTS="$DIST/ExportOptions-DeveloperID.plist"
sed "s/TEAM_ID_HERE/${TEAM_ID}/" "$ROOT/scripts/ExportOptions-DeveloperID.plist" > "$EXPORT_OPTS"

echo "==> Release Version: $VERSION (build $BUILD)"

mkdir -p "$DIST"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
rm -f "$DIST/${DMG_NAME}.dmg" "$DIST/${ZIP_NAME}"

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
  APP="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.app' | head -1)"
fi
if [[ ! -d "$APP" ]]; then
  echo "Export produced no .app in $EXPORT_DIR"
  ls -la "$EXPORT_DIR" || true
  exit 1
fi

echo "==> Notarizing…"
NOTARY_ZIP="$DIST/QAdrito-for-notary.zip"
rm -f "$NOTARY_ZIP"
ditto -c -k --keepParent "$APP" "$NOTARY_ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "${APP_STORE_CONNECT_API_KEY_P8:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  xcrun notarytool submit "$NOTARY_ZIP" \
    --key "$APP_STORE_CONNECT_API_KEY_P8" \
    --key-id "$APP_STORE_CONNECT_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --wait
else
  echo "No notary credentials. Set NOTARY_PROFILE or App Store Connect API env vars."
  exit 1
fi

echo "==> Stapling notarization ticket…"
xcrun stapler staple "$APP"

# Create DMG
STAGING="$DIST/dmg-root"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="$DIST/${DMG_NAME}.dmg"
rm -f "$DMG"
hdiutil create -volname "QAdrito ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

# Create ZIP for Sparkle (smaller download, preferred by Sparkle)
ZIP="$DIST/${ZIP_NAME}"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

rm -f "$NOTARY_ZIP"
rm -rf "$STAGING"

echo "==> Signing update with Sparkle…"
# Locate sign_update tool from Sparkle package
SIGN_UPDATE="$ROOT/Qadrito/Qadrito.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Sparkle/bin/sign_update"
if [[ ! -f "$SIGN_UPDATE" ]]; then
  # Fallback: search in DerivedData or use a globally installed Sparkle
  SIGN_UPDATE="$(find ~/Library/Developer/Xcode/DerivedData -name sign_update | head -1)"
fi
if [[ ! -f "$SIGN_UPDATE" ]]; then
  echo "sign_update not found. Open Xcode project to resolve Sparkle package first."
  exit 1
fi

SIGNATURE=$("$SIGN_UPDATE" "$ZIP" -f "$SPARKLE_PRIVATE_KEY" \
  | sed -n 's/^sparkle:edSignature="\([^"]*\)".*/\1/p')
if [[ -z "$SIGNATURE" ]]; then
  echo "Failed to extract Sparkle EdDSA signature"
  exit 1
fi
FILESIZE=$(stat -f%z "$ZIP")
PUBDATE=$(date -u +"%a, %d %b %Y %H:%M:%S %z")

echo "==> Generating appcast.xml…"
cat > "$DIST/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>QAdrito Updates</title>
    <link>https://github.com/Encuadrado/qadrito/releases</link>
    <description>Most recent QAdrito updates</description>
    <language>en</language>
    <item>
      <title>QAdrito ${VERSION}</title>
      <link>https://github.com/Encuadrado/qadrito/releases/tag/v${VERSION}</link>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <pubDate>${PUBDATE}</pubDate>
      <enclosure
        url="https://github.com/Encuadrado/qadrito/releases/download/v${VERSION}/${ZIP_NAME}"
        length="${FILESIZE}"
        type="application/octet-stream"
        sparkle:edSignature="${SIGNATURE}" />
      <description><![CDATA[
        <h2>QAdrito ${VERSION}</h2>
        <p>See the <a href="https://github.com/Encuadrado/qadrito/releases/tag/v${VERSION}">release notes</a> for details.</p>
      ]]></description>
    </item>
  </channel>
</rss>
EOF

echo "==> Creating GitHub Release v${VERSION}…"
if gh release view "v${VERSION}" &>/dev/null; then
  echo "Release v${VERSION} already exists. Updating assets…"
  gh release upload "v${VERSION}" "$DMG" "$ZIP" "$DIST/appcast.xml" --clobber
else
  gh release create "v${VERSION}" "$DMG" "$ZIP" "$DIST/appcast.xml" \
    --title "QAdrito ${VERSION}" \
    --notes "QAdrito ${VERSION} — automatic updates enabled via Sparkle.

Download the DMG or ZIP, or let existing QAdrito installations auto-update.

**Full Changelog**: https://github.com/Encuadrado/qadrito/commits/v${VERSION}" \
    --draft
  echo ""
  echo "⚠️  Release created as DRAFT. Review and publish at:"
  echo "   https://github.com/Encuadrado/qadrito/releases/tag/v${VERSION}"
fi

echo ""
echo "✅ Release artifacts ready:"
echo "   DMG:     $DMG"
echo "   ZIP:     $ZIP"
echo "   Appcast: $DIST/appcast.xml"
echo ""
echo "Next steps:"
echo "  1. Review draft release on GitHub"
echo "  2. Publish when ready — existing QAdrito installs will auto-update"
