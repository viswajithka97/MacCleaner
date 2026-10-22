import AppKit
import Foundation
import SQLite3

struct TCCGrant: Identifiable, Hashable {
    var id: String { "\(service)-\(client)" }
    var service: String
    var client: String
    var allowed: Bool
}

enum PrivacyService {
    static func browserItems(callbacks: ScanCallbacks) -> [CleanableCategory] {
        var categories: [CleanableCategory] = []
        for browser in BrowserKind.allCases where browser.isInstalled() {
            if callbacks.isCancelled() { break }
            var items: [CleanableItem] = []
            for kind in PrivacyCategoryKind.allCases {
                let urls = BrowserSupport.paths(for: browser, category: kind).filter { FileScanSupport.exists($0.path) }
                let size = urls.reduce(Int64(0)) { $0 + FileSizing.allocatedSize(at: $1) }
                let path = urls.first?.path ?? browser.supportRoot().path
                let selected = kind != .passwords
                items.append(CleanableItem(
                    name: "\(browser.displayName) — \(kind.title)",
                    path: path,
                    size: size,
                    selected: selected,
                    subtitle: urls.map(\.lastPathComponent).joined(separator: ", "),
                    warning: kind == .passwords ? "Off by default. This permanently removes saved website passwords from this browser." : (browser.isRunning ? "Quit \(browser.displayName) before clearing." : nil),
                    extra: [
                        "browser": browser.rawValue,
                        "privacyKind": kind.rawValue,
                        "paths": urls.map(\.path).joined(separator: "|")
                    ]
                ))
            }
            categories.append(CleanableCategory(
                name: browser.displayName,
                symbol: "globe",
                detail: browser.isRunning ? "\(browser.displayName) is running. Quit it before clearing data." : "Ready.",
                items: items
            ))
        }
        return categories
    }

    static func recentsItems() -> CleanableCategory {
        let paths = [
            FileScanSupport.library().appendingPathComponent("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl2"),
            FileScanSupport.library().appendingPathComponent("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentDocuments.sfl3"),
            FileScanSupport.library().appendingPathComponent("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentApplications.sfl2"),
            FileScanSupport.library().appendingPathComponent("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentApplications.sfl3"),
            FileScanSupport.library().appendingPathComponent("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentServers.sfl2"),
            FileScanSupport.library().appendingPathComponent("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.RecentServers.sfl3"),
            FileScanSupport.library().appendingPathComponent("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl2")
        ]
        var items: [CleanableItem] = paths.filter { FileScanSupport.exists($0.path) }.map {
            FileScanSupport.item(name: $0.lastPathComponent, url: $0, extra: ["recents": "true"])
        }
        items.append(CleanableItem(
            name: "Clear recent items via AppleScript",
            path: "recents://clear",
            size: 0,
            subtitle: "Clears Recent Documents, Applications, Servers, and Finder recents.",
            extra: ["recentsCommand": "true"]
        ))
        return CleanableCategory(name: "Recent items", symbol: "clock", items: items)
    }

    static func wifiNetworks() -> CleanableCategory {
        var items: [CleanableItem] = []
        let hardware = (try? ProcessRunner.run("/usr/sbin/networksetup", arguments: ["-listallhardwareports"]))?.stdout ?? ""
        var device = "en0"
        let lines = hardware.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where line.contains("Wi-Fi") {
            if i + 1 < lines.count, lines[i + 1].contains("Device:") {
                device = lines[i + 1].split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "en0"
            }
        }
        if let result = try? ProcessRunner.run("/usr/sbin/networksetup", arguments: ["-listpreferredwirelessnetworks", device]) {
            for line in result.stdout.components(separatedBy: "\n") {
                let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty || name.contains("Preferred networks") { continue }
                items.append(CleanableItem(
                    name: name,
                    path: "wifi://\(name)",
                    size: 0,
                    selected: false,
                    subtitle: "Saved Wi-Fi network on \(device). Removing requires an administrator password.",
                    extra: ["wifi": name, "device": device]
                ))
            }
        }
        return CleanableCategory(name: "Wi-Fi network history", symbol: "wifi", items: items, requiresAdmin: true)
    }

    static func quickLookItem() -> CleanableCategory {
        CleanableCategory(
            name: "Quick Look thumbnails",
            symbol: "eye",
            detail: "Runs `qlmanage -r cache`.",
            items: [CleanableItem(name: "Reset Quick Look cache", path: "ql://reset", size: 0, extra: ["ql": "true"])]
        )
    }

    static func tccGrants() -> [TCCGrant] {
        let dbPaths = [
            FileScanSupport.library().appendingPathComponent("Application Support/com.apple.TCC/TCC.db").path,
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]
        let wanted = ["kTCCServiceCamera": "Camera", "kTCCServiceMicrophone": "Microphone", "kTCCServiceLocation": "Location", "kTCCServiceScreenCapture": "Screen Recording", "kTCCServiceSystemPolicyAllFiles": "Full Disk Access"]
        var grants: [TCCGrant] = []
        for path in dbPaths where FileScanSupport.exists(path) {
            var db: OpaquePointer?
            if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK { continue }
            defer { sqlite3_close(db) }
            let sql = "SELECT service, client, auth_value FROM access;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { continue }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let service = String(cString: sqlite3_column_text(stmt, 0))
                let client = String(cString: sqlite3_column_text(stmt, 1))
                let auth = sqlite3_column_int(stmt, 2)
                if let label = wanted[service] {
                    grants.append(TCCGrant(service: label, client: client, allowed: auth > 0))
                }
            }
        }
        return grants
    }

    static func openPrivacyPane(_ service: String) {
        let map: [String: String] = [
            "Camera": "Privacy_Camera",
            "Microphone": "Privacy_Microphone",
            "Location": "Privacy_LocationServices",
            "Screen Recording": "Privacy_ScreenCapture",
            "Full Disk Access": "Privacy_AllFiles"
        ]
        let anchor = map[service] ?? "Privacy"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func clearRecents() {
        _ = try? ProcessRunner.run("/usr/bin/osascript", arguments: [
            "-e", "tell application \"System Events\" to delete every login item whose name is \"\" ",
            "-e", "tell application \"Finder\" to set recentFolders to {}",
        ])
        NSDocumentController.shared.clearRecentDocuments(nil)
        _ = try? ProcessRunner.run("/usr/bin/defaults", arguments: ["delete", "-g", "NSRecentDocuments"])
        _ = try? ProcessRunner.run("/usr/bin/qlmanage", arguments: ["-r", "cache"])
    }

    static func removeWifi(ssid: String, device: String) async throws {
        _ = try await AdminPrivileges.shared.run(
            command: "/usr/sbin/networksetup -removepreferredwirelessnetwork \(device) \(shellEscape(ssid))",
            explanation: "macOS stores remembered Wi-Fi networks in a privileged configuration. Removing “\(ssid)” needs an administrator password so other users’ networks are not changed silently."
        )
    }

    static func resetQuickLook() {
        _ = try? ProcessRunner.run("/usr/bin/qlmanage", arguments: ["-r", "cache"])
    }

    static func shellEscape(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func scan(callbacks: ScanCallbacks) async -> [CleanableCategory] {
        await Task.detached(priority: .userInitiated) {
            callbacks.progress(0.2, "Browsers")
            var cats = browserItems(callbacks: callbacks)
            callbacks.progress(0.6, "Recents")
            cats.append(recentsItems())
            callbacks.progress(0.75, "Wi-Fi")
            cats.append(wifiNetworks())
            callbacks.progress(0.9, "Quick Look")
            cats.append(quickLookItem())
            return cats
        }.value
    }
}
