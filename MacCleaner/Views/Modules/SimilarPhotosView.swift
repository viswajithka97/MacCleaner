import SwiftUI
import AppKit

struct SimilarPhotosView: View {
    @State private var phase: ScanPhase = .intro
    @State private var progress = 0.0
    @State private var path = ""
    @State private var groups: [SimilarPhotoGroup] = []
    @State private var folder = FileScanSupport.home().appendingPathComponent("Pictures")
    @State private var includeLibrary = true
    @State private var cancelled = false
    @State private var confirm = false
    @State private var summary: CleanupSummary?

    var body: some View {
        VStack {
            switch phase {
            case .intro:
                VStack(spacing: 12) {
                    IntroPane(module: .similarPhotos, onScan: scan)
                    Toggle("Include Photos library (PhotoKit, read until you confirm delete)", isOn: $includeLibrary)
                    Button("Choose image folder…") { pick() }
                }
            case .scanning:
                ScanningPane(module: .similarPhotos, progress: progress, path: path, onCancel: { cancelled = true; phase = .intro })
            case .results:
                VStack {
                    HStack {
                        Text("Best shot is kept (highest resolution + sharpness). Others are selected for deletion.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Delete selected") { confirm = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    List {
                        ForEach($groups) { $group in
                            Section("\(group.photos.count) similar") {
                                ForEach($group.photos) { $photo in
                                    HStack {
                                        Toggle("", isOn: $photo.item.selected).labelsHidden()
                                        VStack(alignment: .leading) {
                                            Text(photo.item.name)
                                            Text("\(photo.width)×\(photo.height) · \(photo.isBest ? "Keep (best)" : "Duplicate")")
                                                .font(.caption)
                                                .foregroundStyle(photo.isBest ? .green : .secondary)
                                        }
                                        Spacer()
                                        Button("Reveal") { FinderReveal.reveal(photo.item.path) }
                                        Button("Quick Look") { QuickLookPreview.shared.preview(paths: [photo.item.path]) }
                                    }
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
        .confirmationDialog("Delete selected similar photos?", isPresented: $confirm) {
            Button("Delete", role: .destructive) { Task { await go() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Photos library items are deleted through PhotoKit. Files go to Trash. This cannot be easily undone.")
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
            groups = await SimilarPhotosService.scan(folders: [folder], includePhotosLibrary: includeLibrary, callbacks: callbacks)
            if cancelled { return }
            phase = .results
        }
    }

    private func go() async {
        let items = groups.flatMap(\.photos).filter { $0.item.selected }.map(\.item)
        let outcome = await DeletionService.remove(items: items, settings: SettingsStore.shared.settings)
        let summary = CleanupSummary(module: .similarPhotos, removedCount: outcome.removed, bytesFreed: outcome.bytes, skipped: outcome.skipped, notes: [])
        HistoryStore.shared.append(summary)
        self.summary = summary
        phase = .summary
    }
}
