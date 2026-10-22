import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var newExclusion = ""

    var body: some View {
        Form {
            Section("Deletion") {
                Picker("When cleaning", selection: $settings.settings.deletionMode) {
                    ForEach(DeletionMode.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Large & Old Files") {
                Stepper("Minimum size: \(ByteFormatting.string(settings.settings.largeFileMinBytes))", value: $settings.settings.largeFileMinBytes, in: 1_000_000...50_000_000_000, step: 50_000_000)
                Stepper("Not opened in \(settings.settings.oldFileDays) days", value: $settings.settings.oldFileDays, in: 7...3650, step: 30)
            }
            Section("Notifications") {
                Toggle("Low disk space", isOn: $settings.settings.notifyLowDisk)
                Toggle("High memory pressure", isOn: $settings.settings.notifyMemoryPressure)
                Toggle("Trash over \(ByteFormatting.string(settings.settings.trashNotifyBytes))", isOn: $settings.settings.notifyLargeTrash)
                Toggle("Weekly Smart Care reminder", isOn: $settings.settings.notifyWeeklySmartCare)
            }
            Section("Menu bar & login") {
                Toggle("Show menu bar monitor", isOn: $settings.settings.showMenuBar)
                Toggle("Launch MacCleaner at login", isOn: $settings.settings.launchAtLogin)
                    .onChange(of: settings.settings.launchAtLogin) { _ in
                        settings.applyLaunchAtLogin()
                    }
            }
            Section("Exclusion list — never touched by any module") {
                ForEach(settings.settings.exclusions, id: \.self) { path in
                    HStack {
                        Text(path)
                        Spacer()
                        Button("Remove") { settings.removeExclusion(path) }
                    }
                }
                HStack {
                    TextField("Folder or app path", text: $newExclusion)
                    Button("Add") {
                        if !newExclusion.isEmpty {
                            settings.addExclusion(newExclusion)
                            newExclusion = ""
                        }
                    }
                    Button("Choose…") { pickExclusion() }
                }
            }
            Section("Permissions") {
                Button("Open Full Disk Access") { FullDiskAccess.openSystemSettings() }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func pickExclusion() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            settings.addExclusion(url.path)
        }
    }
}
