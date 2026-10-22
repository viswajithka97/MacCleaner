import Foundation

/// Smart Care: one scan across several modules, one Run button.
@MainActor
final class SmartCareViewModel: TaskViewModel {
    @Published var phase: FlowPhase = .intro
    @Published var areas: [SmartCareArea: [CleanCategory]] = [:]
    @Published var included: Set<SmartCareArea> = Set(SmartCareArea.allCases)
    @Published var reviewing: SmartCareArea?
    @Published var showConfirmation = false
    @Published var result = CleanupResult()

    func scan() {
        phase = .scanning
        run({ await SmartCareService.scan(progress: $0) }) { [weak self] areas, cancelled in
            guard let self else { return }
            if cancelled && areas.values.allSatisfy(\.isEmpty) { self.phase = .intro; return }
            self.areas = areas.mapValues { $0.map { $0.applyingDefaults() } }
            self.phase = .results
        }
    }

    func categories(_ area: SmartCareArea) -> [CleanCategory] { areas[area] ?? [] }

    func selectedItems(_ area: SmartCareArea) -> [CleanItem] { categories(area).flatMap(\.selectedItems) }

    func selectedSize(_ area: SmartCareArea) -> Int64 { selectedItems(area).reduce(0) { $0 + $1.size } }

    var allSelectedItems: [CleanItem] {
        SmartCareArea.allCases.filter { included.contains($0) }.flatMap { selectedItems($0) }
    }

    var totalSelectedSize: Int64 { allSelectedItems.reduce(0) { $0 + $1.size } }

    /// One line describing what the card found.
    func headline(_ area: SmartCareArea) -> String {
        let cats = categories(area)
        let count = cats.reduce(0) { $0 + $1.items.count }
        switch area {
        case .cleanup: return count == 0 ? "Nothing to clean" : "\(cats.reduce(0) { $0 + $1.totalSize }.formattedBytes) of junk found"
        case .protection: return count == 0 ? "No threats found" : "\(count) item(s) need your attention"
        case .speed: return "\(count) recommendation(s)"
        case .updates: return count == 0 ? "All apps are up to date" : "\(count) update(s) available"
        }
    }

    func setCategory(_ area: SmartCareArea, _ id: String, selected: Bool) {
        guard var cats = areas[area], let index = cats.firstIndex(where: { $0.id == id }) else { return }
        cats[index].setAll(selected)
        areas[area] = cats
    }

    func toggleItem(_ area: SmartCareArea, _ categoryID: String, _ itemID: UUID) {
        guard var cats = areas[area], let c = cats.firstIndex(where: { $0.id == categoryID }),
              let i = cats[c].items.firstIndex(where: { $0.id == itemID }) else { return }
        cats[c].items[i].isSelected.toggle()
        areas[area] = cats
    }

    func requestRun() {
        guard !allSelectedItems.isEmpty else { return }
        showConfirmation = true
    }

    func confirmRun() {
        showConfirmation = false
        let items = allSelectedItems
        phase = .cleaning
        run({ await CleanupExecutor.perform(items, progress: $0, title: "Smart Care") }) { [weak self] result, _ in
            guard let self else { return }
            self.result = result
            HistoryStore.shared.record(module: "Smart Care", result: result)
            self.phase = .summary
        }
    }

    func reset() {
        phase = .intro
        areas = [:]
    }
}
