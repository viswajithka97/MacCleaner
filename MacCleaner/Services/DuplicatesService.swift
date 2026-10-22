import Foundation

struct DuplicateGroup: Identifiable, Hashable {
    var id: UUID = UUID()
    var hash: String
    var size: Int64
    var items: [CleanableItem]
}

enum DuplicatesService {
    static func scan(roots: [URL], callbacks: ScanCallbacks) async -> [DuplicateGroup] {
        await Task.detached(priority: .userInitiated) {
            var bySize: [Int64: [URL]] = [:]
            for root in roots {
                FileScanSupport.collect(at: root, skipPackages: true, callbacks: callbacks) { url, values in
                    guard values.isRegularFile == true else { return }
                    if PathSafety.isForbidden(url.path) { return }
                    let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                    if size < 4096 { return }
                    bySize[size, default: []].append(url)
                }
            }
            var groups: [DuplicateGroup] = []
            let candidates = bySize.filter { $0.value.count > 1 }
            var processed = 0
            let total = max(candidates.count, 1)
            for (size, urls) in candidates {
                if callbacks.isCancelled() { break }
                processed += 1
                callbacks.progress(Double(processed) / Double(total), urls.first?.path ?? "")
                var partial: [String: [URL]] = [:]
                for url in urls {
                    if let hash = Hashing.sha256(url: url, limit: 64 * 1024) {
                        partial[hash, default: []].append(url)
                    }
                }
                for (_, subset) in partial where subset.count > 1 {
                    var full: [String: [URL]] = [:]
                    for url in subset {
                        if let hash = Hashing.sha256(url: url) {
                            full[hash, default: []].append(url)
                        }
                    }
                    for (hash, dups) in full where dups.count > 1 {
                        let dated = dups.map { url -> (URL, Date) in
                            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                            return (url, date)
                        }.sorted { $0.1 > $1.1 }
                        let items: [CleanableItem] = dated.enumerated().map { index, pair in
                            FileScanSupport.item(
                                name: pair.0.lastPathComponent,
                                url: pair.0,
                                selected: index > 0,
                                subtitle: DateFormatting.short(pair.1)
                            )
                        }
                        groups.append(DuplicateGroup(hash: hash, size: size, items: items))
                    }
                }
            }
            return groups.sorted { $0.size * Int64($0.items.count) > $1.size * Int64($1.items.count) }
        }.value
    }

    static func autoSelectNewest(_ groups: inout [DuplicateGroup]) {
        for i in groups.indices {
            let sorted = groups[i].items.sorted { $0.subtitle > $1.subtitle }
            for j in groups[i].items.indices {
                groups[i].items[j].selected = groups[i].items[j].path != sorted.first?.path
            }
        }
    }
}
