import XCTest
@testable import QAdrito

final class PRStackDetectorTests: XCTestCase {
    
    /// Regression: consecutive numbers alone must NOT form a stack (customer-public#162/#163 bug).
    func testDetectStacks_ConsecutiveNumbersWithoutLinkAreSeparate() throws {
        let pr1 = makePR(id: 1, number: 162, author: "user1", repo: "encuadrado-customer-public")
        let pr2 = makePR(id: 2, number: 163, author: "user1", repo: "encuadrado-customer-public")
        
        let stacks = PRStackDetector.detectStacks([pr1, pr2])
        
        XCTAssertEqual(stacks.count, 2, "Consecutive numbers without stack id / base-head link must stay separate")
        XCTAssertTrue(stacks.allSatisfy { $0.stackSize == 1 })
    }
    
    func testDetectStacks_SameGitHubStackIdOrderedByPosition() throws {
        let tip = makePR(
            id: 2, number: 719, author: "user1", repo: "encuadrado-dania-chat-agent",
            githubStackId: 42, stackPosition: 2, githubStackSize: 2,
            baseRef: "stack-bottom", headRef: "stack-tip"
        )
        let bottom = makePR(
            id: 1, number: 718, author: "user1", repo: "encuadrado-dania-chat-agent",
            githubStackId: 42, stackPosition: 1, githubStackSize: 2,
            baseRef: "main", headRef: "stack-bottom"
        )
        
        let stacks = PRStackDetector.detectStacks([tip, bottom])
        
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks.first?.prs.map(\.number), [718, 719])
        XCTAssertEqual(stacks.first?.base.number, 718)
        XCTAssertEqual(stacks.first?.tip.number, 719)
        XCTAssertEqual(stacks.first?.stackSize, 2)
    }
    
    func testDetectStacks_DifferentGitHubStackIdsAreSeparate() throws {
        let a = makePR(
            id: 1, number: 100, author: "user1", repo: "test-repo",
            githubStackId: 1, stackPosition: 1, githubStackSize: 1,
            baseRef: "main", headRef: "a"
        )
        let b = makePR(
            id: 2, number: 101, author: "user1", repo: "test-repo",
            githubStackId: 2, stackPosition: 1, githubStackSize: 1,
            baseRef: "main", headRef: "b"
        )
        
        let stacks = PRStackDetector.detectStacks([a, b])
        
        XCTAssertEqual(stacks.count, 2)
        XCTAssertTrue(stacks.allSatisfy { $0.stackSize == 1 })
    }
    
    func testDetectStacks_GitHubStackSizePrefersFullSize() throws {
        let onlyLoaded = makePR(
            id: 1, number: 719, author: "user1", repo: "dania",
            githubStackId: 7, stackPosition: 2, githubStackSize: 3,
            baseRef: "mid", headRef: "tip"
        )
        
        let stacks = PRStackDetector.detectStacks([onlyLoaded])
        
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks.first?.prs.count, 1)
        XCTAssertEqual(stacks.first?.stackSize, 3, "Badge should show GitHub full size when larger")
    }
    
    func testDetectStacks_FallbackBaseHeadChain() throws {
        let bottom = makePR(
            id: 1, number: 10, author: "user1", repo: "test-repo",
            baseRef: "main", headRef: "feature-1"
        )
        let tip = makePR(
            id: 2, number: 11, author: "user1", repo: "test-repo",
            baseRef: "feature-1", headRef: "feature-2"
        )
        
        let stacks = PRStackDetector.detectStacks([tip, bottom])
        
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks.first?.prs.map(\.number), [10, 11])
        XCTAssertEqual(stacks.first?.tip.number, 11)
    }
    
    func testDetectStacks_BothBasedOnMainAreNotAStack() throws {
        let a = makePR(
            id: 1, number: 162, author: "user1", repo: "test-repo",
            baseRef: "main", headRef: "branch-162"
        )
        let b = makePR(
            id: 2, number: 163, author: "user1", repo: "test-repo",
            baseRef: "main", headRef: "branch-163"
        )
        
        let stacks = PRStackDetector.detectStacks([a, b])
        
        XCTAssertEqual(stacks.count, 2, "Two PRs both based on main are not a stack")
    }
    
    func testDetectStacks_DifferentReposStaySeparate() throws {
        let a = makePR(
            id: 1, number: 100, author: "user1", repo: "repo-a",
            githubStackId: 1, stackPosition: 1, githubStackSize: 1
        )
        let b = makePR(
            id: 2, number: 101, author: "user1", repo: "repo-b",
            githubStackId: 1, stackPosition: 1, githubStackSize: 1
        )
        
        let stacks = PRStackDetector.detectStacks([a, b])
        
        XCTAssertEqual(stacks.count, 2, "Same stack id in different repos must not merge")
    }
    
    func testFormatWithStacks_CollapsesGitHubStackToTipRow() throws {
        let bottom = makePR(
            id: 1, number: 718, author: "user1", repo: "encuadrado-dania-chat-agent",
            githubStackId: 42, stackPosition: 1, githubStackSize: 2,
            baseRef: "main", headRef: "stack-bottom"
        )
        let tip = makePR(
            id: 2, number: 719, author: "user1", repo: "encuadrado-dania-chat-agent",
            githubStackId: 42, stackPosition: 2, githubStackSize: 2,
            baseRef: "stack-bottom", headRef: "stack-tip"
        )
        
        let stacks = PRStackDetector.formatWithStacks([bottom, tip])
        
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks.first?.stackSize, 2)
        XCTAssertEqual(stacks.first?.base.number, 718)
        XCTAssertEqual(stacks.first?.tip.number, 719)
        XCTAssertEqual(stacks.first?.displayName, "dania#718")
        XCTAssertEqual(stacks.first?.prs.map(\.number), [718, 719])
    }
    
    func testFormatWithStacks_KeepsUnrelatedConsecutiveSeparate() throws {
        let pr1 = makePR(id: 1, number: 162, author: "user1", repo: "encuadrado-customer-public")
        let pr2 = makePR(id: 2, number: 163, author: "user1", repo: "encuadrado-customer-public")
        
        let stacks = PRStackDetector.formatWithStacks([pr1, pr2])
        
        XCTAssertEqual(stacks.count, 2)
        XCTAssertEqual(stacks[0].base.number, 162)
        XCTAssertEqual(stacks[1].base.number, 163)
    }
    
    func testFormatWithStacks_KeepsSingles() throws {
        let pr1 = makePR(id: 1, number: 100, author: "user1", repo: "encuadrado-web")
        let pr2 = makePR(id: 2, number: 200, author: "user2", repo: "encuadrado-web")
        
        let stacks = PRStackDetector.formatWithStacks([pr1, pr2])
        
        XCTAssertEqual(stacks.count, 2)
        XCTAssertEqual(stacks[0].stackSize, 1)
        XCTAssertEqual(stacks[1].stackSize, 1)
    }
    
    private func makePR(
        id: Int,
        number: Int,
        author: String,
        repo: String,
        githubStackId: Int? = nil,
        stackPosition: Int? = nil,
        githubStackSize: Int? = nil,
        baseRef: String = "main",
        headRef: String? = nil
    ) -> PullRequest {
        return PullRequest(
            id: id,
            number: number,
            title: "Test PR \(number)",
            htmlUrl: "https://github.com/test/\(repo)/pull/\(number)",
            author: author,
            createdAt: Date(),
            isDraft: false,
            state: "open",
            repositoryName: repo,
            changedFiles: 5,
            additions: 100,
            deletions: 50,
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
