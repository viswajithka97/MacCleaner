import AppKit
import Foundation

struct InstalledApp: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var bundleId: String
    var version: String
    var size: Int64
    var lastOpened: Date?
    var source: String
    var icon: NSImage?
    var isApple: Bool
    var isSelf: Bool

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

enum UninstallerService {
    static func listApps(callbacks: ScanCallbacks) async -> [InstalledApp] {
        await Task.detached(priority: .userInitiated) {
            var apps: [InstalledApp] = []
            let dirs = [
                URL(fileURLWithPath: "/Applications"),
                FileScanSupport.home().appendingPathComponent("Applications")
            ]
            for dir in dirs {
                for url in FileScanSupport.listChildren(of: dir) where url.pathExtension == "app" {
                    if callbacks.isCancelled() { return apps }
                    callbacks.progress(0.3, url.path)
                    apps.append(describe(url))
                }
            }
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value
    }

    static func describe(_ url: URL) -> InstalledApp {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? (NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any]) ?? [:]
        let bid = bundle?.bundleIdentifier ?? info["CFBundleIdentifier"] as? String ?? ""
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        let version = info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? ""
        let receipts = url.appendingPathComponent("Contents/_MASReceipt/receipt")
        let source = FileScanSupport.exists(receipts.path) ? "App Store" : "Other"
        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        return InstalledApp(
            name: name,
            path: url.path,
            bundleId: bid,
            version: version,
            size: FileSizing.allocatedSize(at: url),
            lastOpened: values?.contentAccessDate ?? values?.contentModificationDate,
            source: source,
            icon: icon,
            isApple: PathSafety.isAppleSystemApp(bundleId: bid, path: url.path) || CodeSigning.inspect(path: url.path).isApple && url.path.hasPrefix("/System/"),
            isSelf: PathSafety.isOurOwnApp(url.path) || bid == Bundle.main.bundleIdentifier
        )
    }

    static func leftovers(for app: InstalledApp, callbacks: ScanCallbacks) -> [CleanableItem] {
        let names = Set([app.name, app.bundleId, (app.path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")].filter { !$0.isEmpty })
        let lib = FileScanSupport.library()
        let roots: [URL] = [
            lib.appendingPathComponent("Application Support"),
            lib.appendingPathComponent("Caches"),
            lib.appendingPathComponent("Preferences"),
            lib.appendingPathComponent("Containers"),
            lib.appendingPathComponent("Group Containers"),
            lib.appendingPathComponent("Saved Application State"),
            lib.appendingPathComponent("Logs"),
            lib.appendingPathComponent("LaunchAgents"),
            lib.appendingPathComponent("WebKit"),
            lib.appendingPathComponent("HTTPStorages"),
            lib.appendingPathComponent("Cookies")
        ]
        var items: [CleanableItem] = []
        items.append(FileScanSupport.item(name: app.name, url: URL(fileURLWithPath: app.path), extra: ["appBundle": "true"]))

        for root in roots {
            for child in FileScanSupport.listChildren(of: root) {
                if callbacks.isCancelled() { return items }
                callbacks.progress(0.5, child.path)
                let hay = (child.lastPathComponent + " " + child.path).lowercased()
                if names.contains(where: { hay.contains($0.lowercased()) }) {
                    if PathSafety.isForbidden(child.path) { continue }
                    items.append(FileScanSupport.item(name: child.lastPathComponent, url: child, subtitle: child.path))
                }
            }
        }

        if !app.bundleId.isEmpty, let pkgutil = ProcessRunner.which("pkgutil") ?? Optional("/usr/sbin/pkgutil") {
            if let result = try? ProcessRunner.run(pkgutil, arguments: ["--pkgs-for-bundle", app.bundleId]) {
                for pkg in result.stdout.components(separatedBy: "\n") where !pkg.trimmingCharacters(in: .whitespaces).isEmpty {
                    items.append(CleanableItem(
                        name: "Receipt \(pkg)",
                        path: "pkgutil://\(pkg)",
                        size: 0,
                        subtitle: "pkgutil --forget \(pkg)",
                        extra: ["pkg": pkg.trimmingCharacters(in: .whitespacesAndNewlines)]
                    ))
                }
            }
        }
        return uniqueItems(items)
    }

    static func orphanLeftovers(installed: [InstalledApp], callbacks: ScanCallbacks) -> [CleanableItem] {
        let ids = Set(installed.map { $0.bundleId.lowercased() }.filter { !$0.isEmpty })
        let names = Set(installed.map { $0.name.lowercased() })
        let lib = FileScanSupport.library()
        let roots = [
            lib.appendingPathComponent("Application Support"),
            lib.appendingPathComponent("Caches"),
            lib.appendingPathComponent("Containers"),
            lib.appendingPathComponent("Preferences")
        ]
        var items: [CleanableItem] = []
        for root in roots {
            for child in FileScanSupport.listChildren(of: root) {
                if callbacks.isCancelled() { return items }
                callbacks.progress(0.7, child.path)
                let token = child.lastPathComponent.lowercased()
                if token.hasPrefix("com.apple.") { continue }
                if ids.contains(token) { continue }
                if names.contains(where: { token.contains($0) }) { continue }
                // Heuristic leftovers: container ids that look like bundle ids with no matching app.
                if token.contains(".") && !ids.contains(token) {
                    items.append(FileScanSupport.item(name: child.lastPathComponent, url: child, selected: false, subtitle: "No installed app matches this leftover."))
                }
            }
        }
        return items
    }

    static func uniqueItems(_ items: [CleanableItem]) -> [CleanableItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.path).inserted }
    }
}
