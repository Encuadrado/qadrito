# QAdrito internal beta (.dmg)

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
