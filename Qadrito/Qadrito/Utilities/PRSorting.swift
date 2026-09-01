import Foundation

struct PRSorting {
    static func sortWaitingPRs(_ prs: [PullRequest], userLogin: String) -> [PullRequest] {
        return prs.sorted { pr1, pr2 in
            let isBot1 = isBotPR(pr1)
            let isBot2 = isBotPR(pr2)
            
            if isBot1 && !isBot2 {
                return false
            }
            if !isBot1 && isBot2 {
                return true
            }
            
            let closing1 = pr1.isClosingSoon
            let closing2 = pr2.isClosingSoon
            
            if closing1 && !closing2 {
                return true
            }
            if !closing1 && closing2 {
                return false
            }
            
            let sole1 = isSoleReviewer(pr1, login: userLogin)
            let sole2 = isSoleReviewer(pr2, login: userLogin)
            
            if sole1 && !sole2 {
                return true
            }
            if !sole1 && sole2 {
                return false
            }
            
            return pr1.createdAt < pr2.createdAt
        }
    }
    
    
    private static func isBotPR(_ pr: PullRequest) -> Bool {
        let botKeywords = ["mintlify", "bot", "renovate", "dependabot"]
        let lowerAuthor = pr.author.lowercased()
        return botKeywords.contains { lowerAuthor.contains($0) }
    }
    
    private static func isSoleReviewer(_ pr: PullRequest, login: String) -> Bool {
        return pr.requestedReviewers.count == 1 && 
               pr.requestedReviewers.first?.lowercased() == login.lowercased()
    }
}
