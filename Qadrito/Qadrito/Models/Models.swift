import Foundation

struct AppSettings: Codable {
    var githubLogin: String
    var organization: String
    var slackMap: [String: SlackUser]
    
    init() {
        self.githubLogin = ""
        self.organization = "Encuadrado"
        self.slackMap = [:]
    }
}

struct SlackUser: Codable, Hashable {
    let slackUserId: String
    let slackName: String
}

enum PRScope: String, CaseIterable, Identifiable {
    case myPullRequests = "My Pull Requests"
    case waitingForMe = "Waiting for me"
    case all = "All"
    
    var id: String { rawValue }
    
    /// Shorter label for segmented tabs.
    var tabTitle: String {
        switch self {
        case .waitingForMe: return "Waiting for me"
        case .myPullRequests: return "My Pull Requests"
        case .all: return "All"
        }
    }
    
    /// Stable id for per-scope cache filenames.
    var cacheFileId: String {
        switch self {
        case .myPullRequests: return "myPullRequests"
        case .waitingForMe: return "waitingForMe"
        case .all: return "all"
        }
    }
}

/// Age buckets for the default list layout. Uses wall-clock age, not truncated `ageDays`.
enum PRAgeGroup: Int, CaseIterable, Identifiable {
    case critical
    case warning
    case onTime
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .critical: return "Critical"
        case .warning: return "Warning"
        case .onTime: return "On time"
        }
    }
    
    /// SF Symbol used in section headers.
    var systemImage: String {
        switch self {
        case .critical: return "circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .onTime: return "circle.fill"
        }
    }
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
    /// GitHub official stack id when this PR belongs to a stack; nil for standalone PRs.
    let githubStackId: Int?
    /// 1-based position within the GitHub stack (1 = bottom / closest to trunk).
    let stackPosition: Int?
    /// Full GitHub-reported stack size (may exceed local `prs.count` if not all members are loaded).
    let githubStackSize: Int?
    /// Base branch ref (e.g. `main` or another PR's head branch).
    let baseRef: String
    /// Head branch ref for this PR.
    let headRef: String
    /// Successful check-runs / status contexts counted toward the fraction.
    let checkPassed: Int?
    /// Total relevant checks (excludes skipped). Nil when unknown.
    let checkTotal: Int?
    /// Aggregate checks state: success / failure / pending / neutral (or nil).
    let checksConclusion: String?
    /// Issue comments + review comments count from the PR API.
    let commentCount: Int
    
    init(
        id: Int,
        number: Int,
        title: String,
        htmlUrl: String,
        author: String,
        createdAt: Date,
        isDraft: Bool,
        state: String,
        repositoryName: String,
        changedFiles: Int,
        additions: Int,
        deletions: Int,
        mergeable: Bool?,
        mergeableState: String?,
        hasConflicts: Bool,
        reviewDecision: String?,
        reviewComments: [ReviewComment],
        requestedReviewers: [String],
        githubStackId: Int? = nil,
        stackPosition: Int? = nil,
        githubStackSize: Int? = nil,
        baseRef: String = "",
        headRef: String = "",
        checkPassed: Int? = nil,
        checkTotal: Int? = nil,
        checksConclusion: String? = nil,
        commentCount: Int = 0
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.htmlUrl = htmlUrl
        self.author = author
        self.createdAt = createdAt
        self.isDraft = isDraft
        self.state = state
        self.repositoryName = repositoryName
        self.changedFiles = changedFiles
        self.additions = additions
        self.deletions = deletions
        self.mergeable = mergeable
        self.mergeableState = mergeableState
        self.hasConflicts = hasConflicts
        self.reviewDecision = reviewDecision
        self.reviewComments = reviewComments
        self.requestedReviewers = requestedReviewers
        self.githubStackId = githubStackId
        self.stackPosition = stackPosition
        self.githubStackSize = githubStackSize
        self.baseRef = baseRef
        self.headRef = headRef
        self.checkPassed = checkPassed
        self.checkTotal = checkTotal
        self.checksConclusion = checksConclusion
        self.commentCount = commentCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
        author = try container.decode(String.self, forKey: .author)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isDraft = try container.decode(Bool.self, forKey: .isDraft)
        state = try container.decode(String.self, forKey: .state)
        repositoryName = try container.decode(String.self, forKey: .repositoryName)
        changedFiles = try container.decode(Int.self, forKey: .changedFiles)
        additions = try container.decode(Int.self, forKey: .additions)
        deletions = try container.decode(Int.self, forKey: .deletions)
        mergeable = try container.decodeIfPresent(Bool.self, forKey: .mergeable)
        mergeableState = try container.decodeIfPresent(String.self, forKey: .mergeableState)
        hasConflicts = try container.decode(Bool.self, forKey: .hasConflicts)
        reviewDecision = try container.decodeIfPresent(String.self, forKey: .reviewDecision)
        reviewComments = try container.decode([ReviewComment].self, forKey: .reviewComments)
        requestedReviewers = try container.decode([String].self, forKey: .requestedReviewers)
        githubStackId = try container.decodeIfPresent(Int.self, forKey: .githubStackId)
        stackPosition = try container.decodeIfPresent(Int.self, forKey: .stackPosition)
        githubStackSize = try container.decodeIfPresent(Int.self, forKey: .githubStackSize)
        baseRef = try container.decodeIfPresent(String.self, forKey: .baseRef) ?? ""
        headRef = try container.decodeIfPresent(String.self, forKey: .headRef) ?? ""
        checkPassed = try container.decodeIfPresent(Int.self, forKey: .checkPassed)
        checkTotal = try container.decodeIfPresent(Int.self, forKey: .checkTotal)
        checksConclusion = try container.decodeIfPresent(String.self, forKey: .checksConclusion)
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
    }
    
    var age: TimeInterval {
        Date().timeIntervalSince(createdAt)
    }
    
    var ageDays: Int {
        Int(age / 86400)
    }
    
    var ageGroup: PRAgeGroup {
        if age > 7 * 86400 {
            return .critical
        }
        if age > 2 * 86400 {
            return .warning
        }
        return .onTime
    }
    
    var ageText: String {
        // Under 1 day → hours (including 0h for brand-new PRs).
        if age < 86400 {
            let hours = max(Int(age / 3600), 0)
            return "\(hours)h"
        }
        let days = ageDays
        if days == 1 {
            return "1 day"
        }
        return "\(days) days"
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

/// Stack of related PRs. `prs` is ordered bottom → tip (GitHub position ascending).
struct PRStack: Identifiable {
    let prs: [PullRequest]
    
    /// First in the chain (stack bottom) — shown as the main list row.
    var base: PullRequest { prs.first! }
    /// Last in the chain (stack tip).
    var tip: PullRequest { prs.last! }
    /// Prefer GitHub's full stack size when larger than locally loaded members.
    var stackSize: Int {
        let apiSize = prs.compactMap(\.githubStackSize).max() ?? 0
        return max(prs.count, apiSize)
    }
    var id: Int { base.id }
    
    /// Oldest / bottom member — used for age grouping so long-running stacks stay urgent.
    var groupingPR: PullRequest { base }
    
    var displayName: String {
        base.displayName
    }
}

struct PRAgeSection: Identifiable {
    let group: PRAgeGroup
    let stacks: [PRStack]
    
    var id: Int { group.rawValue }
}

struct ScopeCache {
    var prs: [PullRequest]
    var timestamp: Date
    var capped: Bool
}

struct CachedData: Codable {
    let waitingPRs: [PullRequest]
    let timestamp: Date
    let capped: Bool
    
    init(waitingPRs: [PullRequest], timestamp: Date, capped: Bool = false) {
        self.waitingPRs = waitingPRs
        self.timestamp = timestamp
        self.capped = capped
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        waitingPRs = try container.decode([PullRequest].self, forKey: .waitingPRs)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        capped = try container.decodeIfPresent(Bool.self, forKey: .capped) ?? false
    }
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
