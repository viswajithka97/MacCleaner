import SwiftUI

struct UninstallerView: View {
    @ObservedObject var vm: UninstallerViewModel

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .uninstaller) {
                Picker("", selection: $vm.tab) {
                    ForEach(UninstallerViewModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }
            Divider()
            switch vm.tab {
            case .apps: appsTab
            case .leftovers: LeftoversView(vm: vm.leftovers)
            }
        }
        .onAppear { if !vm.loaded { vm.load() } }
    }

    private var appsTab: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("Search apps", text: $vm.search).textFieldStyle(.roundedBorder).padding(10)
                if vm.isBusy && vm.apps.isEmpty {
                    ScanningView(module: .uninstaller, title: "Finding apps…", snapshot: vm.snapshot, onCancel: vm.cancelTask)
                } else {
                    List(vm.filteredApps, selection: Binding(get: { vm.selectedApp?.id }, set: { id in
                        vm.select(vm.apps.first { $0.id == id })
                    })) { app in
                        AppRow(app: app).tag(app.id)
                    }
                }
            }
            .frame(minWidth: 300, idealWidth: 360)
            detail.frame(minWidth: 420)
        }
    }

    @ViewBuilder private var detail: some View {
        if let app = vm.selectedApp {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(nsImage: SystemLinks.icon(for: app.url)).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.title2.bold())
                        Text("Version \(app.version) · \(app.source) · \(app.bundleID)").font(.callout).foregroundStyle(.secondary)
                        Text("Last opened: \(ByteFormat.relative(app.lastOpened))").font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let refusal = vm.refusal {
                    InfoBanner(style: .danger, text: refusal, symbol: "hand.raised.fill")
                    Spacer()
                } else if let result = vm.result {
                    SummaryView(module: .uninstaller, result: result, doneTitle: "OK") { vm.select(nil) }
                } else if vm.isBusy {
                    ScanningView(module: .uninstaller, title: "Removing…", snapshot: vm.snapshot, onCancel: nil)
                } else {
                    Picker("Mode", selection: $vm.mode) {
                        Text("Complete removal").tag(UninstallerService.Mode.completeRemoval)
                        Text("Reset app (keep the app, delete its data)").tag(UninstallerService.Mode.reset)
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: vm.mode) { _ in vm.findFiles() }
                    if vm.loadingFiles {
                        HStack { ProgressView().controlSize(.small); Text("Finding all of \(app.name)'s files…") }
                        Spacer()
                    } else {
                        List(vm.files) { item in
                            ItemRow(item: item, onToggle: { vm.toggle(item.id) }, onPreview: nil)
                        }
                        HStack {
                            Text("\(vm.selectedFiles.count) of \(vm.files.count) selected").foregroundStyle(.secondary)
                            Spacer()
                            Button(vm.mode == .reset ? "Reset \(vm.selectedSize.formattedBytes)" : "Uninstall \(vm.selectedSize.formattedBytes)") {
                                vm.showConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppModule.uninstaller.tint)
                            .controlSize(.large)
                            .disabled(vm.selectedFiles.isEmpty)
                        }
                    }
                }
            }
            .padding(20)
            .sheet(isPresented: $vm.showConfirmation) {
                ConfirmationSheet(title: vm.mode == .reset ? "Reset \(app.name)?" : "Uninstall \(app.name)?",
                                  items: vm.selectedFiles,
                                  message: "\(app.name) will be quit first. " + (SettingsStore.shared.moveToTrash ? "Files go to the Trash." : "Files are deleted permanently."),
                                  confirmTitle: vm.mode == .reset ? "Reset" : "Uninstall",
                                  onConfirm: vm.confirmRemoval, onCancel: { vm.showConfirmation = false })
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "xmark.app").font(.system(size: 50)).foregroundStyle(AppModule.uninstaller.gradient)
                Text("Select an app to see everything it installed.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AppRow: View {
    var app: InstalledApp

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: SystemLinks.icon(for: app.url)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text("\(app.version) · \(app.source) · opened \(ByteFormat.relative(app.lastOpened))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(app.size.map { $0.formattedBytes } ?? "…").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if app.isProtected { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct LeftoversView: View {
    @ObservedObject var vm: CleanupFlowViewModel

    var body: some View {
        CleanupFlowView(vm: vm, scanTitle: "Find Leftovers") {
            InfoBanner(text: "Looks for data folders named after apps that are no longer installed. Nothing is selected automatically — review each one.")
        } accessory: {
            InfoBanner(style: .warning, text: "Some items may belong to command-line tools or helpers installed without an app. Only remove what you recognize.")
        }
    }
}

struct UpdaterView: View {
    @ObservedObject var vm: UpdaterViewModel

    var body: some View {
        if !vm.checked && !vm.isBusy {
            ModuleIntroView(module: .updater, buttonTitle: "Check", onStart: vm.check) {
                InfoBanner(text: "Checks Sparkle appcasts, the Mac App Store and Homebrew casks. Nothing is installed until you click Update.")
            }
        } else if vm.isBusy {
            ScanningView(module: .updater, title: "Checking for updates…", snapshot: vm.snapshot, onCancel: vm.cancelTask)
        } else {
            VStack(spacing: 0) {
                ModuleHeader(module: .updater, subtitle: vm.updates.isEmpty ? "All your apps are up to date." : "\(vm.updates.count) update(s) available") {
                    Button("Check Again", action: vm.check)
                    Button("Update All", action: vm.installAll).buttonStyle(.borderedProminent).disabled(vm.updates.isEmpty)
                }
                List(vm.updates) { update in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            if let url = update.appURL {
                                Image(nsImage: SystemLinks.icon(for: url)).resizable().frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "mug").font(.title2).frame(width: 32)
                            }
                            VStack(alignment: .leading) {
                                Text(update.appName).font(.headline)
                                Text("\(update.currentVersion) → \(update.newVersion) · \(update.source.label)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if vm.installing.contains(update.id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button(buttonTitle(update)) { vm.install(update) }
                            }
                        }
                        if !update.releaseNotes.isEmpty {
                            DisclosureGroup("Release notes", isExpanded: Binding(get: { vm.expanded.contains(update.id) }, set: { open in
                                if open { vm.expanded.insert(update.id) } else { vm.expanded.remove(update.id) }
                            })) {
                                Text(update.releaseNotes).font(.callout).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        if let message = vm.messages[update.id] {
                            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func buttonTitle(_ update: AppUpdate) -> String {
        switch update.source {
        case .appStore: return "Open App Store"
        case .sparkle: return "Download Update"
        case .homebrew: return "brew upgrade"
        }
    }
}
