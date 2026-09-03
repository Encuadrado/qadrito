import Foundation
import AppKit

enum QAdritoNotificationType: String, Codable, CaseIterable {
    case comment
    case reviewComment
    case commentOnParticipating
    case changesRequested
    case approved
    case checksFailed
    case conflicts
    case readyToMerge
    case opened
    case merged
    case closed
    case reviewRequested
}

struct QAdritoNotification: Identifiable, Codable, Equatable {
    let id: String
    let type: QAdritoNotificationType
    let title: String
    let body: String
    let prDisplayName: String
    let repositoryFullName: String
    let prUrl: String
    let deepLinkUrl: String?
    let createdAt: Date
    var readAt: Date?

    var isUnread: Bool { readAt == nil }

    var openURL: String {
        if let deepLinkUrl, !deepLinkUrl.isEmpty {
            return deepLinkUrl
        }
        return prUrl
    }

    var systemImageName: String {
        switch type {
        case .comment, .commentOnParticipating: return "text.bubble"
        case .reviewComment: return "text.bubble.fill"
        case .changesRequested: return "arrow.triangle.2.circlepath"
        case .approved: return "checkmark.seal.fill"
        case .checksFailed: return "xmark.octagon.fill"
        case .conflicts: return "exclamationmark.triangle.fill"
        case .readyToMerge: return "arrow.triangle.merge"
        case .opened: return "plus.circle.fill"
        case .merged: return "checkmark.circle.fill"
        case .closed: return "xmark.circle.fill"
        case .reviewRequested: return "person.badge.plus"
        }
    }
}

@MainActor
final class NotificationStore: ObservableObject {
    static let shared = NotificationStore()

    private let storageKey = "qadritoNotificationInbox"
    private let maxItems = 100

    @Published private(set) var items: [QAdritoNotification] = []

    var unreadCount: Int {
        items.reduce(0) { $0 + ($1.isUnread ? 1 : 0) }
    }

    private init() {
        load()
        syncBadge()
    }

    func recent(limit: Int = 5) -> [QAdritoNotification] {
        Array(items.prefix(limit))
    }

    @discardableResult
    func record(
        id: String,
        type: QAdritoNotificationType,
        title: String,
        body: String,
        prDisplayName: String,
        repositoryFullName: String,
        prUrl: String,
        deepLinkUrl: String? = nil,
        createdAt: Date = Date()
    ) -> QAdritoNotification? {
        if items.contains(where: { $0.id == id }) {
            return nil
        }

        let item = QAdritoNotification(
            id: id,
            type: type,
            title: title,
            body: body,
            prDisplayName: prDisplayName,
            repositoryFullName: repositoryFullName,
            prUrl: prUrl,
            deepLinkUrl: deepLinkUrl,
            createdAt: createdAt,
            readAt: nil
        )
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        persist()
        syncBadge()
        NotificationCenter.default.post(name: .qadritoNotificationsDidChange, object: nil)
        return item
    }

    func markRead(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].readAt == nil else {
            return
        }
        items[index].readAt = Date()
        persist()
        syncBadge()
        NotificationCenter.default.post(name: .qadritoNotificationsDidChange, object: nil)
    }

    func markAllRead() {
        guard items.contains(where: { $0.isUnread }) else {
            syncBadge()
            return
        }
        let now = Date()
        for index in items.indices where items[index].readAt == nil {
            items[index].readAt = now
        }
        persist()
        syncBadge()
        NotificationCenter.default.post(name: .qadritoNotificationsDidChange, object: nil)
    }

    func open(_ item: QAdritoNotification) {
        markRead(id: item.id)
        if let url = URL(string: item.openURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func syncBadge() {
        AppPreferences.shared.syncBadgeCount(from: unreadCount)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([QAdritoNotification].self, from: data) else {
            items = []
            return
        }
        items = decoded.sorted { $0.createdAt > $1.createdAt }
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
