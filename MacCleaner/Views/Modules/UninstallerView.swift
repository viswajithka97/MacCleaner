import SwiftUI

struct UninstallerView: View {
    @State private var phase: ScanPhase = .intro
    @State private var progress = 0.0
    @State private var path = ""
    @State private var apps: [InstalledApp] = []
    @State private var selected: InstalledApp?
    @State private var leftovers: [CleanableItem] = []
    @State private var orphan: [CleanableItem] = []
    @State private var tab = 0
    @State private var modeComplete = true
    @State private var confirm = false
    @State private var summary: CleanupSummary?
    @State private var cancelled = false

    var body: some View {
        VStack {
            switch phase {
            case .intro: IntroPane(module: .uninstaller, onScan: scan)
            case .scanning: ScanningPane(module: .uninstaller, progress: progress, path: path, onCancel: { cancelled = true; phase = .intro })
            case .results: results
            case .summary:
                if let summary { SummaryPane(summary: summary) { phase = .intro } }
            }
        }
        .background(Theme.background)
        .confirmationDialog("Uninstall \(selected?.name ?? "app")?", isPresented: $confirm) {
            Button(modeComplete ? "Complete removal" : "Reset app data", role: .destructive) {
                Task { await perform() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(leftovers.filter(\.selected).map(\.path).prefix(20).joined(separator: "\n"))
        }
    }

    private var results: some View {
        VStack {
            Picker("", selection: $tab) {
                Text("Apps").tag(0)
                Text("Leftovers").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            if tab == 0 {
                HSplitView {
                    List(apps, selection: Binding(get: { selected?.id }, set: { id in
                        selected = apps.first { $0.id == id }
                        if let selected { loadLeftovers(selected) }
                    })) { app in
                        HStack {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                            }
                            VStack(alignment: .leading) {
                                Text(app.name)
                                Text("\(app.version) · \(app.source) · last opened \(DateFormatting.short(app.lastOpened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ByteFormatting.string(app.size)).monospacedDigit()
                        }
                        .tag(app.id)
                    }
                    leftoverList
                }
            } else {
                List {
                    ForEach($orphan) { $item in
                        ItemRow(item: $item)
                    }
                }
                Button("Move selected leftovers to Trash") {
                    Task {
                        let outcome = await DeletionService.remove(items: orphan.filter(\.selected), settings: SettingsStore.shared.settings)
                        let summary = CleanupSummary(module: .uninstaller, removedCount: outcome.removed, bytesFreed: outcome.bytes, skipped: outcome.skipped, notes: ["Leftovers"])
                        HistoryStore.shared.append(summary)
                        self.summary = summary
                        phase = .summary
                    }
                }
                .padding()
            }
        }
    }

    private var leftoverList: some View {
        VStack(alignment: .leading) {
            if let selected {
                if selected.isApple || selected.isSelf {
                    Text("Apple system apps and MacCleaner itself cannot be removed.")
                        .foregroundStyle(.red)
                        .padding()
                } else {
                    Picker("Mode", selection: $modeComplete) {
                        Text("Complete removal").tag(true)
                        Text("Reset app").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    List {
                        ForEach($leftovers) { $item in
                            ItemRow(item: $item)
                        }
                    }
                    Button("Uninstall \(ByteFormatting.string(leftovers.filter(\.selected).reduce(0) { $0 + $1.size }))") {
                        confirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                    .disabled(leftovers.filter(\.selected).isEmpty)
                }
            } else {
                Text("Select an app to find leftover files.").foregroundStyle(.secondary).padding()
            }
        }
    }

    private func scan() {
        cancelled = false
        phase = .scanning
        Task {
            let callbacks = ScanCallbacks(
                progress: { v, p in Task { @MainActor in progress = v; path = p } },
                isCancelled: { cancelled }
            )
            let list = await UninstallerService.listApps(callbacks: callbacks)
            if cancelled { return }
            apps = list
            orphan = UninstallerService.orphanLeftovers(installed: list, callbacks: callbacks)
            phase = .results
        }
    }

    private func loadLeftovers(_ app: InstalledApp) {
        let callbacks = ScanCallbacks(progress: { _, _ in }, isCancelled: { false })
        leftovers = UninstallerService.leftovers(for: app, callbacks: callbacks)
        if !modeComplete {
            leftovers = leftovers.filter { $0.extra["appBundle"] != "true" }
        }
    }

    private func perform() async {
        var items = leftovers.filter(\.selected)
        if !modeComplete {
            items.removeAll { $0.extra["appBundle"] == "true" }
        }
        for item in items {
            _ = await SpecialActions.perform(item)
        }
        let outcome = await DeletionService.remove(items: items.filter { $0.extra["pkg"] == nil }, settings: SettingsStore.shared.settings)
        let summary = CleanupSummary(module: .uninstaller, removedCount: outcome.removed, bytesFreed: outcome.bytes, skipped: outcome.skipped, notes: [modeComplete ? "Complete removal" : "Reset app"])
        HistoryStore.shared.append(summary)
        self.summary = summary
        phase = .summary
    }
}
