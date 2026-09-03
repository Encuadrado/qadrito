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
    /// Filtered PR count (pre-stack). Header must show this, not stack row count.
    @Published var listedPRCount: Int = 0
    @Published var displayedSections: [PRAgeSection] = []
    @Published var usesAgeGroups = true
    @Published var resultsCapped = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefreshDate: Date?
    
    @Published var selectedMode: ViewMode = .all
    @Published var selectedScope: PRScope
    @Published var authorFilter: Set<String> = []
    @Published var repoFilter: Set<String> = []
    @Published var teamFilter: Set<String> = []
    @Published var tagFilter: Set<String> = []
    /// Accumulated authors seen across refreshes (pre-populates filter).
    @Published private(set) var knownAuthors: [String] = []
    /// Accumulated short repo names (seeded with Encuadrado map + seen PRs).
    @Published private(set) var knownRepos: [String] = []
    /// Org teams from GitHub (name for display; slug for matching `requested_teams`).
    @Published private(set) var knownTeams: [GitHubTeam] = []
    /// Accumulated label/tag names seen on loaded PRs.
    @Published private(set) var knownTags: [String] = []
    
    @Published var isAuthenticated = false
    @Published var currentUsername: String?
    
    /// Configurable default tab (UserDefaults `defaultPRScope`).
    @Published private(set) var defaultPRScope: PRScope
    
    private var settings: AppSettings
    private var githubClient: GitHubClient?
    private let cacheManager = CacheManager.shared
    private let keychainManager = KeychainManager.shared
    let oauthManager = GitHubOAuthManager()
    private var listRefreshTask: Task<Void, Never>?
    private let listRefreshIntervalNanoseconds: UInt64 = 60_000_000_000
    private static let defaultPRScopeKey = "defaultPRScope"
    
    /// In-memory per-scope caches for instant tab switches.
    private var scopeCaches: [PRScope: ScopeCache] = [:]
    private var inFlightScopes: Set<PRScope> = []
    /// Scopes where the UI asked for a body spinner while a quiet/prefetch fetch was already running.
    private var scopesAwaitingSpinnerClear: Set<PRScope> = []
    
    var formattedRefreshTime: String {
        guard let date = lastRefreshDate else { return "Never" }
        
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Santiago")
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        
        return formatter.string(from: date)
    }
    
    var subtitleText: String {
        let cap = resultsCapped ? " · showing first \(GitHubClient.allOpenPRsMaxPages * GitHubClient.searchPageSize)" : ""
        return "[\(settings.githubLogin)] · \(selectedScope.rawValue)\(cap) · list \(formattedRefreshTime)"
    }
    
    var emptyStateTitle: String {
        switch selectedScope {
        case .waitingForMe:
            return "No PRs waiting on you"
        case .myPullRequests:
            return "No pull requests of yours"
        case .all:
            return "No open PRs"
        }
    }
    
    /// Authors for the filter dropdown (known catalog ∪ current list).
    var authorOptions: [String] {
        var set = Set(knownAuthors)
        set.formUnion(waitingPRs.map(\.author))
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    /// Repos for the filter dropdown (known catalog ∪ current list ∪ short-name map).
    var repoOptions: [String] {
        var set = Set(knownRepos)
        set.formUnion(waitingPRs.map(\.shortRepo))
        set.formUnion(repoShortMap.values)
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    /// Team display names for the filter dropdown (from org teams catalog).
    var teamOptions: [String] {
        knownTeams.map(\.name)
    }
    
    /// Name → slug for resolving team filter selections against `requestedTeams`.
    var teamSlugByName: [String: String] {
        Dictionary(uniqueKeysWithValues: knownTeams.map { ($0.name, $0.slug) })
    }
    
    /// Tags/labels for the filter dropdown (known catalog ∪ current list).
    var tagOptions: [String] {
        var set = Set(knownTags)
        for pr in waitingPRs {
            set.formUnion(pr.labels)
        }
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    init() {
        let loadedDefault = Self.loadDefaultScope()
        self.defaultPRScope = loadedDefault
        self.selectedScope = loadedDefault
        self.settings = Self.loadSettings()
        checkAuthentication()
        loadAllScopeCachesFromDisk()
        applyScopeCache(loadedDefault)
        loadKnownFilterOptions()
    }
    
    /// Called after `$selectedScope` binding changes (picker). Applies cache instantly + background refresh.
    func handleScopeChange() {
        applyScopeCache(selectedScope)
        let needsSpinner = scopeCaches[selectedScope] == nil
        // Set synchronously so the body shows a loader before the async refresh starts
        // (and when a quiet prefetch is already in flight for this scope).
        if needsSpinner {
            isLoading = true
            errorMessage = nil
        } else {
            isLoading = false
        }
        Task { await refresh(scope: selectedScope, showLoading: needsSpinner) }
    }
    
    /// Programmatic scope change (sets selectedScope then applies cache + refresh).
    func selectScope(_ scope: PRScope) {
        guard scope != selectedScope else { return }
        selectedScope = scope
        handleScopeChange()
    }
    
    func setDefaultPRScope(_ scope: PRScope) {
        defaultPRScope = scope
        UserDefaults.standard.set(scope.rawValue, forKey: Self.defaultPRScopeKey)
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
                        syncActivityMonitor()
                    }
                }
            }
            Task { await loadOrgTeamsIfNeeded() }
        } else {
            isAuthenticated = false
            currentUsername = nil
            githubClient = nil
        }
        syncActivityMonitor()
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
        listedPRCount = 0
        displayedSections = []
        lastRefreshDate = nil
        resultsCapped = false
        scopeCaches = [:]
        inFlightScopes = []
        scopesAwaitingSpinnerClear = []
        teamFilter = []
        tagFilter = []
        knownTeams = []
        cacheManager.clearCache()
        stopListAutoRefresh()
        PRActivityMonitor.shared.stop()
        AppPreferences.shared.clearBadge()
    }
    
    /// Keep login; org stays hardcoded Encuadrado. Prefer `setDefaultPRScope` for the default tab.
    func updateSettings(_ newSettings: AppSettings) {
        var cleaned = newSettings
        cleaned.organization = "Encuadrado"
        cleaned.slackMap = [:]
        if cleaned.githubLogin.isEmpty {
            cleaned.githubLogin = currentUsername ?? settings.githubLogin
        }
        self.settings = cleaned
        saveSettings()
        syncActivityMonitor()
    }
    
    func refresh() async {
        // Blank the body only when there is nothing cached for this scope.
        // Background/cached refreshes keep the list visible.
        let needsSpinner = scopeCaches[selectedScope] == nil
        await refresh(scope: selectedScope, showLoading: needsSpinner)
    }
    
    /// Scope-aware list refresh. Background polls use `showLoading: false` so the UI does not flash.
    func refresh(showLoading: Bool) async {
        await refresh(scope: selectedScope, showLoading: showLoading)
    }
    
    func refresh(scope: PRScope, showLoading: Bool) async {
        guard isAuthenticated else {
            if showLoading && scope == selectedScope {
                errorMessage = "Please sign in with GitHub first"
                isLoading = false
            }
            return
        }
        
        guard let client = githubClient else {
            if showLoading && scope == selectedScope {
                errorMessage = "GitHub client not initialized"
                isLoading = false
            }
            return
        }
        
        if inFlightScopes.contains(scope) {
            // Quiet prefetch may already be fetching All (slow). Attach a body spinner
            // so the selected tab does not look empty until that fetch publishes.
            if showLoading && scope == selectedScope {
                isLoading = true
                errorMessage = nil
                scopesAwaitingSpinnerClear.insert(scope)
            }
            return
        }
        
        inFlightScopes.insert(scope)
        
        if showLoading && scope == selectedScope {
            isLoading = true
            errorMessage = nil
        }
        
        let wantsVisibleErrors = showLoading || scopesAwaitingSpinnerClear.contains(scope)
        
        do {
            let prs = try await client.fetchPRs(
                scope: scope,
                login: settings.githubLogin,
                org: settings.organization
            )
            
            let sorted = PRSorting.sortWaitingPRs(prs, userLogin: settings.githubLogin)
            let capped = (scope == .all && prs.count >= GitHubClient.allOpenPRsMaxPages * GitHubClient.searchPageSize)
            let timestamp = Date()
            
            let cache = ScopeCache(prs: sorted, timestamp: timestamp, capped: capped)
            scopeCaches[scope] = cache
            publishWaitingForMeMenuIfNeeded(scope: scope, prs: sorted)
            
            let cachedData = CachedData(
                waitingPRs: sorted,
                timestamp: timestamp,
                capped: capped
            )
            cacheManager.saveCache(cachedData, scope: scope)
            
            if scope == selectedScope {
                waitingPRs = sorted
                lastRefreshDate = timestamp
                resultsCapped = capped
                rememberFilterOptionsFromCurrentPRs()
                updateDisplayedPRs()
            }
            
        } catch GitHubError.unauthorized {
            if scope == selectedScope {
                errorMessage = "Unauthorized. Please sign out and sign in again."
            }
        } catch GitHubError.rateLimited {
            if wantsVisibleErrors && scope == selectedScope {
                errorMessage = "Rate limited. Please try again later."
            }
        } catch {
            if wantsVisibleErrors && scope == selectedScope {
                errorMessage = "Failed to fetch PRs: \(error.localizedDescription)"
            }
        }
        
        inFlightScopes.remove(scope)
        
        let shouldClearSpinner = (showLoading || scopesAwaitingSpinnerClear.contains(scope)) && scope == selectedScope
        scopesAwaitingSpinnerClear.remove(scope)
        if shouldClearSpinner {
            isLoading = false
        }
    }
    
    func updateDisplayedPRs() {
        var filtered = waitingPRs
        
        filtered = PRFilters.applyFilters(
            filtered,
            authors: authorFilter.isEmpty ? nil : authorFilter,
            repos: repoFilter.isEmpty ? nil : repoFilter,
            teams: teamFilter.isEmpty ? nil : teamFilter,
            tags: tagFilter.isEmpty ? nil : tagFilter,
            teamSlugByName: teamSlugByName,
            slackMap: [:]
        )
        
        // Real PR count (pre-stack). displayedPRs.count is stack rows only.
        listedPRCount = filtered.count
        
        // View mode (All / Easiest 5 / Oldest 5) removed from UI; always age-group.
        displayedPRs = PRStackDetector.formatWithStacks(filtered)
        usesAgeGroups = true
        displayedSections = PRSorting.groupByAge(displayedPRs)
    }
    
    private func applyScopeCache(_ scope: PRScope) {
        guard let cache = scopeCaches[scope] else {
            waitingPRs = []
            lastRefreshDate = nil
            resultsCapped = false
            updateDisplayedPRs()
            if scope == .waitingForMe {
                WaitingForMeMenuStore.shared.clear()
            }
            return
        }
        waitingPRs = cache.prs
        lastRefreshDate = cache.timestamp
        resultsCapped = cache.capped
        rememberFilterOptionsFromCurrentPRs()
        updateDisplayedPRs()
        publishWaitingForMeMenuIfNeeded(scope: scope, prs: cache.prs)
    }
    
    private func syncActivityMonitor() {
        if isAuthenticated,
           let token = keychainManager.load(key: "githubToken"),
           !token.isEmpty {
            let login = (currentUsername?.isEmpty == false ? currentUsername : nil) ?? (settings.githubLogin.isEmpty ? nil : settings.githubLogin)
            guard let login else { return }
            PRActivityMonitor.shared.start(token: token, login: login, org: settings.organization)
            startListAutoRefresh()
        } else {
            PRActivityMonitor.shared.stop()
            stopListAutoRefresh()
        }
    }
    
    private func startListAutoRefresh() {
        guard listRefreshTask == nil else { return }
        listRefreshTask = Task { [weak self] in
            guard let self else { return }
            // First load with no disk/memory cache (common for All): show body loader.
            let needsInitialSpinner = self.scopeCaches[self.selectedScope] == nil
            if needsInitialSpinner {
                self.isLoading = true
                self.errorMessage = nil
            }
            await self.refresh(showLoading: needsInitialSpinner)
            await self.prefetchOtherScopes()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.listRefreshIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                await self.refresh(showLoading: false)
                await self.prefetchOtherScopes()
            }
        }
    }
    
    /// Quietly refresh non-selected scopes so tab switches stay instant.
    private func prefetchOtherScopes() async {
        for scope in PRScope.allCases where scope != selectedScope {
            await refresh(scope: scope, showLoading: false)
        }
    }
    
    private func stopListAutoRefresh() {
        listRefreshTask?.cancel()
        listRefreshTask = nil
    }

    private func loadAllScopeCachesFromDisk() {
        for scope in PRScope.allCases {
            if let cached = cacheManager.loadCache(scope: scope) {
                scopeCaches[scope] = ScopeCache(
                    prs: cached.waitingPRs,
                    timestamp: cached.timestamp,
                    capped: cached.capped
                )
                publishWaitingForMeMenuIfNeeded(scope: scope, prs: cached.waitingPRs)
            }
        }
        
        // Migrate legacy single-file cache into Waiting for me if that scope has no file yet.
        if scopeCaches[.waitingForMe] == nil,
           let legacy = cacheManager.loadLegacyCache() {
            let migrated = ScopeCache(
                prs: legacy.waitingPRs,
                timestamp: legacy.timestamp,
                capped: legacy.capped
            )
            scopeCaches[.waitingForMe] = migrated
            publishWaitingForMeMenuIfNeeded(scope: .waitingForMe, prs: migrated.prs)
            cacheManager.saveCache(
                CachedData(waitingPRs: legacy.waitingPRs, timestamp: legacy.timestamp, capped: legacy.capped),
                scope: .waitingForMe
            )
        }
    }
    
    private static func loadDefaultScope() -> PRScope {
        if let raw = UserDefaults.standard.string(forKey: defaultPRScopeKey),
           let stored = PRScope(rawValue: raw) {
            return stored
        }
        return .waitingForMe
    }
    
    private static func loadSettings() -> AppSettings {
        var settings = AppSettings()
        
        if let login = UserDefaults.standard.string(forKey: "githubLogin") {
            settings.githubLogin = login
        }
        
        // Org is always Encuadrado; Slack map unused in Settings.
        settings.organization = "Encuadrado"
        settings.slackMap = [:]
        
        return settings
    }
    

    private static let knownAuthorsKey = "knownAuthorOptions"
    private static let knownReposKey = "knownRepoOptions"
    private static let knownTagsKey = "knownTagOptions"
    private static let knownTeamsKey = "knownTeamOptions"

    private func loadKnownFilterOptions() {
        let defaults = UserDefaults.standard
        knownAuthors = defaults.stringArray(forKey: Self.knownAuthorsKey) ?? []
        var repos = Set(defaults.stringArray(forKey: Self.knownReposKey) ?? [])
        repos.formUnion(repoShortMap.values)
        knownRepos = repos.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if knownAuthors.isEmpty == false || knownRepos.isEmpty == false {
            knownAuthors = knownAuthors.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        knownTags = (defaults.stringArray(forKey: Self.knownTagsKey) ?? [])
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if let data = defaults.data(forKey: Self.knownTeamsKey),
           let decoded = try? JSONDecoder().decode([GitHubTeam].self, from: data) {
            knownTeams = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func rememberFilterOptionsFromCurrentPRs() {
        var authors = Set(knownAuthors)
        authors.formUnion(waitingPRs.map(\.author))
        knownAuthors = authors.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var repos = Set(knownRepos)
        repos.formUnion(waitingPRs.map(\.shortRepo))
        repos.formUnion(repoShortMap.values)
        knownRepos = repos.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var tags = Set(knownTags)
        for pr in waitingPRs {
            tags.formUnion(pr.labels)
        }
        knownTags = tags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        UserDefaults.standard.set(knownAuthors, forKey: Self.knownAuthorsKey)
        UserDefaults.standard.set(knownRepos, forKey: Self.knownReposKey)
        UserDefaults.standard.set(knownTags, forKey: Self.knownTagsKey)
    }
    
    /// Fetch org teams once (cached in memory + UserDefaults) after auth.
    private func loadOrgTeamsIfNeeded() async {
        guard let client = githubClient else { return }
        do {
            let teams = try await client.fetchOrgTeams(org: settings.organization)
            knownTeams = teams
            if let data = try? JSONEncoder().encode(teams) {
                UserDefaults.standard.set(data, forKey: Self.knownTeamsKey)
            }
        } catch {
            NSLog("QAdrito: failed to load org teams: \(error.localizedDescription)")
        }
    }


    private func publishWaitingForMeMenuIfNeeded(scope: PRScope, prs: [PullRequest]) {
        guard scope == .waitingForMe else { return }
        WaitingForMeMenuStore.shared.update(prs: prs)
    }

    private func saveSettings() {
        UserDefaults.standard.set(settings.githubLogin, forKey: "githubLogin")
        UserDefaults.standard.set("Encuadrado", forKey: "organization")
    }
}
