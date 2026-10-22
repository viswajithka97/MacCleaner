import Foundation

/// Measuring how much disk space files and folders really use.
///
/// We use the *allocated* size (what the disk actually spends), which is what
/// Finder's "on disk" number shows and what you get back after deleting.
enum FileSize {

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]

    /// Size of a single file (not following symlinks).
    static func of(file url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    /// Size of a file or a whole folder tree. Checks `progress` for cancellation.
    static func of(_ url: URL, progress: ScanProgress? = nil) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isPackageKey])
        if values?.isSymbolicLink == true || !isDir.boolValue {
            return of(file: url)
        }
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: resourceKeys, options: [],
            errorHandler: { failedURL, error in
                PermissionCenter.noteError(error, at: failedURL)
                return true
            }) else { return 0 }

        var counter = 0
        for case let child as URL in enumerator {
            counter += 1
            if counter % 500 == 0 {
                if progress?.isCancelled == true { break }
                progress?.visit(child.path)
            }
            guard let v = try? child.resourceValues(forKeys: Set(resourceKeys)) else { continue }
            if v.isDirectory == true { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
        }
        return total
    }

    /// Lists the direct children of a folder (including hidden ones). Never throws.
    static func children(of url: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: resourceKeys, options: [])
        } catch {
            PermissionCenter.noteError(error, at: url)
            return []
        }
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Modification date of a file or folder.
    static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

extension URL {
    /// Shorthand for building paths under the home folder: `URL.home("Library/Caches")`.
    static func home(_ relative: String = "") -> URL {
        let base = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return relative.isEmpty ? base : base.appendingPathComponent(relative)
    }

    /// The path with the home folder replaced by "~" for compact display.
    var tildePath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
