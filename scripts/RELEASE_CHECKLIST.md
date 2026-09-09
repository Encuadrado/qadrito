# QAdrito Release Checklist

Use this checklist when preparing a new production release with automatic updates.

## Prerequisites (one-time setup)

- [ ] Apple Developer ID certificate installed
- [ ] Notarization credentials configured (`QAdritoNotary` keychain profile)
- [ ] Sparkle EdDSA keypair generated (run `./scripts/sparkle-keygen.sh`)
- [ ] Public key added to Xcode build settings (`INFOPLIST_KEY_SUPublicEDKey`)
- [ ] Private key backed up securely (1Password, Keychain, etc.)
- [ ] GitHub CLI (`gh`) installed and authenticated

## Pre-release

- [ ] All features tested locally
- [ ] Code reviewed and merged to main (or release branch)
- [ ] Update `MARKETING_VERSION` in Xcode (e.g., `1.1.0`)
- [ ] Update `CURRENT_PROJECT_VERSION` in Xcode (must be higher than previous)
- [ ] Update any release notes or CHANGELOG if maintained
- [ ] Commit version bump: `git commit -am "Bump version to X.Y.Z"`
- [ ] Push to GitHub: `git push origin main`

## Build and Release

1. **Run the release script:**
   ```bash
   TEAM_ID=225N4NNDYX NOTARY_PROFILE=QAdritoNotary ./scripts/make-release.sh
   ```

2. **Script will:**
   - Archive and sign the app
   - Notarize with Apple
   - Create DMG and ZIP
   - Sign ZIP with Sparkle
   - Generate `appcast.xml`
   - Create a **draft** GitHub Release

3. **Review the draft release:**
   - Go to https://github.com/Encuadrado/qadrito/releases
   - Check version number, assets (DMG, ZIP, appcast.xml)
   - Edit release notes if needed
   - **Publish the release**

## Post-release

- [ ] Verify release is public on GitHub
- [ ] Test download links work
- [ ] Test appcast URL: `https://github.com/Encuadrado/qadrito/releases/latest/download/appcast.xml`
- [ ] Test automatic update on an existing QAdrito install:
  - Open QAdrito → Settings → Check for Updates
  - Or wait for automatic check (happens on launch)
- [ ] Share release announcement in Slack/team channel

## Troubleshooting

### Notarization fails
- Check notarization credentials: `xcrun notarytool history --keychain-profile QAdritoNotary`
- Verify Team ID matches: `225N4NNDYX`
- Ensure app is signed with Developer ID (not Ad Hoc or Development)

### Sparkle signature mismatch
- Verify private key path: `~/.qadrito/sparkle_eddsa_private.key`
- Ensure public key in Xcode matches the private key
- Re-generate keys if needed (requires re-releasing all future versions)

### Update not detected by existing installs
- Verify `appcast.xml` is accessible: curl the feed URL
- Check `CURRENT_PROJECT_VERSION` is higher than previous
- Ensure release is published (not draft)
- Check Sparkle logs in Console.app (filter for "QAdrito")

### DMG not mountable / app won't open
- Ensure notarization and stapling completed successfully
- Check Gatekeeper: `spctl -a -vvv -t exec /path/to/QAdrito.app`
- Users may need to right-click → Open on first launch (Gatekeeper bypass)

## Version History

Keep track of releases for reference:

| Version | Build | Date       | Notes                              |
|---------|-------|------------|------------------------------------|
| 1.0     | 1     | 2026-XX-XX | Initial release with Sparkle setup |

