import Foundation

/// Hard rules that apply to every module before a delete or shred.
enum PathSafety {
    static let forbiddenPrefixes = [
        "/System",
        "/usr",
        "/bin",
        "/sbin"
    ]

    static func isForbidden(_ path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        for prefix in forbiddenPrefixes {
            if standardized == prefix || standardized.hasPrefix(prefix + "/") {
                return true
            }
        }
        let lower = standardized.lowercased()
        if lower.contains("/library/keychains") { return true }
        if lower.contains("/library/messages") { return true }
        if lower.hasSuffix(".photoslibrary") || lower.contains(".photoslibrary/") { return true }
        // Mail message bodies — never delete these as loose files.
        if lower.contains("/library/mail/") && (lower.hasSuffix(".emlx") || lower.hasSuffix(".emlxpart") || lower.hasSuffix(".partial.emlx")) {
            return true
        }
        if lower.contains("/library/mail/") && lower.contains("/maildata/envelope index") {
            return true
        }
        return false
    }

    static func isOurOwnApp(_ path: String) -> Bool {
        let own = Bundle.main.bundlePath
        return (path as NSString).standardizingPath.hasPrefix((own as NSString).standardizingPath)
    }

    static func isAppleSystemApp(bundleId: String?, path: String) -> Bool {
        if let bundleId, bundleId.hasPrefix("com.apple.") {
            if path.hasPrefix("/System/") || path.hasPrefix("/System/Applications/") || path.hasPrefix("/Applications/Safari.app") {
                return true
            }
            // Built-in apps that live in /Applications still must not be uninstalled.
            let protectedNames = [
                "Safari.app", "Mail.app", "Photos.app", "Music.app", "TV.app", "Books.app",
                "Maps.app", "Notes.app", "Calendar.app", "Contacts.app", "Reminders.app",
                "Freeform.app", "Preview.app", "TextEdit.app", "Time Machine.app",
                "System Settings.app", "System Preferences.app", "Terminal.app",
                "Utilities", "App Store.app", "FindMy.app", "FaceTime.app", "Messages.app"
            ]
            if protectedNames.contains(where: { path.contains($0) }) { return true }
        }
        return path.hasPrefix("/System/")
    }
}
