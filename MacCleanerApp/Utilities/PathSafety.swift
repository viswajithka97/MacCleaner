import Foundation

/// The single place that decides whether a path may be touched.
///
/// Every deletion in the app goes through `PathSafety.reasonToSkip(_:)`.
/// If it returns a reason, the item is skipped and the reason is logged.
enum PathSafety {

    static let home = NSHomeDirectory()

    /// Folders whose contents must never be deleted (anything inside them).
    static var protectedPrefixes: [String] {
        [
            "/System", "/usr", "/bin", "/sbin", "/cores", "/dev",
            home + "/Library/Keychains",
            "/Library/Keychains",
            home + "/Library/Messages",
            home + "/Library/Containers/com.apple.MobileSMS",
            home + "/Library/Mobile Documents",          // iCloud Drive itself
        ]
    }

    /// Important folders that must never be deleted themselves
    /// (but some modules may delete things *inside* them).
    static var protectedExactPaths: Set<String> {
        let h = home
        return [
            "/", "/Applications", "/Library", "/Users", "/Volumes", "/private", "/private/var",
            "/private/var/log", "/var", "/etc", "/tmp", "/opt", "/Library/Logs", "/Library/Caches",
            h, h + "/Library", h + "/Desktop", h + "/Documents", h + "/Downloads", h + "/Pictures",
            h + "/Movies", h + "/Music", h + "/Applications", h + "/Library/Caches", h + "/Library/Logs",
            h + "/Library/Preferences", h + "/Library/Application Support", h + "/Library/Containers",
            h + "/Library/Group Containers", h + "/.Trash", h + "/Library/Mail",
        ]
    }

    /// Where Homebrew installs packages. These are only ever changed through `brew` itself.
    static let homebrewPrefixes = ["/opt/homebrew", "/usr/local/Cellar", "/usr/local/Caskroom",
                                   "/usr/local/Homebrew", "/usr/local/opt", "/usr/local/bin", "/usr/local/lib"]

    static func isHomebrewPath(_ path: String) -> Bool {
        homebrewPrefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// True for installed software: an app bundle in /Applications or ~/Applications
    /// (or anything inside one), or a Homebrew-installed package.
    static func isInstalledSoftware(_ path: String) -> Bool {
        if isHomebrewPath(path) { return true }
        for root in ["/Applications/", home + "/Applications/"] where path.hasPrefix(root) {
            if path.contains(".app") { return true }
        }
        return false
    }

    /// Returns a human readable reason why `url` must NOT be deleted, or nil if it is safe.
    static func reasonToSkip(_ url: URL, exclusions: [String] = SettingsStore.snapshot().exclusions) -> String? {
        let path = url.standardizedFileURL.path
        // Resolve symlinks of the *parent* so /var/log -> /private/var/log is checked properly,
        // while still allowing a symlink itself to be removed.
        let parentResolved = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        let resolved = (parentResolved as NSString).appendingPathComponent(url.lastPathComponent)

        for candidate in Set([path, resolved]) {
            if isHomebrewPath(candidate) {
                return "Installed by Homebrew — use `brew uninstall` to remove it"
            }
            if protectedExactPaths.contains(candidate) {
                return "Protected system folder"
            }
            for prefix in protectedPrefixes where candidate == prefix || candidate.hasPrefix(prefix + "/") {
                return "Inside a protected location (\(prefix))"
            }
            // Photos libraries may only be changed through PhotoKit.
            if candidate.split(separator: "/").contains(where: { $0.hasSuffix(".photoslibrary") }) {
                return "Photos libraries are only modified through the Photos app"
            }
            if let reason = mailReason(candidate) { return reason }
            if candidate == Bundle.main.bundlePath || candidate.hasPrefix(Bundle.main.bundlePath + "/") {
                return "MacCleaner never removes itself"
            }
        }

        if isExcluded(path, exclusions: exclusions) || isExcluded(resolved, exclusions: exclusions) {
            return "On your exclusion list"
        }
        return nil
    }

    /// Mail message files are off-limits; only downloaded attachment copies may go.
    private static func mailReason(_ path: String) -> String? {
        let mailRoot = home + "/Library/Mail/"
        guard path.hasPrefix(mailRoot) else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "emlx" || ext == "mbox" || ext == "eml" { return "Mail message files are never deleted" }
        if path.contains("/Attachments/") { return nil }
        return "Only downloaded Mail attachments may be removed"
    }

    /// True if the path is on (or inside) the exclusion list, or if an excluded
    /// path lives inside it (deleting the parent would delete the excluded item).
    static func isExcluded(_ path: String, exclusions: [String]) -> Bool {
        for raw in exclusions {
            let ex = (raw as NSString).expandingTildeInPath
            guard !ex.isEmpty else { continue }
            if path == ex || path.hasPrefix(ex + "/") || ex.hasPrefix(path + "/") { return true }
        }
        // Excluded apps: also protect their data folders (named after the bundle ID).
        for bundleID in excludedBundleIDs(exclusions) where path.localizedCaseInsensitiveContains(bundleID) {
            return true
        }
        return false
    }

    /// Bundle identifiers of any .app bundles on the exclusion list.
    static func excludedBundleIDs(_ exclusions: [String]) -> [String] {
        exclusions.compactMap { raw in
            let path = (raw as NSString).expandingTildeInPath
            guard path.hasSuffix(".app") else { return nil }
            return Bundle(path: path)?.bundleIdentifier
        }
    }
}
