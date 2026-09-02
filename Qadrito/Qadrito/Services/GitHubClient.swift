import Foundation

enum GitHubError: Error {
    case invalidURL
    case noData
    case decodingError
    case networkError(Error)
    case unauthorized
    case rateLimited
}

class GitHubClient {
    private let baseURL = "https://api.github.com"
    private var token: String
    
    /// Search API returns 30 items per page. All-open scope stops after this many pages (~150 PRs).
    static let allOpenPRsMaxPages = 5
    
    init(token: String) {
        self.token = token
    }
    
    func updateToken(_ newToken: String) {
        self.token = newToken
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
        let allPRs = try await fetchDetailedPRs(queries: queries, maxPagesPerQuery: Self.allOpenPRsMaxPages)
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
        let allPRs = try await fetchDetailedPRs(queries: queries, maxPagesPerQuery: Self.allOpenPRsMaxPages)
        return allPRs.filter { $0.state == "open" }
    }
    
    func fetchOwnPRs(login: String, org: String) async throws -> [PullRequest] {
        try await fetchMyPullRequests(login: login, org: org)
    }
    
    /// All open PRs in the org. Capped at `allOpenPRsMaxPages` pages (30 per page).
    /// Query: `org:{org} is:open is:pr`
    func fetchAllOpenPRs(org: String) async throws -> [PullRequest] {
        let allPRs = try await fetchDetailedPRs(
            queries: ["org:\(org) is:open is:pr"],
            maxPagesPerQuery: Self.allOpenPRsMaxPages
        )
        return allPRs.filter { $0.state == "open" }
    }

    /// Open PRs authored by `login` in `org` — used by the activity / notification monitor.
    func fetchInvolvedOpenPRs(login: String, org: String) async throws -> [InvolvedPR] {
        // Own PRs only (notifications are about activity on PRs you authored).
        let query = "org:\(org) is:open is:pr author:\(login)"
        var searchResults: [SearchResult] = []
        var page = 1
        let maxPages = 2

        while page <= maxPages {
            let batch = try await searchPRs(query: query, page: page)
            if batch.isEmpty {
                break
            }
            searchResults.append(contentsOf: batch)
            if batch.count < 30 {
                break
            }
            page += 1
        }

        var involved: [InvolvedPR] = []
        try await withThrowingTaskGroup(of: InvolvedPR?.self) { group in
            var iterator = searchResults.makeIterator()
            let concurrency = 5
            for _ in 0..<min(concurrency, searchResults.count) {
                if let result = iterator.next() {
                    group.addTask {
                        try await self.fetchPRActivityMetadata(owner: result.owner, repo: result.repo, number: result.number)
                    }
                }
            }
            for try await pr in group {
                if let pr {
                    involved.append(pr)
                }
                if let result = iterator.next() {
                    group.addTask {
                        try await self.fetchPRActivityMetadata(owner: result.owner, repo: result.repo, number: result.number)
                    }
                }
            }
        }
        return involved
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

    private func fetchPRActivityMetadata(owner: String, repo: String, number: Int) async throws -> InvolvedPR? {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)") else {
            throw GitHubError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.noData
        }

        if httpResponse.statusCode == 404 {
            return nil
        }
        if httpResponse.statusCode == 401 {
            throw GitHubError.unauthorized
        }
        if httpResponse.statusCode == 403 {
            throw GitHubError.rateLimited
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let prResponse = try decoder.decode(PRResponse.self, from: data)
        let mergeableState = prResponse.mergeableState
        let hasConflicts = mergeableState == "dirty" || mergeableState == "conflicting"

        return InvolvedPR(
            owner: owner,
            repo: repo,
            number: prResponse.number,
            title: prResponse.title,
            htmlUrl: prResponse.htmlUrl,
            headSha: prResponse.head?.sha ?? "",
            mergeableState: mergeableState,
            hasConflicts: hasConflicts
        )
    }

    private func apiURL(_ path: String) throws -> URL {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw GitHubError.invalidURL
        }
        return url
    }

    private func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.noData
        }
        if httpResponse.statusCode == 401 {
            throw GitHubError.unauthorized
        }
        if httpResponse.statusCode == 403 {
            throw GitHubError.rateLimited
        }
        guard httpResponse.statusCode == 200 else {
            throw GitHubError.noData
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    /// Run one or more search queries, union SearchResults by owner/repo/number, then fetch PR details once each.
    private func fetchDetailedPRs(queries: [String], maxPagesPerQuery: Int) async throws -> [PullRequest] {
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
                if batch.count < 30 {
                    break
                }
                page += 1
            }
        }
        
        var allPRs: [PullRequest] = []
        try await withThrowingTaskGroup(of: PullRequest?.self) { group in
            var iterator = ordered.makeIterator()
            let concurrency = 5
            for _ in 0..<min(concurrency, ordered.count) {
                if let result = iterator.next() {
                    group.addTask {
                        try await self.fetchPRDetails(owner: result.owner, repo: result.repo, number: result.number)
                    }
                }
            }
            for try await pr in group {
                if let pr {
                    allPRs.append(pr)
                }
                if let result = iterator.next() {
                    group.addTask {
                        try await self.fetchPRDetails(owner: result.owner, repo: result.repo, number: result.number)
                    }
                }
            }
        }
        
        var seenIds = Set<Int>()
        return allPRs.filter { seenIds.insert($0.id).inserted }
    }

    private func searchPRs(query: String, page: Int) async throws -> [SearchResult] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search/issues?q=\(encodedQuery)&per_page=30&page=\(page)") else {
            throw GitHubError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.noData
        }
        
        if httpResponse.statusCode == 401 {
            throw GitHubError.unauthorized
        }
        
        if httpResponse.statusCode == 403 {
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
    
    private func fetchPRDetails(owner: String, repo: String, number: Int) async throws -> PullRequest? {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)") else {
            throw GitHubError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubError.noData
        }
        
        if httpResponse.statusCode == 404 {
            return nil
        }
        
        if httpResponse.statusCode == 401 {
            throw GitHubError.unauthorized
        }
        
        if httpResponse.statusCode == 403 {
            throw GitHubError.rateLimited
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        let prResponse = try decoder.decode(PRResponse.self, from: data)
        
        let reviewComments = try await fetchReviewComments(owner: owner, repo: repo, number: number)
        
        let hasConflicts = prResponse.mergeableState == "dirty" || prResponse.mergeableState == "conflicting"
        
        let requestedReviewers = prResponse.requestedReviewers?.map { $0.login } ?? []
        
        let issueCommentCount = prResponse.comments ?? 0
        let reviewCommentCount = prResponse.reviewComments ?? 0
        let commentCount = issueCommentCount + reviewCommentCount
        
        let headSha = prResponse.head?.sha ?? ""
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
        
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
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

private struct ReviewCommentResponse: Codable {
    let id: Int
    let state: String?
    let user: User
    let createdAt: Date
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
