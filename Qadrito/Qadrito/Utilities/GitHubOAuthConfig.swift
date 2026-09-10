import Foundation

enum GitHubOAuthConfig {
    /// GitHub OAuth App Client ID
    /// Encuadrado Qadrito OAuth App (Device Flow enabled)
    /// Configured at: https://github.com/settings/developers
    static let clientID = "Ov23li72xEcbYo1gIhQ5"
    
    /// OAuth scopes required for Qadrito
    /// - repo: Full repository access (required for reading private org PRs; OAuth Apps
    ///   do not support granular read-only repo permissions like GitHub Apps)
    /// - read:user: Read user profile information (for displaying username)
    /// - read:org: Read organization membership and team data (for org PR searches)
    /// - offline_access: Requests expiring access tokens (8 hours) and refresh tokens
    ///   (6 months) for automatic token rotation. See: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#expiring-access-tokens
    ///
    /// Note: The `repo` scope grants broad read/write access. GitHub Apps would allow
    /// more granular permissions (e.g., "Pull requests: Read-only"), but migration
    /// would require infrastructure changes. See: https://docs.github.com/en/apps
    static let scopes = "repo read:user read:org offline_access"
}
