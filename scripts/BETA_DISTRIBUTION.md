# QAdrito Distribution Guide

This document covers both internal beta distribution and production releases with automatic updates via Sparkle.

---

## One-time Apple setup (you)

1. Enroll / use an **Apple Developer Program** team (paid).
2. Open **Xcode → Settings → Accounts** → add your Apple ID → select the **Encuadrado** (or personal) team.
3. Click **Manage Certificates…** → **+** → **Developer ID Application**.  
   Confirm in Terminal: `security find-identity -v -p codesigning` shows `Developer ID Application: …`.
4. Copy your **Team ID** (developer.apple.com → Membership details, 10 characters).
5. Create an [app-specific password](https://appleid.apple.com) for notarization, then:

```bash
xcrun notarytool store-credentials QAdritoNotary \
  --apple-id YOUR_APPLE_ID@email.com \
  --team-id YOUR_TEAM_ID \
  --password app-specific-password
```

6. (Optional but recommended) Set `DEVELOPMENT_TEAM` in the Xcode project to that Team ID so day-to-day archives pick it up.

## Build the DMG

```bash
cd ~/encuadrado/qadrito
TEAM_ID=YOUR_TEAM_ID NOTARY_PROFILE=QAdritoNotary ./scripts/make-beta-dmg.sh
```

Output: `dist/QAdrito-Beta-<version>.dmg`

## Share with the team

- Upload the `.dmg` to Slack / Google Drive / GitHub Release (private).
- Teammates: open DMG → drag **QAdrito** to **Applications** → launch.
- If Gatekeeper complains on an old build, they can right-click → Open once; notarized builds should open cleanly.

## GitHub OAuth

Device-flow OAuth works for every user; they sign in with their own GitHub account. No PAT distribution needed.

---

## Sparkle Automatic Updates Setup

QAdrito uses [Sparkle 2](https://sparkle-project.org/) for automatic updates via GitHub Releases.

### One-time Sparkle key generation

**⚠️ Do this ONCE. The private key must remain secret and be backed up securely.**

1. Generate EdDSA keypair:
   ```bash
   ./scripts/sparkle-keygen.sh
   ```

2. The script will:
   - Save the **private key** to `~/.qadrito/sparkle_eddsa_private.key` (mode 600)
   - Display the **public key** to add to Xcode

3. **Update the public key in Xcode:**
   - Open `Qadrito.xcodeproj` in Xcode
   - Select the **Qadrito** target → **Build Settings** tab
   - Search for `SUPublicEDKey`
   - Replace `REPLACE_WITH_GENERATED_PUBLIC_KEY` with the public key from step 2

   Alternatively, edit `Qadrito/Qadrito.xcodeproj/project.pbxproj` and replace:
   ```
   INFOPLIST_KEY_SUPublicEDKey = "REPLACE_WITH_GENERATED_PUBLIC_KEY";
   ```
   with:
   ```
   INFOPLIST_KEY_SUPublicEDKey = "edXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
   ```

4. **Backup the private key securely:**
   - Store in 1Password, Keychain, or another secure credential manager
   - Path: `~/.qadrito/sparkle_eddsa_private.key`
   - **Never commit this key to git** (already in `.gitignore`)

### Publishing a Release

Once keys are configured:

```bash
TEAM_ID=225N4NNDYX NOTARY_PROFILE=QAdritoNotary ./scripts/make-release.sh
```

This will:
1. Build and archive the app
2. Sign with Developer ID
3. Notarize with Apple
4. Create both DMG and ZIP
5. Sign the ZIP with Sparkle private key
6. Generate `appcast.xml` with version, signature, and download URL
7. Create a **draft** GitHub Release with all assets

The release is created as a **draft** so you can review it before publishing. Once published:
- Existing QAdrito installs will auto-check and offer the update
- New users can download the DMG manually

### Appcast Feed URL

Configured in Xcode build settings:
```
INFOPLIST_KEY_SUFeedURL = "https://github.com/Encuadrado/qadrito/releases/latest/download/appcast.xml"
```

This points to the `appcast.xml` attached to the **latest** GitHub Release. When you publish a new release with an updated `appcast.xml`, all existing installs will detect it.

### Version Numbering

Before running `make-release.sh`, update version numbers in Xcode:
- **MARKETING_VERSION** (e.g., `1.1.0`) — user-facing version
- **CURRENT_PROJECT_VERSION** (e.g., `2`) — build number (must increment)

The script reads these from `project.pbxproj` automatically.

---

## Beta Distribution (pre-Sparkle)

For internal testing before publishing to GitHub Releases, use the beta DMG workflow:
