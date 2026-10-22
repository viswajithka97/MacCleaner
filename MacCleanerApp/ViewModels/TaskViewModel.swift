import Foundation
import Combine

/// Base class for view models that run long jobs in the background.
///
/// `run` starts the job on a background thread and polls its `ScanProgress`
/// ten times a second, so the progress bar and "current path" stay live
/// without ever blocking the main thread.
@MainActor
class TaskViewModel: ObservableObject {
    @Published var snapshot = ScanProgress.Snapshot(fraction: nil, currentPath: "", message: "", itemsScanned: 0)
    @Published var isBusy = false

    private var progress: ScanProgress?
    private var poller: Timer?

    /// `work` is `@Sendable` on purpose: a plain closure written inside a `@MainActor` view model
    /// would inherit main-actor isolation and run the scan on the main thread, freezing the UI.
    func run<T>(_ work: @escaping @Sendable (ScanProgress) async -> T, done: @escaping (T, _ cancelled: Bool) -> Void) {
        progress?.cancel()
        let board = ScanProgress()
        progress = board
        isBusy = true
        snapshot = board.snapshot
        poller?.invalidate()
        poller = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.snapshot = board.snapshot }
        }
        Task {
            let value = await Task.detached(priority: .userInitiated) { await work(board) }.value
            guard self.progress === board else { return }    // a newer job replaced this one
            self.poller?.invalidate()
            self.snapshot = board.snapshot
            self.isBusy = false
            done(value, board.isCancelled)
        }
    }

    /// The Cancel button.
    func cancelTask() {
        progress?.cancel()
    }
}

/// Phases every cleanup module goes through.
enum FlowPhase {
    case intro, scanning, results, cleaning, summary
}

/// The intro → scan → results → clean → summary flow shared by most modules.
@MainActor
final class CleanupFlowViewModel: TaskViewModel {
    let module: AppModule
    let actionTitle: String
    private let scanner: @Sendable (ScanProgress) async -> [CleanCategory]

    @Published var phase: FlowPhase = .intro
    @Published var categories: [CleanCategory] = []
    @Published var result = CleanupResult()
    @Published var showConfirmation = false
    @Published var reviewDetails = false
    @Published var expanded: Set<String> = []
    /// Items queued for removal when the confirmation is shown.
    @Published var pendingItems: [CleanItem] = []

    init(module: AppModule, actionTitle: String, scanner: @escaping @Sendable (ScanProgress) async -> [CleanCategory]) {
        self.module = module
        self.actionTitle = actionTitle
        self.scanner = scanner
    }

    var selectedItems: [CleanItem] { categories.flatMap(\.selectedItems) }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { categories.filter { !$0.infoOnly }.reduce(0) { $0 + $1.totalSize } }

    func scan() {
        phase = .scanning
        categories = []
        run(scanner) { [weak self] categories, cancelled in
            guard let self else { return }
            if cancelled && categories.isEmpty { self.phase = .intro; return }
            self.categories = categories.map { $0.applyingDefaults() }
            self.phase = .results
        }
    }

    // MARK: Selection

    func setCategory(_ id: String, selected: Bool) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].setAll(selected)
    }

    func toggleItem(_ categoryID: String, _ itemID: UUID) {
        guard let c = categories.firstIndex(where: { $0.id == categoryID }),
              let i = categories[c].items.firstIndex(where: { $0.id == itemID }) else { return }
        categories[c].items[i].isSelected.toggle()
    }

    func selectAll(_ selected: Bool) {
        for index in categories.indices where !categories[index].infoOnly { categories[index].setAll(selected) }
    }

    // MARK: Cleaning

    /// Shows the confirmation sheet for everything selected.
    func requestClean() {
        pendingItems = selectedItems
        guard !pendingItems.isEmpty else { return }
        showConfirmation = true
    }

    /// Shows the confirmation sheet for a single item (per-row Remove/Disable buttons).
    func requestSingle(_ item: CleanItem) {
        pendingItems = [item]
        showConfirmation = true
    }

    func confirmClean() {
        showConfirmation = false
        let items = pendingItems
        let title = module.title
        phase = .cleaning
        run({ progress in await CleanupExecutor.perform(items, progress: progress, title: title) }) { [weak self] result, _ in
            guard let self else { return }
            self.result = result
            HistoryStore.shared.record(module: title, result: result)
            self.phase = .summary
        }
    }

    func reset() {
        phase = .intro
        categories = []
        result = CleanupResult()
    }
}
