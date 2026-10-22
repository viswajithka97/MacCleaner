import AppKit

/// Runs the Maintenance tasks.
enum MaintenanceService {

    struct Output {
        var success: Bool
        var log: String
        var freedBytes: Int64 = 0
    }

    /// Runs one task. Admin tasks show the explanation sheet first unless
    /// `alreadyApproved` (Smart Care asks once for everything).
    static func run(_ task: MaintenanceTask, alreadyApproved: Bool = false,
                    progress: ScanProgress? = nil) async -> Output {
        if task.requiresAdmin && !alreadyApproved {
            let approved = await AdminService.shared.requestApproval(
                title: task.title, explanation: task.adminExplanation, commands: [adminCommand(for: task)])
            guard approved else { return Output(success: false, log: "Cancelled: administrator access was not approved.") }
        }

        switch task {
        case .freeRAM:
            let before = SystemMetrics.memory().free
            let result = await AdminService.run(adminCommand(for: task))
            let after = SystemMetrics.memory().free
            let gained = max(0, after - before)
            return Output(success: result.succeeded,
                          log: result.succeeded ? "Free memory went from \(before.formattedBytes) to \(after.formattedBytes) (+\(gained.formattedBytes))." : result.combinedOutput)

        case .freePurgeable:
            return await freePurgeableSpace(progress: progress)

        case .flushDNS, .periodicScripts, .reindexSpotlight, .repairPermissions:
            let result = await AdminService.run(adminCommand(for: task))
            var log = result.combinedOutput
            if log.isEmpty { log = result.succeeded ? "Done." : "Failed with code \(result.exitCode)." }
            if task == .periodicScripts && !FileManager.default.fileExists(atPath: "/usr/sbin/periodic") {
                log = "This macOS version no longer includes `periodic`, so MacCleaner ran its equivalent: log rotation (newsyslog) and removal of temporary files older than 3 days.\n" + log
            }
            return Output(success: result.succeeded, log: log)

        case .thinSnapshots:
            let snapshots = localSnapshots()
            guard !snapshots.isEmpty else { return Output(success: true, log: "There are no local Time Machine snapshots.") }
            let before = SystemMetrics.disk().available
            let result = await AdminService.run(adminCommand(for: task))
            let after = SystemMetrics.disk().available
            return Output(success: result.succeeded,
                          log: "Deleted \(snapshots.count) snapshot(s).\n" + result.combinedOutput,
                          freedBytes: max(0, after - before))

        case .rebuildLaunchServices:
            let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            let result = await Shell.runAsync(lsregister, ["-gc", "-r", "-f", "-all", "local,system,user"], timeout: 1200)
            return Output(success: result.succeeded,
                          log: result.succeeded ? "Launch Services database rebuilt. Restart Finder or log out to see the cleaned-up \"Open With\" menu." : result.combinedOutput)

        case .speedUpMail:
            return speedUpMail()

        case .verifyDisk:
            let result = await Shell.runAsync("/usr/sbin/diskutil", ["verifyVolume", "/"], timeout: 3600)
            return Output(success: result.succeeded, log: result.combinedOutput)
        }
    }

    /// The exact shell line run as root for admin tasks (shown in the sheet).
    static func adminCommand(for task: MaintenanceTask) -> String {
        switch task {
        case .freeRAM:
            return "/usr/sbin/purge"
        case .flushDNS:
            return "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
        case .periodicScripts:
            if FileManager.default.fileExists(atPath: "/usr/sbin/periodic") {
                return "/usr/sbin/periodic daily weekly monthly"
            }
            return "/usr/sbin/newsyslog; /usr/bin/find /private/tmp -xdev -type f -atime +3 -mtime +3 -delete 2>/dev/null; true"
        case .reindexSpotlight:
            return "/usr/bin/mdutil -E /"
        case .repairPermissions:
            return "/usr/sbin/diskutil resetUserPermissions / \(Shell.uid)"
        case .thinSnapshots:
            let dates = localSnapshots()
            if dates.isEmpty { return "/usr/bin/tmutil deletelocalsnapshots <none>" }
            return dates.map { "/usr/bin/tmutil deletelocalsnapshots \(Shell.quote($0))" }.joined(separator: "; ")
        default:
            return task.title
        }
    }

    /// Dates of local Time Machine snapshots, e.g. "2025-03-01-101530".
    static func localSnapshots() -> [String] {
        let output = Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).output
        return output.split(separator: "\n").compactMap { line in
            let text = String(line)
            guard text.hasPrefix("com.apple.TimeMachine.") else { return nil }
            return text.replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
                .replacingOccurrences(of: ".local", with: "")
        }
    }

    // MARK: - Purgeable space

    /// Fills free space with a preallocated temporary file so macOS purges
    /// purgeable data, then deletes the file. Keeps 3 GB of headroom.
    private static func freePurgeableSpace(progress: ScanProgress?) async -> Output {
        let before = SystemMetrics.disk()
        let purgeable = max(0, before.availableForImportantUsage - before.available)
        if purgeable < 512 * 1024 * 1024 {
            return Output(success: true, log: "Less than 512 MB is purgeable right now (\(purgeable.formattedBytes)). Nothing to do.")
        }
        let headroom: Int64 = 3 * 1024 * 1024 * 1024
        let target = before.availableForImportantUsage - headroom
        guard target > 0 else { return Output(success: false, log: "Not enough free space to do this safely.") }

        return await Task.detached(priority: .userInitiated) { () -> Output in
            let path = NSHomeDirectory() + "/.maccleaner-purge-\(UUID().uuidString).tmp"
            let fd = open(path, O_CREAT | O_RDWR, 0o600)
            guard fd >= 0 else { return Output(success: false, log: "Could not create the temporary file.") }
            defer {
                close(fd)
                unlink(path)          // always removed, even if something fails
            }
            let chunk: Int64 = 1024 * 1024 * 1024
            var allocated: Int64 = 0
            while allocated < target {
                if progress?.isCancelled == true { break }
                let length = min(chunk, target - allocated)
                var store = fstore_t(fst_flags: UInt32(F_ALLOCATEALL), fst_posmode: Int32(F_PEOFPOSMODE),
                                     fst_offset: 0, fst_length: off_t(length), fst_bytesalloc: 0)
                if fcntl(fd, F_PREALLOCATE, &store) == -1 { break }    // disk full: macOS has purged what it can
                allocated += length
                ftruncate(fd, off_t(allocated))
                progress?.setFraction(Double(allocated) / Double(target))
                progress?.setMessage("Reserved \(allocated.formattedBytes) of \(target.formattedBytes)…")
            }
            return Output(success: true, log: "")
        }.value.withLog {
            let after = SystemMetrics.disk()
            let gained = max(0, after.available - before.available)
            return "Free space went from \(before.available.formattedBytes) to \(after.available.formattedBytes) (+\(gained.formattedBytes))."
        }
    }

    // MARK: - Mail

    /// Vacuums Mail's "Envelope Index" SQLite database.
    private static func speedUpMail() -> Output {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty {
            return Output(success: false, log: "Quit Mail first, then run this task again.")
        }
        let mail = URL.home("Library/Mail")
        let versions = FileSize.children(of: mail).filter { $0.lastPathComponent.hasPrefix("V") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        guard let latest = versions.first else {
            return Output(success: false, log: "Mail data wasn't found or isn't readable. Grant Full Disk Access to MacCleaner.")
        }
        let index = latest.appendingPathComponent("MailData/Envelope Index")
        guard FileManager.default.fileExists(atPath: index.path) else {
            return Output(success: false, log: "Envelope Index not found in \(latest.tildePath).")
        }
        let before = FileSize.of(file: index)
        guard let db = SQLiteDB(path: index.path) else {
            return Output(success: false, log: "Could not open the Mail database (Full Disk Access needed?).")
        }
        let result = db.execute("VACUUM")
        let after = FileSize.of(file: index)
        if result.ok {
            return Output(success: true,
                          log: "Envelope Index compacted from \(before.formattedBytes) to \(after.formattedBytes).",
                          freedBytes: max(0, before - after))
        }
        return Output(success: false, log: result.error ?? "VACUUM failed")
    }
}

private extension MaintenanceService.Output {
    /// Fills in the log after the fact (used when the message depends on the final state).
    func withLog(_ make: () -> String) -> MaintenanceService.Output {
        var copy = self
        if copy.log.isEmpty { copy.log = make() }
        return copy
    }
}
