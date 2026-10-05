import Foundation

enum GitHubError: Error {
    case invalidURL
    case noData
    case decodingError
    case networkError(Error)
    case unauthorized
    case rateLimited
}

final class ConditionalResponseCache {
    static let shared = ConditionalResponseCache()

    fileprivate final class Entry {
        let etag: String
        let data: Data

        init(etag: String, data: Data) {
            self.etag = etag
            self.data = data
        }
    }

    struct ConditionalRequest {
        let request: URLRequest
        fileprivate let key: NSString?
        fileprivate let generation: Int
        fileprivate let sentEntry: Entry?
    }

    private let entries = NSCache<NSString, Entry>()
    private let lock = NSLock()
    private var generation = 0

    init(totalCostLimit: Int = 32 * 1024 * 1024) {
        entries.totalCostLimit = totalCostLimit
    }

    func prepare(_ request: URLRequest) -> ConditionalRequest {
        var prepared = request
        prepared.cachePolicy = .reloadIgnoringLocalCacheData
        let currentGeneration = self.currentGeneration
        guard let key = Self.key(for: request, generation: currentGeneration) else {
            return ConditionalRequest(request: prepared, key: nil, generation: currentGeneration, sentEntry: nil)
        }
        let entry = entries.object(forKey: key)
        if let entry {
            prepared.setValue(entry.etag, forHTTPHeaderField: "If-None-Match")
        }
        return ConditionalRequest(request: prepared, key: key, generation: currentGeneration, sentEntry: entry)
    }

    func resolve(_ conditional: ConditionalRequest, data: Data, response: HTTPURLResponse) -> (Data, Int) {
        if response.statusCode == 304,
           let entry = conditional.sentEntry,
           conditional.generation == currentGeneration {
            return (entry.data, 200)
        }
        if response.statusCode == 200,
           let key = conditional.key,
           conditional.generation == currentGeneration,
           let etag = response.value(forHTTPHeaderField: "ETag"),
           !etag.isEmpty {
            entries.setObject(Entry(etag: etag, data: data), forKey: key, cost: data.count)
        }
        return (data, response.statusCode)
    }

    func removeAll() {
        lock.lock()
        generation += 1
        lock.unlock()
        entries.removeAllObjects()
    }

    private var currentGeneration: Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    private static func key(for request: URLRequest, generation: Int) -> NSString? {
        guard (request.httpMethod ?? "GET") == "GET", let url = request.url?.absoluteString else {
            return nil
        }
        return "\(generation) \(url)" as NSString
    }
}

class GitHubClient {
    private let baseURL = "https://api.github.com"
    private var token: String
    private var tokenRefreshHandler: (() async -> String?)?
    private let responseCache = ConditionalResponseCache.shared
    
    /// Search page size and pagination limits (GitHub search max 1000 hits).
    static let searchPageSize = 100
    /// Pages for waiting/my scopes (~500 PRs max per query).
    static let scopedSearchMaxPages = 5
    /// GitHub search hard-caps at 1000 results → 10 pages at 100/page.
    static let allOpenPRsMaxPages = 10
    
    init(token: String, tokenRefreshHandler: (() async -> String?)? = nil) {
        self.token = token
        self.tokenRefreshHandler = tokenRefreshHandler
    }
    
    func updateToken(_ newToken: String) {
        self.token = newToken
    }
    
    func setTokenRefreshHandler(_ handler: @escaping () async -> String?) {
        self.tokenRefreshHandler = handler
    }
    
    /// List organization teams (`GET /orgs/{org}/teams`). Requires `read:org`.
    /// Paginates up to a modest page count; returns name + slug for filter matching.
    func fetchOrgTeams(org: String) async throws -> [GitHubTeam] {
        var teams: [GitHubTeam] = []
        var page = 1
        let perPage = 100
        let maxPages = 10
        
        while page <= maxPages {
            let url = try apiURL("/orgs/\(org)/teams?per_page=\(perPage)&page=\(page)")
            let pageTeams: [OrgTeamResponse] = try await getJSON(url)
            if pageTeams.isEmpty { break }
            teams.append(contentsOf: pageTeams.map { GitHubTeam(name: $0.name, slug: $0.slug) })
            if pageTeams.count < perPage { break }
            page += 1
        }
        
        // Dedupe by slug, prefer first name seen.
        var seen = Set<String>()
        var unique: [GitHubTeam] = []
        for team in teams {
            let key = team.slug.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(team)
        }
        return unique.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func fetchPRs(scope: PRScope, login: String, org: String) async throws -> [PullRequest] {
        switch scope {
        case .waitingForMe:
            return try await searchPRsForReview(login: login, org: org)
        case .myPullRequests:
            return try await fetchMyPullRequests(login: login, org: org)
        case .all:
            return try await fetchAllOpenPRs(org: org)
        }
    }
    
    /// Waiting for me: review-requested UNION mentions, deduped by PR id.
    /// Queries: `org:{org} is:open is:pr review-requested:{login}` and `org:{org} is:open is:pr mentions:{login}`
    func searchPRsForReview(login: String, org: String) async throws -> [PullRequest] {
        let queries = [
            "org:\(org) is:open is:pr review-requested:\(login)",
            "org:\(org) is:open is:pr mentions:\(login)"
        ]
        let allPRs = try await fetchDetailedPRs(queries: queries, maxPagesPerQuery: Self.scopedSearchMaxPages)
        return allPRs.filter { pr in
            pr.state == "open" && (!pr.isDraft || !pr.requestedReviewers.isEmpty)
        }
    }
    
    /// My PRs: author UNION assignee, deduped by PR id.
    /// Queries: `org:{org} is:open is:pr author:{login}` and `org:{org} is:open is:pr assignee:{login}`
    func fetchMyPullRequests(login: String, org: String) async throws -> [PullRequest] {
        let queries = [
            "org:\(org) is:open is:pr author:\(login)",
            "org:\(org) is:open is:pr assignee:\(login)"
        ]
        let allPRs = try await fetchDetailedPRs(queries: queries, maxPagesPerQuery: Self.scopedSearchMaxPages)
        return allPRs.filter { $0.state == "open" }
    }
    
    func fetchOwnPRs(login: String, org: String) async throws -> [PullRequest] {
        try await fetchMyPullRequests(login: login, org: org)
    }
    
    /// All open PRs in the org across every repo. Paginates up to GitHub search max (~1000).
    /// Query: `org:{org} is:open is:pr`
    func fetchAllOpenPRs(org: String) async throws -> [PullRequest] {
        // Lightweight details: skip review-comments + check-runs (secondary rate limits).
        let allPRs = try await fetchDetailedPRs(
            queries: ["org:\(org) is:open is:pr"],
            maxPagesPerQuery: Self.allOpenPRsMaxPages,
            includeActivityExtras: false
        )
        return allPRs.filter { $0.state == "open" }
    }

    /// Open PRs to monitor for activity notifications.
    ///
    /// Union of:
    /// 1. `author:login` open PRs
    /// 2. `commenter:login` open PRs (issue / discussion comments)
    /// 3. `reviewed-by:login` open PRs (submitted a review)
    /// plus (in the monitor) sticky snapshots where the user already participated or authored.
    /// Bare `review-requested:` is intentionally excluded — GitHub `involves:` is too broad
    /// (it effectively matches review-requested) and must not be used here.
    func fetchInvolvedOpenPRs(login: String, org: String) async throws -> [InvolvedPR] {
        // Authored + conversations the user commented or reviewed in.
        // Deliberately excludes bare `review-requested:` / `involves:` — those are one-shot only.
        let queries = [
            "org:\(org) is:open is:pr author:\(login)",
            "org:\(org) is:open is:pr commenter:\(login)",
            "org:\(org) is:open is:pr reviewed-by:\(login)"
        ]
        var unique = Set<SearchResult>()
        var ordered: [SearchResult] = []
        let maxPages = 2

        for query in queries {
            var page = 1
            while page <= maxPages {
                let batch = try await searchPRs(query: query, page: page)
                if batch.isEmpty { break }
                for result in batch {
                    if unique.insert(result).inserted {
                        ordered.append(result)
                    }
                }
                if batch.count < Self.searchPageSize { break }
                page += 1
            }
        }

        return try await fetchInvolvedMetadata(for: ordered, login: login)
    }

    /// Keys only for open PRs where `login` is a requested reviewer (no full metadata).
    /// Used solely for one-shot "review requested" notifications — not full activity monitoring.
    func fetchReviewRequestedOpenPRKeys(login: String, org: String) async throws -> Set<String> {
        let query = "org:\(org) is:open is:pr review-requested:\(login)"
        var keys = Set<String>()
        let maxPages = 2
        var page = 1
        while page <= maxPages {
            let batch = try await searchPRs(query: query, page: page)
            if batch.isEmpty { break }
            for result in batch {
                keys.insert("\(result.owner)/\(result.repo)#\(result.number)")
            }
            if batch.count < Self.searchPageSize { break }
            page += 1
        }
        return keys
    }

    /// Fetch activity metadata for specific open PRs (used to keep watching participating PRs
    /// that dropped out of author / commenter / reviewed-by search sets).
    func fetchInvolvedPRs(ownerRepoNumbers: [(owner: String, repo: String, number: Int)], login: String) async throws -> [InvolvedPR] {
        let results = ownerRepoNumbers.map { SearchResult(owner: $0.owner, repo: $0.repo, number: $0.number) }
        return try await fetchInvolvedMetadata(for: results, login: login)
    }

    /// Final state of a PR that left the open watch set (merged vs closed).
    func fetchPRFinalState(owner: String, repo: String, number: Int) async throws -> PRFinalState? {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)") else {
            throw GitHubError.invalidURL
        }

        let (data, statusCode) = try await performRawRequestWithRetry { token in
            var request = URLRequest(url: url)
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
            return request
        }
        
        if statusCode == 404 { return nil }
        if statusCode == 401 { throw GitHubError.unauthorized }
        if statusCode == 403 { throw GitHubError.rateLimited }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let pr = try decoder.decode(PRFinalResponse.self, from: data)
        return PRFinalState(
            owner: owner,
            repo: repo,
            number: pr.number,
            title: pr.title,
            htmlUrl: pr.htmlUrl,
            authorLogin: pr.user.login,
            state: pr.state,
            merged: pr.merged ?? (pr.mergedAt != nil)
        )
    }

    private func fetchInvolvedMetadata(for searchResults: [SearchResult], login: String) async throws -> [InvolvedPR] {
        var involved: [InvolvedPR] = []
        try await withThrowingTaskGroup(of: InvolvedPR?.self) { group in
            var iterator = searchResults.makeIterator()
            let concurrency = 5
            for _ in 0..<min(concurrency, searchResults.count) {
                if let result = iterator.next() {
                    group.addTask {
                        try await self.fetchPRActivityMetadata(
                            owner: result.owner,
                            repo: result.repo,
                            number: result.number,
                            login: login
                        )
                    }
                }
            }
            for try await pr in group {
                if let pr {
                    involved.append(pr)
                }
                if let result = iterator.next() {
                    group.addTask {
                        try await self.fetchPRActivityMetadata(
                            owner: result.owner,
                            repo: result.repo,
                            number: result.number,
                            login: login
                        )
                    }
                }
            }
        }
        var seen = Set<String>()
        return involved.filter { seen.insert($0.key).inserted }
    }

    func fetchIssueComments(owner: String, repo: String, number: Int) async throws -> [ActivityComment] {
        let url = try apiURL("/repos/\(owner)/\(repo)/issues/\(number)/comments?per_page=100")
        let comments: [ActivityCommentResponse] = try await getJSON(url)
        return comments.map {
            ActivityComment(id: $0.id, author: $0.user.login, htmlUrl: $0.htmlUrl)
        }
    }

    func fetchReviews(owner: String, repo: String, number: Int) async throws -> [ActivityReview] {
        let url = try apiURL("/repos/\(owner)/\(repo)/pulls/\(number)/reviews?per_page=100")
        let reviews: [ActivityReviewResponse] = try await getJSON(url)
        return reviews.map {
            ActivityReview(id: $0.id, author: $0.user.login, state: $0.state, htmlUrl: $0.htmlUrl)
        }
    }

    func fetchPullReviewComments(owner: String, repo: String, number: Int) async throws -> [ActivityComment] {
        let url = try apiURL("/repos/\(owner)/\(repo)/pulls/\(number)/comments?per_page=100")
        let comments: [ActivityCommentResponse] = try await getJSON(url)
        return comments.map {
            ActivityComment(id: $0.id, author: $0.user.login, htmlUrl: $0.htmlUrl)
        }
    }

    func fetchCheckFailureSignature(owner: String, repo: String, sha: String) async throws -> String? {
        guard !sha.isEmpty else { return nil }

        var failing: [String] = []

        let checkURL = try apiURL("/repos/\(owner)/\(repo)/commits/\(sha)/check-runs?per_page=100")
        if let checks: CheckRunsResponse = try? await getJSON(checkURL) {
            let failureConclusions: Set<String> = [
                "failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale"
            ]
            for run in checks.checkRuns {
                if let conclusion = run.conclusion?.lowercased(), failureConclusions.contains(conclusion) {
                    failing.append("check:\(run.name):\(conclusion)")
                }
            }
        }

        let statusURL = try apiURL("/repos/\(owner)/\(repo)/commits/\(sha)/status")
        if let combined: CombinedStatusResponse = try? await getJSON(statusURL) {
            let state = combined.state.lowercased()
            if state == "failure" || state == "error" {
                failing.append("combined:\(state)")
            }
        }

        guard !failing.isEmpty else { return nil }
        return "\(sha)|" + failing.sorted().joined(separator: ",")
    }

    private func fetchPRActivityMetadata(owner: String, repo: String, number: Int, login: String) async throws -> InvolvedPR? {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)") else {
            throw GitHubError.invalidURL
        }

        let (data, statusCode) = try await performRawRequestWithRetry { token in
            var request = URLRequest(url: url)
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
            return request
        }

        if statusCode == 404 {
            return nil
        }
        if statusCode == 401 {
            throw GitHubError.unauthorized
        }
        if statusCode == 403 {
            throw GitHubError.rateLimited
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let prResponse = try decoder.decode(PRResponse.self, from: data)
        // Activity monitor only tracks open PRs; closed/merged are handled via disappearance → final state.
        if prResponse.state.lowercased() != "open" {
            return nil
        }
        let mergeableState = prResponse.mergeableState
        let hasConflicts = mergeableState == "dirty" || mergeableState == "conflicting"
        let requested = prResponse.requestedReviewers?.map(\.login) ?? []
        let assignees = prResponse.assignees?.map(\.login) ?? []
        let author = prResponse.user.login
        let isDraft = prResponse.draft ?? false
        let isAuthored = author.caseInsensitiveCompare(login) == .orderedSame
        let isReviewRequested = requested.contains { $0.caseInsensitiveCompare(login) == .orderedSame }
        let isAssignee = assignees.contains { $0.caseInsensitiveCompare(login) == .orderedSame }
        let ready = !isDraft && mergeableState == "clean"

        return InvolvedPR(
            owner: owner,
            repo: repo,
            number: prResponse.number,
            title: prResponse.title,
            htmlUrl: prResponse.htmlUrl,
            headSha: prResponse.head?.sha ?? "",
            mergeableState: mergeableState,
            hasConflicts: hasConflicts,
            authorLogin: author,
            isDraft: isDraft,
            requestedReviewers: requested,
            assignees: assignees,
            isAuthoredByMe: isAuthored,
            isReviewRequestedOfMe: isReviewRequested,
            isAssignedToMe: isAssignee,
            isReadyToMerge: ready
        )
    }

    private func apiURL(_ path: String) throws -> URL {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw GitHubError.invalidURL
        }
        return url
    }

    private func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        return try await performRequestWithRetry { token in
            var request = URLRequest(url: url)
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
            return request
        }
    }
    
    /// Perform a request with automatic token refresh retry on 401.
    private func performRequestWithRetry<T: Decodable>(
        requestBuilder: (String) -> URLRequest
    ) async throws -> T {
        var request = requestBuilder(token)
        
        let (data, statusCode) = try await send(request)
        
        // If we get a 401, try refreshing the token once
        if statusCode == 401 {
            if let refreshedToken = await tokenRefreshHandler?() {
                self.token = refreshedToken
                request = requestBuilder(refreshedToken)
                
                let (retryData, retryStatusCode) = try await send(request)
                
                if retryStatusCode == 401 {
                    throw GitHubError.unauthorized
                }
                if retryStatusCode == 403 {
                    throw GitHubError.rateLimited
                }
                guard retryStatusCode == 200 else {
                    throw GitHubError.noData
                }
                
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(T.self, from: retryData)
            } else {
                // No refresh handler or refresh failed
                throw GitHubError.unauthorized
            }
        }
        
        if statusCode == 403 {
            throw GitHubError.rateLimited
        }
        guard statusCode == 200 else {
            throw GitHubError.noData
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
    
    /// Perform a raw request with automatic token refresh retry on 401.
    /// Returns the response data and HTTP status code.
    private func performRawRequestWithRetry(
        requestBuilder: (String) -> URLRequest
    ) async throws -> (Data, Int) {
        var request = requestBuilder(token)
        
        let (data, statusCode) = try await send(request)
        
        // If we get a 401, try refreshing the token once
        if statusCode == 401 {
            if let refreshedToken = await tokenRefreshHandler?() {
                self.token = refreshedToken
                request = requestBuilder(refreshedToken)
                
                return try await send(request)
            } else {
                // No refresh handler or refresh failed
                throw GitHubError.unauthorized
            }
        }
        
        return (data, statusCode)
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        let conditional = responseCache.prepare(request)
        let (data, response) = try await URLSession.shared.data(for: conditional.request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.noData
        }
        return responseCache.resolve(conditional, data: data, response: httpResponse)
    }

    /// Run one or more search queries, union SearchResults by owner/repo/number, then fetch PR details once each.
    /// - Parameter includeActivityExtras: when false (All tab), skip review-comment *bodies* (checks still fetched for UI).
    private func fetchDetailedPRs(queries: [String], maxPagesPerQuery: Int, includeActivityExtras: Bool = true) async throws -> [PullRequest] {
        var unique = Set<SearchResult>()
        var ordered: [SearchResult] = []
        
        for query in queries {
            var page = 1
            while page <= maxPagesPerQuery {
                let batch = try await searchPRs(query: query, page: page)
                if batch.isEmpty {
                    break
                }
                for result in batch {
                    if unique.insert(result).inserted {
                        ordered.append(result)
                    }
                }
                if batch.count < Self.searchPageSize {
                    break
                }
                page += 1
            }
        }
        
        var allPRs: [PullRequest] = []
        // Non-throwing group: per-task failures must not abort the whole fetch.
        await withTaskGroup(of: PullRequest?.self) { group in
            var iterator = ordered.makeIterator()
            let concurrency = 5
            for _ in 0..<min(concurrency, ordered.count) {
                if let result = iterator.next() {
                    group.addTask {
                        await self.fetchPRDetailsResilient(
                            owner: result.owner,
                            repo: result.repo,
                            number: result.number,
                            includeActivityExtras: includeActivityExtras
                        )
                    }
                }
            }
            for await pr in group {
                if let pr {
                    allPRs.append(pr)
                }
                if let result = iterator.next() {
                    group.addTask {
                        await self.fetchPRDetailsResilient(
                            owner: result.owner,
                            repo: result.repo,
                            number: result.number,
                            includeActivityExtras: includeActivityExtras
                        )
                    }
                }
            }
        }
        
        NSLog(
            "QAdrito: search hits=%d detailed successes=%d includeActivityExtras=%@",
            ordered.count,
            allPRs.count,
            includeActivityExtras ? "true" : "false"
        )
        
        var seenIds = Set<Int>()
        return allPRs.filter { seenIds.insert($0.id).inserted }
    }
    
    /// Fetch PR details with one rate-limit retry; never throws (returns nil on failure).
    private func fetchPRDetailsResilient(
        owner: String,
        repo: String,
        number: Int,
        includeActivityExtras: Bool
    ) async -> PullRequest? {
        do {
            return try await fetchPRDetails(
                owner: owner,
                repo: repo,
                number: number,
                includeActivityExtras: includeActivityExtras
            )
        } catch GitHubError.rateLimited {
            // Brief backoff then one retry.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            do {
                return try await fetchPRDetails(
                    owner: owner,
                    repo: repo,
                    number: number,
                    includeActivityExtras: includeActivityExtras
                )
            } catch {
                NSLog(
                    "QAdrito: detail fetch failed after rate-limit retry for %@/%@#%d: %@",
                    owner, repo, number, String(describing: error)
                )
                return nil
            }
        } catch {
            NSLog(
                "QAdrito: detail fetch failed for %@/%@#%d: %@",
                owner, repo, number, String(describing: error)
            )
            return nil
        }
    }

    private func searchPRs(query: String, page: Int) async throws -> [SearchResult] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search/issues?q=\(encodedQuery)&per_page=\(Self.searchPageSize)&page=\(page)") else {
            throw GitHubError.invalidURL
        }
        
        let (data, statusCode) = try await performRawRequestWithRetry { token in
            var request = URLRequest(url: url)
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
            return request
        }
        
        if statusCode == 401 {
            throw GitHubError.unauthorized
        }
        
        if statusCode == 403 {
            throw GitHubError.rateLimited
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let searchResponse = try decoder.decode(SearchResponse.self, from: data)
        
        return searchResponse.items.compactMap { item in
            guard let prURL = item.pullRequest?.url,
                  let components = URLComponents(string: prURL),
                  let pathComponents = components.path.split(separator: "/").map(String.init) as [String]?,
                  pathComponents.count >= 5 else {
                return nil
            }
            
            let owner = pathComponents[1]
            let repo = pathComponents[2]
            let number = item.number
            
            return SearchResult(owner: owner, repo: repo, number: number)
        }
    }
    
    private func fetchPRDetails(
        owner: String,
        repo: String,
        number: Int,
        includeActivityExtras: Bool = true
    ) async throws -> PullRequest? {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)") else {
            throw GitHubError.invalidURL
        }
        
        let (data, statusCode) = try await performRawRequestWithRetry { token in
            var request = URLRequest(url: url)
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
            return request
        }
        
        if statusCode == 404 {
            return nil
        }
        
        if statusCode == 401 {
            throw GitHubError.unauthorized
        }
        
        if statusCode == 403 {
            throw GitHubError.rateLimited
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        let prResponse = try decoder.decode(PRResponse.self, from: data)
        
        // Always GET the pull. Skip extras for All to avoid secondary rate-limit 403s.
        let reviewComments: [ReviewComment]
        if includeActivityExtras {
            reviewComments = try await fetchReviewComments(owner: owner, repo: repo, number: number)
        } else {
            reviewComments = []
        }
        
        let hasConflicts = prResponse.mergeableState == "dirty" || prResponse.mergeableState == "conflicting"
        
        let requestedReviewers = prResponse.requestedReviewers?.map { $0.login } ?? []
        let requestedTeams = prResponse.requestedTeams?.map(\.slug) ?? []
        let labels = prResponse.labels?.map(\.name) ?? []
        
        let issueCommentCount = prResponse.comments ?? 0
        let reviewCommentCount = prResponse.reviewComments ?? 0
        let commentCount = issueCommentCount + reviewCommentCount
        
let headSha = prResponse.head?.sha ?? ""
        // Always load check summary so list + stack rows can show ✅/❌ fractions (All tab included).
        // Review *bodies* stay gated by includeActivityExtras to limit rate-limit pressure.
        let checkSummary = await fetchCheckSummary(owner: owner, repo: repo, sha: headSha)
        
        return PullRequest(
            id: prResponse.id,
            number: prResponse.number,
            title: prResponse.title,
            htmlUrl: prResponse.htmlUrl,
            author: prResponse.user.login,
            createdAt: prResponse.createdAt,
            isDraft: prResponse.draft ?? false,
            state: prResponse.state,
            repositoryName: repo,
            changedFiles: prResponse.changedFiles ?? 0,
            additions: prResponse.additions ?? 0,
            deletions: prResponse.deletions ?? 0,
            mergeable: prResponse.mergeable,
            mergeableState: prResponse.mergeableState,
            hasConflicts: hasConflicts,
            reviewDecision: nil,
            reviewComments: reviewComments,
            requestedReviewers: requestedReviewers,
            requestedTeams: requestedTeams,
            labels: labels,
            githubStackId: prResponse.stack?.id,
            stackPosition: prResponse.stack?.position,
            githubStackSize: prResponse.stack?.size,
            baseRef: prResponse.base?.ref ?? "",
            headRef: prResponse.head?.ref ?? "",
            checkPassed: checkSummary.passed,
            checkTotal: checkSummary.total,
            checksConclusion: checkSummary.conclusion,
            commentCount: commentCount
        )
    }
    
    /// Summarize check-runs (and legacy commit statuses if no check-runs) for UI fraction + conclusion.
    private func fetchCheckSummary(owner: String, repo: String, sha: String) async -> CheckSummary {
        guard !sha.isEmpty else {
            return CheckSummary(passed: nil, total: nil, conclusion: nil)
        }
        
        let failureConclusions: Set<String> = [
            "failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale"
        ]
        let pendingStatuses: Set<String> = [
            "queued", "in_progress", "pending", "waiting", "requested"
        ]
        
        var passed = 0
        var failed = 0
        var pending = 0
        var total = 0
        
        let checkURL: URL
        do {
            checkURL = try apiURL("/repos/\(owner)/\(repo)/commits/\(sha)/check-runs?per_page=100")
        } catch {
            return CheckSummary(passed: nil, total: nil, conclusion: nil)
        }
        
        if let checks: CheckRunsResponse = try? await getJSON(checkURL) {
            for run in checks.checkRuns {
                let status = run.status.lowercased()
                let conclusion = run.conclusion?.lowercased()
                
                if pendingStatuses.contains(status) {
                    pending += 1
                    total += 1
                    continue
                }
                
                // Skip skipped checks from the fraction.
                if conclusion == "skipped" {
                    continue
                }
                
                total += 1
                if let conclusion, failureConclusions.contains(conclusion) {
                    failed += 1
                } else if conclusion == "success" {
                    passed += 1
                } else if conclusion == "neutral" {
                    // Neutral is not a failure; count toward total but not as a hard pass.
                    passed += 1
                } else if status == "completed" {
                    // Unknown completed conclusion — treat as non-success, non-failure.
                    passed += 0
                }
            }
        }
        
        // Fall back to legacy combined commit statuses when check-runs are empty.
        if total == 0 {
            let statusURL: URL
            do {
                statusURL = try apiURL("/repos/\(owner)/\(repo)/commits/\(sha)/status")
            } catch {
                return CheckSummary(passed: nil, total: nil, conclusion: nil)
            }
            
            if let combined: CombinedStatusResponse = try? await getJSON(statusURL) {
                let statuses = combined.statuses ?? []
                if !statuses.isEmpty {
                    for status in statuses {
                        let state = status.state.lowercased()
                        total += 1
                        switch state {
                        case "success":
                            passed += 1
                        case "failure", "error":
                            failed += 1
                        case "pending":
                            pending += 1
                        default:
                            break
                        }
                    }
                } else {
                    // Only overall state available — don't invent a fraction.
                    switch combined.state.lowercased() {
                    case "success":
                        return CheckSummary(passed: nil, total: nil, conclusion: "success")
                    case "failure", "error":
                        return CheckSummary(passed: nil, total: nil, conclusion: "failure")
                    case "pending":
                        return CheckSummary(passed: nil, total: nil, conclusion: "pending")
                    default:
                        return CheckSummary(passed: nil, total: nil, conclusion: "neutral")
                    }
                }
            }
        }
        
        guard total > 0 else {
            return CheckSummary(passed: nil, total: nil, conclusion: nil)
        }
        
        if failed > 0 {
            return CheckSummary(passed: passed, total: total, conclusion: "failure")
        }
        if pending > 0 {
            return CheckSummary(passed: passed, total: total, conclusion: "pending")
        }
        if passed == total {
            return CheckSummary(passed: passed, total: total, conclusion: "success")
        }
        return CheckSummary(passed: passed, total: total, conclusion: "neutral")
    }
    
    private func fetchReviewComments(owner: String, repo: String, number: Int) async throws -> [ReviewComment] {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)/comments") else {
            throw GitHubError.invalidURL
        }
        
        let (data, statusCode) = try await performRawRequestWithRetry { token in
            var request = URLRequest(url: url)
            request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
            return request
        }
        
        guard statusCode == 200 else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        let comments = try decoder.decode([ReviewCommentResponse].self, from: data)
        
        return comments.map { comment in
            ReviewComment(
                id: comment.id,
                state: comment.state ?? "PENDING",
                author: comment.user.login,
                createdAt: comment.createdAt
            )
        }
    }
}

private struct SearchResponse: Codable {
    let items: [SearchItem]
}

private struct SearchItem: Codable {
    let number: Int
    let pullRequest: PullRequestRef?
}

private struct PullRequestRef: Codable {
    let url: String
}

private struct SearchResult: Hashable {
    let owner: String
    let repo: String
    let number: Int
}

private struct CheckSummary {
    let passed: Int?
    let total: Int?
    let conclusion: String?
}

private struct PRResponse: Codable {
    let id: Int
    let number: Int
    let title: String
    let htmlUrl: String
    let user: User
    let createdAt: Date
    let draft: Bool?
    let state: String
    let changedFiles: Int?
    let additions: Int?
    let deletions: Int?
    let mergeable: Bool?
    let mergeableState: String?
    let requestedReviewers: [User]?
    let requestedTeams: [TeamRef]?
    let labels: [LabelRef]?
    let assignees: [User]?
    let head: PRHead?
    let base: PRBranchRef?
    let stack: GitHubPRStackInfo?
    /// Issue comments count on the PR conversation.
    let comments: Int?
    /// Inline review comments count.
    let reviewComments: Int?
}

private struct GitHubPRStackInfo: Codable {
    let id: Int
    let number: Int
    let size: Int
    let position: Int
}

private struct PRBranchRef: Codable {
    let ref: String
    let sha: String?
}

private struct PRHead: Codable {
    let sha: String
    let ref: String?
}

private struct User: Codable {
    let login: String
}

private struct TeamRef: Codable {
    let name: String?
    let slug: String
}

private struct LabelRef: Codable {
    let name: String
}

private struct OrgTeamResponse: Codable {
    let name: String
    let slug: String
}

private struct ReviewCommentResponse: Codable {
    let id: Int
    let state: String?
    let user: User
    let createdAt: Date
}

struct PRFinalState: Sendable {
    let owner: String
    let repo: String
    let number: Int
    let title: String
    let htmlUrl: String
    let authorLogin: String
    let state: String
    let merged: Bool

    var key: String { "\(owner)/\(repo)#\(number)" }
    var repositoryFullName: String { "\(owner)/\(repo)" }
    var displayName: String {
        let short = repoShortMap[repo] ?? repo
        return "\(short)#\(number)"
    }
}

private struct PRFinalResponse: Codable {
    let number: Int
    let title: String
    let htmlUrl: String
    let user: User
    let state: String
    let merged: Bool?
    let mergedAt: Date?
}

struct ActivityComment: Sendable {
    let id: Int
    let author: String
    let htmlUrl: String
}

struct ActivityReview: Sendable {
    let id: Int
    let author: String
    let state: String
    let htmlUrl: String?
}

private struct ActivityCommentResponse: Codable {
    let id: Int
    let user: User
    let htmlUrl: String
}

private struct ActivityReviewResponse: Codable {
    let id: Int
    let user: User
    let state: String
    let htmlUrl: String?
}

private struct CheckRunsResponse: Codable {
    let checkRuns: [CheckRun]
}

private struct CheckRun: Codable {
    let name: String
    let status: String
    let conclusion: String?
}

private struct CombinedStatusResponse: Codable {
    let state: String
    let statuses: [CommitStatusContext]?
    let totalCount: Int?
}

private struct CommitStatusContext: Codable {
    let context: String
    let state: String
}
