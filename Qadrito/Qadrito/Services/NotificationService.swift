import Foundation
import AppKit
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var didRequestAuthorization = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Presents an OS banner when DND is off. Badge comes from `NotificationStore.unreadCount`
    /// (callers must `record` into the store first so unread stays consistent).
    func post(title: String, body: String, url: String?, notificationId: String? = nil) {
        if AppPreferences.shared.isDoNotDisturb {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: NotificationStore.shared.unreadCount)
        var userInfo: [String: Any] = [:]
        if let url, !url.isEmpty {
            userInfo["url"] = url
        }
        if let notificationId, !notificationId.isEmpty {
            userInfo["notificationId"] = notificationId
        }
        if !userInfo.isEmpty {
            content.userInfo = userInfo
        }

        let request = UNNotificationRequest(
            identifier: notificationId ?? UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let notificationId = userInfo["notificationId"] as? String
        let urlString = userInfo["url"] as? String
        DispatchQueue.main.async {
            if let notificationId {
                NotificationStore.shared.markRead(id: notificationId)
            }
            if let urlString, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                NotificationCenter.default.post(name: .qadritoShowMainWindow, object: nil)
            }
        }
        completionHandler()
    }
}
