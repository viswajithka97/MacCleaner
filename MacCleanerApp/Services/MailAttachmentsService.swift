import Foundation
import UniformTypeIdentifiers

/// Finds local copies of downloaded Mail attachments. Emails themselves are never touched.
enum MailAttachmentsService {

    static func scan(progress: ScanProgress) -> [CleanCategory] {
        var files: [URL] = []
        progress.step(0, of: 2, "Mail Downloads…")
        let downloads = URL.home("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        files += regularFiles(under: downloads, progress: progress)

        progress.step(1, of: 2, "Attachments inside Mail's folders…")
        let mail = URL.home("Library/Mail")
        if let enumerator = FileManager.default.enumerator(at: mail, includingPropertiesForKeys: [.isDirectoryKey],
                                                           errorHandler: { url, error in
                                                               PermissionCenter.noteError(error, at: url); return true }) {
            for case let url as URL in enumerator {
                if progress.isCancelled { break }
                let name = url.lastPathComponent
                // "Messages" folders only contain .emlx message files: skip them entirely.
                if name == "Messages" { enumerator.skipDescendants(); continue }
                if name == "Attachments", FileSize.isDirectory(url) {
                    enumerator.skipDescendants()
                    files += regularFiles(under: url, progress: progress)
                }
            }
        }

        var groups: [String: [CleanItem]] = [:]
        for file in files where PathSafety.reasonToSkip(file) == nil {
            let type = UTType(filenameExtension: file.pathExtension)
            let group = groupName(type)
            let kind = type?.localizedDescription ?? file.pathExtension.uppercased()
            groups[group, default: []].append(CleanItem(name: file.lastPathComponent, url: file, size: FileSize.of(file: file),
                                                        subtitle: kind, date: FileSize.modified(file),
                                                        symbol: symbol(group), action: .remove(file)))
        }
        progress.setFraction(1)
        return groups.map { name, items in
            CleanCategory(id: "mail-\(name)", title: name, symbol: symbol(name),
                          summary: "Downloaded copies of \(name.lowercased()) received by email.",
                          items: items.sorted { $0.size > $1.size },
                          note: "Only the local copies are removed. Your emails stay intact and attachments can be downloaded again from the mail server.")
        }.sorted { $0.totalSize > $1.totalSize }
    }

    private static func regularFiles(under root: URL, progress: ScanProgress) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            if progress.isCancelled { break }
            progress.visit(url.path)
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
               url.lastPathComponent != ".DS_Store", url.pathExtension.lowercased() != "emlx" {
                result.append(url)
            }
        }
        return result
    }

    private static func groupName(_ type: UTType?) -> String {
        guard let type else { return "Other" }
        if type.conforms(to: .image) { return "Images" }
        if type.conforms(to: .audiovisualContent) { return "Audio & Video" }
        if type.conforms(to: .archive) { return "Archives" }
        if type.conforms(to: .pdf) || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet)
            || type.conforms(to: .text) || type.conforms(to: .compositeContent) { return "Documents" }
        return "Other"
    }

    private static func symbol(_ group: String) -> String {
        switch group {
        case "Images": return "photo"
        case "Audio & Video": return "film"
        case "Archives": return "doc.zipper"
        case "Documents": return "doc.richtext"
        default: return "paperclip"
        }
    }
}
