import Foundation

struct PRStackDetector {
    /// Detects PR stacks using GitHub's official `stack` metadata when present,
    /// otherwise falls back to classic base.ref → head.ref chains within a repo.
    /// Never groups by consecutive numbers or same author alone.
    /// Each stack's `prs` is ordered bottom → tip.
    static func detectStacks(_ prs: [PullRequest]) -> [PRStack] {
        var stacks: [PRStack] = []
        var claimedIds = Set<Int>()
        
        // 1) Official GitHub stacks: same (repositoryName, githubStackId)
        var byGitHubStack: [String: [PullRequest]] = [:]
        for pr in prs {
            guard let stackId = pr.githubStackId else { continue }
            let key = "\(pr.repositoryName)#\(stackId)"
            byGitHubStack[key, default: []].append(pr)
        }
        
        for (_, members) in byGitHubStack {
            let sorted = members.sorted { lhs, rhs in
                let lp = lhs.stackPosition ?? Int.max
                let rp = rhs.stackPosition ?? Int.max
                if lp != rp { return lp < rp }
                return lhs.number < rhs.number
            }
            for member in sorted {
                claimedIds.insert(member.id)
            }
            stacks.append(PRStack(prs: sorted))
        }
        
        // 2) Fallback: classic head/base chains among remaining PRs (per repo)
        let remaining = prs.filter { !claimedIds.contains($0.id) }
        var byRepo: [String: [PullRequest]] = [:]
        for pr in remaining {
            byRepo[pr.repositoryName, default: []].append(pr)
        }
        
        for (_, repoPRs) in byRepo {
            stacks.append(contentsOf: detectBaseHeadChains(repoPRs))
        }
        
        return stacks
    }
    
    /// Within one repo, link PRs where child.baseRef == parent.headRef (non-empty).
    /// Walk each chain root → tip; unlinked PRs become size-1 stacks.
    private static func detectBaseHeadChains(_ prs: [PullRequest]) -> [PRStack] {
        guard !prs.isEmpty else { return [] }
        
        // headRef → PR (first wins if duplicates; rare)
        var prByHeadRef: [String: PullRequest] = [:]
        for pr in prs where !pr.headRef.isEmpty {
            if prByHeadRef[pr.headRef] == nil {
                prByHeadRef[pr.headRef] = pr
            }
        }
        
        var parentOf: [Int: PullRequest] = [:]
        var childrenOf: [Int: [PullRequest]] = [:]
        
        for child in prs {
            guard !child.baseRef.isEmpty,
                  let parent = prByHeadRef[child.baseRef],
                  parent.id != child.id else { continue }
            parentOf[child.id] = parent
            childrenOf[parent.id, default: []].append(child)
        }
        
        let roots = prs
            .filter { parentOf[$0.id] == nil }
            .sorted { $0.number < $1.number }
        
        var used = Set<Int>()
        var result: [PRStack] = []
        
        for root in roots {
            if used.contains(root.id) { continue }
            var chain: [PullRequest] = []
            var current: PullRequest? = root
            while let pr = current {
                if used.contains(pr.id) { break }
                used.insert(pr.id)
                chain.append(pr)
                let kids = (childrenOf[pr.id] ?? [])
                    .filter { !used.contains($0.id) }
                    .sorted { $0.number < $1.number }
                current = kids.first
            }
            if !chain.isEmpty {
                result.append(PRStack(prs: chain))
            }
        }
        
        // Orphans (e.g. cycles): size-1
        for pr in prs where !used.contains(pr.id) {
            result.append(PRStack(prs: [pr]))
        }
        
        return result
    }
    
    /// Collapses stacked PRs to one row per stack (base/first), preserving input order of first-seen members.
    /// Non-base members of multi-PR stacks are omitted from the top-level list.
    static func formatWithStacks(_ prs: [PullRequest]) -> [PRStack] {
        let stacks = detectStacks(prs)
        let stackByMemberId: [Int: PRStack] = {
            var map: [Int: PRStack] = [:]
            for stack in stacks {
                for member in stack.prs {
                    map[member.id] = stack
                }
            }
            return map
        }()
        
        var seenBaseIds = Set<Int>()
        var result: [PRStack] = []
        
        for pr in prs {
            guard let stack = stackByMemberId[pr.id] else {
                result.append(PRStack(prs: [pr]))
                continue
            }
            if seenBaseIds.contains(stack.base.id) {
                continue
            }
            seenBaseIds.insert(stack.base.id)
            result.append(stack)
        }
        
        return result
    }
}
