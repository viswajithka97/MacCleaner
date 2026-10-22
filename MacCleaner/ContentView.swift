import SwiftUI

/// Kept so the original Xcode template still compiles. The real UI is `RootView`.
struct ContentView: View {
    var body: some View { RootView() }
}

#Preview {
    RootView()
        .environmentObject(SettingsStore.shared)
        .environmentObject(HistoryStore.shared)
        .environmentObject(SystemMonitorService())
}
