import XCTest
@testable import QAdrito

final class PRFiltersTests: XCTestCase {
    
    func testFilterByAuthor_ExactMatch() throws {
        let pr1 = makePR(id: 1, number: 1, author: "cnovoab")
        let pr2 = makePR(id: 2, number: 2, author: "other")
        
        let filtered = PRFilters.filterByAuthor([pr1, pr2], author: "cnovoab", slackMap: [:])
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.author, "cnovoab")
    }
    
    func testFilterByAuthor_PartialMatch() throws {
        let pr1 = makePR(id: 1, number: 1, author: "cnovoab")
        let pr2 = makePR(id: 2, number: 2, author: "other")
        
        let filtered = PRFilters.filterByAuthor([pr1, pr2], author: "novo", slackMap: [:])
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.author, "cnovoab")
    }
    
    func testFilterByAuthor_SlackNameMatch() throws {
        let pr1 = makePR(id: 1, number: 1, author: "cnovoab")
        let pr2 = makePR(id: 2, number: 2, author: "other")
        
        let slackMap: [String: SlackUser] = [
            "cnovoab": SlackUser(slackUserId: "U123", slackName: "Claudio")
        ]
        
        let filtered = PRFilters.filterByAuthor([pr1, pr2], author: "claudio", slackMap: slackMap)
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.author, "cnovoab")
    }
    
    func testFilterByAuthor_CaseInsensitive() throws {
        let pr1 = makePR(id: 1, number: 1, author: "cnovoab")
        let pr2 = makePR(id: 2, number: 2, author: "other")
        
        let filtered = PRFilters.filterByAuthor([pr1, pr2], author: "CNOVO", slackMap: [:])
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.author, "cnovoab")
    }
    
    func testFilterByRepo_ShortName() throws {
        let pr1 = makePR(id: 1, number: 1, author: "user", repo: "encuadrado-web")
        let pr2 = makePR(id: 2, number: 2, author: "user", repo: "encuadrado-dania-chat-agent")
        
        let filtered = PRFilters.filterByRepo([pr1, pr2], repo: "web")
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.repositoryName, "encuadrado-web")
    }
    
    func testFilterByRepo_FullName() throws {
        let pr1 = makePR(id: 1, number: 1, author: "user", repo: "encuadrado-web")
        let pr2 = makePR(id: 2, number: 2, author: "user", repo: "encuadrado-dania-chat-agent")
        
        let filtered = PRFilters.filterByRepo([pr1, pr2], repo: "encuadrado-web")
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.repositoryName, "encuadrado-web")
    }
    
    func testFilterByRepo_PartialMatch() throws {
        let pr1 = makePR(id: 1, number: 1, author: "user", repo: "encuadrado-web")
        let pr2 = makePR(id: 2, number: 2, author: "user", repo: "encuadrado-dania-chat-agent")
        
        let filtered = PRFilters.filterByRepo([pr1, pr2], repo: "dania")
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.repositoryName, "encuadrado-dania-chat-agent")
    }
    
    func testGetEasiestFive_SortsByFiles() throws {
        let pr1 = makePR(id: 1, number: 1, author: "user", files: 10, additions: 100, deletions: 50)
        let pr2 = makePR(id: 2, number: 2, author: "user", files: 3, additions: 100, deletions: 50)
        let pr3 = makePR(id: 3, number: 3, author: "user", files: 7, additions: 100, deletions: 50)
        
        let easiest = PRFilters.getEasiestFive([pr1, pr2, pr3])
        
        XCTAssertEqual(easiest.count, 3)
        XCTAssertEqual(easiest[0].id, pr2.id, "PR with fewest files should be first")
        XCTAssertEqual(easiest[1].id, pr3.id)
        XCTAssertEqual(easiest[2].id, pr1.id)
    }
    
    func testGetEasiestFive_TieBreakByLines() throws {
        let pr1 = makePR(id: 1, number: 1, author: "user", files: 5, additions: 200, deletions: 100)
        let pr2 = makePR(id: 2, number: 2, author: "user", files: 5, additions: 50, deletions: 25)
        
        let easiest = PRFilters.getEasiestFive([pr1, pr2])
        
        XCTAssertEqual(easiest[0].id, pr2.id, "PR with fewer lines should be first")
        XCTAssertEqual(easiest[1].id, pr1.id)
    }
    
    func testGetEasiestFive_LimitsToFive() throws {
        let prs = (1...10).map { i in
            makePR(id: i, number: i, author: "user", files: i)
        }
        
        let easiest = PRFilters.getEasiestFive(prs)
        
        XCTAssertEqual(easiest.count, 5, "Should return maximum of 5 PRs")
    }
    
    func testGetOldestFive_SortsByCreationDate() throws {
        let pr1 = makePR(id: 1, number: 1, author: "user", daysOld: 5)
        let pr2 = makePR(id: 2, number: 2, author: "user", daysOld: 10)
        let pr3 = makePR(id: 3, number: 3, author: "user", daysOld: 2)
        
        let oldest = PRFilters.getOldestFive([pr1, pr2, pr3])
        
        XCTAssertEqual(oldest.count, 3)
        XCTAssertEqual(oldest[0].id, pr2.id, "Oldest PR should be first")
        XCTAssertEqual(oldest[1].id, pr1.id)
        XCTAssertEqual(oldest[2].id, pr3.id)
    }
    
    func testGetOldestFive_LimitsToFive() throws {
        let prs = (1...10).map { i in
            makePR(id: i, number: i, author: "user", daysOld: i)
        }
        
        let oldest = PRFilters.getOldestFive(prs)
        
        XCTAssertEqual(oldest.count, 5, "Should return maximum of 5 PRs")
        XCTAssertEqual(oldest[0].ageDays, 10, "First should be oldest")
    }
    
    func testApplyFilters_Combined() throws {
        let pr1 = makePR(id: 1, number: 1, author: "cnovoab", repo: "encuadrado-web")
        let pr2 = makePR(id: 2, number: 2, author: "cnovoab", repo: "encuadrado-dania-chat-agent")
        let pr3 = makePR(id: 3, number: 3, author: "other", repo: "encuadrado-web")
        
        let filtered = PRFilters.applyFilters(
            [pr1, pr2, pr3],
            authors: ["cnovo"],
            repos: ["web"],
            slackMap: [:]
        )
        
        XCTAssertEqual(filtered.count, 1, "Should match both author and repo")
        XCTAssertEqual(filtered.first?.id, pr1.id)
    }
    
    func testFilterByAuthor_MultipleAuthors() throws {
        let pr1 = makePR(id: 1, number: 1, author: "cnovoab")
        let pr2 = makePR(id: 2, number: 2, author: "alice")
        let pr3 = makePR(id: 3, number: 3, author: "bob")
        
        let filtered = PRFilters.filterByAuthor(
            [pr1, pr2, pr3],
            authors: ["cnovoab", "alice"],
            slackMap: [:]
        )
        
        XCTAssertEqual(Set(filtered.map(\.id)), Set([1, 2]))
    }
    
    func testFilterByAuthor_EmptySetShowsAll() throws {
        let pr1 = makePR(id: 1, number: 1, author: "cnovoab")
        let pr2 = makePR(id: 2, number: 2, author: "other")
        
        let filtered = PRFilters.filterByAuthor([pr1, pr2], authors: [], slackMap: [:])
        
        XCTAssertEqual(filtered.count, 2)
    }
    
    func testFilterByRepo_MultipleRepos() throws {
        let pr1 = makePR(id: 1, number: 1, author: "user", repo: "encuadrado-web")
        let pr2 = makePR(id: 2, number: 2, author: "user", repo: "encuadrado-dania-chat-agent")
        let pr3 = makePR(id: 3, number: 3, author: "user", repo: "encuadrado-mobile")
        
        let filtered = PRFilters.filterByRepo(
            [pr1, pr2, pr3],
            repos: ["encuadrado-web", "encuadrado-mobile"]
        )
        
        XCTAssertEqual(Set(filtered.map(\.id)), Set([1, 3]))
    }
    
    func testApplyFilters_MultipleAuthorsAndRepos() throws {
        let pr1 = makePR(id: 1, number: 1, author: "cnovoab", repo: "encuadrado-web")
        let pr2 = makePR(id: 2, number: 2, author: "alice", repo: "encuadrado-web")
        let pr3 = makePR(id: 3, number: 3, author: "cnovoab", repo: "encuadrado-mobile")
        let pr4 = makePR(id: 4, number: 4, author: "bob", repo: "encuadrado-dania-chat-agent")
        
        let filtered = PRFilters.applyFilters(
            [pr1, pr2, pr3, pr4],
            authors: ["cnovoab", "alice"],
            repos: ["encuadrado-web", "encuadrado-mobile"],
            slackMap: [:]
        )
        
        // pr1 (cnovoab+web), pr2 (alice+web), pr3 (cnovoab+mobile); not pr4
        XCTAssertEqual(Set(filtered.map(\.id)), Set([1, 2, 3]))
    }
    
    private func makePR(
        id: Int,
        number: Int,
        author: String,
        repo: String = "test-repo",
        files: Int = 5,
        additions: Int = 100,
        deletions: Int = 50,
        daysOld: Int = 1,
        githubStackId: Int? = nil,
        stackPosition: Int? = nil,
        githubStackSize: Int? = nil,
        baseRef: String = "main",
        headRef: String? = nil
    ) -> PullRequest {
        let createdAt = Date().addingTimeInterval(-TimeInterval(daysOld * 86400))
        
        return PullRequest(
            id: id,
            number: number,
            title: "Test PR \(number)",
            htmlUrl: "https://github.com/test/\(repo)/pull/\(number)",
            author: author,
            createdAt: createdAt,
            isDraft: false,
            state: "open",
            repositoryName: repo,
            changedFiles: files,
            additions: additions,
            deletions: deletions,
            mergeable: true,
            mergeableState: "clean",
            hasConflicts: false,
            reviewDecision: nil,
            reviewComments: [],
            requestedReviewers: [],
            githubStackId: githubStackId,
            stackPosition: stackPosition,
            githubStackSize: githubStackSize,
            baseRef: baseRef,
            headRef: headRef ?? "branch-\(number)"
        )
    }
}
