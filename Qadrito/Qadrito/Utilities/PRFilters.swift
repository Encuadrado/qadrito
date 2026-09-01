import Foundation

struct PRFilters {
    static func filterByAuthor(_ prs: [PullRequest], author: String?, slackMap: [String: SlackUser]) -> [PullRequest] {
        guard let author = author, !author.isEmpty else {
            return prs
        }
        
        let normalizedAuthor = author.lowercased().trimmingCharacters(in: .whitespaces)
        
        return prs.filter { pr in
            let prAuthor = pr.author.lowercased()
            
            if prAuthor.contains(normalizedAuthor) {
                return true
            }
            
            if let slackUser = slackMap[pr.author] {
                let slackName = slackUser.slackName.lowercased()
                if slackName.contains(normalizedAuthor) {
                    return true
                }
            }
            
            return false
        }
    }
    
    static func filterByRepo(_ prs: [PullRequest], repo: String?) -> [PullRequest] {
        guard let repo = repo, !repo.isEmpty else {
            return prs
        }
        
        let normalizedRepo = repo.lowercased().trimmingCharacters(in: .whitespaces)
        
        return prs.filter { pr in
            pr.repositoryName.lowercased().contains(normalizedRepo) ||
            pr.shortRepo.lowercased().contains(normalizedRepo)
        }
    }
    
    static func applyFilters(_ prs: [PullRequest], author: String?, repo: String?, slackMap: [String: SlackUser]) -> [PullRequest] {
        var filtered = prs
        
        if let author = author, !author.isEmpty {
            filtered = filterByAuthor(filtered, author: author, slackMap: slackMap)
        }
        
        if let repo = repo, !repo.isEmpty {
            filtered = filterByRepo(filtered, repo: repo)
        }
        
        return filtered
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
