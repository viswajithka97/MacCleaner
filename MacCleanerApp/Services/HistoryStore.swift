import Foundation
import Combine

/// Keeps a log of every cleanup in
/// ~/Library/Application Support/MacCleaner/history.json
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    /// Total bytes freed across all cleanups.
    var totalFreed: Int64 { entries.reduce(0) { $0 + $1.bytesFreed } }

    private let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.home("Library/Application Support")
        let folder = support.appendingPathComponent("MacCleaner", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("history.json")
    }()

    private init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Adds one cleanup to the log (ignored if nothing happened).
    func record(module: String, result: CleanupResult) {
        guard result.removedCount > 0 || result.freedBytes > 0 else { return }
        let entry = HistoryEntry(date: Date(), module: module, itemsRemoved: result.removedCount,
                                 bytesFreed: result.freedBytes, details: Array(result.removedNames.prefix(200)))
        entries.insert(entry, at: 0)
        save()
    }

    func clear() {
        entries = []
        save()
    }

    var fileLocation: URL { fileURL }
}
