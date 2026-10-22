import AppKit

/// Optimization: login items, launch agents, hung apps, heavy consumers.
@MainActor
final class OptimizationViewModel: TaskViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case loginItems = "Login Items", launchAgents = "Launch Agents", hungApps = "Hung Applications", heavy = "Heavy Consumers"
        var id: String { rawValue }
    }

    @Published var tab: Tab = .loginItems
    @Published var loginItems: [LoginItem] = []
    @Published var loginError: String?
    @Published var launchItems: [LaunchItem] = []
    @Published var hungApps: [ProcessService.HungApp] = []
    @Published var processes: [ProcessSample] = []
    @Published var sortByMemory = false
    @Published var message: String?
    @Published var loaded = false

    private var processTimer: Timer?
    private var names: [Int32: String] = [:]

    func loadAll() {
        loaded = true
        run({ progress -> ([LoginItem], String?, [LaunchItem], [ProcessService.HungApp]) in
            progress.setMessage("Reading login items…")
            let login = LoginItemsService.list()
            progress.setMessage("Reading launch agents…")
            let launch = LaunchItemsService.list(progress: progress)
            let hung = ProcessService.hungApps()
            return (login.items, login.error, launch, hung)
        }) { [weak self] value, _ in
            guard let self else { return }
            self.loginItems = value.0
            self.loginError = value.1
            self.launchItems = value.2.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            self.hungApps = value.3
        }
    }

    // MARK: Login items

    func setLoginItem(_ item: LoginItem, enabled: Bool) {
        Task.detached {
            let outcome = enabled ? LoginItemsService.enable(item) : LoginItemsService.disable(item)
            let list = LoginItemsService.list()
            await MainActor.run {
                self.message = outcome.ok ? nil : outcome.message
                self.loginItems = list.items
            }
        }
    }

    func removeLoginItem(_ item: LoginItem) {
        Task.detached {
            let outcome = LoginItemsService.remove(name: item.name)
            let list = LoginItemsService.list()
            await MainActor.run {
                self.message = outcome.ok ? "Removed \(item.name)." : outcome.message
                self.loginItems = list.items
                if outcome.ok { HistoryStore.shared.record(module: "Optimization", result: CleanupResult(removedCount: 1, removedNames: ["Login item \(item.name)"])) }
            }
        }
    }

    // MARK: Launch agents

    func setLaunchItem(_ item: LaunchItem, enabled: Bool) {
        Task {
            let outcome = await LaunchItemsService.setEnabled(item, enabled: enabled)
            message = outcome.ok ? "\(item.label) \(enabled ? "enabled" : "disabled")." : outcome.message
            let list = await Task.detached { LaunchItemsService.list() }.value
            launchItems = list.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        }
    }

    // MARK: Hung apps

    func refreshHung() {
        Task.detached {
            let hung = ProcessService.hungApps()
            await MainActor.run { self.hungApps = hung }
        }
    }

    func forceQuit(_ app: ProcessService.HungApp) {
        let outcome = ProcessService.quit(pid: app.pid, force: true)
        message = outcome.ok ? "Force quit \(app.name)." : outcome.message
        refreshHung()
    }

    // MARK: Heavy consumers (refreshes every 2 seconds while visible)

    func startProcessUpdates() {
        guard processTimer == nil else { return }
        refreshProcesses()
        processTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshProcesses() }
        }
    }

    func stopProcessUpdates() {
        processTimer?.invalidate()
        processTimer = nil
    }

    private func refreshProcesses() {
        names = ProcessService.displayNames()
        let names = self.names
        Task.detached {
            let samples = ProcessService.sample().map { sample -> ProcessSample in
                var copy = sample
                if let name = names[sample.pid] { copy.name = name }
                return copy
            }
            await MainActor.run { self.processes = samples }
        }
    }

    var sortedProcesses: [ProcessSample] {
        let sorted = sortByMemory ? processes.sorted { $0.memoryBytes > $1.memoryBytes } : processes.sorted { $0.cpu > $1.cpu }
        return Array(sorted.prefix(40))
    }

    func quit(_ process: ProcessSample, force: Bool) {
        let outcome = ProcessService.quit(pid: process.pid, force: force)
        message = outcome.ok ? "\(force ? "Force quit" : "Asked to quit") \(process.name)." : outcome.message
        refreshProcesses()
    }
}

/// Maintenance tasks with per-task status and output.
@MainActor
final class MaintenanceViewModel: ObservableObject {
    enum Status: Equatable { case idle, running, succeeded, failed }

    @Published var selected: Set<MaintenanceTask> = [.flushDNS, .freePurgeable]
    @Published var status: [MaintenanceTask: Status] = [:]
    @Published var output: [MaintenanceTask: String] = [:]
    @Published var runningAll = false
    @Published var progressMessage: [MaintenanceTask: String] = [:]

    var mailRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty }

    func quitMail() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").forEach { $0.terminate() }
        objectWillChange.send()
    }

    func run(_ task: MaintenanceTask, approved: Bool = false) async {
        status[task] = .running
        output[task] = nil
        let progress = ScanProgress()
        let poller = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.progressMessage[task] = progress.snapshot.message }
        }
        let result = await MaintenanceService.run(task, alreadyApproved: approved, progress: progress)
        poller.invalidate()
        progressMessage[task] = nil
        status[task] = result.success ? .succeeded : .failed
        output[task] = result.log
        if result.success {
            HistoryStore.shared.record(module: "Maintenance", result: CleanupResult(removedCount: 1, freedBytes: result.freedBytes,
                                                                                     removedNames: [task.title]))
        }
    }

    /// Runs every checked task in order; admin tasks are explained together, once.
    func runSelected() {
        let tasks = MaintenanceTask.allCases.filter { selected.contains($0) }
        guard !tasks.isEmpty else { return }
        runningAll = true
        Task {
            let adminTasks = tasks.filter(\.requiresAdmin)
            var approved = false
            if !adminTasks.isEmpty {
                approved = await AdminService.shared.requestApproval(
                    title: "Maintenance needs administrator access",
                    explanation: adminTasks.map { "• \($0.title): \($0.adminExplanation)" }.joined(separator: "\n\n"),
                    commands: adminTasks.map { MaintenanceService.adminCommand(for: $0) })
            }
            for task in tasks {
                if task.requiresAdmin && !approved {
                    status[task] = .failed
                    output[task] = "Skipped: administrator access was not approved."
                    continue
                }
                await run(task, approved: approved)
            }
            runningAll = false
        }
    }
}
