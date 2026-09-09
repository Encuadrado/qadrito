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
    let scope: String
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

@MainActor
class GitHubOAuthManager: ObservableObject {
    @Published var isAuthenticating = false
    @Published var userCode: String?
    @Published var errorMessage: String?
    
    private let keychainManager = KeychainManager.shared
    private var authenticationTask: Task<Bool, Never>?
    
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
                let saved = keychainManager.save(key: "githubToken", value: tokenResponse.accessToken)
                if !saved {
                    self.errorMessage = "Failed to save token. Please try again."
                    self.isAuthenticating = false
                    self.userCode = nil
                    return false
                }
                
                // Save refresh token if present
                if let refreshToken = tokenResponse.refreshToken {
                    _ = keychainManager.save(key: "githubRefreshToken", value: refreshToken)
                }
                
                // Calculate and save expiry time if present
                if let expiresIn = tokenResponse.expiresIn {
                    let expiryTime = Date().addingTimeInterval(TimeInterval(expiresIn))
                    let expiryString = String(expiryTime.timeIntervalSince1970)
                    _ = keychainManager.save(key: "githubTokenExpiry", value: expiryString)
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
        keychainManager.delete(key: "githubTokenExpiry")
        UserDefaults.standard.removeObject(forKey: "githubLogin")
        UserDefaults.standard.removeObject(forKey: "organization")
        UserDefaults.standard.removeObject(forKey: "slackMap")
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
    static func refreshAccessTokenStatic() async -> String? {
        let keychainManager = KeychainManager.shared
        
        guard let refreshToken = keychainManager.load(key: "githubRefreshToken") else {
            NSLog("QAdrito: No refresh token available for refresh")
            return nil
        }
        
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
            NSLog("QAdrito: Invalid refresh token URL")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": GitHubOAuthConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            NSLog("QAdrito: Failed to serialize refresh token request body")
            return nil
        }
        
        request.httpBody = bodyData
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("QAdrito: Invalid response from refresh token endpoint")
                return nil
            }
            
            if httpResponse.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                NSLog("QAdrito: Refresh token request failed with status %d: %@", httpResponse.statusCode, body)
                return nil
            }
            
            let decoder = JSONDecoder()
            let tokenResponse = try decoder.decode(AccessTokenResponse.self, from: data)
            
            // Save new access token
            let saved = keychainManager.save(key: "githubToken", value: tokenResponse.accessToken)
            if !saved {
                NSLog("QAdrito: Failed to save refreshed access token")
                return nil
            }
            
            // Save new refresh token if present (GitHub may issue a new one)
            if let newRefreshToken = tokenResponse.refreshToken {
                _ = keychainManager.save(key: "githubRefreshToken", value: newRefreshToken)
            }
            
            // Calculate and save new expiry time if present
            if let expiresIn = tokenResponse.expiresIn {
                let expiryTime = Date().addingTimeInterval(TimeInterval(expiresIn))
                let expiryString = String(expiryTime.timeIntervalSince1970)
                _ = keychainManager.save(key: "githubTokenExpiry", value: expiryString)
            }
            
            NSLog("QAdrito: Successfully refreshed access token")
            return tokenResponse.accessToken
            
        } catch {
            NSLog("QAdrito: Failed to refresh token: %@", error.localizedDescription)
            return nil
        }
    }
}
