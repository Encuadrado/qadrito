import Foundation
import AppKit

enum GitHubOAuthError: Error {
    case invalidResponse
    case authorizationPending
    case slowDown
    case accessDenied
    case expiredToken
    case networkError(Error)
}

struct DeviceCodeResponse: Codable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let verificationUriComplete: String?
    let expiresIn: Int
    let interval: Int
    
    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case verificationUriComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

struct AccessTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    /// Optional: GitHub omits this on some token responses, and a missing field would
    /// otherwise turn a successful refresh into a decode failure.
    let scope: String?
    let refreshToken: String?
    let expiresIn: Int?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct GitHubUser: Codable {
    let login: String
    let name: String?
}

/// Error payload GitHub returns from `https://github.com/login/oauth/access_token`.
///
/// Important: that endpoint answers **HTTP 200 for failures too**, with the reason only in
/// the body (e.g. `{"error":"bad_refresh_token", ...}`). Checking the status code alone
/// silently mistakes every rejection for a malformed success response.
private struct OAuthErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

/// Result of a refresh attempt. The distinction matters: a dead refresh token can only be
/// fixed by running the device flow again, while a network blip should leave the stored
/// credentials alone so the next request can retry.
enum TokenRefreshOutcome {
    /// Refresh succeeded; the new access token has already been persisted.
    case success(String)
    /// GitHub refused the stored credentials. They have been cleared from the Keychain and
    /// the user has to sign in again.
    case needsReauthentication(reason: String)
    /// Refresh could not be completed right now. Stored credentials are untouched.
    case transientFailure(reason: String)
}

/// Actor to coordinate single-flight token refresh across concurrent callers
actor RefreshCoordinator {
    private var inFlightRefresh: Task<TokenRefreshOutcome, Never>?

    func refresh() async -> TokenRefreshOutcome {
        if let existing = inFlightRefresh {
            return await existing.value
        }

        let task = Task<TokenRefreshOutcome, Never> {
            let result = await performRefresh()
            return result
        }

        inFlightRefresh = task
        let result = await task.value
        inFlightRefresh = nil
        return result
    }

    /// GitHub error codes that mean the stored refresh token can never work again.
    /// Anything else (5xx, rate limiting, transport errors) is treated as retryable.
    private static let fatalErrorCodes: Set<String> = [
        "bad_refresh_token",
        "bad_verification_code",
        "invalid_grant",
        "unauthorized_client",
        "incorrect_client_credentials",
        "unsupported_grant_type",
        "access_denied"
    ]

    private func performRefresh() async -> TokenRefreshOutcome {
        let keychainManager = KeychainManager.shared

        guard let refreshToken = keychainManager.load(key: "githubRefreshToken"),
              !refreshToken.isEmpty else {
            // Either this OAuth App does not issue refresh tokens, or a previous rotation
            // lost it. Either way the access token cannot be renewed — re-auth is the only path.
            NSLog("QAdrito: No refresh token available; re-authentication required")
            Self.clearStoredTokens()
            return .needsReauthentication(reason: "No refresh token stored")
        }

        guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
            NSLog("QAdrito: Invalid refresh token URL")
            return .transientFailure(reason: "Invalid refresh token URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // No client_secret: this is a public client, and GitHub exempts device-flow tokens
        // from the secret requirement on the refresh grant.
        let body = [
            "client_id": GitHubOAuthConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            NSLog("QAdrito: Failed to serialize refresh token request body")
            return .transientFailure(reason: "Failed to serialize refresh request")
        }

        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("QAdrito: Invalid response from refresh token endpoint")
                return .transientFailure(reason: "Invalid response from GitHub")
            }

            // Check the body before the status code: GitHub returns 200 with an error payload.
            if let payload = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data),
               let errorCode = payload.error {
                let description = payload.errorDescription ?? errorCode
                NSLog("QAdrito: GitHub refused the token refresh (%@): %@", errorCode, description)

                if Self.fatalErrorCodes.contains(errorCode) {
                    Self.clearStoredTokens()
                    return .needsReauthentication(reason: description)
                }
                return .transientFailure(reason: description)
            }

            if httpResponse.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("QAdrito: Refresh token request failed with status %d: %@", httpResponse.statusCode, body)
                return .transientFailure(reason: "GitHub returned HTTP \(httpResponse.statusCode)")
            }

            let decoder = JSONDecoder()
            let tokenResponse = try decoder.decode(AccessTokenResponse.self, from: data)

            // GitHub rotates refresh tokens: the one we just sent is now dead, and the
            // replacement only exists in this response. Persist it FIRST — if the app dies
            // between the two writes, a stored-but-unused refresh token still recovers the
            // session, whereas a fresh access token paired with a spent refresh token
            // bricks it 8 hours later.
            if let newRefreshToken = tokenResponse.refreshToken {
                if !keychainManager.save(key: "githubRefreshToken", value: newRefreshToken) {
                    // Keep going: the new access token below is still worth having, and the
                    // next refresh will fail cleanly into re-authentication rather than here.
                    NSLog("QAdrito: Failed to save rotated refresh token; session will need re-auth when the access token expires")
                }
            }

            if !keychainManager.save(key: "githubToken", value: tokenResponse.accessToken) {
                // The refresh itself succeeded and GitHub has already retired the old access
                // token, so hand the new one to the caller anyway — failing here would throw
                // away a working token and 401 the request for no reason. It only lives for
                // this launch; the next one loads the stale token, 401s, and refreshes again
                // using the rotated refresh token saved above.
                NSLog("QAdrito: Refreshed access token could not be saved to the Keychain; using it for this session only")
            }

            NSLog("QAdrito: Successfully refreshed access token")
            return .success(tokenResponse.accessToken)

        } catch {
            NSLog("QAdrito: Failed to refresh token: %@", error.localizedDescription)
            return .transientFailure(reason: error.localizedDescription)
        }
    }

    /// Drop credentials GitHub has rejected so the app stops retrying them and shows sign-in.
    private static func clearStoredTokens() {
        KeychainManager.shared.delete(key: "githubToken")
        KeychainManager.shared.delete(key: "githubRefreshToken")
        ConditionalResponseCache.shared.removeAll()
    }
}

@MainActor
class GitHubOAuthManager: ObservableObject {
    @Published var isAuthenticating = false
    @Published var userCode: String?
    @Published var errorMessage: String?
    
    private let keychainManager = KeychainManager.shared
    private var authenticationTask: Task<Bool, Never>?
    private static let refreshCoordinator = RefreshCoordinator()
    
    func startDeviceFlow() async -> Bool {
        // Cancel any existing authentication
        authenticationTask?.cancel()
        
        isAuthenticating = true
        userCode = nil
        errorMessage = nil
        
        // Create and retain the authentication task
        let task = Task<Bool, Never> { @MainActor in
            do {
                let deviceCode = try await requestDeviceCode()
                
                guard !Task.isCancelled else {
                    self.isAuthenticating = false
                    self.userCode = nil
                    return false
                }
                
                self.userCode = deviceCode.userCode
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(deviceCode.userCode, forType: .string)
                
                if let verificationUrl = deviceCode.verificationUriComplete,
                   let url = URL(string: verificationUrl) {
                    NSWorkspace.shared.open(url)
                } else if let url = URL(string: deviceCode.verificationUri) {
                    NSWorkspace.shared.open(url)
                }
                
                let tokenResponse = try await pollForAccessToken(
                    deviceCode: deviceCode.deviceCode,
                    interval: deviceCode.interval
                )
                
                guard !Task.isCancelled else {
                    self.isAuthenticating = false
                    self.userCode = nil
                    return false
                }
                
                // Save access token
                ConditionalResponseCache.shared.removeAll()
                let accessTokenSaved = keychainManager.save(key: "githubToken", value: tokenResponse.accessToken)
                if !accessTokenSaved {
                    self.errorMessage = "Failed to save token. Please try again."
                    self.isAuthenticating = false
                    self.userCode = nil
                    return false
                }
                
                // Save refresh token if present (required for token rotation)
                if let refreshToken = tokenResponse.refreshToken {
                    let refreshTokenSaved = keychainManager.save(key: "githubRefreshToken", value: refreshToken)
                    if !refreshTokenSaved {
                        self.errorMessage = "Failed to save refresh token. Please try again."
                        keychainManager.delete(key: "githubToken")
                        self.isAuthenticating = false
                        self.userCode = nil
                        return false
                    }
                }
                
                self.isAuthenticating = false
                self.userCode = nil
                self.authenticationTask = nil
                return true
                
            } catch GitHubOAuthError.accessDenied {
                self.errorMessage = "Access denied. Please try again."
                self.isAuthenticating = false
                self.userCode = nil
                self.authenticationTask = nil
                return false
            } catch GitHubOAuthError.expiredToken {
                self.errorMessage = "Authorization expired. Please try again."
                self.isAuthenticating = false
                self.userCode = nil
                self.authenticationTask = nil
                return false
            } catch is CancellationError {
                self.isAuthenticating = false
                self.userCode = nil
                self.authenticationTask = nil
                return false
            } catch {
                guard !Task.isCancelled else {
                    self.isAuthenticating = false
                    self.userCode = nil
                    self.authenticationTask = nil
                    return false
                }
                self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                self.isAuthenticating = false
                self.userCode = nil
                self.authenticationTask = nil
                return false
            }
        }
        
        authenticationTask = task
        return await task.value
    }
    
    func cancelAuthentication() {
        authenticationTask?.cancel()
        authenticationTask = nil
        isAuthenticating = false
        userCode = nil
        errorMessage = nil
    }
    
    func signOut() {
        keychainManager.delete(key: "githubToken")
        keychainManager.delete(key: "githubRefreshToken")
        UserDefaults.standard.removeObject(forKey: "githubLogin")
        UserDefaults.standard.removeObject(forKey: "organization")
        UserDefaults.standard.removeObject(forKey: "slackMap")
        ConditionalResponseCache.shared.removeAll()
    }
    
    func fetchCurrentUser(token: String) async throws -> GitHubUser {
        guard let url = URL(string: "https://api.github.com/user") else {
            throw GitHubOAuthError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(GitHubUser.self, from: data)
    }
    
    private func requestDeviceCode() async throws -> DeviceCodeResponse {
        guard let url = URL(string: "https://github.com/login/device/code") else {
            throw GitHubOAuthError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": GitHubOAuthConfig.clientID,
            "scope": GitHubOAuthConfig.scopes
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubOAuthError.networkError(NSError(domain: "GitHubOAuth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorString]))
        }
        
        // CodingKeys already map snake_case; convertFromSnakeCase would break decoding.
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(DeviceCodeResponse.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw GitHubOAuthError.networkError(NSError(
                domain: "GitHubOAuth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Device code decode failed: \(error.localizedDescription). Body: \(body)"]
            ))
        }
    }
    
    private func pollForAccessToken(deviceCode: String, interval: Int) async throws -> AccessTokenResponse {
        let pollInterval = TimeInterval(max(interval, 5))
        
        while !Task.isCancelled {
            do {
                let tokenResponse = try await requestAccessToken(deviceCode: deviceCode)
                return tokenResponse
            } catch GitHubOAuthError.authorizationPending {
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                continue
            } catch GitHubOAuthError.slowDown {
                try await Task.sleep(nanoseconds: UInt64((pollInterval + 5) * 1_000_000_000))
                continue
            } catch {
                throw error
            }
        }
        
        throw CancellationError()
    }
    
    private func requestAccessToken(deviceCode: String) async throws -> AccessTokenResponse {
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
            throw GitHubOAuthError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": GitHubOAuthConfig.clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubOAuthError.invalidResponse
        }
        
        // Device flow returns HTTP 200 for both success and pending/error payloads.
        if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
           let error = errorResponse["error"] {
            switch error {
            case "authorization_pending":
                throw GitHubOAuthError.authorizationPending
            case "slow_down":
                throw GitHubOAuthError.slowDown
            case "access_denied":
                throw GitHubOAuthError.accessDenied
            case "expired_token":
                throw GitHubOAuthError.expiredToken
            default:
                let desc = errorResponse["error_description"] ?? error
                throw GitHubOAuthError.networkError(NSError(
                    domain: "GitHubOAuth",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: desc]
                ))
            }
        }
        
        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitHubOAuthError.networkError(NSError(
                domain: "GitHubOAuth",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: body]
            ))
        }
        
        // CodingKeys already map snake_case; do not use convertFromSnakeCase.
        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(AccessTokenResponse.self, from: data)
        
        return tokenResponse
    }
    
    /// Refresh the access token using the refresh token stored in Keychain.
    /// Returns the new access token on success, or nil if refresh fails or no refresh token exists.
    func refreshAccessToken() async -> String? {
        return await Self.refreshAccessTokenStatic()
    }

    /// Static version of token refresh that can be called without an instance.
    /// Returns the new access token on success, or nil if refresh fails or no refresh token exists.
    /// Uses a single-flight pattern to prevent concurrent refreshes from racing.
    ///
    /// When GitHub rejects the stored credentials outright, this posts
    /// `.qadritoSessionExpired` so the app can drop to the sign-in screen instead of
    /// dead-ending on an "Unauthorized" message with no way forward.
    static func refreshAccessTokenStatic() async -> String? {
        switch await refreshCoordinator.refresh() {
        case .success(let token):
            return token

        case .needsReauthentication(let reason):
            NSLog("QAdrito: Session expired, re-authentication required: %@", reason)
            await MainActor.run {
                // Carry the reason so the sign-in screen can say *why* — NSLog output from a
                // sandboxed app is not reachable in practice, so the UI is the only place
                // this is ever seen.
                NotificationCenter.default.post(
                    name: .qadritoSessionExpired,
                    object: nil,
                    userInfo: ["reason": reason]
                )
            }
            return nil

        case .transientFailure(let reason):
            // Keep the stored credentials: the next request retries rather than signing out
            // over a dropped connection.
            NSLog("QAdrito: Token refresh could not complete (will retry): %@", reason)
            return nil
        }
    }
}
