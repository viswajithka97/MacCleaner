import AppKit
import Combine
import Foundation
import IOKit.ps

struct BatteryStatus: Equatable {
    var percent: Int
    var isCharging: Bool
    var cycleCount: Int
    var healthPercent: Int
}

struct NetworkRates: Equatable {
    var up: Double
    var down: Double
}

@MainActor
final class SystemMonitorService: ObservableObject {
    @Published var cpu: Double = 0
    @Published var memoryUsed: UInt64 = 0
    @Published var memoryTotal: UInt64 = 0
    @Published var memoryPressure: String = "Normal"
    @Published var diskFree: Int64 = 0
    @Published var diskTotal: Int64 = 0
    @Published var battery = BatteryStatus(percent: 0, isCharging: false, cycleCount: 0, healthPercent: 100)
    @Published var network = NetworkRates(up: 0, down: 0)
    @Published var topMemory: [ProcessInfoRow] = []

    private var timer: Timer?
    private var lastCPU: (ticks: Double, idle: Double)?
    private var lastNet: (up: UInt64, down: UInt64, date: Date)?

    func start() {
        NotificationManager.shared.requestAuthorization()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func tick() {
        cpu = readCPU()
        readMemory()
        readDisk()
        battery = readBattery()
        network = readNetwork()
        topMemory = Array(OptimizationService.heavyConsumers().prefix(5))
        notifyIfNeeded()
    }

    func freeRAM() {
        Task {
            _ = try? await AdminPrivileges.shared.run(
                command: "/usr/sbin/purge",
                explanation: "Freeing RAM with `purge` needs an administrator password because it reclaims cached pages for the whole system."
            )
        }
    }

    private func readCPU() -> Double {
        guard let result = try? ProcessRunner.run("/usr/sbin/iostat", arguments: ["-c", "1"]) else { return 0 }
        // last line typically:  disk numbers then cpu us sy id
        let parts = result.stdout.split(whereSeparator: { $0.isWhitespace }).compactMap { Double($0) }
        if parts.count >= 3 {
            let idle = parts.last ?? 100
            return max(0, min(100, 100 - idle))
        }
        return 0
    }

    private func readMemory() {
        let pageSize = UInt64(NSPageSize())
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let used = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
            memoryUsed = used
        }
        memoryTotal = ProcessInfo.processInfo.physicalMemory
        if let pressure = try? ProcessRunner.run("/usr/bin/memory_pressure", arguments: []) {
            let text = pressure.stdout.lowercased()
            if text.contains("warn") { memoryPressure = "Warn" }
            else if text.contains("critical") { memoryPressure = "Critical" }
            else { memoryPressure = "Normal" }
        }
    }

    private func readDisk() {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            diskFree = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            diskTotal = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
        }
    }

    private func readBattery() -> BatteryStatus {
        var status = BatteryStatus(percent: 0, isCharging: false, cycleCount: 0, healthPercent: 100)
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return status }
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                status.percent = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
                status.isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            }
        }
        // Cycle count / health from ioreg
        if let result = try? ProcessRunner.run("/usr/sbin/ioreg", arguments: ["-r", "-c", "AppleSmartBattery"]) {
            if let cycles = matchInt(result.stdout, key: "\"CycleCount\" = ") {
                status.cycleCount = cycles
            }
            if let max = matchInt(result.stdout, key: "\"MaxCapacity\" = "),
               let design = matchInt(result.stdout, key: "\"DesignCapacity\" = "), design > 0 {
                status.healthPercent = Int((Double(max) / Double(design)) * 100)
            }
            if let max = matchInt(result.stdout, key: "\"AppleRawMaxCapacity\" = "),
               let design = matchInt(result.stdout, key: "\"DesignCapacity\" = "), design > 0 {
                status.healthPercent = Int((Double(max) / Double(design)) * 100)
            }
        }
        return status
    }

    private func matchInt(_ text: String, key: String) -> Int? {
        guard let range = text.range(of: key) else { return nil }
        let rest = text[range.upperBound...]
        let number = rest.prefix { $0.isNumber || $0 == "-" }
        return Int(number)
    }

    private func readNetwork() -> NetworkRates {
        guard let result = try? ProcessRunner.run("/usr/sbin/netstat", arguments: ["-ibI", "en0"]) else { return network }
        // header then a line with ibytes obytes toward the end
        let lines = result.stdout.components(separatedBy: "\n")
        guard lines.count > 1 else { return network }
        let parts = lines[1].split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count >= 10, let down = UInt64(parts[6]), let up = UInt64(parts[9]) else { return network }
        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.date)
            if dt > 0 {
                let rates = NetworkRates(up: Double(up &- last.up) / dt, down: Double(down &- last.down) / dt)
                lastNet = (up, down, now)
                return rates
            }
        }
        lastNet = (up, down, now)
        return network
    }

    private func notifyIfNeeded() {
        let settings = SettingsStore.shared.settings
        if settings.notifyLowDisk && diskFree > 0 && diskFree < settings.lowDiskBytes {
            NotificationManager.shared.post(id: "low-disk", title: "Low disk space", body: "Only \(ByteFormatting.string(diskFree)) free on the startup disk.")
        }
        if settings.notifyMemoryPressure && memoryPressure != "Normal" {
            NotificationManager.shared.post(id: "mem-pressure", title: "Memory pressure", body: "Memory pressure is \(memoryPressure).")
        }
        if settings.notifyLargeTrash {
            let trash = FileScanSupport.home().appendingPathComponent(".Trash")
            let size = FileSizing.allocatedSize(at: trash)
            if size > settings.trashNotifyBytes {
                NotificationManager.shared.post(id: "large-trash", title: "Trash is getting large", body: "Trash currently holds \(ByteFormatting.string(size)).")
            }
        }
        NotificationManager.shared.scheduleWeeklySmartCareIfNeeded(settings: settings)
    }
}
