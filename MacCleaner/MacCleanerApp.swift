import SwiftUI

@main
struct MacCleanerApp: App {
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var history = HistoryStore.shared
    @StateObject private var monitor = SystemMonitorService()
    @StateObject private var admin = AdminPrivileges.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(monitor)
                .environmentObject(admin)
                .frame(minWidth: 1100, minHeight: 720)
                .onAppear {
                    monitor.start()
                    NotificationManager.shared.requestAuthorization()
                    NotificationManager.shared.scheduleWeeklySmartCareIfNeeded(settings: settings.settings)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 780)

        MenuBarExtra(isInserted: $settings.settings.showMenuBar) {
            MenuBarView()
                .environmentObject(monitor)
                .environmentObject(settings)
        } label: {
            Image(systemName: "leaf.circle.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(width: 640, height: 520)
        }
    }
}
