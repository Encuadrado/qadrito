import Foundation

struct AppSettings: Codable {
    var githubPAT: String
    var githubLogin: String
    var organization: String
    var slackMap: [String: SlackUser]
    
    init() {
        self.githubPAT = ""
        self.githubLogin = ""
        self.organization = "Encuadrado"
        self.slackMap = [:]
    }
}

struct SlackUser: Codable, Hashable {
    let slackUserId: String
    let slackName: String
}

struct PullRequest: Identifiable, Codable, Equatable {
    let id: Int
    let number: Int
    let title: String
    let htmlUrl: String
    let author: String
    let createdAt: Date
    let isDraft: Bool
    let state: String
    let repositoryName: String
    let changedFiles: Int
    let additions: Int
    let deletions: Int
    let mergeable: Bool?
    let mergeableState: String?
    let hasConflicts: Bool
    let reviewDecision: String?
    let reviewComments: [ReviewComment]
    let requestedReviewers: [String]
    
    var age: TimeInterval {
        Date().timeIntervalSince(createdAt)
    }
    
    var ageDays: Int {
        Int(age / 86400)
    }
    
    var shortRepo: String {
        repoShortMap[repositoryName] ?? repositoryName
    }
    
    var displayName: String {
        "\(shortRepo)#\(number)"
    }
    
    var isClosingSoon: Bool {
        ageDays >= 30
    }
    
    var changeSize: Int {
        additions + deletions
    }
    
    static func == (lhs: PullRequest, rhs: PullRequest) -> Bool {
        lhs.id == rhs.id
    }
}

struct ReviewComment: Codable {
    let id: Int
    let state: String
    let author: String
    let createdAt: Date
}

struct PRStack: Identifiable {
    let tip: PullRequest
    let stackSize: Int
    
    var id: Int { tip.id }
    
    var displayName: String {
        if stackSize > 1 {
            return "\(tip.displayName) (\(stackSize))"
        }
        return tip.displayName
    }
}

struct CachedData: Codable {
    let waitingPRs: [PullRequest]
    let timestamp: Date
}

let repoShortMap: [String: String] = [
    "encuadrado-web": "web",
    "encuadrado-dania-chat-agent": "dania",
    "encuadrado-professional-home": "professional-home",
    "encuadrado-customer-public": "customer-public",
    "encuadrado-client-home": "client-home",
    "mobile_app_encuadrado": "mobile",
    "encuadrado-profiles": "profiles",
    "encuadrado-center-profiles": "center-profiles",
    "encuadrado-components": "components",
    "docs": "docs",
    "encuadrado-isapres": "isapres",
    "encuadrado-client-facing-views": "client-facing-views",
    "encuadrado-nextjs": "nextjs"
]
