import SwiftUI
import UniformTypeIdentifiers

struct ShredderView: View {
    @State private var urls: [URL] = []
    @State private var confirm = false
    @State private var summary: CleanupSummary?
    @State private var phase: ScanPhase = .intro
    @State private var progress = 0.0
    @State private var path = ""

    var body: some View {
        VStack {
            if let summary, phase == .summary {
                SummaryPane(summary: summary) { phase = .intro; urls = []; self.summary = nil }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "xmark.seal.fill").font(.system(size: 48)).foregroundStyle(.red)
                    Text("Shredder").font(.largeTitle.bold())
                    Text("Overwrites file contents with random data, then deletes. On SSDs, wear leveling means this is not a guarantee. FileVault encryption is the real protection.")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.red.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .background(RoundedRectangle(cornerRadius: 16).fill(.red.opacity(0.05)))
                        .overlay(Text(urls.isEmpty ? "Drop files or folders here" : urls.map(\.lastPathComponent).joined(separator: ", ")))
                        .frame(height: 160)
                        .padding()
                        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                            for provider in providers {
                                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                    if let url {
                                        DispatchQueue.main.async { urls.append(url) }
                                    }
                                }
                            }
                            return true
                        }
                    Button("Choose…") { pick() }
                    if phase == .scanning {
                        ProgressView(value: progress)
                        Text(path).font(.caption)
                    }
                    Button("Shred \(urls.count) item(s)") { confirm = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(urls.isEmpty)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .confirmationDialog("This cannot be undone.", isPresented: $confirm) {
            Button("Overwrite and delete forever", role: .destructive) { Task { await shred() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MacCleaner will overwrite these paths with random data, then remove them:\n" + urls.map(\.path).joined(separator: "\n"))
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { urls.append(contentsOf: panel.urls) }
    }

    private func shred() async {
        phase = .scanning
        var items: [CleanableItem] = []
        for url in urls {
            path = url.path
            items.append(FileScanSupport.item(name: url.lastPathComponent, url: url))
        }
        let outcome = await DeletionService.remove(items: items, settings: SettingsStore.shared.settings, shred: true)
        let summary = CleanupSummary(module: .shredder, removedCount: outcome.removed, bytesFreed: outcome.bytes, skipped: outcome.skipped, notes: ["Secure overwrite attempted. Not guaranteed on SSDs."])
        HistoryStore.shared.append(summary)
        self.summary = summary
        phase = .summary
    }
}

import AppKit
