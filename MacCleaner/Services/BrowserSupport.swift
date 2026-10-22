import AppKit
import Foundation

struct BrowserApp: Identifiable, Hashable {
    var id: String { bundleId }
    var name: String
    var bundleId: String
    var supportFolder: URL
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }
}

enum BrowserKind: String, CaseIterable, Identifiable {
    case safari, chrome, firefox, edge, brave, arc, opera
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .edge: return "Edge"
        case .brave: return "Brave"
        case .arc: return "Arc"
        case .opera: return "Opera"
        }
    }

    var bundleId: String {
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

    func supportRoot() -> URL {
        let lib = FileScanSupport.library()
        switch self {
        case .safari: return lib.appendingPathComponent("Safari")
        case .chrome: return lib.appendingPathComponent("Application Support/Google/Chrome")
        case .firefox: return lib.appendingPathComponent("Application Support/Firefox")
        case .edge: return lib.appendingPathComponent("Application Support/Microsoft Edge")
        case .brave: return lib.appendingPathComponent("Application Support/BraveSoftware/Brave-Browser")
        case .arc: return lib.appendingPathComponent("Application Support/Arc/User Data")
        case .opera: return lib.appendingPathComponent("Application Support/com.operasoftware.Opera")
        }
    }

    func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil || FileScanSupport.exists(supportRoot().path)
    }

    func quit() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleId) {
            app.terminate()
        }
    }
}

enum PrivacyCategoryKind: String, CaseIterable, Identifiable {
    case history, downloads, cookies, autofill, cache, passwords
    var id: String { rawValue }
    var title: String {
        switch self {
        case .history: return "Browsing history"
        case .downloads: return "Download history"
        case .cookies: return "Cookies"
        case .autofill: return "Autofill form data"
        case .cache: return "Cached images"
        case .passwords: return "Saved passwords"
        }
    }
}

enum BrowserSupport {
    static func chromiumProfile(_ kind: BrowserKind) -> URL {
        switch kind {
        case .chrome, .edge, .brave, .opera:
            return kind.supportRoot().appendingPathComponent("Default")
        case .arc:
            return kind.supportRoot().appendingPathComponent("Default")
        default:
            return kind.supportRoot()
        }
    }

    static func paths(for kind: BrowserKind, category: PrivacyCategoryKind) -> [URL] {
        let lib = FileScanSupport.library()
        switch kind {
        case .safari:
            switch category {
            case .history: return [lib.appendingPathComponent("Safari/History.db"), lib.appendingPathComponent("Safari/History.db-wal")]
            case .downloads: return [lib.appendingPathComponent("Safari/Downloads.plist")]
            case .cookies: return [lib.appendingPathComponent("Cookies/Cookies.binarycookies")]
            case .autofill: return [lib.appendingPathComponent("Safari/Form Values")]
            case .cache: return [lib.appendingPathComponent("Caches/com.apple.Safari")]
            case .passwords: return [] // Safari passwords live in Keychain — we refuse.
            }
        case .firefox:
            let profiles = kind.supportRoot().appendingPathComponent("Profiles")
            let dirs = FileScanSupport.listChildren(of: profiles)
            switch category {
            case .history: return dirs.map { $0.appendingPathComponent("places.sqlite") }
            case .downloads: return dirs.map { $0.appendingPathComponent("downloads.sqlite") }
            case .cookies: return dirs.map { $0.appendingPathComponent("cookies.sqlite") }
            case .autofill: return dirs.map { $0.appendingPathComponent("formhistory.sqlite") }
            case .cache: return [lib.appendingPathComponent("Caches/Firefox")]
            case .passwords: return dirs.map { $0.appendingPathComponent("logins.json") } + dirs.map { $0.appendingPathComponent("key4.db") }
            }
        default:
            let profile = chromiumProfile(kind)
            switch category {
            case .history: return [profile.appendingPathComponent("History")]
            case .downloads: return [profile.appendingPathComponent("History")] // same Chromium DB; we still offer it
            case .cookies: return [profile.appendingPathComponent("Cookies"), profile.appendingPathComponent("Network/Cookies")]
            case .autofill: return [profile.appendingPathComponent("Web Data")]
            case .cache: return [
                profile.appendingPathComponent("Cache"),
                profile.appendingPathComponent("Code Cache"),
                profile.appendingPathComponent("GPUCache"),
                kind.supportRoot().deletingLastPathComponent().appendingPathComponent("../../Caches").standardizedFileURL
            ]
            case .passwords: return [profile.appendingPathComponent("Login Data")]
            }
        }
    }
}
