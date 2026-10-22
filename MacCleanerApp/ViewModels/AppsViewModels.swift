import AppKit

/// Uninstaller: app list, leftover finder, removal and reset.
@MainActor
final class UninstallerViewModel: TaskViewModel {
    enum Tab: String, CaseIterable, Identifiable { case apps = "Applications", leftovers = "Leftovers"; var id: String { rawValue } }

    @Published var tab: Tab = .apps
    @Published var apps: [InstalledApp] = []
    @Published var search = ""
    @Published var selectedApp: InstalledApp?
    @Published var mode: UninstallerService.Mode = .completeRemoval
    @Published var files: [CleanItem] = []
    @Published var loadingFiles = false
    @Published var showConfirmation = false
    @Published var result: CleanupResult?
    @Published var loaded = false
    @Published var refusal: String?

    /// Leftovers of already-deleted apps reuse the generic cleanup flow.
    lazy var leftovers = CleanupFlowViewModel(module: .uninstaller, actionTitle: "Remove") { progress in
        let apps = AppCatalog.installedApps()
        return UninstallerService.orphanedLeftovers(installed: apps, progress: progress)
    }

    private var filesTask: Task<Void, Never>?

    var filteredApps: [InstalledApp] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
    }

    func load() {
        loaded = true
        run({ AppCatalog.installedApps(progress: $0) }) { [weak self] apps, _ in
            guard let self else { return }
            self.apps = apps
            self.computeSizes()
        }
    }

    /// App sizes take a while, so they're filled in one by one afterwards.
    private func computeSizes() {
        let urls = apps.map(\.url)
        Task.detached(priority: .utility) {
            for url in urls {
                let size = FileSize.of(url)
                await MainActor.run {
                    if let index = self.apps.firstIndex(where: { $0.url == url }) { self.apps[index].size = size }
                }
            }
        }
    }

    func select(_ app: InstalledApp?) {
        selectedApp = app
        result = nil
        refusal = nil
        files = []
        guard let app else { return }
        if app.isProtected {
            refusal = app.bundleID == Bundle.main.bundleIdentifier
                ? "MacCleaner can't uninstall itself. Drag it to the Trash from Finder."
                : "\(app.name) is part of macOS and can't be removed."
            return
        }
        findFiles()
    }

    func findFiles() {
        guard let app = selectedApp, !app.isProtected else { return }
        filesTask?.cancel()
        loadingFiles = true
        let mode = self.mode
        filesTask = Task {
            let found = await Task.detached { UninstallerService.files(for: app, mode: mode, progress: ScanProgress()) }.value
            guard !Task.isCancelled, self.selectedApp == app else { return }
            self.files = found
            self.loadingFiles = false
        }
    }

    func toggle(_ id: UUID) {
        if let index = files.firstIndex(where: { $0.id == id }) { files[index].isSelected.toggle() }
    }

    var selectedFiles: [CleanItem] { files.filter(\.isSelected) }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func confirmRemoval() {
        showConfirmation = false
        guard let app = selectedApp, !app.isProtected else { return }
        let items = selectedFiles
        // Quit the app first so its files aren't in use.
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) { running.terminate() }
        run({ progress in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return await CleanupExecutor.perform(items, progress: progress, title: "Uninstaller")
        }) { [weak self] result, _ in
            guard let self else { return }
            self.result = result
            HistoryStore.shared.record(module: self.mode == .reset ? "Uninstaller (reset \(app.name))" : "Uninstaller (\(app.name))",
                                       result: result)
            if self.mode == .completeRemoval && !FileManager.default.fileExists(atPath: app.url.path) {
                self.apps.removeAll { $0.url == app.url }
            }
            self.files = []
        }
    }
}

/// Updater: list available updates and install them.
@MainActor
final class UpdaterViewModel: TaskViewModel {
    @Published var updates: [AppUpdate] = []
    @Published var checked = false
    @Published var installing: Set<String> = []
    @Published var messages: [String: String] = [:]
    @Published var expanded: Set<String> = []

    func check() {
        run({ await UpdaterService.checkAll(progress: $0) }) { [weak self] updates, _ in
            self?.updates = updates
            self?.checked = true
        }
    }

    func install(_ update: AppUpdate) {
        installing.insert(update.id)
        Task {
            let outcome = await UpdaterService.install(update)
            installing.remove(update.id)
            messages[update.id] = outcome.message
            if outcome.ok {
                HistoryStore.shared.record(module: "Updater", result: CleanupResult(removedCount: 1, removedNames: ["Updated \(update.appName) to \(update.newVersion)"]))
                if case .homebrew = update.source { updates.removeAll { $0.id == update.id } }
            }
        }
    }

    func installAll() {
        for update in updates where !installing.contains(update.id) { install(update) }
    }
}
