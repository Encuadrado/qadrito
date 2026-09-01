import XCTest
@testable import Qadrito

final class PRStackDetectorTests: XCTestCase {
    
    func testDetectStacks_ConsecutiveNumbers() throws {
        let pr1 = makePR(id: 1, number: 100, author: "user1", repo: "test-repo")
        let pr2 = makePR(id: 2, number: 101, author: "user1", repo: "test-repo")
        let pr3 = makePR(id: 3, number: 102, author: "user1", repo: "test-repo")
        
        let stacks = PRStackDetector.detectStacks([pr1, pr2, pr3])
        
        XCTAssertEqual(stacks.count, 1, "Should detect one stack")
        XCTAssertEqual(stacks.first?.stackSize, 3, "Stack should have 3 PRs")
        XCTAssertEqual(stacks.first?.tip.number, 102, "Tip should be highest number")
    }
    
    func testDetectStacks_NonConsecutiveNumbers() throws {
        let pr1 = makePR(id: 1, number: 100, author: "user1", repo: "test-repo")
        let pr2 = makePR(id: 2, number: 102, author: "user1", repo: "test-repo")
        let pr3 = makePR(id: 3, number: 103, author: "user1", repo: "test-repo")
        
        let stacks = PRStackDetector.detectStacks([pr1, pr2, pr3])
        
        XCTAssertEqual(stacks.count, 2, "Should detect two separate stacks")
        
        let stack1 = stacks.first { $0.tip.number == 100 }
        let stack2 = stacks.first { $0.tip.number == 103 }
        
        XCTAssertEqual(stack1?.stackSize, 1, "First stack should have 1 PR")
        XCTAssertEqual(stack2?.stackSize, 2, "Second stack should have 2 PRs")
    }
    
    func testDetectStacks_DifferentAuthors() throws {
        let pr1 = makePR(id: 1, number: 100, author: "user1", repo: "test-repo")
        let pr2 = makePR(id: 2, number: 101, author: "user2", repo: "test-repo")
        
        let stacks = PRStackDetector.detectStacks([pr1, pr2])
        
        XCTAssertEqual(stacks.count, 2, "Different authors should create separate stacks")
        XCTAssertEqual(stacks[0].stackSize, 1, "Each stack should have 1 PR")
        XCTAssertEqual(stacks[1].stackSize, 1, "Each stack should have 1 PR")
    }
    
    func testDetectStacks_DifferentRepos() throws {
        let pr1 = makePR(id: 1, number: 100, author: "user1", repo: "repo-a")
        let pr2 = makePR(id: 2, number: 101, author: "user1", repo: "repo-b")
        
        let stacks = PRStackDetector.detectStacks([pr1, pr2])
        
        XCTAssertEqual(stacks.count, 2, "Different repos should create separate stacks")
    }
    
    func testDetectStacks_MultipleStacksSameAuthor() throws {
        let pr1 = makePR(id: 1, number: 100, author: "user1", repo: "test-repo")
        let pr2 = makePR(id: 2, number: 101, author: "user1", repo: "test-repo")
        let pr3 = makePR(id: 3, number: 150, author: "user1", repo: "test-repo")
        let pr4 = makePR(id: 4, number: 151, author: "user1", repo: "test-repo")
        
        let stacks = PRStackDetector.detectStacks([pr1, pr2, pr3, pr4])
        
        XCTAssertEqual(stacks.count, 2, "Should detect two separate stacks")
        
        let stack1 = stacks.first { $0.tip.number == 101 }
        let stack2 = stacks.first { $0.tip.number == 151 }
        
        XCTAssertEqual(stack1?.stackSize, 2, "First stack should have 2 PRs")
        XCTAssertEqual(stack2?.stackSize, 2, "Second stack should have 2 PRs")
    }
    
    func testFormatWithStacks_DisplayName() throws {
        let pr1 = makePR(id: 1, number: 100, author: "user1", repo: "encuadrado-web")
        let pr2 = makePR(id: 2, number: 101, author: "user1", repo: "encuadrado-web")
        
        let stacks = PRStackDetector.formatWithStacks([pr1, pr2])
        
        XCTAssertEqual(stacks.count, 2, "Should return formatted stack for each PR")
        
        let stack2 = stacks.first { $0.tip.number == 101 }
        XCTAssertEqual(stack2?.displayName, "web#101 (2)", "Should show stack size")
        
        let stack1 = stacks.first { $0.tip.number == 100 }
        XCTAssertEqual(stack1?.displayName, "web#100", "Single PR should not show count")
    }
    
    private func makePR(id: Int, number: Int, author: String, repo: String) -> PullRequest {
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
            requestedReviewers: []
        )
    }
}
