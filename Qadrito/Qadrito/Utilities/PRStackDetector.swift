import Foundation

struct PRStackDetector {
    static func detectStacks(_ prs: [PullRequest]) -> [PRStack] {
        var stackMap: [String: [PullRequest]] = [:]
        
        for pr in prs {
            let key = "\(pr.author):\(pr.repositoryName)"
            stackMap[key, default: []].append(pr)
        }
        
        var stacks: [PRStack] = []
        
        for (_, groupPRs) in stackMap {
            let sortedPRs = groupPRs.sorted { $0.number < $1.number }
            
            var currentStack: [PullRequest] = []
            
            for pr in sortedPRs {
                if currentStack.isEmpty {
                    currentStack.append(pr)
                } else if let last = currentStack.last,
                          pr.number == last.number + 1 {
                    currentStack.append(pr)
                } else {
                    if !currentStack.isEmpty {
                        if let tip = currentStack.last {
                            stacks.append(PRStack(tip: tip, stackSize: currentStack.count))
                        }
                    }
                    currentStack = [pr]
                }
            }
            
            if !currentStack.isEmpty {
                if let tip = currentStack.last {
                    stacks.append(PRStack(tip: tip, stackSize: currentStack.count))
                }
            }
        }
        
        return stacks
    }
    
    static func formatWithStacks(_ prs: [PullRequest]) -> [PRStack] {
        let stacks = detectStacks(prs)
        let stackMap = Dictionary(uniqueKeysWithValues: stacks.map { ($0.tip.id, $0) })
        
        return prs.compactMap { pr in
            stackMap[pr.id] ?? PRStack(tip: pr, stackSize: 1)
        }
    }
}
