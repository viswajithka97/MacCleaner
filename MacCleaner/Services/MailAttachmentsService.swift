import Foundation
import UniformTypeIdentifiers

enum MailAttachmentsService {
    static func scan(callbacks: ScanCallbacks) async -> [CleanableCategory] {
        await Task.detached(priority: .userInitiated) {
            let roots = [
                FileScanSupport.library().appendingPathComponent("Containers/com.apple.mail/Data/Library/Mail Downloads"),
                FileScanSupport.library().appendingPathComponent("Mail Downloads"),
                FileScanSupport.home().appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
            ]
            var items: [CleanableItem] = []
            for root in roots {
                if callbacks.isCancelled() { break }
                FileScanSupport.collect(at: root, skipPackages: true, callbacks: callbacks) { url, values in
                    guard values.isRegularFile == true else { return }
                    if PathSafety.isForbidden(url.path) { return }
                    let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                    let type = UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? url.pathExtension.uppercased()
                    items.append(CleanableItem(
                        name: url.lastPathComponent,
                        path: url.path,
                        size: size,
                        subtitle: "\(type) · \(DateFormatting.short(values.contentModificationDate))",
                        extra: [
                            "type": type,
                            "date": DateFormatting.short(values.contentModificationDate)
                        ]
                    ))
                }
            }
            items.sort { $0.size > $1.size }
            return [CleanableCategory(
                name: "Downloaded Mail attachments",
                symbol: "paperclip",
                detail: "These are local copies. The emails themselves are never touched. You can re-download attachments from the mail server.",
                items: items
            )]
        }.value
    }
}
