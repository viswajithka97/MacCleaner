import AppKit

/// Lets the user pick folders with an open panel.
@MainActor
enum FolderPicker {
    static func choose(multiple: Bool = true, filesToo: Bool = false) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = filesToo
        panel.allowsMultipleSelection = multiple
        panel.directoryURL = URL.home()
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.urls : []
    }
}

/// Space Lens: disk map with drill-down.
@MainActor
final class SpaceLensViewModel: TaskViewModel {
    @Published var root: SpaceNode?
    @Published var current: SpaceNode?
    @Published var selected: Set<URL> = []
    @Published var scanTarget: URL = URL.home()
    @Published var showConfirmation = false
    @Published var result: CleanupResult?

    /// From the root to the current folder (for breadcrumbs).
    var path: [SpaceNode] {
        var nodes: [SpaceNode] = []
        var node = current
        while let n = node { nodes.insert(n, at: 0); node = n.parent }
        return nodes
    }

    var volumes: [URL] {
        [URL(fileURLWithPath: "/")] + TrashService.externalVolumes()
    }

    func scan(_ url: URL) {
        scanTarget = url
        root = nil
        current = nil
        selected = []
        result = nil
        run({ SpaceLensService.scan(url, progress: $0) }) { [weak self] node, _ in
            self?.root = node
            self?.current = node
        }
    }

    func open(_ node: SpaceNode) {
        if node.canDrillDown { current = node }
    }

    func toggleSelection(_ node: SpaceNode) {
        guard !node.isAggregate else { return }
        if selected.contains(node.url) { selected.remove(node.url) } else { selected.insert(node.url) }
    }

    /// Selected nodes with their sizes (found by walking the tree).
    var selectedNodes: [SpaceNode] {
        guard let root else { return [] }
        var found: [SpaceNode] = []
        func walk(_ node: SpaceNode) {
            if selected.contains(node.url) && !node.isAggregate && node !== root { found.append(node); return }
            node.children.forEach(walk)
        }
        walk(root)
        return found
    }

    var selectedSize: Int64 { selectedNodes.reduce(0) { $0 + $1.size } }

    func confirmRemove() {
        showConfirmation = false
        let nodes = selectedNodes
        let items = nodes.map { CleanItem(name: $0.name, url: $0.url, size: $0.size, action: .remove($0.url)) }
        run({ await CleanupExecutor.perform(items, progress: $0, title: "Space Lens") }) { [weak self] result, _ in
            guard let self else { return }
            self.result = result
            HistoryStore.shared.record(module: "Space Lens", result: result)
            // Update the map: drop removed nodes and shrink their parents.
            for node in nodes where !FileManager.default.fileExists(atPath: node.url.path) {
                var parent = node.parent
                parent?.children.removeAll { $0 === node }
                while let p = parent { p.size -= node.size; parent = p.parent }
            }
            self.selected = []
            self.objectWillChange.send()
        }
    }
}

/// Large & Old Files.
@MainActor
final class LargeOldFilesViewModel: TaskViewModel {
    enum Sort: String, CaseIterable, Identifiable { case size = "Size", date = "Last opened", name = "Name"; var id: String { rawValue } }

    @Published var folders: [URL] = [URL.home()]
    @Published var minSizeMB: Int = SettingsStore.snapshot().largeFileMB
    @Published var olderThanDays: Int = SettingsStore.snapshot().oldFileDays
    @Published var findLarge = true
    @Published var findOld = true
    @Published var files: [FoundFile] = []
    @Published var scanned = false
    @Published var kind: FileKind = .all
    @Published var sort: Sort = .size
    @Published var confirmMode: ConfirmMode?
    @Published var result: CleanupResult?
    @Published var previewURL: URL?

    enum ConfirmMode: Identifiable { case remove, shred; var id: Int { self == .remove ? 0 : 1 } }

    var visibleFiles: [FoundFile] {
        let filtered = kind == .all ? files : files.filter { $0.kind == kind }
        switch sort {
        case .size: return filtered.sorted { $0.size > $1.size }
        case .date: return filtered.sorted { ($0.lastOpened ?? .distantPast) < ($1.lastOpened ?? .distantPast) }
        case .name: return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var selectedFiles: [FoundFile] { files.filter(\.isSelected) }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func scan() {
        let folders = self.folders, minBytes = Int64(minSizeMB) * 1024 * 1024
        let cutoff = Calendar.current.date(byAdding: .day, value: -olderThanDays, to: Date()) ?? Date()
        let large = findLarge, old = findOld
        result = nil
        run({ LargeOldFilesService.scan(roots: folders, minBytes: minBytes, findLarge: large, cutoff: cutoff, findOld: old, progress: $0) }) { [weak self] files, _ in
            self?.files = files
            self?.scanned = true
        }
    }

    func toggle(_ file: FoundFile) {
        if let index = files.firstIndex(where: { $0.id == file.id }) { files[index].isSelected.toggle() }
    }

    func confirm() {
        guard let mode = confirmMode else { return }
        confirmMode = nil
        let chosen = selectedFiles
        let work: @Sendable (ScanProgress) async -> CleanupResult
        if mode == .shred {
            work = { ShredderService.shred(chosen.map(\.url), progress: $0) }
        } else {
            let items = chosen.map { CleanItem(name: $0.name, url: $0.url, size: $0.size, action: .remove($0.url)) }
            work = { await CleanupExecutor.perform(items, progress: $0, title: "Large & Old Files") }
        }
        run(work) { [weak self] result, _ in
            guard let self else { return }
            self.result = result
            HistoryStore.shared.record(module: "Large & Old Files", result: result)
            self.files.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
        }
    }
}

/// Duplicates finder.
@MainActor
final class DuplicatesViewModel: TaskViewModel {
    enum Keep: String, CaseIterable, Identifiable { case newest = "Newest", oldest = "Oldest (original)"; var id: String { rawValue } }

    @Published var folders: [URL] = [URL.home("Documents"), URL.home("Downloads"), URL.home("Desktop")]
    @Published var minSizeKB: Int = 100
    @Published var groups: [DuplicateGroup] = []
    @Published var scanned = false
    @Published var keep: Keep = .newest
    @Published var showConfirmation = false
    @Published var result: CleanupResult?
    @Published var previewURL: URL?

    var selectedFiles: [FoundFile] { groups.flatMap { $0.files.filter(\.isSelected) } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }
    var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }

    func scan() {
        let folders = self.folders, minBytes = Int64(minSizeKB) * 1024
        result = nil
        run({ DuplicatesService.scan(roots: folders, minBytes: minBytes, progress: $0) }) { [weak self] groups, _ in
            self?.groups = groups
            self?.scanned = true
            self?.autoSelect()
        }
    }

    /// Keeps one copy per group (newest, or the original = oldest / shortest name) and selects the rest.
    func autoSelect() {
        for g in groups.indices {
            let files = groups[g].files
            let keepIndex: Int?
            switch keep {
            case .newest:
                keepIndex = files.indices.max { (files[$0].modified ?? .distantPast) < (files[$1].modified ?? .distantPast) }
            case .oldest:
                keepIndex = files.indices.min { a, b in
                    let da = files[a].lastOpened ?? files[a].modified ?? .distantFuture
                    let db = files[b].lastOpened ?? files[b].modified ?? .distantFuture
                    return da == db ? files[a].name.count < files[b].name.count : da < db
                }
            }
            for f in groups[g].files.indices { groups[g].files[f].isSelected = f != keepIndex }
        }
    }

    func toggle(group: UUID, file: String) {
        guard let g = groups.firstIndex(where: { $0.id == group }),
              let f = groups[g].files.firstIndex(where: { $0.id == file }) else { return }
        groups[g].files[f].isSelected.toggle()
    }

    /// True when every copy in a group is selected (nothing would be kept).
    var hasGroupWithNothingKept: Bool { groups.contains { $0.files.allSatisfy(\.isSelected) } }

    func confirmRemove() {
        showConfirmation = false
        let items = selectedFiles.map { CleanItem(name: $0.name, url: $0.url, size: $0.size, action: .remove($0.url)) }
        run({ await CleanupExecutor.perform(items, progress: $0, title: "Duplicates") }) { [weak self] result, _ in
            guard let self else { return }
            self.result = result
            HistoryStore.shared.record(module: "Duplicates", result: result)
            for g in self.groups.indices {
                self.groups[g].files.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) }
            }
            self.groups.removeAll { $0.files.count < 2 }
        }
    }
}

/// Similar Photos.
@MainActor
final class SimilarPhotosViewModel: TaskViewModel {
    @Published var folders: [URL] = [URL.home("Pictures")]
    @Published var includeLibrary = true
    @Published var threshold: Double = 11
    @Published var groups: [PhotoGroup] = []
    @Published var scanned = false
    @Published var showConfirmation = false
    @Published var result: CleanupResult?

    var selectedPhotos: [PhotoCandidate] { groups.flatMap { $0.photos.filter(\.isSelected) } }
    var selectedSize: Int64 { selectedPhotos.reduce(0) { $0 + $1.size } }

    func scan() {
        let folders = self.folders, library = includeLibrary, threshold = Float(self.threshold)
        result = nil
        run({ await SimilarPhotosService.scan(folders: folders, includeLibrary: library, threshold: threshold, progress: $0) }) { [weak self] groups, _ in
            self?.groups = groups
            self?.scanned = true
        }
    }

    func toggle(group: UUID, photo: UUID) {
        guard let g = groups.firstIndex(where: { $0.id == group }),
              let p = groups[g].photos.firstIndex(where: { $0.id == photo }) else { return }
        groups[g].photos[p].isSelected.toggle()
    }

    func confirmDelete() {
        showConfirmation = false
        let items: [CleanItem] = selectedPhotos.map { photo in
            switch photo.source {
            case .file(let url): return CleanItem(name: photo.name, url: url, size: photo.size, action: .remove(url))
            case .library(let id): return CleanItem(name: photo.name, url: nil, size: photo.size, action: .photoAsset(localIdentifier: id))
            }
        }
        let removedIDs = Set(selectedPhotos.map(\.id))
        run({ await CleanupExecutor.perform(items, progress: $0, title: "Similar Photos") }) { [weak self] result, _ in
            guard let self else { return }
            self.result = result
            HistoryStore.shared.record(module: "Similar Photos", result: result)
            if result.failures.isEmpty {
                for g in self.groups.indices { self.groups[g].photos.removeAll { removedIDs.contains($0.id) } }
                self.groups.removeAll { $0.photos.count < 2 }
            }
        }
    }
}

/// Shredder.
@MainActor
final class ShredderViewModel: TaskViewModel {
    @Published var items: [URL] = []
    @Published var showConfirmation = false
    @Published var result: CleanupResult?

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) { items.append(url) }
        result = nil
    }

    var totalSize: Int64 { items.reduce(0) { $0 + FileSize.of($1) } }

    func confirmShred() {
        showConfirmation = false
        let urls = items
        run({ ShredderService.shred(urls, progress: $0) }) { [weak self] result, _ in
            guard let self else { return }
            self.result = result
            HistoryStore.shared.record(module: "Shredder", result: result)
            self.items.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        }
    }
}
