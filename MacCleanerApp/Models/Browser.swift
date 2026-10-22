import AppKit

/// The browser engine decides where data lives and how to clear it.
enum BrowserEngine {
    case webkit, chromium, firefox
}

/// Every browser MacCleaner knows about.
enum BrowserID: String, CaseIterable, Identifiable, Codable {
    case safari, chrome, firefox, edge, brave, arc, opera

    var id: String { rawValue }

    var name: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .firefox: return "Firefox"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave"
        case .arc: return "Arc"
        case .opera: return "Opera"
        }
    }

    var bundleID: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .firefox: return "org.mozilla.firefox"
        case .edge: return "com.microsoft.edgemac"
        case .brave: return "com.brave.Browser"
        case .arc: return "company.thebrowser.Browser"
        case .opera: return "com.operasoftware.Opera"
        }
    }

    var engine: BrowserEngine {
        switch self {
        case .safari: return .webkit
        case .firefox: return .firefox
        default: return .chromium
        }
    }

    /// Where the browser keeps profiles (Chromium & Firefox).
    var dataRoot: URL {
        switch self {
        case .safari: return .home("Library/Safari")
        case .chrome: return .home("Library/Application Support/Google/Chrome")
        case .firefox: return .home("Library/Application Support/Firefox/Profiles")
        case .edge: return .home("Library/Application Support/Microsoft Edge")
        case .brave: return .home("Library/Application Support/BraveSoftware/Brave-Browser")
        case .arc: return .home("Library/Application Support/Arc/User Data")
        case .opera: return .home("Library/Application Support/com.operasoftware.Opera")
        }
    }

    /// Top-level cache folders (contents are safe to delete).
    var cacheRoots: [URL] {
        switch self {
        case .safari:
            return [.home("Library/Caches/com.apple.Safari"),
                    .home("Library/Containers/com.apple.Safari/Data/Library/Caches")]
        case .chrome: return [.home("Library/Caches/Google/Chrome")]
        case .firefox: return [.home("Library/Caches/Firefox/Profiles")]
        case .edge: return [.home("Library/Caches/Microsoft Edge")]
        case .brave: return [.home("Library/Caches/BraveSoftware/Brave-Browser")]
        case .arc: return [.home("Library/Caches/Arc"), .home("Library/Caches/company.thebrowser.Browser")]
        case .opera: return [.home("Library/Caches/com.operasoftware.Opera")]
        }
    }

    /// The app on disk, if installed.
    var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var isInstalled: Bool { appURL != nil || FileManager.default.fileExists(atPath: dataRoot.path) }

    var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    var isRunning: Bool { runningApp != nil }

    /// Profile folders. Chromium: any folder with a "Preferences" file; Firefox: every profile folder.
    var profiles: [URL] {
        let fm = FileManager.default
        switch engine {
        case .webkit:
            return [dataRoot]
        case .firefox:
            return FileSize.children(of: dataRoot).filter { FileSize.isDirectory($0) }
        case .chromium:
            var result: [URL] = []
            if fm.fileExists(atPath: dataRoot.appendingPathComponent("Preferences").path) {
                result.append(dataRoot)     // Opera keeps its single profile at the root
            }
            for child in FileSize.children(of: dataRoot) where FileSize.isDirectory(child) {
                if fm.fileExists(atPath: child.appendingPathComponent("Preferences").path) {
                    result.append(child)
                }
            }
            return result
        }
    }
}

/// The kinds of browsing data the Privacy module can clear.
enum BrowserDataKind: String, CaseIterable, Identifiable {
    case history, downloads, cookies, autofill, cache, passwords

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "Browsing history"
        case .downloads: return "Download history"
        case .cookies: return "Cookies"
        case .autofill: return "Autofill form data"
        case .cache: return "Cached images and files"
        case .passwords: return "Saved passwords"
        }
    }

    var symbol: String {
        switch self {
        case .history: return "clock"
        case .downloads: return "arrow.down.circle"
        case .cookies: return "circle.grid.cross"
        case .autofill: return "text.cursor"
        case .cache: return "photo.stack"
        case .passwords: return "key"
        }
    }
}

/// The "recent items" lists macOS keeps.
enum RecentItemsKind: String, CaseIterable, Identifiable {
    case documents, applications, servers, finder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documents: return "Recent documents"
        case .applications: return "Recent applications"
        case .servers: return "Recent servers"
        case .finder: return "Finder recent folders & Go to Folder history"
        }
    }
}
