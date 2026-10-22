import SwiftUI

struct UpdaterView: View {
    @State private var phase: ScanPhase = .intro
    @State private var progress = 0.0
    @State private var path = ""
    @State private var updates: [AppUpdate] = []
    @State private var cancelled = false
    @State private var summary: CleanupSummary?

    var body: some View {
        VStack {
            switch phase {
            case .intro: IntroPane(module: .updater, onScan: scan)
            case .scanning: ScanningPane(module: .updater, progress: progress, path: path, onCancel: { cancelled = true; phase = .intro })
            case .results:
                List(updates) { update in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(update.name).font(.headline)
                            Spacer()
                            Text("\(update.currentVersion) → \(update.newVersion ?? "")")
                            Text(update.source.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        if !update.releaseNotes.isEmpty {
                            Text(update.releaseNotes).font(.caption).foregroundStyle(.secondary).lineLimit(6)
                        }
                        Button("Update") {
                            UpdaterService.apply(update)
                        }
                    }
                    .padding(.vertical, 4)
                }
            case .summary:
                if let summary { SummaryPane(summary: summary) { phase = .intro } }
            }
        }
        .background(Theme.background)
    }

    private func scan() {
        cancelled = false
        phase = .scanning
        Task {
            let callbacks = ScanCallbacks(
                progress: { v, p in Task { @MainActor in progress = v; path = p } },
                isCancelled: { cancelled }
            )
            let apps = await UninstallerService.listApps(callbacks: callbacks)
            let found = await UpdaterService.scan(apps: apps, callbacks: callbacks)
            if cancelled { return }
            updates = found
            phase = .results
        }
    }
}
