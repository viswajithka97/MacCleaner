import SwiftUI

@MainActor
final class SmartCareViewModel: ObservableObject {
    @Published var phase: ScanPhase = .intro
    @Published var progress: Double = 0
    @Published var currentPath: String = ""
    @Published var cards: [SmartCareCard] = []
    @Published var confirm = false
    @Published var summary: CleanupSummary?
    private var cancelled = false
    private var task: Task<Void, Never>?

    var selectedSize: Int64 {
        cards.filter(\.selected).flatMap(\.categories).reduce(0) { $0 + $1.selectedSize }
    }

    func scan() {
        cancelled = false
        phase = .scanning
        task = Task {
            let callbacks = ScanCallbacks(
                progress: { v, p in Task { @MainActor in self.progress = v; self.currentPath = p } },
                isCancelled: { self.cancelled || Task.isCancelled }
            )
            let cards = await SmartCareService.scan(callbacks: callbacks)
            if cancelled { phase = .intro; return }
            self.cards = cards
            phase = .results
        }
    }

    func cancel() { cancelled = true; task?.cancel(); phase = .intro }

    func run() async {
        confirm = false
        var all: [CleanableItem] = []
        for card in cards where card.selected {
            all.append(contentsOf: card.categories.flatMap(\.selectedItems))
        }
        var notes: [String] = []
        var leftover: [CleanableItem] = []
        for item in all {
            if let note = await SpecialActions.perform(item) { notes.append(note) }
            else { leftover.append(item) }
        }
        let outcome = await DeletionService.remove(items: leftover, settings: SettingsStore.shared.settings)
        let summary = CleanupSummary(module: .smartCare, removedCount: outcome.removed + notes.count, bytesFreed: outcome.bytes, skipped: outcome.skipped, notes: notes)
        self.summary = summary
        HistoryStore.shared.append(summary)
        phase = .summary
    }
}

struct SmartCareView: View {
    @StateObject private var model = SmartCareViewModel()
    var body: some View {
        VStack {
            FDABanner().padding()
            switch model.phase {
            case .intro:
                IntroPane(module: .smartCare, onScan: model.scan)
            case .scanning:
                ScanningPane(module: .smartCare, progress: model.progress, path: model.currentPath, onCancel: model.cancel)
            case .results:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Recommended actions").font(.title.bold())
                            Spacer()
                            Button("Run \(ByteFormatting.string(model.selectedSize))") { model.confirm = true }
                                .buttonStyle(.borderedProminent)
                        }
                        ForEach($model.cards) { $card in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $card.selected) {
                                    Label(card.module.title, systemImage: card.module.symbol)
                                        .font(.headline)
                                }
                                Text(card.module.subtitle).font(.caption).foregroundStyle(.secondary)
                                ForEach(card.categories) { cat in
                                    HStack {
                                        Text(cat.name)
                                        Spacer()
                                        Text(ByteFormatting.string(cat.selectedSize)).monospacedDigit()
                                        Text("\(cat.selectedItems.count) items").foregroundStyle(.secondary)
                                    }
                                    .font(.callout)
                                }
                            }
                            .macCard(card.module.accent)
                        }
                    }
                    .padding()
                }
            case .summary:
                if let summary = model.summary {
                    SummaryPane(summary: summary) { model.phase = .intro }
                }
            }
        }
        .background(Theme.background)
        .confirmationDialog("Run Smart Care?", isPresented: $model.confirm) {
            Button("Run selected actions", role: .destructive) { Task { await model.run() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This performs junk cleanup, trash emptying, malware removals you selected, force-quits hung apps, and starts available updates.")
        }
    }
}
