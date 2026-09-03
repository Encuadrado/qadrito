# Qadrito

A native macOS desktop app that brings the Encuadrado engineering PR review queue to your Mac. Qadrito shows you all the pull requests waiting for your review, with smart filtering and sorting to help you prioritize your work.

## Features

- 🔍 **Review Queue**: See all PRs in your organization that are waiting for your review
- 📊 **Smart Sorting**: View all PRs, the easiest 5, or the oldest 5
- 🔎 **Powerful Filters**: Filter by author (GitHub username or Slack name) and repository
- 📚 **Stack Detection**: Automatically groups consecutive PRs from the same author/repo
- 💾 **Offline Cache**: Last fetch is cached so you can browse PRs without an internet connection
- 🔒 **Secure**: OAuth token stored in macOS Keychain, never in plaintext
- 🇨🇱 **Santiago Time**: All dates and times displayed in America/Santiago timezone

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later (for building)
- GitHub OAuth App (Client ID required)

## GitHub OAuth App Setup

Qadrito uses OAuth device flow for secure authentication. Before building the app, you need to create a GitHub OAuth App:

### Creating the OAuth App

1. Go to [GitHub Settings > Developer settings > OAuth Apps](https://github.com/settings/developers)
2. Click **"New OAuth App"** (or "Register a new application")
3. Fill in the application details:
   - **Application name**: `Qadrito` (or your preferred name)
   - **Homepage URL**: `https://github.com/Encuadrado/qadrito` (or your fork)
   - **Authorization callback URL**: `http://localhost:8080/callback` (required by GitHub but not used for device flow)
   - **Enable Device Flow**: Check this option if available in the UI
4. Click **"Register application"**
5. On the app page, **copy the Client ID**
6. **Important**: Do NOT generate a client secret (device flow doesn't need it)

### Configuring the App

After creating the OAuth App, paste your Client ID into the app's config file:

1. Open `Qadrito/Qadrito/Utilities/GitHubOAuthConfig.swift`
2. Replace `YOUR_GITHUB_OAUTH_CLIENT_ID` with your actual Client ID:
   ```swift
   static let clientID = "Iv1.a1b2c3d4e5f6g7h8"  // Your actual Client ID
   ```
3. Save the file

### OAuth Scopes

Qadrito requests the following scopes during sign-in:
- **`repo`**: Full repository access (read and write)
- **`read:user`**: Read user profile information
- **`read:org`**: Read organization membership for PR searches

**Why `repo` scope is required:** GitHub OAuth Apps do not support granular read-only repository permissions. To read pull requests from private repositories in your organization, the full `repo` scope is required. This grants both read and write access to repositories, which is broader than ideal.

**Future improvement:** Migrating to a GitHub App would allow more granular permissions (e.g., "Pull requests: Read-only" without write access). This would follow the principle of least privilege but requires infrastructure changes beyond the OAuth device flow. See [GitHub Apps documentation](https://docs.github.com/en/apps) for details.

## Building and Running

### Open in Xcode

1. Clone this repository:
   ```bash
   git clone https://github.com/Encuadrado/qadrito.git
   cd qadrito/Qadrito
   ```

2. Open the Xcode project:
   ```bash
   open Qadrito.xcodeproj
   ```

3. In Xcode, select your development team:
   - Click on the "Qadrito" project in the navigator
   - Select the "Qadrito" target
   - In the "Signing & Capabilities" tab, select your team from the dropdown

4. Build and run:
   - Press `Cmd+R` or click the Play button
   - The app will launch automatically

### Build from Command Line

You can also build the app using `xcodebuild`:

```bash
cd Qadrito
xcodebuild -project Qadrito.xcodeproj -scheme Qadrito -configuration Release build
```

The built app will be in `build/Release/Qadrito.app`.

## First Launch Setup

When you first launch Qadrito:

1. Click **"Sign in with GitHub"** on the welcome screen
2. The app will show you a verification code and open GitHub in your browser
3. Enter the code on GitHub to authorize the app
4. Once authorized, you'll see your PR review queue
5. (Optional) Click the **Settings** icon to configure:
   - **Organization**: Default is `Encuadrado`
   - **Slack User Map**: JSON mapping GitHub logins to Slack names for easier filtering

### Slack User Map (Optional)

The Slack User Map allows you to filter PRs by Slack nickname. It's a JSON object mapping GitHub usernames to Slack user info:

```json
{
  "cnovoab": {
    "slackUserId": "U123ABC456",
    "slackName": "Claudio"
  },
  "other-github-user": {
    "slackUserId": "U789DEF012",
    "slackName": "Other Name"
  }
}
```

With this map, you can filter by "Claudio" instead of having to remember "cnovoab".

## Using Qadrito

### View Modes

Use the segmented control in the toolbar to switch between views:

- **All**: Shows all PRs waiting for your review
- **Easiest 5**: Shows the 5 smallest PRs (by files changed, then lines changed, then age)
- **Oldest 5**: Shows the 5 oldest PRs (by creation date)

### Filters

Filters are combinable and work with all view modes:

#### Author Filter

Filter PRs to show only those authored by a specific person:

- Enter a GitHub username (e.g., `cnovoab`)
- Enter a partial username (e.g., `cnovo`)
- Enter a Slack name (e.g., `Claudio`) if you've configured the Slack User Map
- Matching is case-insensitive and supports partial matches

#### Repository Filter

Filter PRs to show only those from a specific repository:

- Enter a short repo name (e.g., `web`, `dania`, `mobile`)
- Enter a full repo name (e.g., `encuadrado-web`)
- Matching is case-insensitive and supports partial matches

**Repo Short Names:**
- `encuadrado-web` → `web`
- `encuadrado-dania-chat-agent` → `dania`
- `mobile_app_encuadrado` → `mobile`
- `encuadrado-professional-home` → `professional-home`
- `encuadrado-customer-public` → `customer-public`
- `encuadrado-client-home` → `client-home`
- `encuadrado-profiles` → `profiles`
- `encuadrado-center-profiles` → `center-profiles`
- `encuadrado-components` → `components`
- `docs` → `docs`
- `encuadrado-isapres` → `isapres`
- `encuadrado-client-facing-views` → `client-facing-views`
- `encuadrado-nextjs` → `nextjs`

### Combining Filters

You can combine view modes and filters:

- **Easiest 5 + Author "cnovo"**: Shows the 5 easiest PRs authored by cnovoab
- **Oldest 5 + Repo "web"**: Shows the 5 oldest PRs in the web repo
- **All + Author "claudio" + Repo "dania"**: Shows all PRs authored by Claudio in the dania repo

### PR Display

Each PR shows:

- **Short name**: `repo#number` (e.g., `web#123`) or `repo#number (N)` for stacks
- **Author**: GitHub username
- **Age**: How long since the PR was created (in minutes, hours, or days)
- **Title**: First two lines of the PR title

Click any PR to open it in your browser.

### Stack Detection

When an author has multiple consecutive PRs in the same repository (e.g., PR #100, #101, #102), they're automatically grouped into a "stack". The display shows the tip of the stack with the total count:

- `web#102 (3)` means PR #102 is the tip of a 3-PR stack

### Refresh

Click the **Refresh** button (or press `Cmd+R` in the future) to fetch the latest PRs from GitHub. The app caches the last successful fetch, so you can still browse PRs when offline.

## Data Rules

Qadrito follows these rules to match the Encuadrado PR standup experience:

- **Waiting on you**: PRs are fetched using GitHub search: `org:Encuadrado is:open is:pr review-requested:<your-login>`
- **Age**: Calculated from the PR's `created_at` timestamp
- **Sorting**: 
  - Closing soon (≥30 days old) first
  - Sole reviewer (you're the only requested reviewer) next
  - Then oldest first
  - Bot PRs (mintlify, dependabot, etc.) last
- **Stacks**: Same author + same repo + consecutive PR numbers → shown as tip + count
- **Easiest**: Smallest by files changed, then by total lines (+/-), then by age
- **Oldest**: Sorted by creation date

## Architecture

Qadrito follows the MVVM (Model-View-ViewModel) pattern:

- **Models** (`Models.swift`): Data structures for PRs, settings, and cache
- **Views** (`ContentView.swift`, `SettingsView.swift`, `PRRowView.swift`): SwiftUI views
- **ViewModels** (`PRViewModel.swift`): Business logic and state management
- **Services** (`GitHubClient.swift`, `CacheManager.swift`): API and persistence
- **Utilities** (`KeychainManager.swift`, `PRFilters.swift`, `PRSorting.swift`, `PRStackDetector.swift`): Helpers

## Testing

The project includes comprehensive unit tests for the core filtering, sorting, and stack detection logic:

- `PRSortingTests.swift`: Tests for PR sorting (closing soon, sole reviewer, oldest, bot handling)
- `PRStackDetectorTests.swift`: Tests for stack detection and grouping
- `PRFiltersTests.swift`: Tests for author and repo filtering, easiest/oldest selection

To run tests:

```bash
# In Xcode
Press Cmd+U

# From command line
cd Qadrito
xcodebuild test -project Qadrito.xcodeproj -scheme Qadrito -destination 'platform=macOS'
```

## Security

- **OAuth Token**: Stored securely in macOS Keychain using the Security framework
- **No client secret**: Device flow doesn't require embedding secrets in the app binary
- **No plaintext tokens**: OAuth token never stored in UserDefaults or files
- **App Sandbox**: The app runs in a sandbox with network access only
- **HTTPS only**: All GitHub API calls use HTTPS

## Troubleshooting

### "Unauthorized" or Authentication Errors

- Verify you've set up the OAuth App correctly on GitHub
- Check that you pasted the correct Client ID in `GitHubOAuthConfig.swift`
- Make sure "Enable Device Flow" is enabled for your OAuth App (if the option exists)
- Try signing out and signing in again

### "Rate Limited" Error

- GitHub has rate limits on API calls
- Wait a few minutes and try again
- With authentication, you get 5,000 requests per hour

### No PRs Showing

- Click **Refresh** to fetch the latest PRs
- Check your filters (clear author and repo filters)
- Verify you're in the "All" view mode (not "Easiest 5" or "Oldest 5")
- Ensure there are actually PRs requesting your review in the organization

### Build Errors

- Make sure you're using Xcode 15.0 or later
- Verify your deployment target is macOS 14.0 or later
- Select a development team in Signing & Capabilities

## Contributing

This is an internal Encuadrado tool. If you have suggestions or find bugs, please open an issue or submit a pull request.

## License

Copyright © 2026 Encuadrado. All rights reserved.
