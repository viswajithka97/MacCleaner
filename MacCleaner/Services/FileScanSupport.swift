import AppKit
import Foundation

struct ScanCallbacks: @unchecked Sendable {
    var progress: @Sendable (Double, String) -> Void
    var isCancelled: @Sendable () -> Bool
}

enum FileScanSupport {
    static func home() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static func library() -> URL {
        home().appendingPathComponent("Library")
    }

    /// Walks a directory, reporting the current path. Does not follow symlinks.
    static func collect(
        at root: URL,
        options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles],
        skipPackages: Bool = false,
        callbacks: ScanCallbacks,
        fileHandler: (URL, URLResourceValues) -> Void
    ) {
        if callbacks.isCancelled() { return }
        var opts = options
        if skipPackages { opts.insert(.skipsPackageDescendants) }
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .contentModificationDateKey, .contentAccessDateKey,
            .creationDateKey, .nameKey, .typeIdentifierKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: opts,
            errorHandler: { _, _ in true }
        ) else { return }

        for case let url as URL in enumerator {
            if callbacks.isCancelled() { return }
            callbacks.progress(0, url.path)
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            fileHandler(url, values)
        }
    }

    static func listChildren(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .nameKey],
            options: []
        )) ?? []
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    static func item(name: String, url: URL, selected: Bool = true, subtitle: String = "", warning: String? = nil, extra: [String: String] = [:], removable: Bool = true) -> CleanableItem {
        CleanableItem(
            name: name,
            path: url.path,
            size: FileSizing.allocatedSize(at: url),
            selected: selected,
            subtitle: subtitle.isEmpty ? url.path : subtitle,
            warning: warning,
            extra: extra,
            removable: removable
        )
    }
}

enum FullDiskAccess {
    /// Heuristic: Mail and Safari are TCC-protected. If we cannot list them, FDA is missing.
    static func isGranted() -> Bool {
        let mail = FileScanSupport.library().appendingPathComponent("Mail")
        let safari = FileScanSupport.library().appendingPathComponent("Safari")
        let mailOK = !FileScanSupport.exists(mail.path) || (try? FileManager.default.contentsOfDirectory(atPath: mail.path)) != nil
        let safariOK = !FileScanSupport.exists(safari.path) || (try? FileManager.default.contentsOfDirectory(atPath: safari.path)) != nil
        return mailOK && safariOK
    }

    static func openSystemSettings() {
        // Opens the Full Disk Access pane on modern macOS.
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ]
        for string in urls {
            if let url = URL(string: string) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
