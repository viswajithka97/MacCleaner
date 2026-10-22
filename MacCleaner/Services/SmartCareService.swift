import Foundation

struct SmartCareCard: Identifiable {
    var id: AppModule { module }
    var module: AppModule
    var categories: [CleanableCategory]
    var selected: Bool = true
}

enum SmartCareService {
    static func scan(callbacks: ScanCallbacks) async -> [SmartCareCard] {
        var cards: [SmartCareCard] = []
        if callbacks.isCancelled() { return cards }
        callbacks.progress(0.05, "System Junk")
        cards.append(SmartCareCard(module: .systemJunk, categories: await SystemJunkService.scan(callbacks: callbacks)))
        if callbacks.isCancelled() { return cards }
        callbacks.progress(0.4, "Trash Bins")
        cards.append(SmartCareCard(module: .trashBins, categories: await TrashBinsService.scan(callbacks: callbacks)))
        if callbacks.isCancelled() { return cards }
        callbacks.progress(0.55, "Malware")
        cards.append(SmartCareCard(module: .malware, categories: await MalwareService.scan(callbacks: callbacks)))
        if callbacks.isCancelled() { return cards }
        callbacks.progress(0.75, "Optimization")
        let hung = OptimizationService.hungApplications()
        let items = hung.map { CleanableItem(name: $0.name, path: "pid://\($0.pid)", size: 0, subtitle: "Not responding", extra: ["pid": "\($0.pid)", "forceQuit": "true"]) }
        cards.append(SmartCareCard(module: .optimization, categories: [
            CleanableCategory(name: "Hung applications", symbol: "exclamationmark.triangle", items: items)
        ]))
        if callbacks.isCancelled() { return cards }
        callbacks.progress(0.85, "Updater")
        let apps = await UninstallerService.listApps(callbacks: callbacks)
        let updates = await UpdaterService.scan(apps: apps, callbacks: callbacks)
        let updateItems = updates.map {
            CleanableItem(name: $0.name, path: $0.path, size: 0, subtitle: "\($0.currentVersion) → \($0.newVersion ?? "")", extra: ["updateSource": $0.source.rawValue, "updateURL": $0.actionURL ?? "", "cask": $0.caskName ?? ""])
        }
        cards.append(SmartCareCard(module: .updater, categories: [
            CleanableCategory(name: "Available updates", symbol: "arrow.triangle.2.circlepath", items: updateItems)
        ]))
        callbacks.progress(1, "Done")
        return cards
    }
}
