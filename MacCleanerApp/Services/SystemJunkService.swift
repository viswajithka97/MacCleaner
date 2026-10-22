import AppKit

/// Finds system junk: caches, logs, unused languages, developer junk and more.
enum SystemJunkService {

    static func scan(progress: ScanProgress) -> [CleanCategory] {
        let steps: [(String, (ScanProgress) -> CleanCategory?)] = [
            ("User cache files", userCaches),
            ("User log files", userLogs),
            ("System log files", systemLogs),
            ("Language files", languageFiles),
            ("Xcode junk", xcodeJunk),
            ("Browser caches", browserCaches),
            ("Developer caches", developerCaches),
            ("Broken preferences", brokenPreferences),
            ("Broken login items", brokenLoginItems),
            ("iOS device backups", iosBackups),
            ("iOS software updates", iosUpdates),
            ("Document versions", documentVersions),
        ]
        var categories: [CleanCategory] = []
        for (index, step) in steps.enumerated() {
            if progress.isCancelled { break }
            progress.step(index, of: steps.count, "Scanning \(step.0.lowercased())…")
            if let category = step.1(progress), !category.items.isEmpty {
                categories.append(category.applyingDefaults())
            }
        }
        progress.setFraction(1)
        return categories
    }

    // MARK: - Caches & logs

    /// Cache folders handled elsewhere or unsafe to empty (iCloud sync state, downloads in progress).
    private static let skippedCacheNames: Set<String> = [
        "CloudKit", "com.apple.bird", "com.apple.cloudd", "com.apple.nsurlsessiond", "FamilyCircle",
        "com.apple.Safari", "Homebrew", "pip", "Yarn", "CocoaPods", "Google", "Firefox", "Microsoft Edge",
        "BraveSoftware", "Arc", "company.thebrowser.Browser", "com.operasoftware.Opera",
        "com.apple.containermanagerd", "com.apple.akd", "com.apple.ap.adprivacyd",
        // Not caches: developer tools keep installed browsers, binaries and environments here.
        "ms-playwright", "ms-playwright-go", "Cypress", "pypoetry", "pnpm", "puppeteer", "camoufox",
    ]

    private static func folderItems(in root: URL, skip: Set<String> = [], progress: ScanProgress) -> [CleanItem] {
        var items: [CleanItem] = []
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        for child in FileSize.children(of: root) {
            if progress.isCancelled { break }
            let name = child.lastPathComponent
            if skip.contains(name) || name == ".DS_Store" { continue }
            if PathSafety.reasonToSkip(child) != nil { continue }
            progress.visit(child.path)
            let size = FileSize.of(child, progress: progress)
            guard size > 0 else { continue }
            let isDir = FileSize.isDirectory(child)
            items.append(CleanItem(name: name, url: child, size: size,
                                   subtitle: isDir ? "Folder contents" : "File",
                                   date: FileSize.modified(child),
                                   warning: running.contains(name.lowercased()) ? "App is running — some files may be recreated" : nil,
                                   symbol: isDir ? "folder" : "doc",
                                   action: isDir ? .removeContents(child) : .remove(child)))
        }
        return items.sorted { $0.size > $1.size }
    }

    static func userCaches(_ progress: ScanProgress) -> CleanCategory? {
        CleanCategory(id: "user-caches", title: "User Cache Files", symbol: "archivebox",
                      summary: "Temporary files apps keep to work faster. Apps recreate what they need.",
                      items: folderItems(in: .home("Library/Caches"), skip: skippedCacheNames, progress: progress),
                      note: "Only the contents are deleted; each app's cache folder is kept.")
    }

    static func userLogs(_ progress: ScanProgress) -> CleanCategory? {
        CleanCategory(id: "user-logs", title: "User Log Files", symbol: "doc.text",
                      summary: "Activity records written by apps you use.",
                      items: folderItems(in: .home("Library/Logs"), progress: progress))
    }

    static func systemLogs(_ progress: ScanProgress) -> CleanCategory? {
        var items: [CleanItem] = []
        // /Library/Logs: empty each folder; /private/var/log: only plain/rotated log files.
        for child in FileSize.children(of: URL(fileURLWithPath: "/Library/Logs")) {
            progress.visit(child.path)
            let size = FileSize.of(child, progress: progress)
            guard size > 0 else { continue }
            if FileSize.isDirectory(child) {
                let command = ShellCommand(executable: "/usr/bin/find", arguments: [child.path, "-mindepth", "1", "-delete"],
                                           requiresAdmin: true,
                                           explanation: "Delete system log files in /Library/Logs and /private/var/log. These belong to the system, so administrator rights are needed. macOS creates new logs as needed.")
                items.append(CleanItem(name: child.lastPathComponent, url: child, size: size, subtitle: "/Library/Logs",
                                       symbol: "folder", action: .command(command)))
            } else {
                items.append(CleanItem(name: child.lastPathComponent, url: child, size: size, subtitle: "/Library/Logs",
                                       symbol: "doc.text", action: .adminRemove(child)))
            }
        }
        let logPattern = #"(\.log|\.gz|\.bz2|\.asl|\.old|\.out|\.\d+)$"#
        if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: "/private/var/log"),
                                                           includingPropertiesForKeys: FileSize.resourceKeys) {
            for case let file as URL in enumerator {
                if progress.isCancelled { break }
                guard !FileSize.isDirectory(file),
                      file.lastPathComponent.range(of: logPattern, options: .regularExpression) != nil else { continue }
                progress.visit(file.path)
                let size = FileSize.of(file: file)
                guard size > 0 else { continue }
                items.append(CleanItem(name: file.lastPathComponent, url: file, size: size, subtitle: file.deletingLastPathComponent().path,
                                       date: FileSize.modified(file), symbol: "doc.text", action: .adminRemove(file)))
            }
        }
        return CleanCategory(id: "system-logs", title: "System Log Files", symbol: "doc.text.magnifyingglass",
                             summary: "Logs written by macOS services.", items: items.sorted { $0.size > $1.size },
                             note: "Requires your administrator password. Deleted permanently.")
    }

    // MARK: - Languages

    /// Language codes to keep: English, Base, and every language in your system preferences.
    static func keptLanguages() -> Set<String> {
        var keep: Set<String> = ["en", "base", "english"]
        for identifier in Locale.preferredLanguages {
            let lower = identifier.lowercased().replacingOccurrences(of: "-", with: "_")
            keep.insert(lower)
            if let base = lower.split(separator: "_").first { keep.insert(String(base)) }
            // Script variants such as zh_hans
            let parts = lower.split(separator: "_")
            if parts.count >= 2 { keep.insert(parts[0] + "_" + parts[1]) }
        }
        let legacyNames = ["en": "english", "ja": "japanese", "fr": "french", "de": "german",
                           "es": "spanish", "it": "italian", "nl": "dutch"]
        for (code, name) in legacyNames where keep.contains(code) { keep.insert(name) }
        return keep
    }

    static func isKept(_ lproj: String, keep: Set<String>) -> Bool {
        let name = (lproj as NSString).deletingPathExtension.lowercased().replacingOccurrences(of: "-", with: "_")
        if keep.contains(name) { return true }
        if let base = name.split(separator: "_").first, keep.contains(String(base)) {
            // "pt_BR" is kept only if pt or pt_BR is preferred; "en_GB" is kept because en is.
            return true
        }
        return false
    }

    static func languageFiles(_ progress: ScanProgress) -> CleanCategory? {
        let keep = keptLanguages()
        var items: [CleanItem] = []
        var skippedSigned = 0
        for app in AppCatalog.appBundles() {
            if progress.isCancelled { break }
            progress.visit(app.path)
            if FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/_MASReceipt").path) {
                skippedSigned += 1; continue
            }
            let signature = CodeSign.check(path: app.path, fast: true)
            // Removing files from a signed app breaks its seal, so only unsigned apps are touched.
            if signature.isApple || signature.status != .unsigned { skippedSigned += 1; continue }
            guard FileManager.default.isWritableFile(atPath: app.path) else { continue }
            var urls: [URL] = []
            var size: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isDirectoryKey]) {
                for case let url as URL in enumerator where url.pathExtension == "lproj" {
                    enumerator.skipDescendants()
                    if isKept(url.lastPathComponent, keep: keep) { continue }
                    urls.append(url)
                    size += FileSize.of(url)
                }
            }
            if !urls.isEmpty {
                items.append(CleanItem(name: app.deletingPathExtension().lastPathComponent, url: app, size: size,
                                       subtitle: "\(urls.count) unused language(s): " + urls.prefix(6).map { $0.deletingPathExtension().lastPathComponent }.joined(separator: ", "),
                                       symbol: "character.bubble", action: .removeMany(urls)))
            }
        }
        return CleanCategory(id: "languages", title: "Language Files", symbol: "globe",
                             summary: "Translations for languages you don't use. English, Base and your system languages are kept.",
                             items: items.sorted { $0.size > $1.size },
                             warning: "Removing languages from third-party apps can break their auto-updates; reinstall the app if an update fails.",
                             note: "\(skippedSigned) app(s) were skipped because they're signed by Apple, from the App Store, or removing files would break their code signature.")
    }

    // MARK: - Developer

    static func xcodeJunk(_ progress: ScanProgress) -> CleanCategory? {
        let dev = URL.home("Library/Developer")
        var items: [CleanItem] = []
        func add(_ url: URL, _ name: String, selected: Bool = true, warning: String? = nil) {
            progress.visit(url.path)
            let size = FileSize.of(url, progress: progress)
            guard size > 0 else { return }
            items.append(CleanItem(name: name, url: url, size: size, isSelected: selected, warning: warning,
                                   symbol: "hammer", action: .removeContents(url)))
        }
        add(dev.appendingPathComponent("Xcode/DerivedData"), "Derived Data")
        add(dev.appendingPathComponent("Xcode/Archives"), "Archives", selected: false,
            warning: "Archives are needed to symbolicate crash reports of builds you shipped.")
        for platform in ["iOS", "watchOS", "tvOS", "visionOS"] {
            add(dev.appendingPathComponent("Xcode/\(platform) DeviceSupport"), "\(platform) Device Support")
        }
        add(dev.appendingPathComponent("CoreSimulator/Caches"), "Simulator caches")

        if FileManager.default.fileExists(atPath: "/usr/bin/xcrun"),
           Shell.run("/usr/bin/xcode-select", ["-p"], timeout: 10).succeeded {
            let list = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"], timeout: 60)
            if let json = try? JSONSerialization.jsonObject(with: Data(list.output.utf8)) as? [String: Any],
               let devices = json["devices"] as? [String: [[String: Any]]] {
                let udids = devices.values.flatMap { $0 }.compactMap { $0["udid"] as? String }
                if !udids.isEmpty {
                    let size = udids.reduce(Int64(0)) { $0 + FileSize.of(dev.appendingPathComponent("CoreSimulator/Devices/\($1)")) }
                    let command = ShellCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"],
                                               explanation: "Delete simulators whose runtime is no longer installed.")
                    items.append(CleanItem(name: "\(udids.count) unavailable simulator(s)", url: nil, size: size,
                                           subtitle: "xcrun simctl delete unavailable", symbol: "iphone", action: .command(command)))
                }
            }
        }
        return CleanCategory(id: "xcode", title: "Xcode Junk", symbol: "hammer",
                             summary: "Build products, device symbols and simulator leftovers.", items: items)
    }

    static func browserCaches(_ progress: ScanProgress) -> CleanCategory? {
        var items: [CleanItem] = []
        for browser in BrowserID.allCases {
            for root in browser.cacheRoots where FileSize.exists(root) {
                progress.visit(root.path)
                let size = FileSize.of(root, progress: progress)
                guard size > 0 else { continue }
                items.append(CleanItem(name: browser.name, url: root, size: size,
                                       warning: browser.isRunning ? "\(browser.name) is running — quit it for the best result" : nil,
                                       symbol: "globe", action: .removeContents(root)))
            }
        }
        return CleanCategory(id: "browser-caches", title: "Browser Caches", symbol: "safari",
                             summary: "Cached web pages and images. History, cookies and passwords are not touched.", items: items)
    }

    static func developerCaches(_ progress: ScanProgress) -> CleanCategory? {
        var items: [CleanItem] = []
        func add(_ url: URL, _ name: String) {
            guard FileSize.exists(url) else { return }
            progress.visit(url.path)
            let size = FileSize.of(url, progress: progress)
            guard size > 0 else { return }
            items.append(CleanItem(name: name, url: url, size: size, symbol: "shippingbox", action: .removeContents(url)))
        }
        add(.home(".npm/_cacache"), "npm cache")
        add(.home("Library/Caches/Yarn"), "Yarn cache")
        add(.home("Library/Caches/pip"), "pip cache")
        add(.home(".gradle/caches"), "Gradle caches")
        add(.home("Library/Caches/CocoaPods"), "CocoaPods cache")
        add(.home(".cargo/registry/cache"), "Cargo registry cache")
        if let brew = Shell.which("brew") {
            let cacheDir = Shell.run(brew, ["--cache"], environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cache = cacheDir.isEmpty ? URL.home("Library/Caches/Homebrew") : URL(fileURLWithPath: cacheDir)
            let size = FileSize.of(cache, progress: progress)
            let command = ShellCommand(executable: brew, arguments: ["cleanup", "--prune=all"],
                                       explanation: "Remove old Homebrew downloads and outdated versions.",
                                       environment: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"])
            items.append(CleanItem(name: "Homebrew (brew cleanup)", url: cache, size: size, symbol: "mug", action: .command(command)))
        }
        return CleanCategory(id: "dev-caches", title: "Developer Caches", symbol: "terminal",
                             summary: "Package manager downloads that are fetched again when needed.", items: items)
    }

    // MARK: - Broken things

    static func brokenPreferences(_ progress: ScanProgress) -> CleanCategory? {
        var items: [CleanItem] = []
        for file in FileSize.children(of: .home("Library/Preferences")) where file.pathExtension == "plist" {
            progress.visit(file.path)
            guard let data = try? Data(contentsOf: file) else { continue }   // unreadable is not "broken"
            if (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil {
                items.append(CleanItem(name: file.lastPathComponent, url: file, size: FileSize.of(file: file),
                                       subtitle: "Can't be read as a property list", date: FileSize.modified(file),
                                       symbol: "exclamationmark.triangle", action: .remove(file)))
            }
        }
        return CleanCategory(id: "broken-prefs", title: "Broken Preferences", symbol: "wrench",
                             summary: "Damaged settings files. Apps create fresh ones with default settings.", items: items)
    }

    static func brokenLoginItems(_ progress: ScanProgress) -> CleanCategory? {
        let items = LoginItemsService.brokenItems().map { item in
            CleanItem(name: item.name, url: URL(fileURLWithPath: item.path), size: 0,
                      subtitle: "App not found: \(item.path)", symbol: "person.crop.circle.badge.xmark",
                      action: .removeLoginItem(name: item.name, path: item.path))
        }
        return CleanCategory(id: "broken-login", title: "Broken Login Items", symbol: "person.crop.circle.badge.xmark",
                             summary: "Login items pointing to apps that no longer exist.", items: items)
    }

    // MARK: - iOS

    static func iosBackups(_ progress: ScanProgress) -> CleanCategory? {
        var items: [CleanItem] = []
        for backup in FileSize.children(of: .home("Library/Application Support/MobileSync/Backup")) where FileSize.isDirectory(backup) {
            progress.visit(backup.path)
            let info = NSDictionary(contentsOf: backup.appendingPathComponent("Info.plist")) as? [String: Any]
            let device = info?["Device Name"] as? String ?? info?["Display Name"] as? String ?? backup.lastPathComponent
            let date = info?["Last Backup Date"] as? Date ?? FileSize.modified(backup)
            let product = info?["Product Type"] as? String
            items.append(CleanItem(name: device, url: backup, size: FileSize.of(backup, progress: progress),
                                   subtitle: [product, "Backed up \(ByteFormat.date(date))"].compactMap { $0 }.joined(separator: " · "),
                                   date: date, symbol: "iphone", action: .remove(backup)))
        }
        return CleanCategory(id: "ios-backups", title: "Old iOS Device Backups", symbol: "iphone",
                             summary: "Local backups of iPhones and iPads made with Finder.", items: items,
                             warning: "Removing a backup means you can't restore that device from it.",
                             offByDefault: true)
    }

    static func iosUpdates(_ progress: ScanProgress) -> CleanCategory? {
        var items: [CleanItem] = []
        let folders = ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"].map { URL.home("Library/iTunes/\($0)") }
            + [URL.home("Downloads")]
        for folder in folders {
            for file in FileSize.children(of: folder) where file.pathExtension.lowercased() == "ipsw" {
                progress.visit(file.path)
                items.append(CleanItem(name: file.lastPathComponent, url: file, size: FileSize.of(file: file),
                                       date: FileSize.modified(file), symbol: "arrow.down.circle", action: .remove(file)))
            }
        }
        return CleanCategory(id: "ipsw", title: "iOS Software Updates", symbol: "arrow.down.app",
                             summary: "Downloaded iOS/iPadOS firmware (.ipsw) files.", items: items)
    }

    static func documentVersions(_ progress: ScanProgress) -> CleanCategory? {
        let url = URL(fileURLWithPath: "/.DocumentRevisions-V100")
        progress.visit(url.path)
        let size = FileSize.of(url, progress: progress)
        let item = CleanItem(name: "Document versions", url: url, size: size, isSelected: false,
                             subtitle: size > 0 ? "Managed by macOS" : "Size not readable without Full Disk Access",
                             symbol: "clock.arrow.circlepath", action: .none)
        return CleanCategory(id: "versions", title: "Document Versions", symbol: "doc.on.doc",
                             summary: "Earlier versions of documents saved by apps like Pages and Preview.",
                             items: [item],
                             note: "macOS manages this storage itself and removes old versions when space is needed. Shown for information only.",
                             infoOnly: true)
    }
}
