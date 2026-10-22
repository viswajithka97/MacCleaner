import AppKit

/// Finds every file an app leaves behind, and leftovers of apps already deleted.
enum UninstallerService {

    /// Library folders searched for app data.
    static var searchFolders: [URL] {
        let userLibrary = [
            "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
            "Saved Application State", "Logs", "LaunchAgents", "WebKit", "HTTPStorages", "Cookies",
            "Application Scripts", "Internet Plug-Ins", "Services",
        ].map { URL.home("Library/" + $0) }
        let systemLibrary = [
            "Application Support", "Caches", "Preferences", "LaunchAgents", "LaunchDaemons",
            "PrivilegedHelperTools", "Logs", "Internet Plug-Ins",
        ].map { URL(fileURLWithPath: "/Library/" + $0) }
        return userLibrary + systemLibrary
    }

    enum Mode { case completeRemoval, reset }

    /// Everything belonging to `app`. In reset mode the app itself and its receipts are kept.
    static func files(for app: InstalledApp, mode: Mode, progress: ScanProgress) -> [CleanItem] {
        var items: [CleanItem] = []
        if mode == .completeRemoval {
            progress.visit(app.url.path)
            let size = app.size ?? FileSize.of(app.url, progress: progress)
            items.append(CleanItem(name: app.url.lastPathComponent, url: app.url, size: size,
                                   subtitle: "Application", symbol: "app", action: removal(for: app.url)))
        }
        for folder in searchFolders {
            if progress.isCancelled { break }
            for child in FileSize.children(of: folder) {
                progress.visit(child.path)
                guard matches(child.lastPathComponent, bundleID: app.bundleID, appName: app.name) else { continue }
                let size = FileSize.of(child, progress: progress)
                items.append(CleanItem(name: child.lastPathComponent, url: child, size: size,
                                       subtitle: folder.tildePath, date: FileSize.modified(child),
                                       symbol: FileSize.isDirectory(child) ? "folder" : "doc",
                                       action: removal(for: child)))
            }
        }
        if mode == .completeRemoval {
            for receipt in receipts(for: app) {
                items.append(CleanItem(name: receipt, url: nil, size: 0, subtitle: "Installer receipt (pkgutil)",
                                       symbol: "shippingbox", action: .forgetReceipt(receipt)))
            }
        }
        return items
    }

    /// Does a file/folder name belong to this app?
    static func matches(_ fileName: String, bundleID: String, appName: String) -> Bool {
        let name = fileName.lowercased()
        let stem = (name as NSString).deletingPathExtension
        if !bundleID.isEmpty {
            let id = bundleID.lowercased()
            if name.contains(id) { return true }
        }
        let app = appName.lowercased()
        guard app.count >= 3 else { return false }
        return stem == app || name == app || stem == app.replacingOccurrences(of: " ", with: "")
    }

    /// Installer package receipts that mention the app.
    static func receipts(for app: InstalledApp) -> [String] {
        let output = Shell.run("/usr/sbin/pkgutil", ["--pkgs"], timeout: 30).output
        let id = app.bundleID.lowercased()
        let compactName = app.name.lowercased().replacingOccurrences(of: " ", with: "")
        return output.split(separator: "\n").map(String.init).filter { pkg in
            let lower = pkg.lowercased()
            if lower.hasPrefix("com.apple.") { return false }
            return (!id.isEmpty && lower.hasPrefix(id)) || (compactName.count >= 4 && lower.contains(compactName))
        }
    }

    /// Trash normally; use admin when the parent folder isn't writable (e.g. /Library/…).
    static func removal(for url: URL) -> RemovalAction {
        let parent = url.deletingLastPathComponent().path
        if FileManager.default.isWritableFile(atPath: parent) && FileManager.default.isDeletableFile(atPath: url.path) {
            return .remove(url)
        }
        return .adminRemove(url)
    }

    // MARK: - Leftovers of deleted apps

    /// Looks for data folders named after bundle IDs whose app is no longer installed.
    static func orphanedLeftovers(installed: [InstalledApp], progress: ScanProgress) -> [CleanCategory] {
        let installedIDs = Set(installed.map { $0.bundleID.lowercased() }.filter { !$0.isEmpty })
        var groups: [String: [CleanItem]] = [:]
        let folders = searchFolders
        for (index, folder) in folders.enumerated() {
            if progress.isCancelled { break }
            progress.step(index, of: folders.count, "Searching \(folder.tildePath)…")
            for child in FileSize.children(of: folder) {
                progress.visit(child.path)
                guard let id = bundleIDLike(child.lastPathComponent) else { continue }
                if isStillInstalled(id, installedIDs: installedIDs) { continue }
                let size = FileSize.of(child, progress: progress)
                let item = CleanItem(name: child.lastPathComponent, url: child, size: size, isSelected: false,
                                     subtitle: folder.tildePath, date: FileSize.modified(child),
                                     symbol: FileSize.isDirectory(child) ? "folder" : "doc",
                                     action: removal(for: child))
                groups[id, default: []].append(item)
            }
        }
        return groups.map { id, items in
            CleanCategory(id: "orphan-\(id)", title: id, symbol: "questionmark.app.dashed",
                          summary: "\(items.count) item(s) from an app that's no longer installed",
                          items: items.sorted { $0.size > $1.size })
        }
        .filter { $0.totalSize > 0 || $0.items.count > 1 }
        .sorted { $0.totalSize > $1.totalSize }
    }

    /// "com.vendor.App.plist" -> "com.vendor.app"; "ABCDE12345.com.vendor.app" -> "com.vendor.app".
    static func bundleIDLike(_ fileName: String) -> String? {
        var name = fileName
        for ext in [".plist", ".savedState", ".binarycookies", ".log"] where name.hasSuffix(ext) {
            name.removeLast(ext.count)
        }
        var parts = name.split(separator: ".").map(String.init)
        // Group containers start with a 10-character team ID.
        if let first = parts.first, first.count == 10, first == first.uppercased(), parts.count > 3 {
            parts.removeFirst()
        }
        if parts.first == "group" { parts.removeFirst() }
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty && $0.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil }) else {
            return nil
        }
        let id = parts.joined(separator: ".").lowercased()
        guard ["com", "org", "net", "io", "de", "co", "uk", "app", "dev", "jp", "fr", "ru", "me", "us", "ch", "nl", "se", "it", "info"]
            .contains(parts[0].lowercased()) else { return nil }
        if id.hasPrefix("com.apple.") || id.hasPrefix(Bundle.main.bundleIdentifier?.lowercased() ?? "~") { return nil }
        // Data of developer toolchains, not of an app (e.g. SwiftPM caches).
        if id.hasPrefix("org.swift.") || id.hasPrefix("com.apple") { return nil }
        return id
    }

    private static func isStillInstalled(_ id: String, installedIDs: Set<String>) -> Bool {
        if installedIDs.contains(id) { return true }
        // Helpers and extensions: "com.vendor.app.helper" belongs to "com.vendor.app".
        for installed in installedIDs where id.hasPrefix(installed + ".") || installed.hasPrefix(id + ".") {
            return true
        }
        // Apps anywhere else on disk (LaunchServices knows them).
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { return true }
        return false
    }
}
