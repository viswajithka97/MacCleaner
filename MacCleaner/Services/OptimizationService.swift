import AppKit
import Foundation

struct LaunchAgentInfo: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var signer: String
    var enabled: Bool
    var domain: String
}

struct ProcessInfoRow: Identifiable, Hashable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var cpu: Double
    var memoryBytes: UInt64
    var hung: Bool
}

enum OptimizationService {
    static func loginItems() -> [CleanableItem] {
        var items: [CleanableItem] = []
        if let result = try? ProcessRunner.run("/usr/bin/osascript", arguments: [
            "-e", "tell application \"System Events\" to get {name, path, POSIX path of (path of every login item)} of every login item"
        ]) {
            // Fallback simpler listing
            _ = result
        }
        if let names = try? ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to get the name of every login item"]),
           let paths = try? ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to get POSIX path of (path of every login item)"]) {
            let nameList = names.stdout.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let pathList = paths.stdout.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            for (i, name) in nameList.enumerated() {
                let path = i < pathList.count ? pathList[i] : ""
                items.append(CleanableItem(name: name, path: path, size: 0, extra: ["loginItem": name]))
            }
        }
        return items
    }

    static func setLoginItem(_ name: String, enabled: Bool) {
        if enabled {
            _ = try? ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to make login item at end with properties {name:\"\(name)\", hidden:false}"])
        } else {
            _ = try? ProcessRunner.run("/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to delete login item \"\(name)\""])
        }
    }

    static func removeLoginItem(_ name: String) {
        setLoginItem(name, enabled: false)
    }

    static func launchAgents() -> [LaunchAgentInfo] {
        var rows: [LaunchAgentInfo] = []
        let dirs = [
            (FileScanSupport.library().appendingPathComponent("LaunchAgents"), "user"),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), "system")
        ]
        for (dir, domain) in dirs {
            for plist in FileScanSupport.listChildren(of: dir) where plist.pathExtension == "plist" {
                let dict = NSDictionary(contentsOf: plist) as? [String: Any]
                let label = dict?["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
                let program = (dict?["Program"] as? String) ?? (dict?["ProgramArguments"] as? [String])?.first ?? plist.path
                let sign = CodeSigning.inspect(path: FileScanSupport.exists(program) ? program : plist.path)
                let disabled = (dict?["Disabled"] as? Bool) ?? false
                rows.append(LaunchAgentInfo(
                    name: label,
                    path: plist.path,
                    signer: sign.signingAuthority ?? (sign.signed ? "Signed" : "Unsigned"),
                    enabled: !disabled,
                    domain: domain
                ))
            }
        }
        return rows
    }

    static func setLaunchAgent(path: String, label: String, enabled: Bool) {
        if enabled {
            _ = try? ProcessRunner.run("/bin/launchctl", arguments: ["load", "-w", path])
            _ = try? ProcessRunner.run("/bin/launchctl", arguments: ["enable", "gui/\(getuid())/\(label)"])
        } else {
            _ = try? ProcessRunner.run("/bin/launchctl", arguments: ["unload", "-w", path])
            _ = try? ProcessRunner.run("/bin/launchctl", arguments: ["disable", "gui/\(getuid())/\(label)"])
        }
    }

    static func hungApplications() -> [ProcessInfoRow] {
        guard let result = try? ProcessRunner.run("/usr/bin/lsappinfo", arguments: ["list"]) else { return [] }
        var hung: [ProcessInfoRow] = []
        // lsappinfo prints ASN blocks; "not responding" appears next to the app name.
        let blocks = result.stdout.components(separatedBy: "\n ")
        for block in blocks where block.lowercased().contains("not responding") {
            let name = block.split(separator: "\"").dropFirst().first.map(String.init) ?? "Unknown"
            let pid = extractPid(from: block)
            hung.append(ProcessInfoRow(pid: pid, name: name, cpu: 0, memoryBytes: 0, hung: true))
        }
        return hung
    }

    static func heavyConsumers() -> [ProcessInfoRow] {
        guard let result = try? ProcessRunner.run("/bin/ps", arguments: ["-axo", "pid,%cpu,rss,comm"]) else { return [] }
        var rows: [ProcessInfoRow] = []
        let hungPids = Set(hungApplications().map(\.pid))
        for line in result.stdout.components(separatedBy: "\n").dropFirst() {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]), let rss = UInt64(parts[2]) else { continue }
            let name = parts.dropFirst(3).joined(separator: " ")
            rows.append(ProcessInfoRow(pid: pid, name: (name as NSString).lastPathComponent, cpu: cpu, memoryBytes: rss * 1024, hung: hungPids.contains(pid)))
        }
        return rows.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    static func quit(pid: Int32, force: Bool) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            if force { app.forceTerminate() } else { app.terminate() }
        } else {
            kill(pid, force ? SIGKILL : SIGTERM)
        }
    }

    private static func extractPid(from block: String) -> Int32 {
        if let range = block.range(of: "pid = ") {
            let rest = block[range.upperBound...]
            let number = rest.prefix { $0.isNumber }
            return Int32(number) ?? 0
        }
        return 0
    }
}
