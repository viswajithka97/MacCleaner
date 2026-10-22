import AppKit
import Foundation

/// Handles logical items that are not plain files (brew cleanup, simctl, Mail trash, Wi-Fi, etc.)
enum SpecialActions {
    @MainActor
    static func perform(_ item: CleanableItem) async -> String? {
        if let command = item.extra["command"] {
            if command.contains("simctl") {
                _ = try? ProcessRunner.run("/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"])
                return "Removed unavailable simulators."
            }
            if command.contains("brew cleanup") {
                if let brew = ProcessRunner.which("brew") {
                    let result = try? ProcessRunner.run(brew, arguments: ["cleanup", "-s"], timeout: 300)
                    return result?.stdout ?? "brew cleanup finished."
                }
            }
        }
        if item.extra["mailEmpty"] == "true" {
            try? TrashBinsService.emptyMailTrash()
            return "Asked Mail to empty Trash and Junk."
        }
        if item.extra["photosRecentlyDeleted"] == "true" {
            await TrashBinsService.emptyPhotosRecentlyDeleted()
            return "Requested Photos to empty Recently Deleted."
        }
        if item.extra["ql"] == "true" {
            PrivacyService.resetQuickLook()
            return "Quick Look cache reset."
        }
        if item.extra["recentsCommand"] == "true" {
            PrivacyService.clearRecents()
            return "Cleared recent items lists."
        }
        if let ssid = item.extra["wifi"], let device = item.extra["device"] {
            try? await PrivacyService.removeWifi(ssid: ssid, device: device)
            return "Removed Wi-Fi network \(ssid)."
        }
        if let pkg = item.extra["pkg"] {
            _ = try? await AdminPrivileges.shared.run(
                command: "/usr/sbin/pkgutil --forget \(pkg)",
                explanation: "Forgetting a package receipt updates macOS Installer records and needs administrator rights."
            )
            return "Forgot receipt \(pkg)."
        }
        if item.extra["launchctl"] != nil || item.extra["origin"] != nil && item.extra["reasons"] != nil {
            await MalwareService.unloadAndTrash(item: item)
            return "Unloaded and moved \(item.name) to Trash."
        }
        if let name = item.extra["loginItem"] {
            OptimizationService.removeLoginItem(name)
            return "Removed login item \(name)."
        }
        if let pidString = item.extra["pid"], let pid = Int32(pidString) {
            OptimizationService.quit(pid: pid, force: item.extra["forceQuit"] == "true")
            return "Quit \(item.name)."
        }
        if let paths = item.extra["paths"] {
            for path in paths.split(separator: "|") {
                var resulting: NSURL?
                try? FileManager.default.trashItem(at: URL(fileURLWithPath: String(path)), resultingItemURL: &resulting)
            }
            return "Cleared \(item.name)."
        }
        if item.extra["privacyKind"] == PrivacyCategoryKind.passwords.rawValue {
            // Already handled via paths; extra warning only.
        }
        if let source = item.extra["updateSource"] {
            let update = AppUpdate(
                name: item.name,
                path: item.path,
                currentVersion: "",
                newVersion: item.subtitle,
                releaseNotes: "",
                source: AppUpdate.Source(rawValue: source) ?? .sparkle,
                actionURL: item.extra["updateURL"],
                caskName: item.extra["cask"]
            )
            UpdaterService.apply(update)
            return "Started update for \(item.name)."
        }
        if item.path.hasPrefix("xcrun://") || item.path.hasPrefix("brew://") || item.path.hasPrefix("mail://") || item.path.hasPrefix("photos://") || item.path.hasPrefix("ql://") || item.path.hasPrefix("wifi://") || item.path.hasPrefix("pkgutil://") || item.path.hasPrefix("pid://") || item.path.hasPrefix("recents://") {
            return "Handled special item."
        }
        return nil
    }
}
