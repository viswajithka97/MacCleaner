import SwiftUI

struct HistoryView: View {
    @ObservedObject var history = HistoryStore.shared
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .history, subtitle: "Total space freed: \(history.totalFreed.formattedBytes)") {
                Button("Show File") { SystemLinks.reveal(history.fileLocation) }
                Button("Clear History") { confirmClear = true }.disabled(history.entries.isEmpty)
            }
            if history.entries.isEmpty {
                Spacer()
                Text("Nothing cleaned yet.").foregroundStyle(.secondary)
                Spacer()
            } else {
                List(history.entries) { entry in
                    DisclosureGroup {
                        ForEach(entry.details, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.module).font(.headline)
                                Text(ByteFormat.dateTime(entry.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(entry.itemsRemoved) item(s)").foregroundStyle(.secondary)
                            Text(entry.bytesFreed.formattedBytes).monospacedDigit().frame(width: 90, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .alert("Clear the cleanup history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { history.clear() }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var permissions = PermissionCenter.shared

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .settings)
            Form {
                Section("Removing files") {
                    Picker("When removing files", selection: $settings.moveToTrash) {
                        Text("Move to Trash (recommended)").tag(true)
                        Text("Delete permanently").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                    Text("Emptying a Trash, shredding and system log removal always delete permanently.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Exclusions — never touched by any module") {
                    if settings.exclusions.isEmpty {
                        Text("No exclusions").foregroundStyle(.secondary)
                    }
                    ForEach(settings.exclusions, id: \.self) { path in
                        HStack {
                            Image(systemName: path.hasSuffix(".app") ? "app" : "folder")
                            Text(path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { settings.removeExclusion(path) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Button("Add Folder…") {
                            for url in FolderPicker.choose() { settings.addExclusion(url.path) }
                        }
                        Button("Add App…") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.application]
                            panel.directoryURL = URL(fileURLWithPath: "/Applications")
                            panel.allowsMultipleSelection = true
                            if panel.runModal() == .OK { panel.urls.forEach { settings.addExclusion($0.path) } }
                        }
                    }
                    Text("Excluding an app also protects its data folders (matched by bundle ID).").font(.caption).foregroundStyle(.secondary)
                }

                Section("Large & Old Files") {
                    Stepper("Large files: at least \(settings.largeFileMB) MB", value: $settings.largeFileMB, in: 10...10_000, step: 50)
                    Stepper("Old files: not opened for \(settings.oldFileDays) days", value: $settings.oldFileDays, in: 30...3650, step: 30)
                }

                Section("Notifications") {
                    HStack {
                        Toggle("Low disk space", isOn: $settings.notifyLowDisk)
                        Stepper("below \(settings.lowDiskGB) GB", value: $settings.lowDiskGB, in: 1...500).disabled(!settings.notifyLowDisk)
                    }
                    Toggle("High memory pressure", isOn: $settings.notifyMemoryPressure)
                    HStack {
                        Toggle("Trash is large", isOn: $settings.notifyTrashSize)
                        Stepper("over \(settings.trashSizeGB) GB", value: $settings.trashSizeGB, in: 1...500).disabled(!settings.notifyTrashSize)
                    }
                    Toggle("Weekly reminder to run Smart Care (Mondays 10:00)", isOn: $settings.weeklyReminder)
                    Button("Notification Settings…") { SystemLinks.open(.notifications) }
                }

                Section("General") {
                    Toggle("Show menu bar monitor", isOn: $settings.showMenuBar)
                    Toggle("Launch MacCleaner at login", isOn: Binding(get: { settings.launchAtLogin },
                                                                       set: { settings.setLaunchAtLogin($0) }))
                    if let error = settings.launchAtLoginError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    Button("Forget administrator password for this session") { AdminService.shared.forgetPassword() }
                }

                Section("Permissions") {
                    HStack {
                        Image(systemName: permissions.hasFullDiskAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(permissions.hasFullDiskAccess ? .green : .orange)
                        Text(permissions.hasFullDiskAccess ? "Full Disk Access is granted." : "Full Disk Access is not granted. Some folders (Mail, Safari, Trash, iOS backups) can't be scanned.")
                        Spacer()
                        Button("Open Settings") { SystemLinks.open(.fullDiskAccess) }
                        Button("Check") { permissions.refresh() }
                    }
                    Button("Automation permissions (System Events, Mail)…") { SystemLinks.open(.automation) }
                }
            }
            .formStyle(.grouped)
        }
    }
}
