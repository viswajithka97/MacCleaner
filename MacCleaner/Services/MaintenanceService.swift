import AppKit
import Foundation

struct MaintenanceTask: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var command: String
    var requiresAdmin: Bool
    var explanation: String
    var requiresMailQuit: Bool = false
}

enum MaintenanceService {
    static let tasks: [MaintenanceTask] = [
        MaintenanceTask(
            id: "purge-ram",
            title: "Free up RAM",
            detail: "Asks macOS to purge inactive memory with the `purge` tool.",
            command: "/usr/sbin/purge",
            requiresAdmin: true,
            explanation: "The purge command needs administrator rights because it forces the system to reclaim cached memory for every user."
        ),
        MaintenanceTask(
            id: "purgeable",
            title: "Free up purgeable space",
            detail: "Creates and deletes a large temporary file so macOS releases purgeable storage.",
            command: "PURGEABLE_FILE",
            requiresAdmin: false,
            explanation: "This writes a temporary file in /private/var/tmp then deletes it. No admin password is required."
        ),
        MaintenanceTask(
            id: "dns",
            title: "Flush DNS cache",
            detail: "dscacheutil -flushcache and a HUP to mDNSResponder.",
            command: "dscacheutil -flushcache; killall -HUP mDNSResponder",
            requiresAdmin: true,
            explanation: "Flushing the system DNS cache restarts mDNSResponder, which only an administrator can signal."
        ),
        MaintenanceTask(
            id: "periodic",
            title: "Run maintenance scripts",
            detail: "periodic daily weekly monthly — Apple’s built-in cleanup scripts.",
            command: "periodic daily weekly monthly",
            requiresAdmin: true,
            explanation: "Apple’s periodic scripts live in /etc and must run as root."
        ),
        MaintenanceTask(
            id: "spotlight",
            title: "Reindex Spotlight",
            detail: "mdutil -E / erases and rebuilds the Spotlight index on the startup disk.",
            command: "mdutil -E /",
            requiresAdmin: true,
            explanation: "Rebuilding Spotlight touches system metadata stores and needs administrator rights."
        ),
        MaintenanceTask(
            id: "launchservices",
            title: "Rebuild Launch Services database",
            detail: "Fixes duplicate “Open With” entries.",
            command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user",
            requiresAdmin: false,
            explanation: "This rewrites your user’s Launch Services database so duplicate apps disappear from Open With."
        ),
        MaintenanceTask(
            id: "permissions",
            title: "Repair home folder permissions",
            detail: "diskutil resetUserPermissions / $(id -u)",
            command: "diskutil resetUserPermissions / $(id -u)",
            requiresAdmin: true,
            explanation: "Resetting POSIX/ACL permissions on your home folder is a privileged diskutil operation."
        ),
        MaintenanceTask(
            id: "snapshots",
            title: "Thin Time Machine local snapshots",
            detail: "Lists local snapshots and deletes them one by one.",
            command: "SNAPSHOTS",
            requiresAdmin: false,
            explanation: "Local snapshots are managed by tmutil for the current user."
        ),
        MaintenanceTask(
            id: "mail-vacuum",
            title: "Speed up Mail",
            detail: "Vacuums the Mail envelope index SQLite database. Mail must be quit first.",
            command: "MAIL_VACUUM",
            requiresAdmin: false,
            explanation: "The envelope index is a SQLite file. Mail must be closed so the database is not in use.",
            requiresMailQuit: true
        ),
        MaintenanceTask(
            id: "verify-disk",
            title: "Verify the startup disk",
            detail: "diskutil verifyVolume / — read-only check.",
            command: "diskutil verifyVolume /",
            requiresAdmin: false,
            explanation: "This is a read-only verification of the startup volume."
        )
    ]

    @MainActor
    static func run(_ task: MaintenanceTask) async -> String {
        do {
            if task.requiresMailQuit {
                let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
                if running {
                    return "Mail is still running. Quit Mail, then run this task again."
                }
            }
            switch task.id {
            case "purgeable":
                return try await freePurgeableSpace()
            case "snapshots":
                return try thinSnapshots()
            case "mail-vacuum":
                return try vacuumMail()
            default:
                if task.requiresAdmin {
                    return try await AdminPrivileges.shared.run(command: task.command, explanation: task.explanation)
                }
                let result = try ProcessRunner.runShell(task.command)
                return result.stdout + result.stderr
            }
        } catch {
            return error.localizedDescription
        }
    }

    private static func freePurgeableSpace() async throws -> String {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: "/private/var/tmp/maccleaner-purgeable-\(UUID().uuidString)")
        // Try to fill a few gigabytes; stop early if the disk cannot take it.
        let chunk = Data(repeating: 0, count: 8 * 1024 * 1024)
        fm.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
            try? fm.removeItem(at: url)
        }
        var written = 0
        let target = 4 * 1024 * 1024 * 1024
        while written < target {
            do {
                try handle.write(contentsOf: chunk)
                written += chunk.count
            } catch {
                break
            }
        }
        try handle.close()
        try fm.removeItem(at: url)
        return "Wrote and removed \(ByteFormatting.string(Int64(written))) of temporary data to nudge macOS to reclaim purgeable space."
    }

    private static func thinSnapshots() throws -> String {
        let list = try ProcessRunner.run("/usr/bin/tmutil", arguments: ["listlocalsnapshots", "/"])
        let dates = list.stdout.components(separatedBy: "\n").compactMap { line -> String? in
            // com.apple.TimeMachine.2024-01-01-123456.local
            guard let range = line.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) else { return nil }
            return String(line[range])
        }
        var log = list.stdout + "\n"
        for date in dates {
            let result = try ProcessRunner.run("/usr/bin/tmutil", arguments: ["deletelocalsnapshots", date])
            log += result.stdout + result.stderr + "\n"
        }
        if dates.isEmpty { log += "No local snapshots found.\n" }
        return log
    }

    private static func vacuumMail() throws -> String {
        let mailData = FileScanSupport.library().appendingPathComponent("Mail")
        var logs: [String] = []
        FileScanSupport.collect(at: mailData, skipPackages: true, callbacks: ScanCallbacks(progress: { _, _ in }, isCancelled: { false })) { url, _ in
            if url.lastPathComponent.lowercased() == "envelope index" || url.lastPathComponent.lowercased().hasPrefix("envelope index") {
                if PathSafety.isForbidden(url.path) {
                    // Envelope index is forbidden for deletion, but vacuum is an in-place SQLite command.
                }
                if let sqlite = ProcessRunner.which("sqlite3") ?? Optional("/usr/bin/sqlite3") {
                    if let result = try? ProcessRunner.run(sqlite, arguments: [url.path, "VACUUM;"]) {
                        logs.append("\(url.path): \(result.exitCode == 0 ? "vacuumed" : result.stderr)")
                    }
                }
            }
        }
        if logs.isEmpty { return "No Mail envelope index found. Grant Full Disk Access and try again." }
        return logs.joined(separator: "\n")
    }
}
