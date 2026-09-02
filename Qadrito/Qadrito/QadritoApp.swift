import SwiftUI

@main
struct QadritoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("QAdrito", id: "main") {
            ContentView()
                .environmentObject(AppPreferences.shared)
                .environmentObject(NotificationStore.shared)
                .background(WindowOpenBridge())
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

private struct WindowOpenBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                AppDelegate.openMainWindowHandler = {
                    openWindow(id: "main")
                }
            }
    }
}
