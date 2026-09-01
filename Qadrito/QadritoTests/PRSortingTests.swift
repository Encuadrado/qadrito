import XCTest
@testable import Qadrito

final class PRSortingTests: XCTestCase {
    
    func testSortWaitingPRs_ClosingSoonFirst() throws {
        let oldPR = makePR(id: 1, number: 1, author: "user1", daysOld: 35)
        let recentPR = makePR(id: 2, number: 2, author: "user2", daysOld: 5)
        
        let sorted = PRSorting.sortWaitingPRs([recentPR, oldPR], userLogin: "testuser")
        
        XCTAssertEqual(sorted.first?.id, oldPR.id, "Closing soon PR should be first")
    }
    
    func testSortWaitingPRs_BotPRsLast() throws {
        let regularPR = makePR(id: 1, number: 1, author: "user1", daysOld: 10)
        let botPR = makePR(id: 2, number: 2, author: "mintlify-bot", daysOld: 5)
        
        let sorted = PRSorting.sortWaitingPRs([botPR, regularPR], userLogin: "testuser")
        
        XCTAssertEqual(sorted.first?.id, regularPR.id, "Regular PR should come before bot PR")
        XCTAssertEqual(sorted.last?.id, botPR.id, "Bot PR should be last")
    }
    
    func testSortWaitingPRs_SoleReviewerPriority() throws {
        let soleReviewerPR = makePR(id: 1, number: 1, author: "user1", daysOld: 10, requestedReviewers: ["testuser"])
        let multiReviewerPR = makePR(id: 2, number: 2, author: "user2", daysOld: 5, requestedReviewers: ["testuser", "other"])
        
        let sorted = PRSorting.sortWaitingPRs([multiReviewerPR, soleReviewerPR], userLogin: "testuser")
        
        XCTAssertEqual(sorted.first?.id, soleReviewerPR.id, "Sole reviewer PR should be first")
    }
    
    func testSortWaitingPRs_OldestWhenOtherwiseEqual() throws {
        let olderPR = makePR(id: 1, number: 1, author: "user1", daysOld: 10)
        let newerPR = makePR(id: 2, number: 2, author: "user2", daysOld: 5)
        
        let sorted = PRSorting.sortWaitingPRs([newerPR, olderPR], userLogin: "testuser")
        
        XCTAssertEqual(sorted.first?.id, olderPR.id, "Older PR should be first when other factors equal")
    }
    
    func testSortWaitingPRs_ComplexScenario() throws {
        let botPR = makePR(id: 1, number: 1, author: "dependabot", daysOld: 50)
        let closingPR = makePR(id: 2, number: 2, author: "user1", daysOld: 32)
        let solePR = makePR(id: 3, number: 3, author: "user2", daysOld: 7, requestedReviewers: ["testuser"])
        let regularPR = makePR(id: 4, number: 4, author: "user3", daysOld: 5, requestedReviewers: ["testuser", "other"])
        
        let sorted = PRSorting.sortWaitingPRs([regularPR, botPR, solePR, closingPR], userLogin: "testuser")
        
        XCTAssertEqual(sorted[0].id, closingPR.id, "Closing soon should be first")
        XCTAssertEqual(sorted[1].id, solePR.id, "Sole reviewer should be second")
        XCTAssertEqual(sorted[2].id, regularPR.id, "Regular PR should be third")
        XCTAssertEqual(sorted[3].id, botPR.id, "Bot PR should be last")
    }
    
    private func makePR(
        id: Int,
        number: Int,
        author: String,
        daysOld: Int,
        requestedReviewers: [String] = []
    ) -> PullRequest {
        let createdAt = Date().addingTimeInterval(-TimeInterval(daysOld * 86400))
        
        return PullRequest(
            id: id,
            number: number,
            title: "Test PR \(number)",
            htmlUrl: "https://github.com/test/repo/pull/\(number)",
            author: author,
            createdAt: createdAt,
            isDraft: false,
            state: "open",
            repositoryName: "test-repo",
            changedFiles: 5,
            additions: 100,
            deletions: 50,
            mergeable: true,
            mergeableState: "clean",
            hasConflicts: false,
            reviewDecision: nil,
            reviewComments: [],
            requestedReviewers: requestedReviewers
        )
    }
}
