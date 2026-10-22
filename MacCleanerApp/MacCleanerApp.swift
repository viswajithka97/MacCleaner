import SwiftUI

/// App entry point: the main window plus the menu bar monitor.
@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = SettingsStore.shared

    /// SwiftUI writes back to this binding whenever macOS shows/hides the status item
    /// (e.g. when the menu bar is full). Writing only on a real change prevents an
    /// endless update loop: write → settings publish → scene update → write…
    private var menuBarBinding: Binding<Bool> {
        Binding(get: { settings.showMenuBar },
                set: { newValue in
                    if newValue != settings.showMenuBar { settings.showMenuBar = newValue }
                })
    }

    var body: some Scene {
        WindowGroup("MacCleaner", id: "main") {
            RootView()
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra(isInserted: menuBarBinding) {
            MenuBarView()
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            NotificationService.shared.requestAuthorization()
            NotificationService.shared.updateWeeklyReminder(enabled: SettingsStore.shared.weeklyReminder)
            // Starts sampling so notifications work even when the menu isn't open.
            SystemMonitor.shared.start()
            PermissionCenter.shared.refresh()
        }
        #if DEBUG
        // Debug aid: MACCLEANER_SNAPSHOT=/path/out.png [MACCLEANER_MODULE=systemJunk] saves the window as a PNG.
        if let path = ProcessInfo.processInfo.environment["MACCLEANER_SNAPSHOT"] {
            Task { @MainActor in
                if let raw = ProcessInfo.processInfo.environment["MACCLEANER_MODULE"], let module = AppModule(rawValue: raw) {
                    AppState.shared.selection = module
                    // MACCLEANER_AUTOSCAN=1 starts the module's scan (generic cleanup modules only).
                    if ProcessInfo.processInfo.environment["MACCLEANER_AUTOSCAN"] != nil {
                        let state = AppState.shared
                        let flows: [AppModule: CleanupFlowViewModel] = [.systemJunk: state.systemJunk, .mailAttachments: state.mailAttachments,
                                                                        .trashBins: state.trashBins, .malware: state.malware,
                                                                        .privacy: state.privacy, .extensions: state.extensions]
                        flows[module]?.scan()
                        if module == .smartCare { state.smartCare.scan() }
                    }
                }
                let delay = Double(ProcessInfo.processInfo.environment["MACCLEANER_DELAY"] ?? "3") ?? 3
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let view = NSApp.windows.first(where: { $0.isVisible && $0.frame.height > 300 })?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                var lines: [String] = ["window \(view.window!.frame) layout \(view.window!.contentLayoutRect)"]
                @MainActor func dump(_ v: NSView, _ depth: Int) {
                    guard depth < 9 else { return }
                    lines.append(String(repeating: "  ", count: depth) + "\(type(of: v)) \(v.frame) fit \(v.fittingSize)")
                    v.subviews.forEach { dump($0, depth + 1) }
                }
                dump(view, 0)
                try? lines.joined(separator: "\n").write(toFile: path + ".txt", atomically: true, encoding: .utf8)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
        #endif
    }

    /// Keep running in the menu bar after the window closes (if the monitor is shown).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: SettingsStore.Key.showMenuBar)
    }
}
