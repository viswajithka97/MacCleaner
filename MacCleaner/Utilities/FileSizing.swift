import Foundation

enum FileSizing {
    /// Allocated size on disk (the number that actually frees space when deleted).
    static func allocatedSize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .isDirectoryKey,
            .isSymbolicLinkKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory == true {
            return directoryAllocatedSize(at: url)
        }
        if let total = values.totalFileAllocatedSize { return Int64(total) }
        if let allocated = values.fileAllocatedSize { return Int64(allocated) }
        return 0
    }

    static func directoryAllocatedSize(at url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true {
                if let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    static func contentsAllocatedSize(at directory: URL, skippingFolderItself: Bool = true) -> (Int64, [URL]) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return (0, [])
        }
        var size: Int64 = 0
        var urls: [URL] = []
        for child in children {
            size += allocatedSize(at: child)
            urls.append(child)
        }
        return (size, urls)
    }
}
