# QAdrito

A native macOS desktop app that brings the Encuadrado engineering PR review queue to your Mac. QAdrito shows you all the pull requests waiting for your review, with smart filtering and sorting to help you prioritize your work.

## Features

- 🔍 **Review Queue**: See all PRs in your organization that are waiting for your review
- 📊 **Smart Sorting**: View all PRs, the easiest 5, or the oldest 5
- 🔎 **Powerful Filters**: Filter by author (GitHub username or Slack name) and repository
- 📚 **Stack Detection**: Automatically groups consecutive PRs from the same author/repo
- 💾 **Offline Cache**: Last fetch is cached so you can browse PRs without an internet connection
- 🔒 **Secure**: GitHub PAT stored in macOS Keychain, never in plaintext
- 🇨🇱 **Santiago Time**: All dates and times displayed in America/Santiago timezone

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later (for building)
- GitHub Personal Access Token with appropriate scopes

## GitHub Personal Access Token Setup

You'll need a GitHub Personal Access Token (PAT) to use QAdrito. Here's how to create one:

1. Go to [GitHub Settings > Developer settings > Personal access tokens > Tokens (classic)](https://github.com/settings/tokens)
2. Click "Generate new token" > "Generate new token (classic)"
3. Give your token a descriptive name (e.g., "QAdrito macOS App")
4. Select the following scopes:
   - **`repo`** (Full control of private repositories)
   - **`read:org`** (Read org and team membership, read org projects)
5. Click "Generate token"
6. **Copy the token immediately** (you won't be able to see it again!)

### Required Scopes

- **`repo`**: Allows the app to read PR details, comments, and mergeable status
- **`read:org`**: Allows the app to search for PRs across your organization

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

When you first launch QAdrito, you'll need to configure your settings:

1. Click the **Settings** (gear) icon in the toolbar
2. Enter your **GitHub Personal Access Token** (see above for how to create one)
3. Enter your **GitHub Login** (your GitHub username, e.g., `cnovoab`)
4. Enter your **Organization** (default: `Encuadrado`)
5. (Optional) Add a **Slack User Map** JSON to map GitHub usernames to Slack names
6. Click **Save**

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

## Using QAdrito

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

QAdrito follows these rules to match the Encuadrado PR standup experience:

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

QAdrito follows the MVVM (Model-View-ViewModel) pattern:

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

- **GitHub PAT**: Stored securely in macOS Keychain using the Security framework
- **No plaintext secrets**: The PAT is never stored in UserDefaults or files
- **App Sandbox**: The app runs in a sandbox with network access only
- **HTTPS only**: All GitHub API calls use HTTPS

## Troubleshooting

### "Unauthorized" Error

- Check that your GitHub PAT is correct
- Verify your PAT has the required scopes (`repo` and `read:org`)
- Try regenerating your PAT if it's expired

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
