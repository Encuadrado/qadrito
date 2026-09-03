import Foundation
import AppKit
import ServiceManagement
import UserNotifications

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private let dndKey = "isDoNotDisturb"
    private let launchAtLoginKey = "launchAtLogin"
    private let badgeKey = "unreadBadgeCount"
    private let collapseStackedKey = "collapseStackedPRs"

    @Published private(set) var isDoNotDisturb: Bool
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var unreadBadgeCount: Int
    @Published private(set) var collapseStackedPRs: Bool

    private init() {
        let defaults = UserDefaults.standard
        isDoNotDisturb = defaults.bool(forKey: dndKey)
        unreadBadgeCount = defaults.integer(forKey: badgeKey)
        if defaults.object(forKey: collapseStackedKey) == nil {
            collapseStackedPRs = true
            defaults.set(true, forKey: collapseStackedKey)
        } else {
            collapseStackedPRs = defaults.bool(forKey: collapseStackedKey)
        }

        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            defaults.set(launchAtLogin, forKey: launchAtLoginKey)
        } else {
            launchAtLogin = defaults.bool(forKey: launchAtLoginKey)
        }

        applyDockBadge()
    }

    func setDoNotDisturb(_ enabled: Bool) {
        isDoNotDisturb = enabled
        UserDefaults.standard.set(enabled, forKey: dndKey)
        NotificationCenter.default.post(name: .qadritoPreferencesDidChange, object: nil)
    }

    func setCollapseStackedPRs(_ enabled: Bool) {
        collapseStackedPRs = enabled
        UserDefaults.standard.set(enabled, forKey: collapseStackedKey)
        NotificationCenter.default.post(name: .qadritoPreferencesDidChange, object: nil)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
                NSLog("QAdrito: failed to update launch at login: \(error.localizedDescription)")
            }
        } else {
            launchAtLogin = enabled
        }
        UserDefaults.standard.set(launchAtLogin, forKey: launchAtLoginKey)
        NotificationCenter.default.post(name: .qadritoPreferencesDidChange, object: nil)
    }

    /// Drive Dock / menu-bar badge from `NotificationStore.unreadCount` (source of truth).
    func syncBadgeCount(from unreadCount: Int) {
        let count = max(0, unreadCount)
        guard unreadBadgeCount != count else {
            applyDockBadge()
            return
        }
        unreadBadgeCount = count
        persistBadge()
        applyDockBadge()
        NotificationCenter.default.post(name: .qadritoPreferencesDidChange, object: nil)
    }

    func incrementBadge(by amount: Int = 1) {
        // Prefer recording into NotificationStore; kept for rare direct callers.
        guard amount > 0 else { return }
        unreadBadgeCount += amount
        persistBadge()
        applyDockBadge()
        NotificationCenter.default.post(name: .qadritoPreferencesDidChange, object: nil)
    }

    func clearBadge() {
        NotificationStore.shared.markAllRead()
    }

    func applyDockBadge() {
        let label = unreadBadgeCount > 0 ? "\(unreadBadgeCount)" : nil
        NSApp.dockTile.badgeLabel = label
        NSApp.dockTile.display()
        // macOS 14+ often ignores dockTile alone unless the notification badge API is used too.
        if #available(macOS 14.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(unreadBadgeCount) { error in
                if let error {
                    NSLog("QAdrito: setBadgeCount failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func persistBadge() {
        UserDefaults.standard.set(unreadBadgeCount, forKey: badgeKey)
    }
}

extension Notification.Name {
    static let qadritoPreferencesDidChange = Notification.Name("qadritoPreferencesDidChange")
    static let qadritoShowMainWindow = Notification.Name("qadritoShowMainWindow")
    static let qadritoWaitingForMeMenuDidChange = Notification.Name("qadritoWaitingForMeMenuDidChange")
    static let qadritoOpenNotificationsPanel = Notification.Name("qadritoOpenNotificationsPanel")
    static let qadritoNotificationsDidChange = Notification.Name("qadritoNotificationsDidChange")
}

/// Snapshot for the menu-bar "Waiting for me" submenu (age-grouped, same order as the main list).
@MainActor
final class WaitingForMeMenuStore {
    static let shared = WaitingForMeMenuStore()
    
    private(set) var sections: [PRAgeSection] = []
    
    private init() {}
    
    func update(prs: [PullRequest]) {
        let stacks = PRStackDetector.formatWithStacks(prs)
        sections = PRSorting.groupByAge(stacks)
        NotificationCenter.default.post(name: .qadritoWaitingForMeMenuDidChange, object: nil)
    }
    
    func clear() {
        sections = []
        NotificationCenter.default.post(name: .qadritoWaitingForMeMenuDidChange, object: nil)
    }
}
