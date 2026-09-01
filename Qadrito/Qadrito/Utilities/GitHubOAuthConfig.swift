import Foundation

enum GitHubOAuthConfig {
    /// GitHub OAuth App Client ID
    /// Encuadrado QAdrito OAuth App (Device Flow enabled)
    /// Configured at: https://github.com/settings/developers
    static let clientID = "Ov23li72xEcbYo1gIhQ5"
    
    /// OAuth scopes required for QAdrito
    /// - repo: Access to private repositories and PR details
    /// - read:user: Read user profile information (for displaying username)
    /// - read:org: Read organization membership and team data
    static let scopes = "repo read:user read:org"
}
