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
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
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
    private var pollingTask: Task<Void, Never>?
    
    func startDeviceFlow() async -> Bool {
        isAuthenticating = true
        userCode = nil
        errorMessage = nil
        
        do {
            let deviceCode = try await requestDeviceCode()
            userCode = deviceCode.userCode
            
            if let verificationUrl = deviceCode.verificationUriComplete,
               let url = URL(string: verificationUrl) {
                NSWorkspace.shared.open(url)
            } else if let url = URL(string: deviceCode.verificationUri) {
                NSWorkspace.shared.open(url)
            }
            
            let token = try await pollForAccessToken(
                deviceCode: deviceCode.deviceCode,
                interval: deviceCode.interval
            )
            
            _ = keychainManager.save(key: "githubToken", value: token)
            
            isAuthenticating = false
            userCode = nil
            return true
            
        } catch GitHubOAuthError.accessDenied {
            errorMessage = "Access denied. Please try again."
            isAuthenticating = false
            userCode = nil
            return false
        } catch GitHubOAuthError.expiredToken {
            errorMessage = "Authorization expired. Please try again."
            isAuthenticating = false
            userCode = nil
            return false
        } catch {
            errorMessage = "Authentication failed: \(error.localizedDescription)"
            isAuthenticating = false
            userCode = nil
            return false
        }
    }
    
    func cancelAuthentication() {
        pollingTask?.cancel()
        pollingTask = nil
        isAuthenticating = false
        userCode = nil
        errorMessage = nil
    }
    
    func signOut() {
        keychainManager.delete(key: "githubToken")
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
        
        let body = [
            "client_id": GitHubOAuthConfig.clientID,
            "scope": GitHubOAuthConfig.scopes
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        return try decoder.decode(DeviceCodeResponse.self, from: data)
    }
    
    private func pollForAccessToken(deviceCode: String, interval: Int) async throws -> String {
        let pollInterval = TimeInterval(max(interval, 5))
        
        while !Task.isCancelled {
            do {
                let token = try await requestAccessToken(deviceCode: deviceCode)
                return token
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
        
        throw GitHubOAuthError.accessDenied
    }
    
    private func requestAccessToken(deviceCode: String) async throws -> String {
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else {
            throw GitHubOAuthError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
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
        
        if httpResponse.statusCode != 200 {
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
                    throw GitHubOAuthError.invalidResponse
                }
            }
            throw GitHubOAuthError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tokenResponse = try decoder.decode(AccessTokenResponse.self, from: data)
        
        return tokenResponse.accessToken
    }
}
