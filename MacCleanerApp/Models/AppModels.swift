import Foundation

/// An application found in /Applications or ~/Applications.
struct InstalledApp: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var name: String
    var bundleID: String
    var version: String
    var buildVersion: String
    var size: Int64?
    var lastOpened: Date?
    var isAppStore: Bool
    var isApple: Bool

    var source: String { isAppStore ? "App Store" : (isApple ? "Apple" : "Other") }

    /// True if MacCleaner must refuse to uninstall it.
    var isProtected: Bool {
        isApple || bundleID.hasPrefix("com.apple.") || bundleID == Bundle.main.bundleIdentifier
    }
}

/// Where an update comes from and how to install it.
enum UpdateSource: Hashable {
    case sparkle(downloadURL: URL?)
    case appStore(pageURL: URL)
    case homebrew(cask: String)

    var label: String {
        switch self {
        case .sparkle: return "Sparkle"
        case .appStore: return "App Store"
        case .homebrew: return "Homebrew"
        }
    }
}

/// An available update for one app.
struct AppUpdate: Identifiable, Hashable {
    var id: String { appName + source.label }
    var appName: String
    var bundleID: String?
    var appURL: URL?
    var currentVersion: String
    var newVersion: String
    var releaseNotes: String
    var source: UpdateSource
}

/// One entry in the cleanup history.
struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var module: String
    var itemsRemoved: Int
    var bytesFreed: Int64
    var details: [String]
}

/// A login item (an app that opens when you log in).
struct LoginItem: Identifiable, Hashable {
    var id: String { name + path }
    var name: String
    var path: String
    var hidden: Bool
    var enabled: Bool
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

/// A launchd job: launch agents (per user) and daemons (system wide).
struct LaunchItem: Identifiable, Hashable {
    enum Domain: String { case user = "User agent", globalAgent = "Global agent", daemon = "System daemon" }

    var id: String { plist.path }
    var label: String
    var plist: URL
    var program: String?
    var domain: Domain
    var signer: String
    var isDisabled: Bool
    var isLoaded: Bool

    var isSystem: Bool { domain != .user }
}

/// A row in the "Heavy consumers" table.
struct ProcessSample: Identifiable, Hashable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var cpu: Double
    var memoryBytes: Int64
    var user: String
}
