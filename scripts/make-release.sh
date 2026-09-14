#!/usr/bin/env bash
# Build, sign, notarize, and publish a QAdrito release via GitHub Releases with Sparkle.
#
# Prerequisites:
#   1. All beta DMG prerequisites (Developer ID cert, notarization profile)
#   2. Sparkle EdDSA private key at ~/.qadrito/sparkle_eddsa_private.key
#      (Generate once: ./scripts/sparkle-tools/generate_keys)
#   3. GitHub CLI (`gh`) authenticated
#   4. A version to ship: either pass --new-version to bump it automatically, or set
#      MARKETING_VERSION and CURRENT_PROJECT_VERSION in the Xcode project by hand
#
# Usage:
#   TEAM_ID=225N4NNDYX NOTARY_PROFILE=QAdritoNotary ./scripts/make-release.sh [options]
#
# Options:
#   --new-version[=LEVEL]  Bump the version before building instead of reusing whatever
#                          is in the Xcode project. LEVEL is patch (default), minor, or
#                          major; the build number always increments by 1.
#                          Requires a clean working tree, commits the bump, and pushes it
#                          so the release tag lands on the commit that actually built.
#   --no-push              With --new-version, commit the bump but do not push it. The
#                          build still runs, but publishing is skipped: the release tag
#                          would be cut from the remote branch, which lacks the bump.
#   --force                Allow re-uploading assets over an already published release.
#   -h, --help             Show this help.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Qadrito/Qadrito.xcodeproj"
SCHEME="Qadrito"
DIST="$ROOT/dist"
ARCHIVE="$DIST/QAdrito.xcarchive"
EXPORT_DIR="$DIST/export"
APP_NAME="QAdrito"

PBXPROJ="$PROJECT/project.pbxproj"

BUMP_LEVEL=""
DO_PUSH=1
FORCE=0
# Set when --no-push leaves the bump commit local; publishing is skipped in that case.
BUMP_UNPUSHED=0

usage() {
  cat <<'USAGE'
Build, sign, notarize, and publish a QAdrito release.

Usage:
  TEAM_ID=<id> NOTARY_PROFILE=<profile> ./scripts/make-release.sh [options]

Options:
  --new-version[=LEVEL]  Bump the version before building instead of reusing whatever
                         is in the Xcode project. LEVEL is patch (default), minor, or
                         major; the build number always increments by 1.
                         Requires a clean working tree, commits the bump, and pushes it
                         so the release tag lands on the commit that actually built.
  --no-push              With --new-version, commit the bump but do not push it. The
                         build still runs, but publishing is skipped: the release tag
                         would be cut from the remote branch, which lacks the bump.
  --force                Allow re-uploading assets over an already published release.
  -h, --help             Show this help.
USAGE
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --new-version)        BUMP_LEVEL="patch" ;;
    --new-version=*)
      BUMP_LEVEL="${1#*=}"
      # An empty value would fall through the validation below and silently skip the
      # bump, rebuilding the version already in the project instead of the documented
      # patch default. Make it an error rather than a surprise.
      if [[ -z "$BUMP_LEVEL" ]]; then
        echo "--new-version= needs a level: patch, minor, or major." >&2
        echo "Pass --new-version on its own for the patch default." >&2
        exit 1
      fi
      ;;
    --no-push)            DO_PUSH=0 ;;
    --force)              FORCE=1 ;;
    -h|--help)            usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 1 ;;
  esac
  shift
done

case "$BUMP_LEVEL" in
  ""|patch|minor|major) ;;
  *) echo "--new-version must be patch, minor, or major (got: $BUMP_LEVEL)" >&2; exit 1 ;;
esac

# Preflight before anything with side effects: --new-version commits and pushes a
# version bump, and failing these checks afterwards would leave that bump stranded
# on a release that never got built.
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

# Read every MARKETING_VERSION / CURRENT_PROJECT_VERSION in the project, not just the
# first. The four build configurations must agree, or the version in the release name
# may not be the one the Release configuration actually built.
read_project_setting() {
  grep "$1" "$PBXPROJ" | sed 's/.*= //;s/;//' | tr -d ' ' | sort -u
}

require_single_value() {
  local name="$1" values="$2"
  if [[ -z "$values" ]]; then
    echo "❌ $name not found in $PBXPROJ" >&2
    exit 1
  fi
  if [[ $(wc -l <<< "$values") -ne 1 ]]; then
    echo "❌ Build configurations disagree on $name:" >&2
    sed 's/^/     /' <<< "$values" >&2
    echo "   Make them match before releasing." >&2
    exit 1
  fi
}

VERSION=$(read_project_setting 'MARKETING_VERSION')
BUILD=$(read_project_setting 'CURRENT_PROJECT_VERSION')
require_single_value "MARKETING_VERSION" "$VERSION"
require_single_value "CURRENT_PROJECT_VERSION" "$BUILD"

if [[ -n "$BUMP_LEVEL" ]]; then
  if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "❌ Cannot bump non-numeric MARKETING_VERSION: $VERSION" >&2
    exit 1
  fi
  if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
    echo "❌ Cannot bump non-numeric CURRENT_PROJECT_VERSION: $BUILD" >&2
    exit 1
  fi

  IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"
  MINOR="${MINOR:-0}"
  PATCH="${PATCH:-0}"
  case "$BUMP_LEVEL" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
  esac

  NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
  NEW_BUILD=$((BUILD + 1))

  # Fail before the ~10 minute build rather than after it.
  if git -C "$ROOT" rev-parse "v${NEW_VERSION}" &>/dev/null \
     || gh release view "v${NEW_VERSION}" &>/dev/null; then
    echo "❌ v${NEW_VERSION} already exists. Bump past it or release it by hand." >&2
    exit 1
  fi
  if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo "❌ --new-version needs a clean working tree so the bump commit contains only" >&2
    echo "   the version change. Commit or stash your work first." >&2
    exit 1
  fi

  echo "==> Bumping $VERSION ($BUILD) → $NEW_VERSION ($NEW_BUILD)"
  /usr/bin/sed -i '' \
    -e "s/^\([[:space:]]*\)MARKETING_VERSION = .*;/\1MARKETING_VERSION = ${NEW_VERSION};/" \
    -e "s/^\([[:space:]]*\)CURRENT_PROJECT_VERSION = .*;/\1CURRENT_PROJECT_VERSION = ${NEW_BUILD};/" \
    "$PBXPROJ"

  WROTE_VERSION=$(read_project_setting 'MARKETING_VERSION')
  WROTE_BUILD=$(read_project_setting 'CURRENT_PROJECT_VERSION')
  if [[ "$WROTE_VERSION" != "$NEW_VERSION" || "$WROTE_BUILD" != "$NEW_BUILD" ]]; then
    echo "❌ Version rewrite did not apply cleanly. Reverting." >&2
    git -C "$ROOT" checkout -- "$PBXPROJ"
    exit 1
  fi

  VERSION="$NEW_VERSION"
  BUILD="$NEW_BUILD"

  # The release tag is cut from the remote default branch, so the bump has to be
  # committed and pushed or the tag would point at the previous version's code.
  git -C "$ROOT" add "$PBXPROJ"
  git -C "$ROOT" commit -m "Bump version to ${VERSION} (${BUILD})"
  if [[ "$DO_PUSH" -eq 1 ]]; then
    echo "==> Pushing bump commit…"
    git -C "$ROOT" push
  else
    BUMP_UNPUSHED=1
  fi
fi

DMG_NAME="QAdrito-${VERSION}"
ZIP_NAME="QAdrito-${VERSION}.zip"

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

if [[ "$BUMP_UNPUSHED" -eq 1 ]]; then
  # `gh release create` tags the remote default branch, which does not have the bump
  # commit. Publishing now would point v${VERSION} at its predecessor's code while the
  # uploaded build came from the bump. Artifacts are built and left for inspection.
  echo ""
  echo "✅ Built ${VERSION} (${BUILD}), but not released — --no-push kept the bump local."
  echo ""
  echo "   DMG:     $DMG"
  echo "   ZIP:     $ZIP"
  echo "   Appcast: $DIST/appcast.xml"
  echo ""
  echo "   To publish, push the bump and re-run without --new-version:"
  echo "     git push"
  echo "     TEAM_ID=$TEAM_ID NOTARY_PROFILE=\${NOTARY_PROFILE:-} $0"
  exit 0
fi

echo "==> Creating GitHub Release v${VERSION}…"
if gh release view "v${VERSION}" &>/dev/null; then
  IS_DRAFT=$(gh release view "v${VERSION}" --json isDraft -q '.isDraft' 2>/dev/null || echo "false")
  if [[ "$IS_DRAFT" != "true" && "$FORCE" -ne 1 ]]; then
    echo "❌ v${VERSION} is already published. Replacing its assets would hand a different" >&2
    echo "   binary to everyone who already downloaded it, and Sparkle keys updates off" >&2
    echo "   the build number (${BUILD}), so existing installs would not see a new version." >&2
    echo "" >&2
    echo "   Release a new version:  $0 --new-version" >&2
    echo "   Or overwrite anyway:    $0 --force" >&2
    exit 1
  fi
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
