import Foundation

struct PRFilters {
    static func filterByAuthor(_ prs: [PullRequest], authors: Set<String>?, slackMap: [String: SlackUser]) -> [PullRequest] {
        guard let authors = authors, !authors.isEmpty else {
            return prs
        }
        
        let normalizedAuthors = authors
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !normalizedAuthors.isEmpty else {
            return prs
        }
        
        return prs.filter { pr in
            let prAuthor = pr.author.lowercased()
            let slackName = slackMap[pr.author]?.slackName.lowercased()
            
            return normalizedAuthors.contains { selected in
                if prAuthor.contains(selected) {
                    return true
                }
                if let slackName, slackName.contains(selected) {
                    return true
                }
                return false
            }
        }
    }
    
    /// Backward-compatible single-author entry point.
    static func filterByAuthor(_ prs: [PullRequest], author: String?, slackMap: [String: SlackUser]) -> [PullRequest] {
        guard let author = author, !author.isEmpty else {
            return prs
        }
        return filterByAuthor(prs, authors: [author], slackMap: slackMap)
    }
    
    static func filterByRepo(_ prs: [PullRequest], repos: Set<String>?) -> [PullRequest] {
        guard let repos = repos, !repos.isEmpty else {
            return prs
        }
        
        let normalizedRepos = repos
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !normalizedRepos.isEmpty else {
            return prs
        }
        
        return prs.filter { pr in
            let full = pr.repositoryName.lowercased()
            let short = pr.shortRepo.lowercased()
            return normalizedRepos.contains { selected in
                full.contains(selected) || short.contains(selected)
            }
        }
    }
    
    /// Backward-compatible single-repo entry point.
    static func filterByRepo(_ prs: [PullRequest], repo: String?) -> [PullRequest] {
        guard let repo = repo, !repo.isEmpty else {
            return prs
        }
        return filterByRepo(prs, repos: [repo])
    }
    
    /// Filter by org team review requests. `teams` are display names and/or slugs;
    /// `teamSlugByName` maps display name → slug (from org teams catalog).
    static func filterByTeam(
        _ prs: [PullRequest],
        teams: Set<String>?,
        teamSlugByName: [String: String] = [:]
    ) -> [PullRequest] {
        guard let teams = teams, !teams.isEmpty else {
            return prs
        }
        
        let selected = teams
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !selected.isEmpty else { return prs }
        
        // Resolve each selection to a set of match keys (slug + name, lowercased).
        var keys = Set<String>()
        for raw in selected {
            let lower = raw.lowercased()
            keys.insert(lower)
            if let slug = teamSlugByName[raw] ?? teamSlugByName.first(where: {
                $0.key.caseInsensitiveCompare(raw) == .orderedSame
            })?.value {
                keys.insert(slug.lowercased())
            }
        }
        
        return prs.filter { pr in
            pr.requestedTeams.contains { team in
                keys.contains(team.lowercased())
            }
        }
    }
    
    /// Filter PRs whose labels intersect the selection (label names).
    static func filterByTag(_ prs: [PullRequest], tags: Set<String>?) -> [PullRequest] {
        guard let tags = tags, !tags.isEmpty else {
            return prs
        }
        
        let normalized = tags
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return prs }
        
        return prs.filter { pr in
            pr.labels.contains { label in
                normalized.contains(label.lowercased())
            }
        }
    }
    
    static func applyFilters(
        _ prs: [PullRequest],
        authors: Set<String>?,
        repos: Set<String>?,
        teams: Set<String>? = nil,
        tags: Set<String>? = nil,
        teamSlugByName: [String: String] = [:],
        slackMap: [String: SlackUser]
    ) -> [PullRequest] {
        var filtered = prs
        
        if let teams = teams, !teams.isEmpty {
            filtered = filterByTeam(filtered, teams: teams, teamSlugByName: teamSlugByName)
        }
        
        if let authors = authors, !authors.isEmpty {
            filtered = filterByAuthor(filtered, authors: authors, slackMap: slackMap)
        }
        
        if let repos = repos, !repos.isEmpty {
            filtered = filterByRepo(filtered, repos: repos)
        }
        
        if let tags = tags, !tags.isEmpty {
            filtered = filterByTag(filtered, tags: tags)
        }
        
        return filtered
    }
    
    /// Backward-compatible single-value filters.
    static func applyFilters(_ prs: [PullRequest], author: String?, repo: String?, slackMap: [String: SlackUser]) -> [PullRequest] {
        let authors: Set<String>? = {
            guard let author = author, !author.isEmpty else { return nil }
            return [author]
        }()
        let repos: Set<String>? = {
            guard let repo = repo, !repo.isEmpty else { return nil }
            return [repo]
        }()
        return applyFilters(prs, authors: authors, repos: repos, slackMap: slackMap)
    }
    
    static func getEasiestFive(_ prs: [PullRequest]) -> [PullRequest] {
        let sorted = prs.sorted { pr1, pr2 in
            if pr1.changedFiles != pr2.changedFiles {
                return pr1.changedFiles < pr2.changedFiles
            }
            
            let size1 = pr1.additions + pr1.deletions
            let size2 = pr2.additions + pr2.deletions
            
            if size1 != size2 {
                return size1 < size2
            }
            
            return pr1.createdAt < pr2.createdAt
        }
        
        return Array(sorted.prefix(5))
    }
    
    static func getOldestFive(_ prs: [PullRequest]) -> [PullRequest] {
        let sorted = prs.sorted { $0.createdAt < $1.createdAt }
        return Array(sorted.prefix(5))
    }
}
