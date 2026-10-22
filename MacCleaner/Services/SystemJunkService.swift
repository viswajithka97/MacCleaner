import Foundation

enum SystemJunkService {
    static func scan(callbacks: ScanCallbacks) async -> [CleanableCategory] {
        await Task.detached(priority: .userInitiated) {
            var categories: [CleanableCategory] = []
            categories.append(userCaches(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(userLogs(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(systemLogs(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(languageFiles(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(xcodeJunk(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(browserCaches(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(developerCaches(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(brokenPreferences(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(brokenLoginItems(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(iosBackups(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(ipswFiles(callbacks: callbacks))
            if callbacks.isCancelled() { return categories }
            categories.append(documentVersions(callbacks: callbacks))
            return categories.filter { !$0.items.isEmpty || $0.name.contains("Document") }
        }.value
    }

    private static func userCaches(callbacks: ScanCallbacks) -> CleanableCategory {
        let root = FileScanSupport.library().appendingPathComponent("Caches")
        var items: [CleanableItem] = []
        for folder in FileScanSupport.listChildren(of: root) {
            if callbacks.isCancelled() { break }
            callbacks.progress(0.05, folder.path)
            // Delete contents inside each app folder, not the folder itself.
            let children = FileScanSupport.listChildren(of: folder)
            for child in children {
                items.append(FileScanSupport.item(name: "\(folder.lastPathComponent)/\(child.lastPathComponent)", url: child, subtitle: child.path))
            }
        }
        return CleanableCategory(
            name: "User cache files",
            symbol: "internaldrive",
            detail: "Contents of ~/Library/Caches. App cache folders themselves are kept.",
            items: items
        )
    }

    private static func userLogs(callbacks: ScanCallbacks) -> CleanableCategory {
        let root = FileScanSupport.library().appendingPathComponent("Logs")
        var items: [CleanableItem] = []
        for child in FileScanSupport.listChildren(of: root) {
            if callbacks.isCancelled() { break }
            callbacks.progress(0.1, child.path)
            items.append(FileScanSupport.item(name: child.lastPathComponent, url: child))
        }
        return CleanableCategory(name: "User log files", symbol: "doc.text", detail: "~/Library/Logs", items: items)
    }

    private static func systemLogs(callbacks: ScanCallbacks) -> CleanableCategory {
        var items: [CleanableItem] = []
        for path in ["/Library/Logs", "/private/var/log"] {
            let url = URL(fileURLWithPath: path)
            callbacks.progress(0.15, path)
            for child in FileScanSupport.listChildren(of: url) {
                items.append(FileScanSupport.item(name: child.lastPathComponent, url: child, subtitle: child.path))
            }
        }
        return CleanableCategory(
            name: "System log files",
            symbol: "lock.doc",
            detail: "/Library/Logs and /private/var/log. Deleting these requires an administrator password.",
            items: items,
            requiresAdmin: true
        )
    }

    private static func languageFiles(callbacks: ScanCallbacks) -> CleanableCategory {
        let preferred = Set(Locale.preferredLanguages.map { $0.prefix(2).lowercased() } + ["en", "base"])
        var items: [CleanableItem] = []
        let appsDir = URL(fileURLWithPath: "/Applications")
        let enumerator = FileManager.default.enumerator(at: appsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            if callbacks.isCancelled() { break }
            if url.pathExtension == "app" {
                enumerator?.skipDescendants()
                callbacks.progress(0.25, url.path)
                let sign = CodeSigning.inspect(path: url.path)
                if sign.isApple { continue }
                let resources = url.appendingPathComponent("Contents/Resources")
                let lprojs = FileScanSupport.listChildren(of: resources).filter { $0.pathExtension == "lproj" }
                for lproj in lprojs {
                    let code = lproj.deletingPathExtension().lastPathComponent.lowercased()
                    if preferred.contains(code) || code == "base" { continue }
                    let warning = sign.signed
                        ? "Removing languages from a signed third-party app can break its code signature and auto-updates."
                        : nil
                    items.append(FileScanSupport.item(
                        name: "\(url.deletingPathExtension().lastPathComponent) — \(lproj.lastPathComponent)",
                        url: lproj,
                        selected: !sign.signed,
                        warning: warning
                    ))
                }
            }
        }
        return CleanableCategory(
            name: "Language files",
            symbol: "globe",
            detail: "Unused .lproj folders. English, Base, and your system languages are kept. Apple-signed apps are skipped.",
            items: items,
            warning: "Removing localizations from third-party apps can break auto-updates and code signatures."
        )
    }

    private static func xcodeJunk(callbacks: ScanCallbacks) -> CleanableCategory {
        let home = FileScanSupport.home()
        let developer = home.appendingPathComponent("Library/Developer")
        var items: [CleanableItem] = []
        let targets = [
            developer.appendingPathComponent("Xcode/DerivedData"),
            developer.appendingPathComponent("Xcode/Archives"),
            developer.appendingPathComponent("Xcode/iOS DeviceSupport"),
            developer.appendingPathComponent("CoreSimulator/Caches")
        ]
        for url in targets {
            callbacks.progress(0.4, url.path)
            if FileScanSupport.exists(url.path) {
                items.append(FileScanSupport.item(name: url.lastPathComponent, url: url, subtitle: url.path))
            }
        }
        // Unavailable simulators — represented as a logical item; the action runs simctl.
        if ProcessRunner.which("xcrun") != nil {
            items.append(CleanableItem(
                name: "Unavailable simulators",
                path: "xcrun://simctl/delete/unavailable",
                size: 0,
                selected: true,
                subtitle: "Runs `xcrun simctl delete unavailable`",
                extra: ["command": "xcrun simctl delete unavailable"]
            ))
        }
        return CleanableCategory(name: "Xcode junk", symbol: "hammer", detail: "DerivedData, Archives, DeviceSupport, CoreSimulator caches, unavailable simulators.", items: items)
    }

    private static func browserCaches(callbacks: ScanCallbacks) -> CleanableCategory {
        let home = FileScanSupport.home()
        let lib = FileScanSupport.library()
        let paths: [(String, String)] = [
            ("Safari", lib.appendingPathComponent("Caches/com.apple.Safari").path),
            ("Safari WebKit", lib.appendingPathComponent("Caches/com.apple.WebKit.Networking").path),
            ("Chrome", home.appendingPathComponent("Library/Caches/Google/Chrome").path),
            ("Chrome Cache", lib.appendingPathComponent("Application Support/Google/Chrome/Default/Cache").path),
            ("Chrome Code Cache", lib.appendingPathComponent("Application Support/Google/Chrome/Default/Code Cache").path),
            ("Firefox", lib.appendingPathComponent("Caches/Firefox").path),
            ("Edge", lib.appendingPathComponent("Caches/Microsoft Edge").path),
            ("Brave", lib.appendingPathComponent("Caches/BraveSoftware/Brave-Browser").path),
            ("Arc", lib.appendingPathComponent("Caches/Arc").path),
            ("Arc Company", lib.appendingPathComponent("Caches/company.thebrowser.Browser").path),
            ("Opera", lib.appendingPathComponent("Caches/com.operasoftware.Opera").path)
        ]
        var items: [CleanableItem] = []
        for (name, path) in paths {
            callbacks.progress(0.55, path)
            let url = URL(fileURLWithPath: path)
            if FileScanSupport.exists(path) {
                items.append(FileScanSupport.item(name: name, url: url, subtitle: "Cache only — cookies and passwords are left alone."))
            }
        }
        return CleanableCategory(name: "Browser caches", symbol: "safari", detail: "Safari, Chrome, Firefox, Edge, Brave, Arc, Opera cache folders only.", items: items)
    }

    private static func developerCaches(callbacks: ScanCallbacks) -> CleanableCategory {
        let home = FileScanSupport.home()
        var items: [CleanableItem] = []
        let map: [(String, String)] = [
            ("npm", home.appendingPathComponent(".npm/_cacache").path),
            ("yarn", home.appendingPathComponent("Library/Caches/Yarn").path),
            ("pip", home.appendingPathComponent("Library/Caches/pip").path),
            ("Gradle", home.appendingPathComponent(".gradle/caches").path),
            ("CocoaPods", home.appendingPathComponent("Library/Caches/CocoaPods").path),
            ("Cargo", home.appendingPathComponent(".cargo/registry").path)
        ]
        for (name, path) in map {
            callbacks.progress(0.65, path)
            if FileScanSupport.exists(path) {
                items.append(FileScanSupport.item(name: name, url: URL(fileURLWithPath: path)))
            }
        }
        if ProcessRunner.which("brew") != nil {
            items.append(CleanableItem(
                name: "Homebrew leftover downloads",
                path: "brew://cleanup",
                size: 0,
                subtitle: "Runs `brew cleanup -s`",
                extra: ["command": "brew cleanup -s"]
            ))
        }
        return CleanableCategory(name: "Developer caches", symbol: "chevron.left.forwardslash.chevron.right", items: items)
    }

    private static func brokenPreferences(callbacks: ScanCallbacks) -> CleanableCategory {
        let root = FileScanSupport.library().appendingPathComponent("Preferences")
        var items: [CleanableItem] = []
        for child in FileScanSupport.listChildren(of: root) where child.pathExtension == "plist" {
            if callbacks.isCancelled() { break }
            callbacks.progress(0.75, child.path)
            if let data = try? Data(contentsOf: child) {
                var format = PropertyListSerialization.PropertyListFormat.xml
                if (try? PropertyListSerialization.propertyList(from: data, options: [], format: &format)) == nil {
                    items.append(FileScanSupport.item(name: child.lastPathComponent, url: child, subtitle: "Failed to parse"))
                }
            }
        }
        return CleanableCategory(name: "Broken preferences", symbol: "exclamationmark.triangle", detail: ".plist files in ~/Library/Preferences that fail to parse.", items: items)
    }

    private static func brokenLoginItems(callbacks: ScanCallbacks) -> CleanableCategory {
        callbacks.progress(0.82, "login items")
        var items: [CleanableItem] = []
        if let result = try? ProcessRunner.run("/usr/bin/osascript", arguments: [
            "-e", "tell application \"System Events\" to get POSIX path of (path of every login item)"
        ]) {
            let paths = result.stdout.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            for path in paths where !path.isEmpty && !FileScanSupport.exists(path) {
                items.append(CleanableItem(name: (path as NSString).lastPathComponent, path: path, size: 0, subtitle: "Login item points to a missing app"))
            }
        }
        return CleanableCategory(name: "Broken login items", symbol: "person.crop.circle.badge.exclamationmark", items: items)
    }

    private static func iosBackups(callbacks: ScanCallbacks) -> CleanableCategory {
        let root = FileScanSupport.library().appendingPathComponent("Application Support/MobileSync/Backup")
        var items: [CleanableItem] = []
        for child in FileScanSupport.listChildren(of: root) {
            callbacks.progress(0.9, child.path)
            var device = child.lastPathComponent
            var date = ""
            let info = child.appendingPathComponent("Info.plist")
            if let dict = NSDictionary(contentsOf: info) {
                device = dict["Display Name"] as? String ?? dict["Device Name"] as? String ?? device
                date = dict["Last Backup Date"] as? Date != nil ? DateFormatting.short(dict["Last Backup Date"] as? Date) : (dict["Last Backup Date"] as? String ?? "")
            }
            items.append(FileScanSupport.item(
                name: device,
                url: child,
                selected: false,
                subtitle: date.isEmpty ? child.path : "Last backup: \(date)"
            ))
        }
        return CleanableCategory(
            name: "Old iOS device backups",
            symbol: "iphone",
            detail: "Off by default — these can be large and are the only local copy of an iPhone backup.",
            items: items,
            selected: false
        )
    }

    private static func ipswFiles(callbacks: ScanCallbacks) -> CleanableCategory {
        let ipswRoots = [
            FileScanSupport.home().appendingPathComponent("Library/iTunes"),
            FileScanSupport.home().appendingPathComponent("Library/Application Support/com.apple.TCC"),
            FileScanSupport.library().appendingPathComponent("iTunes/iPhone Software Updates"),
            FileScanSupport.home().appendingPathComponent("Downloads")
        ]
        var items: [CleanableItem] = []
        for root in ipswRoots {
            FileScanSupport.collect(at: root, skipPackages: true, callbacks: callbacks) { url, _ in
                if url.pathExtension.lowercased() == "ipsw" {
                    items.append(FileScanSupport.item(name: url.lastPathComponent, url: url))
                }
            }
        }
        let updates = FileScanSupport.library().appendingPathComponent("iTunes/iPad Software Updates")
        FileScanSupport.collect(at: updates, skipPackages: true, callbacks: callbacks) { url, _ in
            if url.pathExtension.lowercased() == "ipsw" {
                items.append(FileScanSupport.item(name: url.lastPathComponent, url: url))
            }
        }
        return CleanableCategory(name: "Old iOS/iPadOS software updates", symbol: "arrow.down.app", detail: ".ipsw files left from Finder/iTunes restores.", items: items)
    }

    private static func documentVersions(callbacks: ScanCallbacks) -> CleanableCategory {
        let url = FileScanSupport.home().appendingPathComponent(".DocumentRevisions-V100")
        callbacks.progress(0.97, url.path)
        var items: [CleanableItem] = []
        if FileScanSupport.exists(url.path) {
            var item = FileScanSupport.item(
                name: "Document versions (macOS managed)",
                url: url,
                selected: false,
                subtitle: "Shown for size only. macOS owns this database — MacCleaner will not delete it.",
                removable: false
            )
            item.removable = false
            item.selected = false
            items.append(item)
        }
        return CleanableCategory(
            name: "Document versions",
            symbol: "clock.arrow.2.circlepath",
            detail: "macOS keeps previous versions of documents here. Size is informational; deletion is disabled.",
            items: items,
            selected: false,
            removable: false
        )
    }
}
