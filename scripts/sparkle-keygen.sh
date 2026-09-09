#!/usr/bin/env bash
# Generate Sparkle EdDSA keypair for signing updates
#
# Usage:
#   ./scripts/sparkle-keygen.sh
#
# This will:
#   1. Ensure an EdDSA keypair exists in the login Keychain (generate if needed)
#   2. Export the private key to ~/.qadrito/sparkle_eddsa_private.key via generate_keys -x
#   3. Display the public key to add to Xcode build settings
#
# Note: Sparkle does NOT print the private key on stdout. Always use -x to export it.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Find generate_keys tool from Sparkle package
GENERATE_KEYS="$ROOT/Qadrito/Qadrito.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Sparkle/bin/generate_keys"

if [[ ! -f "$GENERATE_KEYS" ]]; then
  # Try DerivedData / SPM artifacts
  GENERATE_KEYS="$(find ~/Library/Developer/Xcode/DerivedData -name generate_keys -type f 2>/dev/null | head -1 || true)"
fi

if [[ -z "${GENERATE_KEYS:-}" || ! -f "$GENERATE_KEYS" ]]; then
  echo "❌ generate_keys tool not found."
  echo ""
  echo "To generate keys:"
  echo "  1. Open Qadrito.xcodeproj in Xcode"
  echo "  2. Wait for Swift Package dependencies to resolve"
  echo "  3. Run this script again, or manually run:"
  echo "     <DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
  exit 1
fi

PRIVATE_KEY_PATH="${SPARKLE_PRIVATE_KEY:-$HOME/.qadrito/sparkle_eddsa_private.key}"
mkdir -p "$(dirname "$PRIVATE_KEY_PATH")"

parse_public_key() {
  local output="$1"
  local key=""
  # Documented Info.plist-style output: <string>BASE64</string>
  key=$(printf '%s\n' "$output" | sed -n 's/.*<string>\([^<]*\)<\/string>.*/\1/p' | head -1)
  if [[ -z "$key" ]]; then
    # -p mode may print bare base64
    key=$(printf '%s\n' "$output" | grep -E '^[A-Za-z0-9+/=]{43,44}$' | head -1 || true)
  fi
  printf '%s' "$key"
}

PUBLIC_KEY=""

if [[ -f "$PRIVATE_KEY_PATH" ]]; then
  echo "==> Private key already exists at $PRIVATE_KEY_PATH — reusing (not regenerating)."
  # Ensure Keychain has the key so we can print the matching public key.
  "$GENERATE_KEYS" -f "$PRIVATE_KEY_PATH" >/dev/null 2>&1 || true
  KEYS=$("$GENERATE_KEYS" -p 2>&1) || KEYS=$("$GENERATE_KEYS" 2>&1)
  PUBLIC_KEY=$(parse_public_key "$KEYS")
else
  echo "==> Ensuring Sparkle EdDSA keypair exists in Keychain…"
  # Default mode generates (if needed) and prints public-key instructions. Private key is NOT on stdout.
  KEYS=$("$GENERATE_KEYS")
  PUBLIC_KEY=$(parse_public_key "$KEYS")

  echo "==> Exporting private key with generate_keys -x to $PRIVATE_KEY_PATH…"
  "$GENERATE_KEYS" -x "$PRIVATE_KEY_PATH"
fi

if [[ ! -f "$PRIVATE_KEY_PATH" ]]; then
  echo "Failed to create private key at $PRIVATE_KEY_PATH"
  exit 1
fi

chmod 600 "$PRIVATE_KEY_PATH"

if [[ -z "$PUBLIC_KEY" ]]; then
  # Final attempt: print existing public key
  KEYS=$("$GENERATE_KEYS" -p 2>&1) || KEYS=$("$GENERATE_KEYS" 2>&1)
  PUBLIC_KEY=$(parse_public_key "$KEYS")
fi

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "Failed to parse public key from generate_keys output:"
  echo "$KEYS"
  exit 1
fi

echo ""
echo "✅ Keys ready!"
echo ""
echo "📝 Private key saved to:"
echo "   $PRIVATE_KEY_PATH"
echo ""
echo "⚠️  KEEP THIS SAFE! Backup to 1Password or secure location. Never commit it."
echo ""
echo "🔑 Public key:"
echo "   $PUBLIC_KEY"
echo ""
echo "📋 Next steps:"
echo "  1. Update Xcode build settings:"
echo "     Open Qadrito.xcodeproj in Xcode → select Qadrito target → Build Settings"
echo "     Search for 'SUPublicEDKey' and set INFOPLIST_KEY_SUPublicEDKey to:"
echo "     $PUBLIC_KEY"
echo ""
echo "  2. Or update project.pbxproj directly:"
echo "     Replace INFOPLIST_KEY_SUPublicEDKey = \"REPLACE_WITH_GENERATED_PUBLIC_KEY\";"
echo "     with INFOPLIST_KEY_SUPublicEDKey = \"$PUBLIC_KEY\";"
echo ""
