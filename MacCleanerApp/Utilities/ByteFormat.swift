import Foundation

/// Helpers for turning raw byte counts and dates into friendly text.
enum ByteFormat {
    /// "1.2 GB", "340 KB", ... using the same rules Finder uses.
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    /// "Mar 3, 2025"
    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// "Mar 3, 2025 at 14:02"
    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// "3 days ago"
    static func relative(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension Int64 {
    /// Convenience: `size.formattedBytes`
    var formattedBytes: String { ByteFormat.string(self) }
}
