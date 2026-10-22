import Foundation

/// One file, folder, or logical target the user can tick before cleanup.
struct CleanableItem: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var path: String
    var size: Int64
    var selected: Bool
    var subtitle: String
    var warning: String?
    /// Extra JSON-ish metadata (device name, version, reason flagged, etc.)
    var extra: [String: String]
    /// When false, the item is listed for information only (Document Versions).
    var removable: Bool
    /// PhotoKit local identifier when the item lives in the Photos library.
    var photoAssetId: String?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        size: Int64,
        selected: Bool = true,
        subtitle: String = "",
        warning: String? = nil,
        extra: [String: String] = [:],
        removable: Bool = true,
        photoAssetId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.selected = selected
        self.subtitle = subtitle
        self.warning = warning
        self.extra = extra
        self.removable = removable
        self.photoAssetId = photoAssetId
    }
}

struct CleanableCategory: Identifiable, Hashable {
    let id: UUID
    var name: String
    var symbol: String
    var detail: String
    var items: [CleanableItem]
    var selected: Bool
    var requiresAdmin: Bool
    var warning: String?
    /// When false, the whole category is informational (no delete).
    var removable: Bool

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        detail: String = "",
        items: [CleanableItem] = [],
        selected: Bool = true,
        requiresAdmin: Bool = false,
        warning: String? = nil,
        removable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.detail = detail
        self.items = items
        self.selected = selected
        self.requiresAdmin = requiresAdmin
        self.warning = warning
        self.removable = removable
    }

    var size: Int64 { items.reduce(0) { $0 + $1.size } }

    var selectedSize: Int64 {
        items.filter { $0.selected && $0.removable }.reduce(0) { $0 + $1.size }
    }

    var selectedItems: [CleanableItem] {
        items.filter { $0.selected && $0.removable }
    }
}

enum ScanPhase: Equatable {
    case intro
    case scanning
    case results
    case summary
}

struct CleanupSummary: Equatable {
    var module: AppModule
    var removedCount: Int
    var bytesFreed: Int64
    var skipped: [String]
    var notes: [String]
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var moduleRaw: String
    var itemsRemoved: Int
    var bytesFreed: Int64
    var notes: String

    var moduleTitle: String {
        AppModule(rawValue: moduleRaw)?.title ?? moduleRaw
    }
}
