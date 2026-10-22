import Foundation

final class DiskNode: Identifiable, Hashable {
    let id: URL
    let url: URL
    let name: String
    var size: Int64
    var isDirectory: Bool
    var children: [DiskNode]

    init(url: URL, name: String, size: Int64, isDirectory: Bool, children: [DiskNode] = []) {
        self.id = url
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
    }

    static func == (lhs: DiskNode, rhs: DiskNode) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

enum SpaceLensService {
    static func scan(root: URL, callbacks: ScanCallbacks) async -> DiskNode {
        await Task.detached(priority: .userInitiated) {
            build(url: root, callbacks: callbacks, depth: 0)
        }.value
    }

    private static func build(url: URL, callbacks: ScanCallbacks, depth: Int) -> DiskNode {
        if callbacks.isCancelled() {
            return DiskNode(url: url, name: url.lastPathComponent, size: 0, isDirectory: true)
        }
        callbacks.progress(min(0.95, Double(depth) / 12.0), url.path)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isPackageKey]
        let values = try? url.resourceValues(forKeys: keys)
        if values?.isSymbolicLink == true {
            return DiskNode(url: url, name: url.lastPathComponent, size: 0, isDirectory: false)
        }
        if values?.isDirectory == true && values?.isPackage != true {
            var children: [DiskNode] = []
            var total: Int64 = 0
            let listed = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
            for child in listed {
                if callbacks.isCancelled() { break }
                let node = build(url: child, callbacks: callbacks, depth: depth + 1)
                total += node.size
                children.append(node)
            }
            children.sort { $0.size > $1.size }
            // Keep the visualization readable: only the heaviest children.
            if children.count > 40 {
                let dropped = children.suffix(from: 40)
                let leftover = dropped.reduce(Int64(0)) { $0 + $1.size }
                children = Array(children.prefix(40))
                if leftover > 0 {
                    children.append(DiskNode(url: url.appendingPathComponent(".other"), name: "Other", size: leftover, isDirectory: false))
                }
            }
            return DiskNode(url: url, name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, size: total, isDirectory: true, children: children)
        }
        let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        return DiskNode(url: url, name: url.lastPathComponent, size: size, isDirectory: false)
    }
}
