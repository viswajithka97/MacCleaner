import Foundation

/// The four areas shown as cards on the Smart Care dashboard.
enum SmartCareArea: String, CaseIterable, Identifiable {
    case cleanup, protection, speed, updates
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cleanup: return "Cleanup"
        case .protection: return "Protection"
        case .speed: return "Speed"
        case .updates: return "Updates"
        }
    }

    var symbol: String {
        switch self {
        case .cleanup: return "trash.circle.fill"
        case .protection: return "shield.lefthalf.filled"
        case .speed: return "speedometer"
        case .updates: return "arrow.down.app.fill"
        }
    }
}

/// Runs System Junk, Trash Bins, Malware, Optimization and Updater scans together.
enum SmartCareService {

    static func scan(progress: ScanProgress) async -> [SmartCareArea: [CleanCategory]] {
        // Each scan gets its own progress board; we show the combined message.
        let junkProgress = ScanProgress(), trashProgress = ScanProgress(), malwareProgress = ScanProgress()
        let speedProgress = ScanProgress(), updateProgress = ScanProgress()
        let all = [junkProgress, trashProgress, malwareProgress, speedProgress, updateProgress]

        let monitor = Task.detached {
            while !Task.isCancelled {
                if progress.isCancelled { all.forEach { $0.cancel() } }
                let snaps = all.map(\.snapshot)
                progress.setFraction(snaps.map { $0.fraction ?? 0 }.reduce(0, +) / Double(all.count))
                if let busy = snaps.first(where: { ($0.fraction ?? 0) < 1 && !$0.currentPath.isEmpty }) {
                    progress.visit(busy.currentPath)
                    progress.setMessage(busy.message)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
        defer { monitor.cancel() }

        async let junk = Task.detached { SystemJunkService.scan(progress: junkProgress) }.value
        async let trash = Task.detached { TrashService.scan(progress: trashProgress) }.value
        async let malware = Task.detached { MalwareService.scan(progress: malwareProgress) }.value
        async let speed = Task.detached { speedRecommendations(progress: speedProgress) }.value
        async let updates = UpdaterService.checkAll(progress: updateProgress)

        let cleanup = await junk + trash
        let protection = await malware
        let speedCategories = await speed
        let updateList = await updates
        var updateCategories: [CleanCategory] = []
        if !updateList.isEmpty {
            updateCategories.append(CleanCategory(
                id: "updates", title: "App Updates", symbol: "arrow.down.app",
                summary: "Newer versions are available.",
                items: updateList.map { update in
                    CleanItem(name: update.appName, url: update.appURL, size: 0,
                              subtitle: "\(update.currentVersion) → \(update.newVersion) · \(update.source.label)",
                              symbol: "arrow.down.circle", action: .update(update))
                }))
        }
        progress.setFraction(1)
        return [.cleanup: safeCleanup(cleanup),
                .protection: safeProtection(protection),
                .speed: speedCategories,
                .updates: updateCategories]
    }

    // MARK: - Safety policy: Smart Care never removes installed software

    /// Junk categories Smart Care leaves to their own module for manual review.
    /// (Language files edit app bundles; backups and versions aren't junk you can regenerate.)
    private static let manualOnlyCategories: Set<String> = ["languages", "ios-backups", "versions"]

    /// Keeps only removals of caches, logs, Trash contents and broken references.
    /// Commands that change installed tools (`brew cleanup`, `simctl delete`) and anything
    /// inside an installed app or Homebrew are dropped.
    static func safeCleanup(_ categories: [CleanCategory]) -> [CleanCategory] {
        categories.compactMap { category in
            guard !category.infoOnly, !manualOnlyCategories.contains(category.id) else { return nil }
            var copy = category
            copy.items = category.items.filter { item in
                switch item.action {
                case .remove, .removeContents, .deletePermanently, .adminRemove, .removeLoginItem, .mailTrash:
                    break
                default:
                    return false
                }
                if let path = item.url?.path, PathSafety.isInstalledSoftware(path) { return false }
                return true
            }
            return copy.items.isEmpty ? nil : copy
        }
    }

    /// Only items matching the known-adware database. Heuristic findings (unsigned apps,
    /// odd launch agents) may be legitimate software, so they stay in Malware Removal for review.
    static func safeProtection(_ categories: [CleanCategory]) -> [CleanCategory] {
        categories.compactMap { category in
            var copy = category
            copy.items = category.items.filter(\.knownThreat)
            return copy.items.isEmpty ? nil : copy
        }
    }

    /// Speed recommendations: force quit hung apps, flush DNS, free RAM.
    static func speedRecommendations(progress: ScanProgress) -> [CleanCategory] {
        progress.step(0, of: 2, "Looking for apps that aren't responding…")
        var categories: [CleanCategory] = []
        let hung = ProcessService.hungApps().map { app in
            CleanItem(name: app.name, url: app.bundleURL, size: 0, subtitle: "Not responding",
                      symbol: "exclamationmark.octagon", action: .forceQuit(pid: app.pid))
        }
        if !hung.isEmpty {
            categories.append(CleanCategory(id: "hung", title: "Hung Applications", symbol: "hourglass",
                                            summary: "Apps that stopped responding.", items: hung))
        }
        progress.step(1, of: 2, "Checking memory…")
        let memory = SystemMetrics.memory()
        var tasks: [CleanItem] = [
            CleanItem(name: MaintenanceTask.flushDNS.title, url: nil, size: 0,
                      subtitle: MaintenanceTask.flushDNS.description, symbol: "network", action: .maintenance(.flushDNS)),
        ]
        let freeRatio = Double(memory.free) / Double(max(1, memory.total))
        tasks.insert(CleanItem(name: MaintenanceTask.freeRAM.title, url: nil, size: 0, isSelected: freeRatio < 0.15 || memory.pressureLevel > 1,
                               subtitle: "Free memory: \(memory.free.formattedBytes) · pressure \(memory.pressureText)",
                               symbol: "memorychip", action: .maintenance(.freeRAM)), at: 0)
        categories.append(CleanCategory(id: "tasks", title: "Maintenance Tasks", symbol: "wrench.and.screwdriver",
                                        summary: "Quick tasks that keep your Mac responsive.", items: tasks,
                                        note: "These tasks need your administrator password."))
        progress.setFraction(1)
        return categories
    }
}
