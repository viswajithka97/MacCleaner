import Foundation
import Combine

@MainActor
final class CleaningFlowViewModel: ObservableObject {
    @Published var phase: ScanPhase = .intro
    @Published var progress: Double = 0
    @Published var currentPath: String = ""
    @Published var categories: [CleanableCategory] = []
    @Published var summary: CleanupSummary?
    @Published var confirmVisible = false
    @Published var errorMessage: String?
    @Published var reviewing = false

    let module: AppModule
    private var scanTask: Task<Void, Never>?
    private var cancelled = false

    init(module: AppModule) {
        self.module = module
    }

    var selectedSize: Int64 {
        categories.reduce(0) { $0 + $1.selectedSize }
    }

    var selectedItems: [CleanableItem] {
        categories.flatMap(\.selectedItems)
    }

    func startScan() {
        cancelled = false
        phase = .scanning
        progress = 0
        currentPath = "Starting…"
        categories = []
        scanTask = Task { [weak self] in
            guard let self else { return }
            let callbacks = ScanCallbacks(
                progress: { value, path in
                    Task { @MainActor in
                        self.progress = value
                        self.currentPath = path
                    }
                },
                isCancelled: { [weak self] in
                    self?.cancelled == true || Task.isCancelled
                }
            )
            let result = await self.runScan(callbacks: callbacks)
            if self.cancelled { self.phase = .intro; return }
            self.categories = result
            self.progress = 1
            self.phase = .results
        }
    }

    func cancel() {
        cancelled = true
        scanTask?.cancel()
        phase = .intro
    }

    func toggleCategory(_ id: UUID, selected: Bool) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[i].selected = selected
        for j in categories[i].items.indices {
            if categories[i].items[j].removable {
                categories[i].items[j].selected = selected
            }
        }
    }

    func toggleItem(category: UUID, item: UUID, selected: Bool) {
        guard let i = categories.firstIndex(where: { $0.id == category }) else { return }
        guard let j = categories[i].items.firstIndex(where: { $0.id == item }) else { return }
        categories[i].items[j].selected = selected
        categories[i].selected = categories[i].items.contains { $0.selected }
    }

    func performCleanup() {
        confirmVisible = true
    }

    func confirmCleanup() async {
        confirmVisible = false
        let items = selectedItems
        var notes: [String] = []
        var specialSkippedFileDelete: [CleanableItem] = []
        var leftover: [CleanableItem] = []
        for item in items {
            if let note = await SpecialActions.perform(item) {
                notes.append(note)
                specialSkippedFileDelete.append(item)
            } else {
                leftover.append(item)
            }
        }
        let settings = SettingsStore.shared.settings
        let outcome = await DeletionService.remove(items: leftover, settings: settings, shred: module == .shredder)
        let bytes = outcome.bytes
        let summary = CleanupSummary(
            module: module,
            removedCount: outcome.removed + specialSkippedFileDelete.count,
            bytesFreed: bytes,
            skipped: outcome.skipped,
            notes: notes
        )
        self.summary = summary
        HistoryStore.shared.append(summary)
        phase = .summary
    }

    func reset() {
        phase = .intro
        categories = []
        summary = nil
        progress = 0
    }

    private func runScan(callbacks: ScanCallbacks) async -> [CleanableCategory] {
        switch module {
        case .systemJunk: return await SystemJunkService.scan(callbacks: callbacks)
        case .mailAttachments: return await MailAttachmentsService.scan(callbacks: callbacks)
        case .trashBins: return await TrashBinsService.scan(callbacks: callbacks)
        case .malware: return await MalwareService.scan(callbacks: callbacks)
        case .privacy: return await PrivacyService.scan(callbacks: callbacks)
        case .extensions: return await ExtensionsService.scan(callbacks: callbacks)
        default: return []
        }
    }
}
