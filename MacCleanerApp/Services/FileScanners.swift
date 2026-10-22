import Foundation
import UniformTypeIdentifiers

// MARK: - Space Lens

/// One file or folder in the Space Lens tree.
final class SpaceNode: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    var size: Int64
    let isDirectory: Bool
    var children: [SpaceNode]
    weak var parent: SpaceNode?
    /// "N smaller items" placeholder that can't be opened or deleted.
    var isAggregate = false

    init(url: URL, name: String, size: Int64, isDirectory: Bool, children: [SpaceNode] = []) {
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
    }

    var canDrillDown: Bool { isDirectory && !isAggregate && !children.isEmpty }
}

enum SpaceLensService {
    /// Children kept per folder; the rest are grouped into one "smaller items" node.
    private static let maxChildren = 150

    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
                                                    .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .volumeIdentifierKey]

    static func scan(_ root: URL, progress: ScanProgress) -> SpaceNode {
        let topLevel = FileSize.children(of: root)
        let rootNode = SpaceNode(url: root, name: FileManager.default.displayName(atPath: root.path), size: 0, isDirectory: true)
        let rootVolume = (try? root.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        var children: [SpaceNode] = []
        for (index, child) in topLevel.enumerated() {
            if progress.isCancelled { break }
            progress.setFraction(Double(index) / Double(max(1, topLevel.count)))
            if root.path == "/" && ["/System/Volumes", "/Volumes", "/dev", "/private/var/vm"].contains(child.path) { continue }
            if let node = build(child, rootVolume: rootVolume, progress: progress) { children.append(node) }
        }
        finalize(rootNode, children: children)
        progress.setFraction(1)
        return rootNode
    }

    private static func build(_ url: URL, rootVolume: NSObject?, progress: ScanProgress) -> SpaceNode? {
        guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else { return nil }
        progress.visit(url.path)
        let name = url.lastPathComponent
        if values.isDirectory == true {
            // Don't cross into other volumes (e.g. mounted drives under the folder).
            if let rootVolume, let volume = values.volumeIdentifier as? NSObject, !volume.isEqual(rootVolume) { return nil }
            if values.isPackage == true {
                return SpaceNode(url: url, name: name, size: FileSize.of(url, progress: progress), isDirectory: false)
            }
            let node = SpaceNode(url: url, name: name, size: 0, isDirectory: true)
            var children: [SpaceNode] = []
            for child in FileSize.children(of: url) {
                if progress.isCancelled { break }
                if let childNode = build(child, rootVolume: rootVolume, progress: progress) { children.append(childNode) }
            }
            finalize(node, children: children)
            return node
        }
        let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        return SpaceNode(url: url, name: name, size: size, isDirectory: false)
    }

    private static func finalize(_ node: SpaceNode, children: [SpaceNode]) {
        var sorted = children.sorted { $0.size > $1.size }
        node.size = sorted.reduce(0) { $0 + $1.size }
        if sorted.count > maxChildren {
            let rest = Array(sorted[maxChildren...])
            sorted = Array(sorted[..<maxChildren])
            let other = SpaceNode(url: node.url, name: "\(rest.count) smaller items", size: rest.reduce(0) { $0 + $1.size },
                                  isDirectory: false)
            other.isAggregate = true
            sorted.append(other)
        }
        for child in sorted { child.parent = node }
        node.children = sorted
    }
}

// MARK: - Large & Old Files

enum FileKind: String, CaseIterable, Identifiable {
    case all = "All", archives = "Archives", videos = "Videos", diskImages = "Disk Images"
    case documents = "Documents", music = "Music", other = "Other"
    var id: String { rawValue }

    static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if ["dmg", "iso", "img", "sparseimage", "sparsebundle", "toast", "vmdk", "qcow2"].contains(ext) { return .diskImages }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .archive) || ["zip", "rar", "7z", "tar", "gz", "xz", "bz2", "pkg", "xip"].contains(ext) { return .archives }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
        if type.conforms(to: .audio) { return .music }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent) || type.conforms(to: .image) { return .documents }
        return .other
    }
}

struct FoundFile: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var size: Int64
    var lastOpened: Date?
    var modified: Date?
    var kind: FileKind
    var isSelected = false
    var name: String { url.lastPathComponent }
}

enum LargeOldFilesService {
    /// Files at least `minBytes` big and/or not opened since `cutoff`.
    static func scan(roots: [URL], minBytes: Int64, findLarge: Bool, cutoff: Date, findOld: Bool,
                     progress: ScanProgress) -> [FoundFile] {
        let exclusions = SettingsStore.snapshot().exclusions
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                      .contentAccessDateKey, .contentModificationDateKey, .isPackageKey]
        // "Old" files on their own still need a floor, otherwise every tiny file would match.
        let oldFloor: Int64 = 1024 * 1024
        var results: [FoundFile] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                                  errorHandler: { url, error in
                                                                      PermissionCenter.noteError(error, at: url); return true }) else { continue }
            for case let url as URL in enumerator {
                if progress.isCancelled { return results }
                progress.visit(url.path)
                if url.pathExtension == "photoslibrary" || PathSafety.isExcluded(url.path, exclusions: exclusions) {
                    enumerator.skipDescendants(); continue
                }
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                let isFile = v.isRegularFile == true || v.isPackage == true
                guard isFile else { continue }
                let size = v.isPackage == true ? FileSize.of(url) : Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                let isLarge = findLarge && size >= minBytes
                var lastOpened = v.contentAccessDate
                var isOld = false
                if findOld && size >= oldFloor {
                    // Spotlight's "last opened" is more reliable than the access time.
                    lastOpened = AppCatalog.lastUsedDate(url) ?? v.contentAccessDate
                    isOld = (lastOpened ?? v.contentModificationDate ?? Date()) < cutoff
                }
                guard isLarge || isOld else { continue }
                if PathSafety.reasonToSkip(url, exclusions: exclusions) != nil { continue }
                results.append(FoundFile(url: url, size: size, lastOpened: lastOpened ?? AppCatalog.lastUsedDate(url),
                                         modified: v.contentModificationDate, kind: FileKind.of(url)))
            }
        }
        return results.sorted { $0.size > $1.size }
    }
}

// MARK: - Duplicates

struct DuplicateGroup: Identifiable {
    let id = UUID()
    var hash: String
    var files: [FoundFile]
    var wasted: Int64 { files.dropFirst().reduce(0) { $0 + $1.size } }
}

enum DuplicatesService {
    /// Size -> partial hash (first 64 KB) -> full SHA-256.
    static func scan(roots: [URL], minBytes: Int64, progress: ScanProgress) -> [DuplicateGroup] {
        let exclusions = SettingsStore.snapshot().exclusions
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                      .fileResourceIdentifierKey, .contentModificationDateKey, .creationDateKey]
        progress.setMessage("Listing files…")
        var bySize: [Int64: [URL]] = [:]
        var seenInodes = Set<NSObject>()
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if progress.isCancelled { return [] }
                progress.visit(url.path)
                if url.pathExtension == "photoslibrary" || PathSafety.isExcluded(url.path, exclusions: exclusions) {
                    enumerator.skipDescendants(); continue
                }
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let size = v.fileSize, Int64(size) >= max(1, minBytes) else { continue }
                // Hard links point to the same data: count them once.
                if let inode = v.fileResourceIdentifier as? NSObject, !seenInodes.insert(inode).inserted { continue }
                bySize[Int64(size), default: []].append(url)
            }
        }
        let candidates = bySize.filter { $0.value.count > 1 }
        progress.setMessage("Comparing \(candidates.values.reduce(0) { $0 + $1.count }) files with matching sizes…")

        var groups: [DuplicateGroup] = []
        var processed = 0
        let total = candidates.count
        for (_, urls) in candidates {
            if progress.isCancelled { break }
            processed += 1
            progress.setFraction(Double(processed) / Double(max(1, total)))
            var byPartial: [String: [URL]] = [:]
            for url in urls {
                progress.visit(url.path)
                if let hash = Hashing.partialHash(url) { byPartial[hash, default: []].append(url) }
            }
            for (_, partialGroup) in byPartial where partialGroup.count > 1 {
                var byFull: [String: [URL]] = [:]
                for url in partialGroup {
                    progress.visit(url.path)
                    if let hash = Hashing.fullHash(url, progress: progress) { byFull[hash, default: []].append(url) }
                }
                for (hash, same) in byFull where same.count > 1 {
                    let files = same.map { url -> FoundFile in
                        let v = try? url.resourceValues(forKeys: Set(keys))
                        return FoundFile(url: url, size: Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0),
                                         lastOpened: v?.creationDate, modified: v?.contentModificationDate, kind: FileKind.of(url))
                    }
                    groups.append(DuplicateGroup(hash: hash, files: files))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }
}

// MARK: - Shredder

enum ShredderService {
    /// Overwrites every file with random data, then deletes it. Folders are processed recursively.
    static func shred(_ urls: [URL], progress: ScanProgress) -> CleanupResult {
        var result = CleanupResult()
        var files: [URL] = []
        var folders: [URL] = []
        for url in urls {
            if let reason = PathSafety.reasonToSkip(url) { result.fail(url.path, reason); continue }
            if FileSize.isDirectory(url) {
                folders.append(url)
                if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                    for case let f as URL in e where (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                        files.append(f)
                    }
                }
            } else {
                files.append(url)
            }
        }
        let inUse = FileInUse.openFiles(files)
        for (index, file) in files.enumerated() {
            if progress.isCancelled { break }
            progress.step(index, of: files.count, "Shredding \(file.lastPathComponent)…")
            progress.visit(file.path)
            if inUse.contains(file.path) { result.fail(file.path, "File is open in another app — skipped"); continue }
            let size = FileSize.of(file: file)
            if let error = overwriteAndDelete(file, progress: progress) {
                result.fail(file.path, error)
            } else {
                result.success(file.lastPathComponent, bytes: size)
            }
        }
        // Remove the (now empty) folders, deepest first.
        for folder in folders.sorted(by: { $0.path.count > $1.path.count }) where !progress.isCancelled {
            do { try FileManager.default.removeItem(at: folder) } catch { result.fail(folder.path, error.localizedDescription) }
        }
        progress.setFraction(1)
        return result
    }

    private static func overwriteAndDelete(_ url: URL, progress: ScanProgress) -> String? {
        let fd = open(url.path, O_WRONLY)
        guard fd >= 0 else { return String(cString: strerror(errno)) }
        var st = stat()
        fstat(fd, &st)
        let length = Int64(st.st_size)
        let chunkSize = 1024 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var written: Int64 = 0
        while written < length {
            if progress.isCancelled { close(fd); return "Cancelled" }
            let count = Int(min(Int64(chunkSize), length - written))
            arc4random_buf(&buffer, count)
            let n = buffer.withUnsafeBytes { pwrite(fd, $0.baseAddress, count, off_t(written)) }
            if n <= 0 { close(fd); return "Write failed: \(String(cString: strerror(errno)))" }
            written += Int64(n)
        }
        fsync(fd)
        ftruncate(fd, 0)
        close(fd)
        // Rename to a random name so the original file name doesn't linger in the directory.
        let scrambled = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        let target = (try? FileManager.default.moveItem(at: url, to: scrambled)) != nil ? scrambled : url
        do { try FileManager.default.removeItem(at: target) } catch { return error.localizedDescription }
        return nil
    }
}
