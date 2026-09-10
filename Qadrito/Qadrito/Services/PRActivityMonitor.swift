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
    let authorLogin: String
    let isDraft: Bool
    let requestedReviewers: [String]
    let assignees: [String]
    let isAuthoredByMe: Bool
    let isReviewRequestedOfMe: Bool
    let isAssignedToMe: Bool
    let isReadyToMerge: Bool

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
    /// Lowercased logins currently in `requested_reviewers`.
    var requestedReviewerLogins: Set<String>
    var isDraft: Bool
    var isReadyToMerge: Bool
    /// Sticky: once the user participates, keep watching for comments / close / merge.
    var userParticipated: Bool
    var authorLogin: String
    var isAuthoredByMe: Bool
    var isReviewRequestedOfMe: Bool

    enum CodingKeys: String, CodingKey {
        case issueCommentIDs, reviewCommentIDs, reviewIDs
        case lastCheckFailureSignature, lastHadConflicts
        case requestedReviewerLogins, isDraft, isReadyToMerge
        case userParticipated, authorLogin, isAuthoredByMe, isReviewRequestedOfMe
    }

    init(
        issueCommentIDs: Set<Int>,
        reviewCommentIDs: Set<Int>,
        reviewIDs: Set<Int>,
        lastCheckFailureSignature: String?,
        lastHadConflicts: Bool,
        requestedReviewerLogins: Set<String>,
        isDraft: Bool,
        isReadyToMerge: Bool,
        userParticipated: Bool,
        authorLogin: String,
        isAuthoredByMe: Bool,
        isReviewRequestedOfMe: Bool
    ) {
        self.issueCommentIDs = issueCommentIDs
        self.reviewCommentIDs = reviewCommentIDs
        self.reviewIDs = reviewIDs
        self.lastCheckFailureSignature = lastCheckFailureSignature
        self.lastHadConflicts = lastHadConflicts
        self.requestedReviewerLogins = requestedReviewerLogins
        self.isDraft = isDraft
        self.isReadyToMerge = isReadyToMerge
        self.userParticipated = userParticipated
        self.authorLogin = authorLogin
        self.isAuthoredByMe = isAuthoredByMe
        self.isReviewRequestedOfMe = isReviewRequestedOfMe
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        issueCommentIDs = try c.decodeIfPresent(Set<Int>.self, forKey: .issueCommentIDs) ?? []
        reviewCommentIDs = try c.decodeIfPresent(Set<Int>.self, forKey: .reviewCommentIDs) ?? []
        reviewIDs = try c.decodeIfPresent(Set<Int>.self, forKey: .reviewIDs) ?? []
        lastCheckFailureSignature = try c.decodeIfPresent(String.self, forKey: .lastCheckFailureSignature)
        lastHadConflicts = try c.decodeIfPresent(Bool.self, forKey: .lastHadConflicts) ?? false
        requestedReviewerLogins = try c.decodeIfPresent(Set<String>.self, forKey: .requestedReviewerLogins) ?? []
        isDraft = try c.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        isReadyToMerge = try c.decodeIfPresent(Bool.self, forKey: .isReadyToMerge) ?? false
        userParticipated = try c.decodeIfPresent(Bool.self, forKey: .userParticipated) ?? false
        authorLogin = try c.decodeIfPresent(String.self, forKey: .authorLogin) ?? ""
        isAuthoredByMe = try c.decodeIfPresent(Bool.self, forKey: .isAuthoredByMe) ?? true
        isReviewRequestedOfMe = try c.decodeIfPresent(Bool.self, forKey: .isReviewRequestedOfMe) ?? false
    }
}

@MainActor
final class PRActivityMonitor {
    static let shared = PRActivityMonitor()

    private let pollIntervalNanoseconds: UInt64 = 60_000_000_000
    private let snapshotsKey = "prActivitySnapshots"
    private let identityKey = "prActivityIdentity"
    private let baselineKey = "prActivityHasBaseline"
    private let reviewRequestedKeysKey = "prActivityReviewRequestedKeys"

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
            UserDefaults.standard.removeObject(forKey: reviewRequestedKeysKey)
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
        let client = GitHubClient(token: token, tokenRefreshHandler: { [weak self] in
            let newToken = await GitHubOAuthManager.refreshAccessTokenStatic()
            if let newToken {
                await MainActor.run {
                    self?.token = newToken
                }
            }
            return newToken
        })
        let prefs = NotificationPreferences.shared

        do {
            /*
             Watch scope (full activity: comments, reviews, checks, conflicts, lifecycle):
               • authored open PRs (`author:login`)
               • open PRs the user commented on (`commenter:login`) or reviewed
                 (`reviewed-by:login`) — NOT GitHub `involves:` (too broad / matches
                 bare review-requested)
               • sticky snapshots where the user previously participated or authored

             Status alerts (conflicts, checks failed, ready to merge): authored PRs only.
             Comment / review / closed-merged alerts: also for sticky participating PRs.

             Bare `review-requested:` PRs are NOT fully monitored. If the Review requested
             preference is on, those keys are polled separately for one-shot alerts only.

             Merged/closed: when a watched open PR disappears, fetch final state once.
             */
            var snapshots = loadSnapshots()
            let isBaseline = !UserDefaults.standard.bool(forKey: baselineKey)

            var prs = try await client.fetchInvolvedOpenPRs(login: login, org: org)
            var byKey = Dictionary(uniqueKeysWithValues: prs.map { ($0.key, $0) })

            // Keep watching sticky authored / participating PRs that dropped out of search results.
            // Do NOT keep watching solely because review was once requested.
            let missingParticipating: [(owner: String, repo: String, number: Int)] = snapshots.compactMap { key, snap in
                guard snap.userParticipated || snap.isAuthoredByMe else { return nil }
                guard byKey[key] == nil else { return nil }
                let parts = key.split(separator: "#", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                let repoParts = parts[0].split(separator: "/", maxSplits: 1)
                guard repoParts.count == 2, let number = Int(parts[1]) else { return nil }
                return (owner: String(repoParts[0]), repo: String(repoParts[1]), number: number)
            }

            if !missingParticipating.isEmpty {
                let extras = try await client.fetchInvolvedPRs(ownerRepoNumbers: missingParticipating, login: login)
                for pr in extras {
                    byKey[pr.key] = pr
                }
                prs = Array(byKey.values)
            }

            let liveKeys = Set(byKey.keys)
            let previousKeys = Set(snapshots.keys)

            for pr in prs {
                let current = try await captureSnapshot(client: client, pr: pr, login: login, previous: snapshots[pr.key])
                let previous = snapshots[pr.key]
                snapshots[pr.key] = current

                if isBaseline || previous == nil {
                    // First sighting after baseline: treat newly appearing review-requested PRs as opened.
                    if !isBaseline, previous == nil, pr.isReviewRequestedOfMe, !pr.isAuthoredByMe {
                        if prefs.opened {
                            emit(
                                id: "opened:\(pr.key)",
                                type: .opened,
                                title: "\(pr.displayName) opened",
                                body: "\(pr.authorLogin): \(pr.title)",
                                pr: pr
                            )
                        }
                        if prefs.reviewRequested {
                            emit(
                                id: "reviewRequested:\(pr.key):initial",
                                type: .reviewRequested,
                                title: "\(pr.displayName) review requested",
                                body: pr.title,
                                pr: pr
                            )
                        }
                    }
                    continue
                }

                guard let previous else { continue }
                await emitDiffs(pr: pr, previous: previous, current: current, login: login, prefs: prefs)
            }

            // One-shot "review requested" for PRs we do not fully monitor.
            if prefs.reviewRequested {
                await emitNewReviewRequests(
                    client: client,
                    login: login,
                    org: org,
                    watchedKeys: liveKeys,
                    isBaseline: isBaseline
                )
            }

            // Disappeared from open watch set → fetch final state (merged / closed).
            let disappeared = previousKeys.subtracting(liveKeys)
            for key in disappeared {
                let prior = snapshots[key]
                snapshots.removeValue(forKey: key)
                guard !isBaseline else { continue }
                guard let prior else { continue }

                let parts = key.split(separator: "#", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let repoParts = parts[0].split(separator: "/", maxSplits: 1)
                guard repoParts.count == 2, let number = Int(parts[1]) else { continue }
                let owner = String(repoParts[0])
                let repo = String(repoParts[1])

                guard let final = try? await client.fetchPRFinalState(owner: owner, repo: repo, number: number) else {
                    continue
                }
                if final.state.lowercased() == "open" {
                    // Still open but left our search set (e.g. review submitted) — already handled via sticky watch.
                    continue
                }

                // Lifecycle alerts only for authored / participating — not bare review-requested.
                let relevant = prior.isAuthoredByMe || prior.userParticipated
                guard relevant else { continue }

                if final.merged {
                    if prefs.merged {
                        emitFinal(
                            id: "merged:\(final.key)",
                            type: .merged,
                            title: "\(final.displayName) merged",
                            body: final.title,
                            final: final
                        )
                    }
                } else if prefs.closed {
                    emitFinal(
                        id: "closed:\(final.key)",
                        type: .closed,
                        title: "\(final.displayName) closed",
                        body: final.title,
                        final: final
                    )
                }
            }

            // Bound store to the live watch set (author ∪ commenter ∪ reviewed-by ∪ sticky).
            // Never retain review-requested-only snapshots outside that set.
            snapshots = snapshots.filter { liveKeys.contains($0.key) }
            saveSnapshots(snapshots)
            UserDefaults.standard.set(true, forKey: baselineKey)
        } catch {
            NSLog("QAdrito: activity scan failed: \(error.localizedDescription)")
        }
    }

    private func captureSnapshot(
        client: GitHubClient,
        pr: InvolvedPR,
        login: String,
        previous: PRActivitySnapshot?
    ) async throws -> PRActivitySnapshot {
        async let issueComments = client.fetchIssueComments(owner: pr.owner, repo: pr.repo, number: pr.number)
        async let reviewComments = client.fetchPullReviewComments(owner: pr.owner, repo: pr.repo, number: pr.number)
        async let reviews = client.fetchReviews(owner: pr.owner, repo: pr.repo, number: pr.number)
        async let checkFailure = client.fetchCheckFailureSignature(owner: pr.owner, repo: pr.repo, sha: pr.headSha)

        let (issues, lines, revs, failureSig) = try await (issueComments, reviewComments, reviews, checkFailure)

        let nonPending = revs.filter { $0.state.uppercased() != "PENDING" }
        let userLeftActivity =
            issues.contains { $0.author.caseInsensitiveCompare(login) == .orderedSame }
            || lines.contains { $0.author.caseInsensitiveCompare(login) == .orderedSame }
            || nonPending.contains { $0.author.caseInsensitiveCompare(login) == .orderedSame }

        // Sticky participation = authored or prior comments/reviews — NOT assignee, NOT review-requested.
        let participated =
            (previous?.userParticipated ?? false)
            || pr.isAuthoredByMe
            || userLeftActivity

        let requested = Set(pr.requestedReviewers.map { $0.lowercased() })

        return PRActivitySnapshot(
            issueCommentIDs: Set(issues.map(\.id)),
            reviewCommentIDs: Set(lines.map(\.id)),
            reviewIDs: Set(nonPending.map(\.id)),
            lastCheckFailureSignature: failureSig,
            lastHadConflicts: pr.hasConflicts,
            requestedReviewerLogins: requested,
            isDraft: pr.isDraft,
            isReadyToMerge: pr.isReadyToMerge,
            userParticipated: participated,
            authorLogin: pr.authorLogin,
            isAuthoredByMe: pr.isAuthoredByMe,
            isReviewRequestedOfMe: pr.isReviewRequestedOfMe
        )
    }

    private func emitDiffs(
        pr: InvolvedPR,
        previous: PRActivitySnapshot,
        current: PRActivitySnapshot,
        login: String,
        prefs: NotificationPreferences
    ) async {
        let newIssueIDs = current.issueCommentIDs.subtracting(previous.issueCommentIDs)
        let newLineIDs = current.reviewCommentIDs.subtracting(previous.reviewCommentIDs)
        let newReviewIDs = current.reviewIDs.subtracting(previous.reviewIDs)

        if !newIssueIDs.isEmpty || !newLineIDs.isEmpty || !newReviewIDs.isEmpty {
            await emitCommentAndReviewNotifications(
                pr: pr,
                newIssueIDs: newIssueIDs,
                newLineIDs: newLineIDs,
                newReviewIDs: newReviewIDs,
                login: login,
                prefs: prefs
            )
        }

        // Review requested / re-requested: login newly appears in requested_reviewers.
        let loginLower = login.lowercased()
        let newlyRequested =
            current.requestedReviewerLogins.contains(loginLower)
            && !previous.requestedReviewerLogins.contains(loginLower)
        if newlyRequested, !pr.isAuthoredByMe, prefs.reviewRequested {
            emit(
                id: "reviewRequested:\(pr.key):\(Int(Date().timeIntervalSince1970))",
                type: .reviewRequested,
                title: "\(pr.displayName) review requested",
                body: pr.title,
                pr: pr
            )
        }

        // Ready to merge: authored PR transitions into clean + not draft.
        if pr.isAuthoredByMe,
           current.isReadyToMerge,
           !previous.isReadyToMerge,
           prefs.readyToMerge {
            emit(
                id: "readyToMerge:\(pr.key):\(Int(Date().timeIntervalSince1970))",
                type: .readyToMerge,
                title: "\(pr.displayName) ready to merge",
                body: pr.title,
                pr: pr
            )
        }

        // Status alerts only for PRs the user authored — never for participating-only.
        if pr.isAuthoredByMe,
           let sig = current.lastCheckFailureSignature,
           sig != previous.lastCheckFailureSignature,
           prefs.checksFailed {
            emit(
                id: "checks:\(pr.key):\(sig)",
                type: .checksFailed,
                title: "\(pr.displayName) checks failed",
                body: pr.title,
                pr: pr
            )
        }

        if pr.isAuthoredByMe,
           current.lastHadConflicts && !previous.lastHadConflicts,
           prefs.conflicts {
            emit(
                id: "conflicts:\(pr.key):\(Int(Date().timeIntervalSince1970))",
                type: .conflicts,
                title: "\(pr.displayName) has conflicts",
                body: pr.title,
                pr: pr
            )
        }
    }

    private func emitCommentAndReviewNotifications(
        pr: InvolvedPR,
        newIssueIDs: Set<Int>,
        newLineIDs: Set<Int>,
        newReviewIDs: Set<Int>,
        login: String,
        prefs: NotificationPreferences
    ) async {
        guard let token else { return }
        let client = GitHubClient(token: token, tokenRefreshHandler: {
            await GitHubOAuthManager.refreshAccessTokenStatic()
        })

        // Authored → "comment on my PR"; else participating → "comment in conversation I'm in".
        let allowMyPR = pr.isAuthoredByMe && prefs.commentOnMyPR
        // Full watch set is author ∪ commenter ∪ reviewed-by ∪ sticky — bare review-requested is not here.
        // Any non-authored watched PR is a conversation the user commented/reviewed in.
        let allowParticipating = !pr.isAuthoredByMe && prefs.commentOnParticipating

        if !newIssueIDs.isEmpty {
            if let comments = try? await client.fetchIssueComments(owner: pr.owner, repo: pr.repo, number: pr.number) {
                for comment in comments where newIssueIDs.contains(comment.id) {
                    if comment.author.caseInsensitiveCompare(login) == .orderedSame { continue }
                    if allowMyPR {
                        emit(
                            id: "comment:\(pr.key):\(comment.id)",
                            type: .comment,
                            title: "\(pr.displayName) new comment",
                            body: "\(comment.author): \(pr.title)",
                            pr: pr,
                            deepLink: comment.htmlUrl.isEmpty ? nil : comment.htmlUrl
                        )
                    } else if allowParticipating {
                        emit(
                            id: "commentParticipating:\(pr.key):\(comment.id)",
                            type: .commentOnParticipating,
                            title: "\(pr.displayName) new comment",
                            body: "\(comment.author): \(pr.title)",
                            pr: pr,
                            deepLink: comment.htmlUrl.isEmpty ? nil : comment.htmlUrl
                        )
                    }
                }
            }
        }

        if !newLineIDs.isEmpty {
            if let comments = try? await client.fetchPullReviewComments(owner: pr.owner, repo: pr.repo, number: pr.number) {
                for comment in comments where newLineIDs.contains(comment.id) {
                    if comment.author.caseInsensitiveCompare(login) == .orderedSame { continue }
                    if allowMyPR {
                        emit(
                            id: "reviewComment:\(pr.key):\(comment.id)",
                            type: .reviewComment,
                            title: "\(pr.displayName) new review comment",
                            body: "\(comment.author): \(pr.title)",
                            pr: pr,
                            deepLink: comment.htmlUrl.isEmpty ? nil : comment.htmlUrl
                        )
                    } else if allowParticipating {
                        emit(
                            id: "reviewCommentParticipating:\(pr.key):\(comment.id)",
                            type: .commentOnParticipating,
                            title: "\(pr.displayName) new review comment",
                            body: "\(comment.author): \(pr.title)",
                            pr: pr,
                            deepLink: comment.htmlUrl.isEmpty ? nil : comment.htmlUrl
                        )
                    }
                }
            }
        }

        if !newReviewIDs.isEmpty {
            if let reviews = try? await client.fetchReviews(owner: pr.owner, repo: pr.repo, number: pr.number) {
                for review in reviews where newReviewIDs.contains(review.id) && review.state.uppercased() != "PENDING" {
                    if review.author.caseInsensitiveCompare(login) == .orderedSame { continue }
                    let state = review.state.uppercased()
                    let link = (review.htmlUrl?.isEmpty == false) ? review.htmlUrl! : pr.htmlUrl

                    switch state {
                    case "APPROVED":
                        guard pr.isAuthoredByMe, prefs.approved else { continue }
                        emit(
                            id: "approved:\(pr.key):\(review.id)",
                            type: .approved,
                            title: "\(pr.displayName) approved",
                            body: "\(review.author): \(pr.title)",
                            pr: pr,
                            deepLink: link
                        )
                    case "CHANGES_REQUESTED":
                        guard pr.isAuthoredByMe, prefs.changesRequested else { continue }
                        emit(
                            id: "changesRequested:\(pr.key):\(review.id)",
                            type: .changesRequested,
                            title: "\(pr.displayName) changes requested",
                            body: "\(review.author): \(pr.title)",
                            pr: pr,
                            deepLink: link
                        )
                    case "COMMENTED":
                        // Treat review-body comments like conversation comments.
                        if allowMyPR {
                            emit(
                                id: "reviewBody:\(pr.key):\(review.id)",
                                type: .comment,
                                title: "\(pr.displayName) new review",
                                body: "\(review.author): \(pr.title)",
                                pr: pr,
                                deepLink: link
                            )
                        } else if allowParticipating {
                            emit(
                                id: "reviewBodyParticipating:\(pr.key):\(review.id)",
                                type: .commentOnParticipating,
                                title: "\(pr.displayName) new review",
                                body: "\(review.author): \(pr.title)",
                                pr: pr,
                                deepLink: link
                            )
                        }
                    default:
                        break
                    }
                }
            }
        }
    }


    /// Poll `review-requested:` for one-shot alerts only; do not add those PRs to full watch snapshots.
    private func emitNewReviewRequests(
        client: GitHubClient,
        login: String,
        org: String,
        watchedKeys: Set<String>,
        isBaseline: Bool
    ) async {
        do {
            let currentKeys = try await client.fetchReviewRequestedOpenPRKeys(login: login, org: org)
            let previousKeys = loadReviewRequestedKeys()
            defer { saveReviewRequestedKeys(currentKeys) }

            if isBaseline || previousKeys.isEmpty {
                return
            }

            let newlyRequested = currentKeys.subtracting(previousKeys).subtracting(watchedKeys)
            for key in newlyRequested.sorted() {
                let parts = key.split(separator: "#", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let repoParts = parts[0].split(separator: "/", maxSplits: 1)
                guard repoParts.count == 2, let number = Int(parts[1]) else { continue }
                let owner = String(repoParts[0])
                let repo = String(repoParts[1])
                let short = repoShortMap[repo] ?? repo
                let display = "\(short)#\(number)"
                let url = "https://github.com/\(owner)/\(repo)/pull/\(number)"
                let id = "reviewRequested:\(key):oneshot:\(Int(Date().timeIntervalSince1970))"
                _ = NotificationStore.shared.record(
                    id: id,
                    type: .reviewRequested,
                    title: "Review requested",
                    body: display,
                    prDisplayName: display,
                    repositoryFullName: "\(owner)/\(repo)",
                    prUrl: url,
                    deepLinkUrl: nil
                )
                NotificationService.shared.post(title: "Review requested", body: display, url: url, notificationId: id)
            }
        } catch {
            // Soft-fail; next poll retries.
        }
    }

    private func loadReviewRequestedKeys() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: reviewRequestedKeysKey),
              let keys = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(keys)
    }

    private func saveReviewRequestedKeys(_ keys: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(keys)) {
            UserDefaults.standard.set(data, forKey: reviewRequestedKeysKey)
        }
    }

    private func emit(
        id: String,
        type: QAdritoNotificationType,
        title: String,
        body: String,
        pr: InvolvedPR,
        deepLink: String? = nil
    ) {
        _ = NotificationStore.shared.record(
            id: id,
            type: type,
            title: title,
            body: body,
            prDisplayName: pr.displayName,
            repositoryFullName: pr.repositoryFullName,
            prUrl: pr.htmlUrl,
            deepLinkUrl: deepLink
        )
        NotificationService.shared.post(title: title, body: body, url: deepLink ?? pr.htmlUrl, notificationId: id)
    }

    private func emitFinal(
        id: String,
        type: QAdritoNotificationType,
        title: String,
        body: String,
        final: PRFinalState
    ) {
        _ = NotificationStore.shared.record(
            id: id,
            type: type,
            title: title,
            body: body,
            prDisplayName: final.displayName,
            repositoryFullName: final.repositoryFullName,
            prUrl: final.htmlUrl,
            deepLinkUrl: final.htmlUrl
        )
        NotificationService.shared.post(title: title, body: body, url: final.htmlUrl, notificationId: id)
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
