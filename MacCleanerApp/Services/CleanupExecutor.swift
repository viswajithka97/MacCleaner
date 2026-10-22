import AppKit
import Photos

/// Performs the removal actions chosen in any module's results screen.
///
/// Rules applied to every item:
/// * `PathSafety` must allow the path (protected locations + exclusion list).
/// * Files that are open in another app are skipped.
/// * Admin actions are explained once (one sheet per run) before anything runs.
/// * Failures are logged and the run continues; nothing ever crashes the app.
enum CleanupExecutor {

    static func perform(_ items: [CleanItem], progress: ScanProgress, title: String) async -> CleanupResult {
        let settings = SettingsStore.snapshot()
        var result = CleanupResult()
        let actionable = items.filter { !$0.action.isInfoOnly }
        guard !actionable.isEmpty else { return result }

        // 1. Ask for admin approval once, covering every admin item in this run.
        var adminApproved = false
        let adminItems = actionable.filter { $0.action.requiresAdmin }
        if !adminItems.isEmpty {
            var explanations: [String] = []
            for item in adminItems {
                let text = adminExplanation(for: item.action)
                if !explanations.contains(text) { explanations.append(text) }
            }
            let commands = adminItems.prefix(30).map { adminCommandPreview(for: $0.action) }
            adminApproved = await AdminService.shared.requestApproval(
                title: "\(title) needs administrator access",
                explanation: explanations.joined(separator: "\n\n"),
                commands: Array(commands))
        }

        // 2. Find plain files that are currently open in other apps, so we can skip them.
        let fileURLs: [URL] = actionable.compactMap { item in
            if case .remove(let url) = item.action, !FileSize.isDirectory(url) { return url }
            return nil
        }
        progress.setMessage("Checking for files in use…")
        let inUse = FileInUse.openFiles(fileURLs)

        // 3. System files needing root are deleted in batches (much faster than one by one).
        let adminRemovals: [(CleanItem, URL)] = actionable.compactMap { item in
            if case .adminRemove(let url) = item.action { return (item, url) }
            return nil
        }
        if !adminRemovals.isEmpty {
            if adminApproved {
                result.merge(await adminRemove(adminRemovals, progress: progress))
            } else {
                for (_, url) in adminRemovals { result.fail(url.path, "Administrator access was not approved") }
            }
        }

        // 4. Photos are deleted in one PhotoKit request (macOS shows its own confirmation).
        let photoIDs: [(CleanItem, String)] = actionable.compactMap { item in
            if case .photoAsset(let id) = item.action { return (item, id) }
            return nil
        }
        if !photoIDs.isEmpty {
            progress.setMessage("Deleting photos from your Photos library…")
            result.merge(await deletePhotos(photoIDs))
        }

        // 5. Everything else, one by one.
        let remaining = actionable.filter { item in
            switch item.action {
            case .adminRemove, .photoAsset: return false
            default: return true
            }
        }
        for (index, item) in remaining.enumerated() {
            if progress.isCancelled {
                result.messages.append("Stopped before finishing: \(remaining.count - index) item(s) were not processed.")
                break
            }
            progress.step(index, of: remaining.count, "Removing \(item.name)")
            if let url = item.url { progress.visit(url.path) }
            if item.action.requiresAdmin && !adminApproved {
                result.fail(item.url?.path ?? item.name, "Administrator access was not approved")
                continue
            }
            await perform(item, settings: settings, inUse: inUse, result: &result)
        }
        progress.setFraction(1)
        return result
    }

    // MARK: - Single item

    private static func perform(_ item: CleanItem, settings: SettingsStore.Snapshot,
                                inUse: Set<String>, result: inout CleanupResult) async {
        let permanent = !settings.moveToTrash
        switch item.action {
        case .none, .adminRemove, .photoAsset:
            break

        case .remove(let url):
            if inUse.contains(url.path) {
                result.fail(url.path, "File is open in another app — skipped")
                return
            }
            removeFile(url, permanently: permanent, knownSize: item.size, name: item.name, result: &result)

        case .removeMany(let urls):
            var freed: Int64 = 0
            var removed = 0
            for url in urls {
                if let reason = PathSafety.reasonToSkip(url) { result.fail(url.path, reason); continue }
                let size = FileSize.of(url)
                do {
                    try FileRemover.remove(url, permanently: permanent)
                    freed += size
                    removed += 1
                } catch {
                    result.fail(url.path, error.localizedDescription)
                }
            }
            if removed > 0 { result.success("\(item.name) (\(removed) items)", bytes: freed) }

        case .removeContents(let folder):
            removeContents(of: folder, permanently: permanent, name: item.name, result: &result)

        case .deletePermanently(let url):
            removeFile(url, permanently: true, knownSize: item.size, name: item.name, result: &result)

        case .command(let command):
            let output: ShellResult
            if command.requiresAdmin {
                output = await AdminService.run(command.shellLine)
            } else {
                output = await Shell.runAsync(command.executable, command.arguments, environment: command.environment)
            }
            if output.succeeded {
                result.success(item.name, bytes: item.size)
                let text = output.combinedOutput
                if !text.isEmpty { result.messages.append("\(item.name): \(text.suffix(400))") }
            } else {
                result.fail(item.name, output.combinedOutput.isEmpty ? "Command failed (\(output.exitCode))" : output.combinedOutput)
            }

        case .removeLoginItem(let name, let path):
            let outcome = LoginItemsService.remove(name: name)
            if outcome.ok {
                result.success("Login item \(name)", bytes: 0)
            } else {
                result.fail(path, outcome.message)
            }

        case .removeLaunchItem(let plist, let label, let isSystem):
            if let reason = PathSafety.reasonToSkip(plist) { result.fail(plist.path, reason); return }
            let outcome = await LaunchItemsService.remove(plist: plist, label: label, isSystem: isSystem, permanently: permanent)
            if outcome.ok {
                result.success(label, bytes: item.size)
            } else {
                result.fail(plist.path, outcome.message)
            }

        case .browserData(let browser, let kind):
            if browser.isRunning {
                result.fail(browser.name, "Quit \(browser.name) first — its data is locked while it runs")
                return
            }
            let outcome = BrowserDataService.clear(browser, kind)
            if outcome.failures.isEmpty || outcome.freed > 0 {
                result.success("\(browser.name): \(kind.title)", bytes: outcome.freed)
            }
            for failure in outcome.failures { result.fail(failure.path, failure.reason) }

        case .recentItems(let kind):
            let outcome = PrivacyService.clearRecentItems(kind)
            if outcome.ok { result.success(kind.title, bytes: item.size) } else { result.fail(kind.title, outcome.message) }

        case .wifiNetwork(let interface, let ssid):
            let line = ShellCommand(executable: "/usr/sbin/networksetup",
                                    arguments: ["-removepreferredwirelessnetwork", interface, ssid],
                                    requiresAdmin: true, explanation: "").shellLine
            let output = await AdminService.run(line)
            if output.succeeded { result.success("Wi-Fi network \(ssid)", bytes: 0) }
            else { result.fail(ssid, output.combinedOutput) }

        case .quickLookCache:
            _ = await Shell.runAsync("/usr/bin/qlmanage", ["-r", "cache"])
            let reset = await Shell.runAsync("/usr/bin/qlmanage", ["-r"])
            if reset.succeeded { result.success("QuickLook thumbnail cache", bytes: item.size) }
            else { result.fail("QuickLook", reset.combinedOutput) }

        case .mailTrash:
            let outcome = await TrashService.emptyMailTrash()
            if outcome.ok { result.success("Mail trash", bytes: item.size) } else { result.fail("Mail", outcome.message) }

        case .disablePlugin(let identifier):
            let output = await Shell.runAsync("/usr/bin/pluginkit", ["-e", "ignore", "-i", identifier])
            if output.succeeded { result.success("Disabled \(item.name)", bytes: 0) }
            else { result.fail(identifier, output.combinedOutput) }

        case .forceQuit(let pid):
            let ok = await MainActor.run { () -> Bool in
                if let app = NSRunningApplication(processIdentifier: pid) { return app.forceTerminate() }
                return kill(pid, SIGKILL) == 0
            }
            if ok { result.success("Force quit \(item.name)", bytes: 0) } else { result.fail(item.name, "Could not force quit") }

        case .maintenance(let task):
            let output = await MaintenanceService.run(task, alreadyApproved: true)
            if output.success { result.success(task.title, bytes: output.freedBytes) }
            else { result.fail(task.title, output.log) }

        case .update(let update):
            let outcome = await UpdaterService.install(update)
            if outcome.ok { result.success("Updated \(update.appName)", bytes: 0); result.messages.append(outcome.message) }
            else { result.fail(update.appName, outcome.message) }

        case .forgetReceipt(let packageID):
            let line = ShellCommand(executable: "/usr/sbin/pkgutil", arguments: ["--forget", packageID],
                                    requiresAdmin: true, explanation: "").shellLine
            let output = await AdminService.run(line)
            if output.succeeded { result.success("Receipt \(packageID)", bytes: item.size) }
            else { result.fail(packageID, output.combinedOutput) }
        }
    }

    // MARK: - Files

    private static func removeFile(_ url: URL, permanently: Bool, knownSize: Int64, name: String, result: inout CleanupResult) {
        if let reason = PathSafety.reasonToSkip(url) {
            result.fail(url.path, reason)
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) || (try? url.checkResourceIsReachable()) == true
                || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil else {
            result.fail(url.path, "Already gone")
            return
        }
        do {
            try FileRemover.remove(url, permanently: permanently)
            result.success(name, bytes: knownSize)
        } catch {
            result.fail(url.path, error.localizedDescription)
        }
    }

    /// Deletes each child of `folder`, keeping the folder itself (apps expect their cache folder to exist).
    private static func removeContents(of folder: URL, permanently: Bool, name: String, result: inout CleanupResult) {
        if let reason = PathSafety.reasonToSkip(folder.appendingPathComponent("x")) {
            result.fail(folder.path, reason)
            return
        }
        var freed: Int64 = 0
        var failures = 0
        var removed = 0
        for child in FileSize.children(of: folder) {
            if PathSafety.reasonToSkip(child) != nil { continue }
            let size = FileSize.of(child)
            do {
                try FileRemover.remove(child, permanently: permanently)
                freed += size
                removed += 1
            } catch {
                failures += 1
                if failures <= 3 { result.fail(child.path, error.localizedDescription) }
            }
        }
        if failures > 3 { result.fail(folder.path, "\(failures - 3) more item(s) in this folder could not be removed") }
        if removed > 0 || failures == 0 { result.success(name, bytes: freed) }
    }

    /// Deletes root-owned files with `rm -rf` in batches, then checks what's gone.
    private static func adminRemove(_ entries: [(CleanItem, URL)], progress: ScanProgress) async -> CleanupResult {
        var result = CleanupResult()
        var allowed: [(CleanItem, URL)] = []
        for entry in entries {
            if let reason = PathSafety.reasonToSkip(entry.1) { result.fail(entry.1.path, reason) } else { allowed.append(entry) }
        }
        let batchSize = 150
        var start = 0
        while start < allowed.count {
            if progress.isCancelled { break }
            let batch = Array(allowed[start..<min(start + batchSize, allowed.count)])
            progress.step(start, of: allowed.count, "Removing system files…")
            let line = "/bin/rm -rf -- " + batch.map { Shell.quote($0.1.path) }.joined(separator: " ")
            let output = await AdminService.run(line)
            for (item, url) in batch {
                if FileManager.default.fileExists(atPath: url.path) {
                    result.fail(url.path, output.combinedOutput.isEmpty ? "Could not remove" : output.combinedOutput)
                } else {
                    result.success(item.name, bytes: item.size)
                }
            }
            start += batchSize
        }
        return result
    }

    // MARK: - Photos

    private static func deletePhotos(_ entries: [(CleanItem, String)]) async -> CleanupResult {
        var result = CleanupResult()
        let ids = entries.map(\.1)
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else {
            result.fail("Photos", "The selected photos were not found in the library")
            return result
        }
        let outcome: (Bool, Error?) = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets)
            }, completionHandler: { success, error in
                continuation.resume(returning: (success, error))
            })
        }
        if outcome.0 {
            for (item, _) in entries { result.success(item.name, bytes: item.size) }
            result.messages.append("Deleted photos are in Photos → Recently Deleted for 30 days.")
        } else {
            result.fail("Photos", outcome.1?.localizedDescription ?? "Photos did not delete the items")
        }
        return result
    }

    // MARK: - Admin explanations

    static func adminExplanation(for action: RemovalAction) -> String {
        switch action {
        case .adminRemove:
            return "Delete system files you selected (such as system log files). They belong to the system (root user), so macOS requires administrator rights to remove them."
        case .command(let command):
            return command.explanation
        case .removeLaunchItem:
            return "Stop system-wide launch agents/daemons with `launchctl bootout` and remove their files from /Library. These are shared by all users, so administrator rights are needed."
        case .wifiNetwork:
            return "Forget the selected Wi-Fi networks with `networksetup -removepreferredwirelessnetwork`. Network settings are system-wide, so administrator rights are needed."
        case .forgetReceipt:
            return "Remove installer receipts with `pkgutil --forget`. Receipts are stored in a system folder, so administrator rights are needed. This doesn't delete any files, it only makes macOS forget the package was installed."
        case .maintenance(let task):
            return task.adminExplanation
        default:
            return "Perform a system-level change."
        }
    }

    static func adminCommandPreview(for action: RemovalAction) -> String {
        switch action {
        case .adminRemove(let url): return "rm -rf \(Shell.quote(url.path))"
        case .command(let command): return command.shellLine
        case .removeLaunchItem(let plist, let label, _): return "launchctl bootout system/\(label); remove \(plist.path)"
        case .wifiNetwork(let interface, let ssid): return "networksetup -removepreferredwirelessnetwork \(interface) \(Shell.quote(ssid))"
        case .forgetReceipt(let id): return "pkgutil --forget \(id)"
        case .maintenance(let task): return task.title
        default: return ""
        }
    }
}

/// Moves to Trash or deletes, following the user's setting.
enum FileRemover {
    static func remove(_ url: URL, permanently: Bool) throws {
        if permanently {
            try FileManager.default.removeItem(at: url)
        } else {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                // Volumes without a Trash (e.g. some network shares) can't trash: say so clearly.
                let ns = error as NSError
                if ns.domain == NSCocoaErrorDomain && ns.code == NSFeatureUnsupportedError {
                    throw NSError(domain: NSCocoaErrorDomain, code: ns.code, userInfo: [
                        NSLocalizedDescriptionKey: "This volume has no Trash. Switch to \"Delete permanently\" in Settings to remove it."])
                }
                throw error
            }
        }
    }
}

/// Detects files currently open by any process (using `lsof`).
enum FileInUse {
    static func openFiles(_ urls: [URL]) -> Set<String> {
        guard !urls.isEmpty else { return [] }
        var open = Set<String>()
        var start = 0
        while start < urls.count {
            let chunk = urls[start..<min(start + 200, urls.count)]
            let output = Shell.run("/usr/sbin/lsof", ["-F", "n", "--"] + chunk.map(\.path), timeout: 30)
            for line in output.output.split(separator: "\n") where line.hasPrefix("n") {
                open.insert(String(line.dropFirst()))
            }
            start += 200
        }
        return open
    }
}
