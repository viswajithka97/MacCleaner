import Foundation

/// Launch agents and daemons: background programs started by launchd.
enum LaunchItemsService {

    struct Outcome { var ok: Bool; var message: String }

    static let folders: [(URL, LaunchItem.Domain)] = [
        (.home("Library/LaunchAgents"), .user),
        (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
        (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
    ]

    /// The parts of a launchd plist we care about.
    struct PlistInfo {
        var label: String
        var program: String?
        var arguments: [String]
        var disabledKey: Bool
    }

    static func parse(_ plist: URL) -> PlistInfo? {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let args = dict["ProgramArguments"] as? [String] ?? []
        let program = (dict["Program"] as? String) ?? args.first
        let label = dict["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
        return PlistInfo(label: label, program: program, arguments: args, disabledKey: dict["Disabled"] as? Bool ?? false)
    }

    /// Lists every agent/daemon with its signer and status.
    static func list(progress: ScanProgress? = nil) -> [LaunchItem] {
        let userDisabled = disabledLabels(domain: "gui/\(Shell.uid)")
        let systemDisabled = disabledLabels(domain: "system")
        let loadedUser = loadedUserLabels()

        var items: [LaunchItem] = []
        for (folder, domain) in folders {
            for plist in FileSize.children(of: folder) where plist.pathExtension == "plist" {
                if progress?.isCancelled == true { return items }
                progress?.visit(plist.path)
                let info = parse(plist)
                let label = info?.label ?? plist.deletingPathExtension().lastPathComponent
                let signer: String
                if let program = info?.program {
                    signer = CodeSign.check(path: program).summary
                } else {
                    signer = "Unknown"
                }
                let disabledSet = domain == .daemon ? systemDisabled : userDisabled
                let isDisabled = disabledSet[label] ?? (info?.disabledKey ?? false)
                let isLoaded: Bool
                if domain == .daemon {
                    isLoaded = Shell.run("/bin/launchctl", ["print", "system/\(label)"], timeout: 5).succeeded
                } else {
                    isLoaded = loadedUser.contains(label)
                }
                items.append(LaunchItem(label: label, plist: plist, program: info?.program, domain: domain,
                                        signer: signer, isDisabled: isDisabled, isLoaded: isLoaded))
            }
        }
        return items
    }

    /// Parses `launchctl print-disabled <domain>` into label -> isDisabled.
    static func disabledLabels(domain: String) -> [String: Bool] {
        let output = Shell.run("/bin/launchctl", ["print-disabled", domain], timeout: 10).output
        var result: [String: Bool] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            result[label] = (state == "disabled" || state == "true")
        }
        return result
    }

    /// Labels currently loaded in the user's session (`launchctl list`).
    static func loadedUserLabels() -> Set<String> {
        let output = Shell.run("/bin/launchctl", ["list"], timeout: 10).output
        var labels = Set<String>()
        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: "\t")
            if parts.count >= 3 { labels.insert(String(parts[2])) }
        }
        return labels
    }

    /// Enables or disables a job (persistently, via `launchctl enable/disable`).
    static func setEnabled(_ item: LaunchItem, enabled: Bool) async -> Outcome {
        let uid = Shell.uid
        if item.domain == .daemon {
            let label = Shell.quote(item.label), plist = Shell.quote(item.plist.path)
            let line = enabled
                ? "/bin/launchctl enable system/\(label); /bin/launchctl bootstrap system \(plist) 2>/dev/null; true"
                : "/bin/launchctl bootout system/\(label) 2>/dev/null; /bin/launchctl disable system/\(label)"
            let approved = await AdminService.shared.requestApproval(
                title: enabled ? "Enable \(item.label)" : "Disable \(item.label)",
                explanation: "\(enabled ? "Turn on" : "Turn off") the system daemon \"\(item.label)\" with launchctl. System daemons run for all users, so administrator rights are needed. You can switch it back at any time.",
                commands: [line])
            guard approved else { return Outcome(ok: false, message: "Administrator access was not approved") }
            let result = await AdminService.run(line)
            return Outcome(ok: result.succeeded, message: result.combinedOutput)
        }
        let target = "gui/\(uid)/\(item.label)"
        if enabled {
            let enable = await Shell.runAsync("/bin/launchctl", ["enable", target])
            let boot = await Shell.runAsync("/bin/launchctl", ["bootstrap", "gui/\(uid)", item.plist.path])
            // "already bootstrapped" (error 5/37) is fine.
            return Outcome(ok: enable.succeeded, message: enable.succeeded ? "" : enable.combinedOutput + boot.combinedOutput)
        } else {
            _ = await Shell.runAsync("/bin/launchctl", ["bootout", "gui/\(uid)", item.plist.path])
            let disable = await Shell.runAsync("/bin/launchctl", ["disable", target])
            return Outcome(ok: disable.succeeded, message: disable.combinedOutput)
        }
    }

    /// Unloads a job and moves its plist to the Trash (or deletes it).
    /// For system items the caller must have obtained admin approval already.
    static func remove(plist: URL, label: String, isSystem: Bool, permanently: Bool) async -> Outcome {
        let uid = Shell.uid
        // Unload from the user's session (works for user and global agents).
        _ = await Shell.runAsync("/bin/launchctl", ["bootout", "gui/\(uid)", plist.path])
        if !isSystem {
            do {
                try FileRemover.remove(plist, permanently: permanently)
                return Outcome(ok: true, message: "")
            } catch {
                return Outcome(ok: false, message: error.localizedDescription)
            }
        }
        // System items: unload from the system domain and move the file as root.
        let quoted = Shell.quote(plist.path)
        var line = "/bin/launchctl bootout system \(quoted) 2>/dev/null; "
        if permanently {
            line += "/bin/rm -f \(quoted)"
        } else {
            let stamp = Int(Date().timeIntervalSince1970)
            let destination = NSHomeDirectory() + "/.Trash/\(plist.deletingPathExtension().lastPathComponent)-\(stamp).plist"
            line += "/bin/mv -f \(quoted) \(Shell.quote(destination)) && /usr/sbin/chown \(uid) \(Shell.quote(destination))"
        }
        let result = await AdminService.run(line)
        let gone = !FileManager.default.fileExists(atPath: plist.path)
        return Outcome(ok: gone, message: gone ? "" : result.combinedOutput)
    }
}
