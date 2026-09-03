import XCTest
@testable import QAdrito

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
    
    func testAgeGroup_Boundaries() throws {
        XCTAssertEqual(makePR(id: 1, number: 1, author: "u", daysOld: 8).ageGroup, .critical)
        XCTAssertEqual(makePR(id: 2, number: 2, author: "u", daysOld: 7).ageGroup, .warning)
        XCTAssertEqual(makePR(id: 3, number: 3, author: "u", daysOld: 3).ageGroup, .warning)
        XCTAssertEqual(makePR(id: 4, number: 4, author: "u", daysOld: 2).ageGroup, .onTime)
        XCTAssertEqual(makePR(id: 5, number: 5, author: "u", daysOld: 0).ageGroup, .onTime)
    }
    
    func testGroupByAge_SectionsAndOldestFirst() throws {
        let critical = makePR(id: 1, number: 1, author: "a", daysOld: 10)
        let criticalNewer = makePR(id: 2, number: 2, author: "b", daysOld: 8)
        let warning = makePR(id: 3, number: 3, author: "c", daysOld: 4)
        let onTime = makePR(id: 4, number: 4, author: "d", daysOld: 1)
        
        let sections = PRSorting.groupByAge([
            PRStack(prs: [onTime]),
            PRStack(prs: [criticalNewer]),
            PRStack(prs: [warning]),
            PRStack(prs: [critical])
        ])
        
        XCTAssertEqual(sections.map(\.group), [.critical, .warning, .onTime])
        XCTAssertEqual(sections[0].stacks.map(\.tip.id), [critical.id, criticalNewer.id])
        XCTAssertEqual(sections[1].stacks.map(\.tip.id), [warning.id])
        XCTAssertEqual(sections[2].stacks.map(\.tip.id), [onTime.id])
    }
    
    func testGroupByAge_UsesOldestStackMember() throws {
        let base = makePR(id: 1, number: 10, author: "a", daysOld: 9)
        let tip = makePR(id: 2, number: 11, author: "a", daysOld: 1)
        let sections = PRSorting.groupByAge([PRStack(prs: [base, tip])])
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.group, .critical)
        XCTAssertEqual(sections.first?.stacks.first?.base.id, base.id)
        XCTAssertEqual(sections.first?.stacks.first?.tip.id, tip.id)
    }
    
    func testPRScopeDefaultRawValue() throws {
        XCTAssertEqual(PRScope.waitingForMe.rawValue, "Waiting for me")
        XCTAssertEqual(PRScope.allCases.first, .waitingForMe)
    }
    
    private func makePR(
        id: Int,
        number: Int,
        author: String,
        daysOld: Int,
        requestedReviewers: [String] = [],
        githubStackId: Int? = nil,
        stackPosition: Int? = nil,
        githubStackSize: Int? = nil,
        baseRef: String = "main",
        headRef: String? = nil
    ) -> PullRequest {
        let createdAt = Date().addingTimeInterval(-TimeInterval(daysOld * 86400) + 30)
        
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
            requestedReviewers: requestedReviewers,
            githubStackId: githubStackId,
            stackPosition: stackPosition,
            githubStackSize: githubStackSize,
            baseRef: baseRef,
            headRef: headRef ?? "branch-\(number)"
        )
    }
}
