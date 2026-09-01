import Foundation

enum GitHubOAuthConfig {
    /// GitHub OAuth App Client ID
    /// To obtain:
    /// 1. Go to https://github.com/settings/developers
    /// 2. Click "OAuth Apps" → "New OAuth App" (or register a new application)
    /// 3. Enable "Device Flow" if the option is available in the UI
    /// 4. Set any callback URL (e.g., http://localhost:8080/callback) - not used for device flow
    /// 5. Copy the Client ID here
    static let clientID = "YOUR_GITHUB_OAUTH_CLIENT_ID"
    
    /// OAuth scopes required for QAdrito
    /// - repo: Access to private repositories and PR details
    /// - read:user: Read user profile information (for displaying username)
    /// - read:org: Read organization membership and team data
    static let scopes = "repo read:user read:org"
}
