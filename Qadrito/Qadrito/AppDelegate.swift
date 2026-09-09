import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var openMainWindowHandler: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var preferencesObserver: NSObjectProtocol?
    private var showWindowObserver: NSObjectProtocol?
    private var waitingMenuObserver: NSObjectProtocol?
    private var notificationsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppPreferences.shared.applyDockBadge()
        _ = NotificationService.shared
        setupStatusItem()
        rebuildStatusMenu()

        preferencesObserver = NotificationCenter.default.addObserver(
            forName: .qadritoPreferencesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildStatusMenu()
            }
        }

        showWindowObserver = NotificationCenter.default.addObserver(
            forName: .qadritoShowMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showMainWindow()
            }
        }

        waitingMenuObserver = NotificationCenter.default.addObserver(
            forName: .qadritoWaitingForMeMenuDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildStatusMenu()
            }
        }

        notificationsObserver = NotificationCenter.default.addObserver(
            forName: .qadritoNotificationsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildStatusMenu()
            }
        }

        // Ensure store is loaded and badge synced on launch.
        _ = NotificationStore.shared
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
        if let showWindowObserver {
            NotificationCenter.default.removeObserver(showWindowObserver)
        }
        if let waitingMenuObserver {
            NotificationCenter.default.removeObserver(waitingMenuObserver)
        }
        if let notificationsObserver {
            NotificationCenter.default.removeObserver(notificationsObserver)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppPreferences.shared.applyDockBadge()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "QAdrito"
        statusItem = item
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let prefs = AppPreferences.shared
        let base = menuBarBaseImage()
        if prefs.isDoNotDisturb {
            statusItem?.button?.image = badgedMenuBarImage(base: base, style: .doNotDisturb)
        } else if prefs.unreadBadgeCount > 0 {
            statusItem?.button?.image = badgedMenuBarImage(base: base, style: .unread(prefs.unreadBadgeCount))
        } else {
            statusItem?.button?.image = base
        }
        statusItem?.button?.imagePosition = .imageOnly
    }

    private func menuBarBaseImage() -> NSImage {
        let side: CGFloat = 18
        let source = NSImage(named: "MenuBarIcon")
            ?? NSImage(size: NSSize(width: side, height: side))
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        image.unlockFocus()
        // White-on-transparent asset; template so macOS tints for light/dark menu bar.
        image.isTemplate = true
        return image
    }

    private enum MenuBarBadgeStyle {
        case unread(Int)
        case doNotDisturb
    }

    private func badgedMenuBarImage(base: NSImage, style: MenuBarBadgeStyle) -> NSImage {
        // Larger canvas so a 2x badge still clears the robot silhouette.
        let iconSide: CGFloat = 18
        let badgeSide: CGFloat = 14
        let canvas: CGFloat = 24
        let image = NSImage(size: NSSize(width: canvas, height: canvas))
        image.lockFocus()
        // Bake current menu-bar tint so we can overlay a real badge (templates recolor overlays too).
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tint = isDark ? NSColor.white : NSColor.black
        let iconRect = NSRect(x: 0, y: 0, width: iconSide, height: iconSide)
        base.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        tint.set()
        iconRect.fill(using: .sourceAtop)

        let badgeRect = NSRect(
            x: canvas - badgeSide,
            y: canvas - badgeSide,
            width: badgeSide,
            height: badgeSide
        )

        switch style {
        case .doNotDisturb:
            let label = "🚫"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12)
            ]
            let size = label.size(withAttributes: attrs)
            let point = NSPoint(
                x: badgeRect.midX - size.width / 2,
                y: badgeRect.midY - size.height / 2 - 0.5
            )
            label.draw(at: point, withAttributes: attrs)
        case .unread(let count):
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
            if count > 1 {
                let label = count > 9 ? "9+" : "\(count)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let size = label.size(withAttributes: attrs)
                let point = NSPoint(
                    x: badgeRect.midX - size.width / 2,
                    y: badgeRect.midY - size.height / 2 - 0.5
                )
                label.draw(at: point, withAttributes: attrs)
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func rebuildStatusMenu() {
        updateStatusIcon()

        let menu = NSMenu()
        menu.addItem(withTitle: "Open QAdrito", action: #selector(openQAdrito), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(makeWaitingForMeMenuItem())
        menu.addItem(.separator())
        menu.addItem(makeNotificationsMenuItem())
        menu.addItem(.separator())

        let dndTitle = AppPreferences.shared.isDoNotDisturb ? "Do Not Disturb: On" : "Do Not Disturb: Off"
        menu.addItem(withTitle: dndTitle, action: #selector(toggleDoNotDisturb), keyEquivalent: "")

        let loginTitle = AppPreferences.shared.launchAtLogin ? "Open at Login: On" : "Open at Login: Off"
        menu.addItem(withTitle: loginTitle, action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

        menu.addItem(.separator())
        let badge = AppPreferences.shared.unreadBadgeCount
        let clearItem = menu.addItem(
            withTitle: badge > 0 ? "Clear Badge (\(badge))" : "Clear Badge",
            action: #selector(clearBadge),
            keyEquivalent: ""
        )
        clearItem.isEnabled = badge > 0
        menu.addItem(withTitle: "Test Badge +1", action: #selector(testBadge), keyEquivalent: "")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit QAdrito", action: #selector(quitApp), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }
        statusItem?.menu = menu
    }

    @objc private func openQAdrito() {
        showMainWindow()
    }

    @objc private func toggleDoNotDisturb() {
        let prefs = AppPreferences.shared
        prefs.setDoNotDisturb(!prefs.isDoNotDisturb)
    }

    @objc private func toggleLaunchAtLogin() {
        let prefs = AppPreferences.shared
        prefs.setLaunchAtLogin(!prefs.launchAtLogin)
    }

    @objc private func clearBadge() {
        AppPreferences.shared.clearBadge()
    }

    @objc private func testBadge() {
        // Bypass DND so badge/menu-bar can be verified without waiting for PR activity.
        let id = "test:\(Int(Date().timeIntervalSince1970 * 1000))"
        _ = NotificationStore.shared.record(
            id: id,
            type: .comment,
            title: "QAdrito test notification",
            body: "Test inbox + badge",
            prDisplayName: "test",
            repositoryFullName: "test/test",
            prUrl: "https://github.com",
            deepLinkUrl: "https://github.com"
        )
        NotificationService.shared.requestAuthorizationIfNeeded()
        let wasDND = AppPreferences.shared.isDoNotDisturb
        if wasDND {
            // Still want a visible OS banner for this manual test.
            let content = UNMutableNotificationContent()
            content.title = "QAdrito"
            content.body = "Test notification"
            content.sound = .default
            content.badge = NSNumber(value: NotificationStore.shared.unreadCount)
            content.userInfo = ["url": "https://github.com", "notificationId": id]
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        } else {
            NotificationService.shared.post(
                title: "QAdrito",
                body: "Test notification",
                url: "https://github.com",
                notificationId: id
            )
        }
    }

    private func makeNotificationsMenuItem() -> NSMenuItem {
        let unread = NotificationStore.shared.unreadCount
        let rootTitle = unread > 0 ? "Notifications (\(unread))" : "Notifications"
        let root = NSMenuItem(title: rootTitle, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Notifications")

        let recent = NotificationStore.shared.recent(limit: 5)
        if recent.isEmpty {
            let empty = NSMenuItem(title: "No notifications", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for item in recent {
                var title = item.title
                if title.count > 52 {
                    title = String(title.prefix(49)) + "…"
                }
                if item.isUnread {
                    title = "• " + title
                }
                let menuItem = NSMenuItem(
                    title: title,
                    action: #selector(openInboxNotification(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item.id
                menuItem.toolTip = item.body
                submenu.addItem(menuItem)
            }
        }

        submenu.addItem(.separator())
        let openItem = NSMenuItem(
            title: "Open Notifications…",
            action: #selector(openNotificationsPanel),
            keyEquivalent: ""
        )
        openItem.target = self
        submenu.addItem(openItem)

        root.submenu = submenu
        return root
    }

    @objc private func openInboxNotification(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = NotificationStore.shared.items.first(where: { $0.id == id }) else {
            return
        }
        NotificationStore.shared.open(item)
    }

    @objc private func openNotificationsPanel() {
        showMainWindow()
        NotificationCenter.default.post(name: .qadritoOpenNotificationsPanel, object: nil)
    }

    @objc private func checkForUpdates() {
        UpdaterService.shared.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }


    private func makeWaitingForMeMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Waiting for me", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Waiting for me")
        let sections = WaitingForMeMenuStore.shared.sections
        
        if sections.isEmpty {
            let empty = NSMenuItem(title: "No PRs waiting on you", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for (index, section) in sections.enumerated() {
                let headerTitle = "\(ageGroupEmoji(section.group)) \(section.group.title)"
                let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
                header.isEnabled = false
                submenu.addItem(header)
                
                for stack in section.stacks {
                    let pr = stack.base
                    var label = stack.displayName
                    if stack.stackSize > 1 {
                        label += " (\(stack.stackSize))"
                    }
                    let truncatedTitle = pr.title.count > 48
                        ? String(pr.title.prefix(45)) + "…"
                        : pr.title
                    label += " — \(truncatedTitle)"
                    
                    let item = NSMenuItem(
                        title: label,
                        action: #selector(openWaitingPR(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = pr.htmlUrl
                    item.toolTip = pr.htmlUrl
                    submenu.addItem(item)
                }
                
                if index < sections.count - 1 {
                    submenu.addItem(.separator())
                }
            }
        }
        
        root.submenu = submenu
        return root
    }
    
    private func ageGroupEmoji(_ group: PRAgeGroup) -> String {
        switch group {
        case .critical: return "🔴"
        case .warning: return "⚠️"
        case .onTime: return "🟢"
        }
    }
    
    @objc private func openWaitingPR(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let windows = NSApp.windows.filter { window in
            let className = window.className
            if className.contains("StatusBar") || className.contains("NSMenu") {
                return false
            }
            return window.canBecomeMain || window.canBecomeKey
        }

        if let window = windows.first(where: { $0.isMiniaturized }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let window = windows.first {
            window.makeKeyAndOrderFront(nil)
            return
        }
        Self.openMainWindowHandler?()
    }
}
