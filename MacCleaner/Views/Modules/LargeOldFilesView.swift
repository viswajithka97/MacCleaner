import SwiftUI

struct LargeOldFilesView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var phase: ScanPhase = .intro
    @State private var progress = 0.0
    @State private var path = ""
    @State private var items: [CleanableItem] = []
    @State private var kind: FileKindFilter = .all
    @State private var sort = 0
    @State private var folder = FileScanSupport.home()
    @State private var cancelled = false
    @State private var confirm = false
    @State private var shred = false
    @State private var summary: CleanupSummary?

    var sorted: [CleanableItem] {
        switch sort {
        case 1: return items.sorted { $0.subtitle < $1.subtitle }
        case 2: return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        default: return items.sorted { $0.size > $1.size }
        }
    }

    var body: some View {
        VStack {
            switch phase {
            case .intro:
                VStack {
                    IntroPane(module: .largeOldFiles, onScan: scan)
                    HStack {
                        Text("Min size: \(ByteFormatting.string(settings.settings.largeFileMinBytes))")
                        Text("Older than \(settings.settings.oldFileDays) days")
                        Button("Choose folder…") { pick() }
                    }
                }
            case .scanning:
                ScanningPane(module: .largeOldFiles, progress: progress, path: path, onCancel: { cancelled = true; phase = .intro })
            case .results:
                VStack {
                    HStack {
                        Picker("Kind", selection: $kind) {
                            ForEach(FileKindFilter.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Sort", selection: $sort) {
                            Text("Size").tag(0)
                            Text("Date").tag(1)
                            Text("Name").tag(2)
                        }
                        Spacer()
                        Button("Remove \(ByteFormatting.string(items.filter(\.selected).reduce(0) { $0 + $1.size }))") { shred = false; confirm = true }
                            .buttonStyle(.borderedProminent)
                        Button("Shred selected") { shred = true; confirm = true }
                    }
                    .padding()
                    List {
                        ForEach($items) { $item in
                            if kind == .all || LargeOldFilesServiceMatches(item: item.wrappedValue, kind: kind) {
                                ItemRow(item: $item)
                            }
                        }
                    }
                }
            case .summary:
                if let summary { SummaryPane(summary: summary) { phase = .intro } }
            }
        }
        .background(Theme.background)
        .confirmationDialog(shred ? "Shred files? This cannot be undone." : "Remove files?", isPresented: $confirm) {
            Button(shred ? "Shred" : "Remove", role: .destructive) { Task { await go() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(items.filter(\.selected).map(\.path).prefix(20).joined(separator: "\n"))
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
            let older = Calendar.current.date(byAdding: .day, value: -settings.settings.oldFileDays, to: Date())
            items = await LargeOldFilesService.scan(roots: [folder], minBytes: settings.settings.largeFileMinBytes, olderThan: older, kind: .all, callbacks: callbacks)
            if cancelled { return }
            phase = .results
        }
    }

    private func go() async {
        let selected = items.filter(\.selected)
        let outcome = await DeletionService.remove(items: selected, settings: settings.settings, shred: shred)
        let summary = CleanupSummary(module: .largeOldFiles, removedCount: outcome.removed, bytesFreed: outcome.bytes, skipped: outcome.skipped, notes: shred ? ["Shredded"] : [])
        HistoryStore.shared.append(summary)
        self.summary = summary
        phase = .summary
    }
}

private func LargeOldFilesServiceMatches(item: CleanableItem, kind: FileKindFilter) -> Bool {
    let ext = (item.path as NSString).pathExtension.lowercased()
    switch kind {
    case .all: return true
    case .archives: return ["zip", "rar", "7z", "tar", "gz"].contains(ext)
    case .videos: return ["mp4", "mov", "mkv", "m4v"].contains(ext)
    case .diskImages: return ["dmg", "iso", "img"].contains(ext)
    case .documents: return ["pdf", "doc", "docx", "pages", "txt"].contains(ext)
    case .music: return ["mp3", "m4a", "wav", "flac"].contains(ext)
    case .other: return true
    }
}

import AppKit
