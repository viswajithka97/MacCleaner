import AppKit

/// Privacy module: browser data, recent items, Wi-Fi history, QuickLook cache,
/// and an overview of app permissions.
enum PrivacyService {

    struct Outcome { var ok: Bool; var message: String }

    // MARK: - Scan (results for the generic cleanup flow)

    static func scan(progress: ScanProgress) -> [CleanCategory] {
        var categories: [CleanCategory] = []
        let browsers = BrowserID.allCases.filter(\.isInstalled)
        let totalSteps = browsers.count + 3

        for (index, browser) in browsers.enumerated() {
            if progress.isCancelled { return categories }
            progress.step(index, of: totalSteps, "Looking at \(browser.name)…")
            progress.visit(browser.dataRoot.path)
            var items: [CleanItem] = []
            for kind in BrowserDataKind.allCases {
                if let reason = BrowserDataService.unsupportedReason(browser, kind) {
                    items.append(CleanItem(name: kind.title, url: nil, size: 0, isSelected: false,
                                           subtitle: reason, symbol: kind.symbol, action: .none))
                    continue
                }
                guard BrowserDataService.hasData(browser, kind) else { continue }
                let size = BrowserDataService.size(browser, kind)
                var item = CleanItem(name: kind.title, url: nil, size: size, symbol: kind.symbol,
                                     action: .browserData(browser, kind))
                if kind == .passwords {
                    item.isSelected = false
                    item.warning = "Deletes every password saved in \(browser.name). They cannot be recovered unless synced elsewhere."
                }
                items.append(item)
            }
            guard !items.isEmpty else { continue }
            categories.append(CleanCategory(
                id: "browser-\(browser.rawValue)", title: browser.name, symbol: "globe",
                summary: "History, cookies, downloads, autofill, cache and passwords.",
                items: items,
                warning: browser.isRunning ? "\(browser.name) is running. Quit it before clearing its data." : nil,
                note: "Saved passwords are off by default."))
        }

        progress.step(browsers.count, of: totalSteps, "Recent items…")
        var recentItems: [CleanItem] = []
        for kind in RecentItemsKind.allCases {
            let size = recentItemsFiles(kind).reduce(Int64(0)) { $0 + FileSize.of($1) }
            recentItems.append(CleanItem(name: kind.title, url: nil, size: size, symbol: "clock.arrow.circlepath",
                                         action: .recentItems(kind)))
        }
        categories.append(CleanCategory(id: "recents", title: "Recent Items", symbol: "clock",
                                        summary: "Lists of recently opened documents, apps and servers.",
                                        items: recentItems,
                                        note: "Finder is restarted to apply the change."))

        progress.step(browsers.count + 1, of: totalSteps, "QuickLook thumbnails…")
        let qlSize = FileSize.of(quickLookCacheURL)
        categories.append(CleanCategory(id: "quicklook", title: "QuickLook Thumbnails", symbol: "eye",
                                        summary: "Previews of files you looked at, kept by QuickLook.",
                                        items: [CleanItem(name: "QuickLook thumbnail cache", url: quickLookCacheURL,
                                                          size: qlSize, symbol: "photo", action: .quickLookCache)]))

        progress.step(browsers.count + 2, of: totalSteps, "Wi-Fi networks…")
        if let interface = wifiInterface() {
            let current = currentNetwork(interface)
            let items = preferredNetworks(interface).map { ssid in
                CleanItem(name: ssid, url: nil, size: 0, isSelected: false,
                          subtitle: ssid == current ? "Currently connected" : "Saved network",
                          warning: ssid == current ? "You'll be disconnected and need the password to rejoin." : nil,
                          symbol: "wifi", action: .wifiNetwork(interface: interface, ssid: ssid))
            }
            if !items.isEmpty {
                categories.append(CleanCategory(id: "wifi", title: "Wi-Fi Network History", symbol: "wifi",
                                                summary: "Networks your Mac remembers and joins automatically.",
                                                items: items,
                                                note: "Choose the networks to forget. Requires administrator password."))
            }
        }
        progress.setFraction(1)
        return categories
    }

    // MARK: - Recent items

    private static let sharedFileList = URL.home("Library/Application Support/com.apple.sharedfilelist")

    static func recentItemsFiles(_ kind: RecentItemsKind) -> [URL] {
        func variants(_ base: String) -> [URL] {
            ["sfl3", "sfl2", "sfl"].map { sharedFileList.appendingPathComponent("\(base).\($0)") }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        switch kind {
        case .documents:
            let perApp = FileSize.children(of: sharedFileList.appendingPathComponent("com.apple.LSSharedFileList.ApplicationRecentDocuments"))
            return variants("com.apple.LSSharedFileList.RecentDocuments") + perApp
        case .applications:
            return variants("com.apple.LSSharedFileList.RecentApplications")
        case .servers:
            return variants("com.apple.LSSharedFileList.RecentServers") + variants("com.apple.LSSharedFileList.RecentHosts")
        case .finder:
            return []
        }
    }

    static func clearRecentItems(_ kind: RecentItemsKind) -> Outcome {
        if kind == .finder {
            Shell.run("/usr/bin/defaults", ["delete", "com.apple.finder", "FXRecentFolders"])
            Shell.run("/usr/bin/defaults", ["delete", "com.apple.finder", "GoToFieldHistory"])
            Shell.run("/usr/bin/killall", ["Finder"])     // Finder relaunches automatically
            return Outcome(ok: true, message: "")
        }
        var errors: [String] = []
        for file in recentItemsFiles(kind) {
            do { try FileManager.default.removeItem(at: file) } catch { errors.append(error.localizedDescription) }
        }
        // sharedfilelistd caches the lists; restarting it makes the change visible immediately.
        Shell.run("/usr/bin/killall", ["sharedfilelistd"])
        return Outcome(ok: errors.isEmpty, message: errors.joined(separator: "\n"))
    }

    // MARK: - QuickLook

    static var quickLookCacheURL: URL {
        let dir = Shell.run("/usr/bin/getconf", ["DARWIN_USER_CACHE_DIR"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: dir).appendingPathComponent("com.apple.QuickLook.thumbnailcache")
    }

    // MARK: - Wi-Fi

    /// The Wi-Fi device name, usually "en0".
    static func wifiInterface() -> String? {
        let output = Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"]).output
        let lines = output.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() where line.contains("Wi-Fi") || line.contains("AirPort") {
            if index + 1 < lines.count, lines[index + 1].hasPrefix("Device: ") {
                return String(lines[index + 1].dropFirst("Device: ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func preferredNetworks(_ interface: String) -> [String] {
        let output = Shell.run("/usr/sbin/networksetup", ["-listpreferredwirelessnetworks", interface]).output
        return output.components(separatedBy: "\n").dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func currentNetwork(_ interface: String) -> String? {
        let output = Shell.run("/usr/sbin/networksetup", ["-getairportnetwork", interface]).output
        guard let range = output.range(of: "Network: ") else { return nil }
        return output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - App permissions (read from TCC where accessible)

    struct PermissionGroup: Identifiable {
        var id: String { title }
        var title: String
        var symbol: String
        var pane: SystemLinks.Pane
        var apps: [String]
        var accessible: Bool
    }

    static func permissions() -> [PermissionGroup] {
        let services: [(String, String, String, SystemLinks.Pane)] = [
            ("kTCCServiceCamera", "Camera", "camera", .camera),
            ("kTCCServiceMicrophone", "Microphone", "mic", .microphone),
            ("kTCCServiceScreenCapture", "Screen Recording", "rectangle.dashed.badge.record", .screenRecording),
            ("kTCCServiceSystemPolicyAllFiles", "Full Disk Access", "externaldrive.badge.checkmark", .fullDiskAccess),
        ]
        let userDB = URL.home("Library/Application Support/com.apple.TCC/TCC.db").path
        let systemDB = "/Library/Application Support/com.apple.TCC/TCC.db"
        let userRows = tccRows(userDB)
        let systemRows = tccRows(systemDB)

        var groups: [PermissionGroup] = []
        for (service, title, symbol, pane) in services {
            let rows = (userRows ?? []) + (systemRows ?? [])
            let clients = rows.filter { $0.service == service && $0.allowed }.map { appName(for: $0.client) }
            let accessible = userRows != nil || systemRows != nil
            groups.append(PermissionGroup(title: title, symbol: symbol, pane: pane,
                                          apps: Array(Set(clients)).sorted(), accessible: accessible))
        }
        // Location Services keeps its own list, readable only by root.
        let location = locationClients()
        groups.insert(PermissionGroup(title: "Location", symbol: "location", pane: .location,
                                      apps: location ?? [], accessible: location != nil), at: 2)
        return groups
    }

    private struct TCCRow { var service: String; var client: String; var allowed: Bool }

    private static func tccRows(_ path: String) -> [TCCRow]? {
        guard let db = SQLiteDB(path: path, immutable: true) else { return nil }
        guard db.hasTable("access") else { return nil }
        // Newer macOS uses auth_value (2 = allowed, 3 = limited); older used `allowed` (1 = allowed).
        var rows = db.rows("SELECT service, client, auth_value FROM access")
        var legacy = false
        if rows.isEmpty {
            rows = db.rows("SELECT service, client, allowed FROM access")
            legacy = true
        }
        return rows.compactMap { row in
            guard row.count == 3, let service = row[0], let client = row[1] else { return nil }
            let value = Int(row[2] ?? "0") ?? 0
            let allowed = legacy ? value == 1 : (value == 2 || value == 3)
            return TCCRow(service: service, client: client, allowed: allowed)
        }
    }

    private static func locationClients() -> [String]? {
        let url = URL(fileURLWithPath: "/var/db/locationd/clients.plist")
        guard let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        var names: [String] = []
        for (key, value) in dict {
            guard let info = value as? [String: Any], (info["Authorized"] as? Bool) == true else { continue }
            let id = key.components(separatedBy: ":").last ?? key
            names.append(appName(for: (info["BundleId"] as? String) ?? id))
        }
        return names.sorted()
    }

    /// Turns a bundle ID or path into an app name.
    static func appName(for client: String) -> String {
        if client.hasPrefix("/") { return (client as NSString).lastPathComponent }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return client
    }
}
