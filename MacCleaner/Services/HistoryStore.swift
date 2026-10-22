import Foundation
import Combine

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    var totalBytesFreed: Int64 {
        entries.reduce(0) { $0 + $1.bytesFreed }
    }

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MacCleaner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = decoded.sorted { $0.date > $1.date }
        }
    }

    func append(_ summary: CleanupSummary) {
        let entry = HistoryEntry(
            id: UUID(),
            date: Date(),
            moduleRaw: summary.module.rawValue,
            itemsRemoved: summary.removedCount,
            bytesFreed: summary.bytesFreed,
            notes: (summary.notes + summary.skipped.prefix(8).map { "Skipped: \($0)" }).joined(separator: " · ")
        )
        entries.insert(entry, at: 0)
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
