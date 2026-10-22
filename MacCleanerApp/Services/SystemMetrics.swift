import Foundation
import IOKit
import IOKit.ps

/// Low-level readings of CPU, memory, disk, battery and network.
/// All functions are safe to call from any thread.
enum SystemMetrics {

    // MARK: - Memory

    struct Memory {
        var total: Int64
        var used: Int64          // app memory + wired + compressed (like Activity Monitor)
        var free: Int64
        var compressed: Int64
        var cached: Int64        // file cache that macOS can drop
        /// 1 = normal, 2 = warning, 4 = critical (kern.memorystatus_vm_pressure_level)
        var pressureLevel: Int

        var pressureText: String {
            switch pressureLevel {
            case 4: return "Critical"
            case 2: return "Warning"
            default: return "Normal"
            }
        }
    }

    static func memory() -> Memory {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = Int64(pageSize)
        guard result == KERN_SUCCESS else {
            return Memory(total: total, used: 0, free: 0, compressed: 0, cached: 0, pressureLevel: 1)
        }
        let appMemory = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        let wired = Int64(stats.wire_count)
        let compressed = Int64(stats.compressor_page_count)
        let cached = Int64(stats.external_page_count) + Int64(stats.purgeable_count)
        let free = Int64(stats.free_count) - Int64(stats.speculative_count)
        return Memory(total: total,
                      used: (appMemory + wired + compressed) * page,
                      free: max(0, free) * page,
                      compressed: compressed * page,
                      cached: cached * page,
                      pressureLevel: sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    // MARK: - CPU

    /// Raw CPU tick counters; compare two samples to get the load.
    struct CPUTicks {
        var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64
    }

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    /// CPU usage between two samples: (user %, system %).
    static func cpuLoad(from a: CPUTicks, to b: CPUTicks) -> (user: Double, system: Double) {
        let user = Double(b.user &- a.user) + Double(b.nice &- a.nice)
        let system = Double(b.system &- a.system)
        let idle = Double(b.idle &- a.idle)
        let total = user + system + idle
        guard total > 0 else { return (0, 0) }
        return (user / total, system / total)
    }

    // MARK: - Disk

    struct Disk {
        var total: Int64
        var available: Int64
        var availableForImportantUsage: Int64   // includes purgeable space
    }

    static func disk(_ path: String = "/") -> Disk {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                                       .volumeAvailableCapacityForImportantUsageKey])
        let available = Int64(values?.volumeAvailableCapacity ?? 0)
        return Disk(total: Int64(values?.volumeTotalCapacity ?? 0),
                    available: available,
                    availableForImportantUsage: values?.volumeAvailableCapacityForImportantUsage ?? available)
    }

    // MARK: - Battery (IOKit)

    struct Battery {
        var chargePercent: Int
        var healthPercent: Int?
        var cycleCount: Int?
        var isCharging: Bool
        var onAC: Bool
        var condition: String
    }

    static func battery() -> Battery? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        // Newer macOS versions keep the mAh figures inside a nested "BatteryData" dictionary.
        let data = dict["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? { dict[key] as? Int ?? data[key] as? Int }
        let current = int("CurrentCapacity") ?? 0
        let max = int("MaxCapacity") ?? 100
        let design = int("DesignCapacity")
        let rawMax = int("AppleRawMaxCapacity") ?? int("NominalChargeCapacity") ?? int("FullChargeCapacity")
        // On Apple silicon Current/MaxCapacity are percentages; on Intel they are mAh.
        let charge = max > 100 ? Int(Double(current) / Double(max) * 100) : current
        var health: Int?
        if let design, design > 0 {
            if let rawMax { health = Int(Double(rawMax) / Double(design) * 100) }
            else if max > 100 { health = Int(Double(max) / Double(design) * 100) }
        }
        let condition = (dict["PermanentFailureStatus"] as? Int ?? 0) != 0 ? "Service recommended"
            : ((health ?? 100) < 80 ? "Service recommended" : "Normal")
        return Battery(chargePercent: charge, healthPercent: health.map { Swift.min($0, 100) },
                       cycleCount: dict["CycleCount"] as? Int,
                       isCharging: dict["IsCharging"] as? Bool ?? false,
                       onAC: dict["ExternalConnected"] as? Bool ?? false,
                       condition: condition)
    }

    // MARK: - Network

    /// Total bytes received/sent on all interfaces except loopback.
    static func networkBytes() -> (received: UInt64, sent: UInt64) {
        var received: UInt64 = 0, sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let ifa = current.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let data = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                if !name.hasPrefix("lo") {
                    let stats = data.assumingMemoryBound(to: if_data.self).pointee
                    received += UInt64(stats.ifi_ibytes)
                    sent += UInt64(stats.ifi_obytes)
                }
            }
            cursor = ifa.ifa_next
        }
        return (received, sent)
    }
}
