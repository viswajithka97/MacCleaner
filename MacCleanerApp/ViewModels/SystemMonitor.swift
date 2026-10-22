import AppKit
import Combine

/// Live system stats for the menu bar monitor. Refreshes every 2 seconds and
/// checks the notification thresholds once a minute.
@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    struct TopApp: Identifiable {
        var id: Int32 { pid }
        var pid: Int32
        var name: String
        var memory: Int64
        var icon: NSImage?
    }

    @Published var cpuUser: Double = 0
    @Published var cpuSystem: Double = 0
    @Published var memory = SystemMetrics.memory()
    @Published var disk = SystemMetrics.disk()
    @Published var battery: SystemMetrics.Battery? = SystemMetrics.battery()
    @Published var downloadSpeed: Double = 0     // bytes per second
    @Published var uploadSpeed: Double = 0
    @Published var topApps: [TopApp] = []
    @Published var freeingRAM = false
    @Published var lastRAMResult: String?

    var cpuTotal: Double { cpuUser + cpuSystem }

    private var timer: Timer?
    private var lastTicks = SystemMetrics.cpuTicks()
    private var lastNet = SystemMetrics.networkBytes()
    private var lastNetDate = Date()
    private var tickCount = 0
    private var sampling = false

    private init() {}

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Takes a new sample. The slow parts run in the background.
    func refresh() {
        guard !sampling else { return }
        sampling = true
        let previousTicks = lastTicks
        let previousNet = lastNet
        let previousDate = lastNetDate
        tickCount += 1
        let checkAlerts = tickCount % 30 == 1          // every ~60 s
        Task.detached(priority: .utility) {
            let ticks = SystemMetrics.cpuTicks()
            let memory = SystemMetrics.memory()
            let disk = SystemMetrics.disk()
            let battery = SystemMetrics.battery()
            let net = SystemMetrics.networkBytes()
            let now = Date()
            let processes = ProcessService.sample()
            let trashSize: Int64? = checkAlerts ? TrashService.userTrashSize() : nil
            await MainActor.run {
                self.apply(ticks: ticks, previousTicks: previousTicks, memory: memory, disk: disk, battery: battery,
                           net: net, previousNet: previousNet, now: now, previousDate: previousDate,
                           processes: processes, trashSize: trashSize, checkAlerts: checkAlerts)
            }
        }
    }

    private func apply(ticks: SystemMetrics.CPUTicks?, previousTicks: SystemMetrics.CPUTicks?,
                       memory: SystemMetrics.Memory, disk: SystemMetrics.Disk, battery: SystemMetrics.Battery?,
                       net: (received: UInt64, sent: UInt64), previousNet: (received: UInt64, sent: UInt64),
                       now: Date, previousDate: Date, processes: [ProcessSample], trashSize: Int64?, checkAlerts: Bool) {
        if let ticks, let previousTicks {
            let load = SystemMetrics.cpuLoad(from: previousTicks, to: ticks)
            cpuUser = load.user
            cpuSystem = load.system
        }
        lastTicks = ticks
        self.memory = memory
        self.disk = disk
        self.battery = battery
        let seconds = max(0.5, now.timeIntervalSince(previousDate))
        // Interface counters are 32-bit and wrap around; ignore negative jumps.
        downloadSpeed = net.received >= previousNet.received ? Double(net.received - previousNet.received) / seconds : 0
        uploadSpeed = net.sent >= previousNet.sent ? Double(net.sent - previousNet.sent) / seconds : 0
        lastNet = net
        lastNetDate = now

        // Top memory consumers among apps (group helpers under their app where possible).
        let names = ProcessService.displayNames()
        topApps = processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5).map { sample in
            let app = NSRunningApplication(processIdentifier: sample.pid)
            return TopApp(pid: sample.pid, name: names[sample.pid] ?? sample.name, memory: sample.memoryBytes, icon: app?.icon)
        }
        sampling = false
        if checkAlerts { checkThresholds(trashSize: trashSize) }
    }

    /// Posts notifications when thresholds from Settings are crossed.
    private func checkThresholds(trashSize: Int64?) {
        let settings = SettingsStore.shared
        let gb: Int64 = 1024 * 1024 * 1024
        if settings.notifyLowDisk && disk.availableForImportantUsage < Int64(settings.lowDiskGB) * gb {
            NotificationService.shared.post(id: "low-disk", title: "Your startup disk is almost full",
                                            body: "Only \(disk.availableForImportantUsage.formattedBytes) free. Open MacCleaner to free up space.")
        }
        if settings.notifyMemoryPressure && memory.pressureLevel >= 4 {
            NotificationService.shared.post(id: "memory", title: "High memory pressure",
                                            body: "Your Mac is running low on memory. Quit unused apps or use Free up RAM.",
                                            minimumInterval: 3600)
        }
        if settings.notifyTrashSize, let trashSize, trashSize > Int64(settings.trashSizeGB) * gb {
            NotificationService.shared.post(id: "trash", title: "Your Trash is getting big",
                                            body: "The Trash holds \(trashSize.formattedBytes). Empty it to get that space back.",
                                            minimumInterval: 24 * 3600)
        }
    }

    /// "Free up RAM" button in the menu bar.
    func freeRAM() {
        guard !freeingRAM else { return }
        freeingRAM = true
        lastRAMResult = nil
        Task {
            let output = await MaintenanceService.run(.freeRAM)
            freeingRAM = false
            lastRAMResult = output.log
            refresh()
        }
    }
}
