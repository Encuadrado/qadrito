import Foundation
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case all = "All"
    case easiest = "Easiest 5"
    case oldest = "Oldest 5"
    
    var id: String { rawValue }
}

@MainActor
class PRViewModel: ObservableObject {
    @Published var waitingPRs: [PullRequest] = []
    @Published var displayedPRs: [PRStack] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefreshDate: Date?
    
    @Published var selectedMode: ViewMode = .all
    @Published var authorFilter: String = ""
    @Published var repoFilter: String = ""
    
    @Published var isAuthenticated = false
    @Published var currentUsername: String?
    
    private var settings: AppSettings
    private var githubClient: GitHubClient?
    private let cacheManager = CacheManager.shared
    private let keychainManager = KeychainManager.shared
    let oauthManager = GitHubOAuthManager()
    
    var formattedRefreshTime: String {
        guard let date = lastRefreshDate else { return "Never" }
        
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Santiago")
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        
        return formatter.string(from: date)
    }
    
    var subtitleText: String {
        "[\(settings.githubLogin)] · \(formattedRefreshTime) · last refresh"
    }
    
    init() {
        self.settings = Self.loadSettings()
        checkAuthentication()
        loadFromCache()
    }
    
    func checkAuthentication() {
        if let token = keychainManager.load(key: "githubToken"), !token.isEmpty {
            githubClient = GitHubClient(token: token)
            isAuthenticated = true
            
            if let login = UserDefaults.standard.string(forKey: "githubLogin"), !login.isEmpty {
                currentUsername = login
            } else {
                Task {
                    if let user = try? await oauthManager.fetchCurrentUser(token: token) {
                        currentUsername = user.login
                        settings.githubLogin = user.login
                        UserDefaults.standard.set(user.login, forKey: "githubLogin")
                    }
                }
            }
        } else {
            isAuthenticated = false
            currentUsername = nil
            githubClient = nil
        }
    }
    
    func completeAuthentication() async -> Bool {
        let success = await oauthManager.startDeviceFlow()
        
        if success {
            checkAuthentication()
            return true
        }
        
        return false
    }
    
    func signOut() {
        oauthManager.signOut()
        isAuthenticated = false
        currentUsername = nil
        githubClient = nil
        waitingPRs = []
        displayedPRs = []
        lastRefreshDate = nil
        cacheManager.clearCache()
    }
    
    func updateSettings(_ newSettings: AppSettings) {
        self.settings = newSettings
        saveSettings()
    }
    
    func refresh() async {
        guard isAuthenticated else {
            errorMessage = "Please sign in with GitHub first"
            return
        }
        
        guard let client = githubClient else {
            errorMessage = "GitHub client not initialized"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let prs = try await client.searchPRsForReview(
                login: settings.githubLogin,
                org: settings.organization
            )
            
            waitingPRs = PRSorting.sortWaitingPRs(prs, userLogin: settings.githubLogin)
            lastRefreshDate = Date()
            
            let cachedData = CachedData(
                waitingPRs: waitingPRs,
                timestamp: Date()
            )
            cacheManager.saveCache(cachedData)
            
            updateDisplayedPRs()
            
        } catch GitHubError.unauthorized {
            errorMessage = "Unauthorized. Please sign out and sign in again."
        } catch GitHubError.rateLimited {
            errorMessage = "Rate limited. Please try again later."
        } catch {
            errorMessage = "Failed to fetch PRs: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func updateDisplayedPRs() {
        var filtered = waitingPRs
        
        filtered = PRFilters.applyFilters(
            filtered,
            author: authorFilter.isEmpty ? nil : authorFilter,
            repo: repoFilter.isEmpty ? nil : repoFilter,
            slackMap: settings.slackMap
        )
        
        switch selectedMode {
        case .all:
            break
        case .easiest:
            filtered = PRFilters.getEasiestFive(filtered)
        case .oldest:
            filtered = PRFilters.getOldestFive(filtered)
        }
        
        displayedPRs = PRStackDetector.formatWithStacks(filtered)
    }
    
    private func loadFromCache() {
        guard let cached = cacheManager.loadCache() else { return }
        
        waitingPRs = cached.waitingPRs
        lastRefreshDate = cached.timestamp
        updateDisplayedPRs()
    }
    
    private static func loadSettings() -> AppSettings {
        var settings = AppSettings()
        
        if let login = UserDefaults.standard.string(forKey: "githubLogin") {
            settings.githubLogin = login
        }
        
        if let org = UserDefaults.standard.string(forKey: "organization") {
            settings.organization = org
        }
        
        if let slackMapData = UserDefaults.standard.data(forKey: "slackMap"),
           let slackMap = try? JSONDecoder().decode([String: SlackUser].self, from: slackMapData) {
            settings.slackMap = slackMap
        }
        
        return settings
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(settings.githubLogin, forKey: "githubLogin")
        UserDefaults.standard.set(settings.organization, forKey: "organization")
        
        if let encoded = try? JSONEncoder().encode(settings.slackMap) {
            UserDefaults.standard.set(encoded, forKey: "slackMap")
        }
    }
}
