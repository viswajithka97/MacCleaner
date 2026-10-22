import SwiftUI
import AppKit

struct DuplicatesView: View {
    @State private var phase: ScanPhase = .intro
    @State private var progress = 0.0
    @State private var path = ""
    @State private var groups: [DuplicateGroup] = []
    @State private var folder = FileScanSupport.home()
    @State private var cancelled = false
    @State private var confirm = false
    @State private var summary: CleanupSummary?

    var body: some View {
        VStack {
            switch phase {
            case .intro:
                VStack {
                    IntroPane(module: .duplicates, onScan: scan)
                    Button("Choose folder…") { pick() }
                }
            case .scanning:
                ScanningPane(module: .duplicates, progress: progress, path: path, onCancel: { cancelled = true; phase = .intro })
            case .results:
                VStack {
                    HStack {
                        Button("Auto Select (keep newest)") {
                            DuplicatesService.autoSelectNewest(&groups)
                        }
                        Spacer()
                        Button("Move selected to Trash") { confirm = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    List {
                        ForEach($groups) { $group in
                            Section("\(group.items.count) copies · \(ByteFormatting.string(group.size))") {
                                ForEach($group.items) { $item in
                                    ItemRow(item: $item)
                                }
                            }
                        }
                    }
                }
            case .summary:
                if let summary { SummaryPane(summary: summary) { phase = .intro } }
            }
        }
        .background(Theme.background)
        .confirmationDialog("Remove selected duplicates?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { Task { await go() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            let items = groups.flatMap(\.items).filter(\.selected)
            Text(items.map(\.path).prefix(20).joined(separator: "\n"))
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { folder = url }
    }

    private func scan() {
        cancelled = false
        phase = .scanning
        Task {
            let callbacks = ScanCallbacks(
                progress: { v, p in Task { @MainActor in progress = v; path = p } },
                isCancelled: { cancelled }
            )
            groups = await DuplicatesService.scan(roots: [folder], callbacks: callbacks)
            if cancelled { return }
            phase = .results
        }
    }

    private func go() async {
        let items = groups.flatMap(\.items).filter(\.selected)
        let outcome = await DeletionService.remove(items: items, settings: SettingsStore.shared.settings)
        let summary = CleanupSummary(module: .duplicates, removedCount: outcome.removed, bytesFreed: outcome.bytes, skipped: outcome.skipped, notes: [])
        HistoryStore.shared.append(summary)
        self.summary = summary
        phase = .summary
    }
}
