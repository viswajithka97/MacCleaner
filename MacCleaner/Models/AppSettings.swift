import Foundation

enum DeletionMode: String, Codable, CaseIterable, Identifiable {
    case moveToTrash
    case deletePermanently
    var id: String { rawValue }
    var title: String {
        switch self {
        case .moveToTrash: return "Move to Trash"
        case .deletePermanently: return "Delete permanently"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var deletionMode: DeletionMode = .moveToTrash
    var exclusions: [String] = []
    var largeFileMinBytes: Int64 = 100 * 1024 * 1024
    var oldFileDays: Int = 365
    var notifyLowDisk: Bool = true
    var notifyMemoryPressure: Bool = true
    var notifyLargeTrash: Bool = true
    var notifyWeeklySmartCare: Bool = true
    var trashNotifyBytes: Int64 = 2 * 1024 * 1024 * 1024
    var lowDiskBytes: Int64 = 10 * 1024 * 1024 * 1024
    var showMenuBar: Bool = true
    var launchAtLogin: Bool = false
    var lastSmartCareReminder: Date?
}
