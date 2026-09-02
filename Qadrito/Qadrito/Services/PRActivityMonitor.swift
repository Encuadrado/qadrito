import Foundation

struct InvolvedPR: Sendable {
    let owner: String
    let repo: String
    let number: Int
    let title: String
    let htmlUrl: String
    let headSha: String
    let mergeableState: String?
    let hasConflicts: Bool

    var key: String { "\(owner)/\(repo)#\(number)" }

    var repositoryFullName: String { "\(owner)/\(repo)" }

    var displayName: String {
        let short = repoShortMap[repo] ?? repo
        return "\(short)#\(number)"
    }
}

struct PRActivitySnapshot: Codable, Equatable {
    var issueCommentIDs: Set<Int>
    var reviewCommentIDs: Set<Int>
    var reviewIDs: Set<Int>
    var lastCheckFailureSignature: String?
    var lastHadConflicts: Bool
}

@MainActor
final class PRActivityMonitor {
    static let shared = PRActivityMonitor()

    private let pollIntervalNanoseconds: UInt64 = 60_000_000_000
    private let snapshotsKey = "prActivitySnapshots"
    private let identityKey = "prActivityIdentity"
    private let baselineKey = "prActivityHasBaseline"

    private var loopTask: Task<Void, Never>?
    private var token: String?
    private var login: String?
    private var org: String?

    private init() {}

    func start(token: String, login: String, org: String) {
        let identity = "\(login)@\(org)"
        if self.token == token, self.login == login, self.org == org, loopTask != nil {
            return
        }

        if UserDefaults.standard.string(forKey: identityKey) != identity {
            UserDefaults.standard.removeObject(forKey: snapshotsKey)
            UserDefaults.standard.set(false, forKey: baselineKey)
            UserDefaults.standard.set(identity, forKey: identityKey)
        }

        stopLoop()
        self.token = token
        self.login = login
        self.org = org
        NotificationService.shared.requestAuthorizationIfNeeded()

        loopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.scanOnce()
                try? await Task.sleep(nanoseconds: self.pollIntervalNanoseconds)
            }
        }
    }

    func stop() {
        stopLoop()
        token = nil
        login = nil
        org = nil
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func scanOnce() async {
        guard let token, let login, let org else { return }
        let client = GitHubClient(token: token)

        do {
            let prs = try await client.fetchInvolvedOpenPRs(login: login, org: org)
            var snapshots = loadSnapshots()
            let isBaseline = !UserDefaults.standard.bool(forKey: baselineKey)

            for pr in prs {
                let current = try await captureSnapshot(client: client, pr: pr)
                let previous = snapshots[pr.key]
                snapshots[pr.key] = current

                if isBaseline || previous == nil {
                    continue
                }

                guard let previous else { continue }
                await emitDiffs(pr: pr, previous: previous, current: current)
            }

            // Drop snapshots for PRs that are no longer open/authored so the store stays bounded.
            let liveKeys = Set(prs.map(\.key))
            snapshots = snapshots.filter { liveKeys.contains($0.key) }
            saveSnapshots(snapshots)
            UserDefaults.standard.set(true, forKey: baselineKey)
        } catch {
            NSLog("QAdrito: activity scan failed: \(error.localizedDescription)")
        }
    }

    private func captureSnapshot(client: GitHubClient, pr: InvolvedPR) async throws -> PRActivitySnapshot {
        async let issueComments = client.fetchIssueComments(owner: pr.owner, repo: pr.repo, number: pr.number)
        async let reviewComments = client.fetchPullReviewComments(owner: pr.owner, repo: pr.repo, number: pr.number)
        async let reviews = client.fetchReviews(owner: pr.owner, repo: pr.repo, number: pr.number)
        async let checkFailure = client.fetchCheckFailureSignature(owner: pr.owner, repo: pr.repo, sha: pr.headSha)

        let (issues, lines, revs, failureSig) = try await (issueComments, reviewComments, reviews, checkFailure)

        return PRActivitySnapshot(
            issueCommentIDs: Set(issues.map(\.id)),
            reviewCommentIDs: Set(lines.map(\.id)),
            reviewIDs: Set(revs.filter { $0.state.uppercased() != "PENDING" }.map(\.id)),
            lastCheckFailureSignature: failureSig,
            lastHadConflicts: pr.hasConflicts
        )
    }

    private func emitDiffs(
        pr: InvolvedPR,
        previous: PRActivitySnapshot,
        current: PRActivitySnapshot
    ) async {
        // Comments are re-fetched with authors so we can name them in the body.
        // Snapshot diffs only have IDs; fetch details again only when there are new IDs.
        let newIssueIDs = current.issueCommentIDs.subtracting(previous.issueCommentIDs)
        let newLineIDs = current.reviewCommentIDs.subtracting(previous.reviewCommentIDs)
        let newReviewIDs = current.reviewIDs.subtracting(previous.reviewIDs)

        if !newIssueIDs.isEmpty || !newLineIDs.isEmpty || !newReviewIDs.isEmpty {
            await emitCommentAndReviewNotifications(
                pr: pr,
                newIssueIDs: newIssueIDs,
                newLineIDs: newLineIDs,
                newReviewIDs: newReviewIDs
            )
        }

        if let sig = current.lastCheckFailureSignature,
           sig != previous.lastCheckFailureSignature {
            let title = "\(pr.displayName) checks failed"
            let body = pr.title
            let id = "checks:\(pr.key):\(sig)"
            _ = NotificationStore.shared.record(
                id: id,
                type: .checksFailed,
                title: title,
                body: body,
                prDisplayName: pr.displayName,
                repositoryFullName: pr.repositoryFullName,
                prUrl: pr.htmlUrl,
                deepLinkUrl: pr.htmlUrl
            )
            NotificationService.shared.post(title: title, body: body, url: pr.htmlUrl, notificationId: id)
        }

        if current.lastHadConflicts && !previous.lastHadConflicts {
            let title = "\(pr.displayName) has conflicts"
            let body = pr.title
            let id = "conflicts:\(pr.key):\(Int(Date().timeIntervalSince1970))"
            _ = NotificationStore.shared.record(
                id: id,
                type: .conflicts,
                title: title,
                body: body,
                prDisplayName: pr.displayName,
                repositoryFullName: pr.repositoryFullName,
                prUrl: pr.htmlUrl,
                deepLinkUrl: pr.htmlUrl
            )
            NotificationService.shared.post(title: title, body: body, url: pr.htmlUrl, notificationId: id)
        }
    }

    private func emitCommentAndReviewNotifications(
        pr: InvolvedPR,
        newIssueIDs: Set<Int>,
        newLineIDs: Set<Int>,
        newReviewIDs: Set<Int>
    ) async {
        guard let token else { return }
        let client = GitHubClient(token: token)
        let store = NotificationStore.shared

        if !newIssueIDs.isEmpty {
            if let comments = try? await client.fetchIssueComments(owner: pr.owner, repo: pr.repo, number: pr.number) {
                for comment in comments where newIssueIDs.contains(comment.id) {
                    // Skip your own comments on your PRs.
                    if let login, comment.author.caseInsensitiveCompare(login) == .orderedSame { continue }
                    let author = comment.author
                    let title = "\(pr.displayName) new comment"
                    let body = "\(author): \(pr.title)"
                    let id = "comment:\(pr.key):\(comment.id)"
                    let link = comment.htmlUrl.isEmpty ? pr.htmlUrl : comment.htmlUrl
                    _ = store.record(
                        id: id,
                        type: .comment,
                        title: title,
                        body: body,
                        prDisplayName: pr.displayName,
                        repositoryFullName: pr.repositoryFullName,
                        prUrl: pr.htmlUrl,
                        deepLinkUrl: link
                    )
                    NotificationService.shared.post(title: title, body: body, url: link, notificationId: id)
                }
            }
        }

        if !newLineIDs.isEmpty {
            if let comments = try? await client.fetchPullReviewComments(owner: pr.owner, repo: pr.repo, number: pr.number) {
                for comment in comments where newLineIDs.contains(comment.id) {
                    if let login, comment.author.caseInsensitiveCompare(login) == .orderedSame { continue }
                    let author = comment.author
                    let title = "\(pr.displayName) new review comment"
                    let body = "\(author): \(pr.title)"
                    let id = "reviewComment:\(pr.key):\(comment.id)"
                    let link = comment.htmlUrl.isEmpty ? pr.htmlUrl : comment.htmlUrl
                    _ = store.record(
                        id: id,
                        type: .reviewComment,
                        title: title,
                        body: body,
                        prDisplayName: pr.displayName,
                        repositoryFullName: pr.repositoryFullName,
                        prUrl: pr.htmlUrl,
                        deepLinkUrl: link
                    )
                    NotificationService.shared.post(title: title, body: body, url: link, notificationId: id)
                }
            }
        }

        if !newReviewIDs.isEmpty {
            if let reviews = try? await client.fetchReviews(owner: pr.owner, repo: pr.repo, number: pr.number) {
                for review in reviews where newReviewIDs.contains(review.id) && review.state.uppercased() != "PENDING" {
                    if let login, review.author.caseInsensitiveCompare(login) == .orderedSame { continue }
                    let state = review.state.uppercased()
                    let label: String
                    switch state {
                    case "APPROVED":
                        label = "approved"
                    case "CHANGES_REQUESTED":
                        label = "requested changes"
                    case "COMMENTED":
                        label = "left a review"
                    default:
                        label = state.lowercased().replacingOccurrences(of: "_", with: " ")
                    }
                    let title = "\(pr.displayName) review \(label)"
                    let body = "\(review.author): \(pr.title)"
                    let link = (review.htmlUrl?.isEmpty == false) ? review.htmlUrl! : pr.htmlUrl

                    if state == "CHANGES_REQUESTED" {
                        let id = "changesRequested:\(pr.key):\(review.id)"
                        _ = store.record(
                            id: id,
                            type: .changesRequested,
                            title: title,
                            body: body,
                            prDisplayName: pr.displayName,
                            repositoryFullName: pr.repositoryFullName,
                            prUrl: pr.htmlUrl,
                            deepLinkUrl: link
                        )
                        NotificationService.shared.post(title: title, body: body, url: link, notificationId: id)
                    } else {
                        // Keep existing OS banners for approved / commented reviews (no inbox item).
                        NotificationService.shared.post(title: title, body: body, url: link)
                    }
                }
            }
        }
    }

    private func loadSnapshots() -> [String: PRActivitySnapshot] {
        guard let data = UserDefaults.standard.data(forKey: snapshotsKey),
              let decoded = try? JSONDecoder().decode([String: PRActivitySnapshot].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveSnapshots(_ snapshots: [String: PRActivitySnapshot]) {
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: snapshotsKey)
        }
    }
}
