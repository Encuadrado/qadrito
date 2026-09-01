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
    
    init(token: String) {
        self.token = token
    }
    
    func updateToken(_ newToken: String) {
        self.token = newToken
    }
    
    func searchPRsForReview(login: String, org: String) async throws -> [PullRequest] {
        let query = "org:\(org) is:open is:pr review-requested:\(login)"
        var allPRs: [PullRequest] = []
        var page = 1
        
        while true {
            let searchResults = try await searchPRs(query: query, page: page)
            
            if searchResults.isEmpty {
                break
            }
            
            for searchResult in searchResults {
                if let detailedPR = try await fetchPRDetails(
                    owner: searchResult.owner,
                    repo: searchResult.repo,
                    number: searchResult.number
                ) {
                    allPRs.append(detailedPR)
                }
            }
            
            if searchResults.count < 30 {
                break
            }
            page += 1
        }
        
        return allPRs.filter { pr in
            pr.state == "open" && (!pr.isDraft || !pr.requestedReviewers.isEmpty)
        }
    }
    
    func fetchOwnPRs(login: String, org: String) async throws -> [PullRequest] {
        let query = "org:\(org) is:open is:pr author:\(login)"
        var allPRs: [PullRequest] = []
        var page = 1
        
        while true {
            let searchResults = try await searchPRs(query: query, page: page)
            
            if searchResults.isEmpty {
                break
            }
            
            for searchResult in searchResults {
                if let detailedPR = try await fetchPRDetails(
                    owner: searchResult.owner,
                    repo: searchResult.repo,
                    number: searchResult.number
                ) {
                    allPRs.append(detailedPR)
                }
            }
            
            if searchResults.count < 30 {
                break
            }
            page += 1
        }
        
        return allPRs.filter { $0.state == "open" }
    }
    
    private func searchPRs(query: String, page: Int) async throws -> [SearchResult] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/search/issues?q=\(encodedQuery)&per_page=30&page=\(page)") else {
            throw GitHubError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
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
            requestedReviewers: requestedReviewers
        )
    }
    
    private func fetchReviewComments(owner: String, repo: String, number: Int) async throws -> [ReviewComment] {
        guard let url = URL(string: "\(baseURL)/repos/\(owner)/\(repo)/pulls/\(number)/comments") else {
            throw GitHubError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
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

private struct SearchResult {
    let owner: String
    let repo: String
    let number: Int
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
