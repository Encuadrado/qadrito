import Foundation

/// User-configurable notification toggles. Persisted in UserDefaults; defaults are ON.
@MainActor
final class NotificationPreferences: ObservableObject {
    static let shared = NotificationPreferences()

    // MARK: - UserDefaults keys

    static let commentOnMyPRKey = "notif.commentOnMyPR"
    static let commentOnParticipatingKey = "notif.commentOnParticipating"
    static let approvedKey = "notif.approved"
    static let changesRequestedKey = "notif.changesRequested"
    static let reviewRequestedKey = "notif.reviewRequested"
    static let openedKey = "notif.opened"
    static let readyToMergeKey = "notif.readyToMerge"
    static let mergedKey = "notif.merged"
    static let closedKey = "notif.closed"
    static let checksFailedKey = "notif.checksFailed"
    static let conflictsKey = "notif.conflicts"

    // MARK: - Published state (defaults ON)

    @Published private(set) var commentOnMyPR: Bool
    @Published private(set) var commentOnParticipating: Bool
    @Published private(set) var approved: Bool
    @Published private(set) var changesRequested: Bool
    @Published private(set) var reviewRequested: Bool
    @Published private(set) var opened: Bool
    @Published private(set) var readyToMerge: Bool
    @Published private(set) var merged: Bool
    @Published private(set) var closed: Bool
    @Published private(set) var checksFailed: Bool
    @Published private(set) var conflicts: Bool

    private init() {
        let d = UserDefaults.standard
        commentOnMyPR = Self.boolDefaultOn(d, Self.commentOnMyPRKey)
        commentOnParticipating = Self.boolDefaultOn(d, Self.commentOnParticipatingKey)
        approved = Self.boolDefaultOn(d, Self.approvedKey)
        changesRequested = Self.boolDefaultOn(d, Self.changesRequestedKey)
        reviewRequested = Self.boolDefaultOn(d, Self.reviewRequestedKey)
        opened = Self.boolDefaultOn(d, Self.openedKey)
        readyToMerge = Self.boolDefaultOn(d, Self.readyToMergeKey)
        merged = Self.boolDefaultOn(d, Self.mergedKey)
        closed = Self.boolDefaultOn(d, Self.closedKey)
        checksFailed = Self.boolDefaultOn(d, Self.checksFailedKey)
        conflicts = Self.boolDefaultOn(d, Self.conflictsKey)
    }

    /// Missing key → ON (product default). Explicit `false` stays off.
    private static func boolDefaultOn(_ defaults: UserDefaults, _ key: String) -> Bool {
        if defaults.object(forKey: key) == nil {
            defaults.set(true, forKey: key)
            return true
        }
        return defaults.bool(forKey: key)
    }

    private func set(_ keyPath: ReferenceWritableKeyPath<NotificationPreferences, Bool>, key: String, value: Bool) {
        self[keyPath: keyPath] = value
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: .qadritoPreferencesDidChange, object: nil)
    }

    func setCommentOnMyPR(_ enabled: Bool) { set(\.commentOnMyPR, key: Self.commentOnMyPRKey, value: enabled) }
    func setCommentOnParticipating(_ enabled: Bool) { set(\.commentOnParticipating, key: Self.commentOnParticipatingKey, value: enabled) }
    func setApproved(_ enabled: Bool) { set(\.approved, key: Self.approvedKey, value: enabled) }
    func setChangesRequested(_ enabled: Bool) { set(\.changesRequested, key: Self.changesRequestedKey, value: enabled) }
    func setReviewRequested(_ enabled: Bool) { set(\.reviewRequested, key: Self.reviewRequestedKey, value: enabled) }
    func setOpened(_ enabled: Bool) { set(\.opened, key: Self.openedKey, value: enabled) }
    func setReadyToMerge(_ enabled: Bool) { set(\.readyToMerge, key: Self.readyToMergeKey, value: enabled) }
    func setMerged(_ enabled: Bool) { set(\.merged, key: Self.mergedKey, value: enabled) }
    func setClosed(_ enabled: Bool) { set(\.closed, key: Self.closedKey, value: enabled) }
    func setChecksFailed(_ enabled: Bool) { set(\.checksFailed, key: Self.checksFailedKey, value: enabled) }
    func setConflicts(_ enabled: Bool) { set(\.conflicts, key: Self.conflictsKey, value: enabled) }
}
