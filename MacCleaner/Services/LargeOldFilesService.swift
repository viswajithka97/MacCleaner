import Foundation
import UniformTypeIdentifiers

enum FileKindFilter: String, CaseIterable, Identifiable {
    case all, archives, videos, diskImages, documents, music, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .archives: return "Archives"
        case .videos: return "Videos"
        case .diskImages: return "Disk images"
        case .documents: return "Documents"
        case .music: return "Music"
        case .other: return "Other"
        }
    }
}

enum LargeOldFilesService {
    static func scan(roots: [URL], minBytes: Int64, olderThan: Date?, kind: FileKindFilter, callbacks: ScanCallbacks) async -> [CleanableItem] {
        await Task.detached(priority: .userInitiated) {
            var items: [CleanableItem] = []
            for root in roots {
                FileScanSupport.collect(at: root, skipPackages: true, callbacks: callbacks) { url, values in
                    guard values.isRegularFile == true else { return }
                    if PathSafety.isForbidden(url.path) { return }
                    let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                    if size < minBytes { return }
                    let opened = values.contentAccessDate ?? values.contentModificationDate
                    if let olderThan, let opened, opened > olderThan { return }
                    if !matches(url: url, type: values.typeIdentifier, kind: kind) { return }
                    items.append(CleanableItem(
                        name: url.lastPathComponent,
                        path: url.path,
                        size: size,
                        subtitle: "\(DateFormatting.short(opened)) · \(url.deletingLastPathComponent().path)"
                    ))
                }
            }
            items.sort { $0.size > $1.size }
            return items
        }.value
    }

    private static func matches(url: URL, type: String?, kind: FileKindFilter) -> Bool {
        if kind == .all { return true }
        let ext = url.pathExtension.lowercased()
        switch kind {
        case .archives: return ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"].contains(ext)
        case .videos: return ["mp4", "mov", "m4v", "mkv", "avi"].contains(ext)
        case .diskImages: return ["dmg", "iso", "img", "sparseimage", "sparsebundle"].contains(ext)
        case .documents: return ["pdf", "doc", "docx", "pages", "key", "ppt", "pptx", "xls", "xlsx", "rtf", "txt"].contains(ext)
        case .music: return ["mp3", "aac", "m4a", "wav", "flac", "aiff"].contains(ext)
        case .other: return true
        case .all: return true
        }
    }
}
