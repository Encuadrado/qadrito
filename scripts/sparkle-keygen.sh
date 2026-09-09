#!/usr/bin/env bash
# Generate Sparkle EdDSA keypair for signing updates
#
# Usage:
#   ./scripts/sparkle-keygen.sh
#
# This will:
#   1. Generate a new EdDSA keypair
#   2. Save the private key to ~/.qadrito/sparkle_eddsa_private.key
#   3. Display the public key to add to Xcode build settings
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Find generate_keys tool from Sparkle package
GENERATE_KEYS="$ROOT/Qadrito/Qadrito.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Sparkle/bin/generate_keys"

if [[ ! -f "$GENERATE_KEYS" ]]; then
  # Try DerivedData
  GENERATE_KEYS="$(find ~/Library/Developer/Xcode/DerivedData -name generate_keys 2>/dev/null | head -1)"
fi

if [[ ! -f "$GENERATE_KEYS" ]]; then
  echo "❌ generate_keys tool not found."
  echo ""
  echo "To generate keys:"
  echo "  1. Open Qadrito.xcodeproj in Xcode"
  echo "  2. Wait for Swift Package dependencies to resolve"
  echo "  3. Run this script again, or manually run:"
  echo "     <DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
  exit 1
fi

echo "==> Generating Sparkle EdDSA keypair…"
KEYS=$("$GENERATE_KEYS")

PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | sed 's/Private key: //')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | sed 's/Public key: //')

if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
  echo "Failed to generate keys"
  exit 1
fi

PRIVATE_KEY_PATH="${SPARKLE_PRIVATE_KEY:-$HOME/.qadrito/sparkle_eddsa_private.key}"
mkdir -p "$(dirname "$PRIVATE_KEY_PATH")"
echo "$PRIVATE_KEY" > "$PRIVATE_KEY_PATH"
chmod 600 "$PRIVATE_KEY_PATH"

echo ""
echo "✅ Keys generated successfully!"
echo ""
echo "📝 Private key saved to:"
echo "   $PRIVATE_KEY_PATH"
echo ""
echo "⚠️  KEEP THIS SAFE! Backup to 1Password or secure location."
echo ""
echo "🔑 Public key:"
echo "   $PUBLIC_KEY"
echo ""
echo "📋 Next steps:"
echo "  1. Update Xcode build settings:"
echo "     Open Qadrito.xcodeproj in Xcode → select Qadrito target → Build Settings"
echo "     Search for 'SUPublicEDKey' and replace REPLACE_WITH_GENERATED_PUBLIC_KEY with:"
echo "     $PUBLIC_KEY"
echo ""
echo "  2. Or update project.pbxproj directly:"
echo "     Replace INFOPLIST_KEY_SUPublicEDKey = \"REPLACE_WITH_GENERATED_PUBLIC_KEY\";"
echo "     with INFOPLIST_KEY_SUPublicEDKey = \"$PUBLIC_KEY\";"
echo ""
