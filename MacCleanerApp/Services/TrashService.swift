import Foundation

/// Trash Bins module: user Trash, Mail trash, Photos "Recently Deleted" (info), external drives.
enum TrashService {

    struct Outcome { var ok: Bool; var message: String }

    static func scan(progress: ScanProgress) -> [CleanCategory] {
        var categories: [CleanCategory] = []

        // 1. Your Trash
        progress.step(0, of: 4, "Your Trash…")
        let userTrash = URL.home(".Trash")
        let trashItems = FileSize.children(of: userTrash).compactMap { url -> CleanItem? in
            if progress.isCancelled { return nil }
            progress.visit(url.path)
            if url.lastPathComponent == ".DS_Store" { return nil }
            return CleanItem(name: url.lastPathComponent, url: url, size: FileSize.of(url, progress: progress),
                             date: FileSize.modified(url), action: .deletePermanently(url))
        }
        if !trashItems.isEmpty {
            categories.append(CleanCategory(id: "user-trash", title: "Trash", symbol: "trash",
                                            summary: "Files you moved to the Trash.", items: trashItems.sorted { $0.size > $1.size }))
        }

        // 2. Mail trash (erased through Mail itself; we never delete message files)
        progress.step(1, of: 4, "Mail trash…")
        let mailTrashSize = mailTrashFolders().reduce(Int64(0)) { $0 + FileSize.of($1, progress: progress) }
        if mailTrashSize > 0 {
            categories.append(CleanCategory(
                id: "mail-trash", title: "Mail Trash", symbol: "envelope",
                summary: "Messages in Mail's Trash mailboxes.",
                items: [CleanItem(name: "Erase deleted messages in Mail", url: nil, size: mailTrashSize,
                                  subtitle: "Mail will open and erase the messages in its Trash", symbol: "envelope.badge",
                                  action: .mailTrash)],
                note: "MacCleaner asks Mail to erase its Trash. Message files are never deleted directly."))
        }

        // 3. Photos Recently Deleted (information only)
        progress.step(2, of: 4, "Photos Recently Deleted…")
        if let photos = photosRecentlyDeleted() {
            categories.append(CleanCategory(
                id: "photos-trash", title: "Photos Recently Deleted", symbol: "photo.on.rectangle",
                summary: "Photos you deleted are kept for 30 days.",
                items: [CleanItem(name: "\(photos.count) item(s) in Recently Deleted", url: nil, size: photos.bytes,
                                  subtitle: "Empty it in Photos → Recently Deleted → Delete All", symbol: "photo",
                                  action: .none)],
                note: "Photos libraries are only changed by the Photos app.", infoOnly: true))
        }

        // 4. External drives: /Volumes/<drive>/.Trashes/<your uid>
        progress.step(3, of: 4, "External drives…")
        for volume in externalVolumes() {
            let trash = volume.appendingPathComponent(".Trashes/\(Shell.uid)")
            let items = FileSize.children(of: trash).compactMap { url -> CleanItem? in
                if url.lastPathComponent == ".DS_Store" { return nil }
                progress.visit(url.path)
                return CleanItem(name: url.lastPathComponent, url: url, size: FileSize.of(url, progress: progress),
                                 date: FileSize.modified(url), action: .deletePermanently(url))
            }
            if !items.isEmpty {
                categories.append(CleanCategory(id: "volume-\(volume.lastPathComponent)",
                                                title: "Trash on \(volume.lastPathComponent)", symbol: "externaldrive",
                                                summary: "Deleted files still stored on this drive.", items: items))
            }
        }
        progress.setFraction(1)
        return categories
    }

    /// Mounted volumes other than the startup disk.
    static func externalVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return url.path.hasPrefix("/Volumes/") && values?.volumeIsRootFileSystem != true
        }
    }

    /// Size of the user Trash (used by the Trash-size notification).
    static func userTrashSize() -> Int64 {
        FileSize.of(URL.home(".Trash"))
    }

    // MARK: - Mail

    /// Mail's Trash/Deleted Messages mailbox folders (used for measuring only).
    static func mailTrashFolders() -> [URL] {
        var result: [URL] = []
        let mail = URL.home("Library/Mail")
        for version in FileSize.children(of: mail) where version.lastPathComponent.hasPrefix("V") {
            for account in FileSize.children(of: version) where FileSize.isDirectory(account) {
                for box in FileSize.children(of: account) {
                    let name = box.lastPathComponent.lowercased()
                    if name == "deleted messages.mbox" || name == "trash.mbox" || name == "bin.mbox" || name == "deleted items.mbox" {
                        result.append(box)
                    }
                }
            }
        }
        return result
    }

    /// Asks Mail (via AppleScript) to permanently erase messages in its Trash.
    static func emptyMailTrash() async -> Outcome {
        let script = """
        tell application "Mail"
            set n to 0
            repeat with acc in accounts
                try
                    set tb to mailbox "Deleted Messages" of acc
                    set n to n + (count of messages of tb)
                    delete every message of tb
                end try
                try
                    set tb to mailbox "Trash" of acc
                    set n to n + (count of messages of tb)
                    delete every message of tb
                end try
            end repeat
            try
                delete every message of trash mailbox
            end try
            return n
        end tell
        """
        let result = await Shell.runAsync("/usr/bin/osascript", ["-e", script], timeout: 300)
        if result.succeeded {
            return Outcome(ok: true, message: "Mail erased \(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) message(s).")
        }
        if result.error.contains("-1743") {
            return Outcome(ok: false, message: "MacCleaner isn't allowed to control Mail. Enable it in System Settings → Privacy & Security → Automation.")
        }
        return Outcome(ok: false, message: result.combinedOutput)
    }

    // MARK: - Photos

    /// Count and size of photos in "Recently Deleted", read (read-only) from the Photos database.
    static func photosRecentlyDeleted() -> (count: Int, bytes: Int64)? {
        let library = URL.home("Pictures/Photos Library.photoslibrary/database/Photos.sqlite")
        guard let db = SQLiteDB(path: library.path, immutable: true) else { return nil }
        let queries = [
            "SELECT COUNT(*), COALESCE(SUM(a.ZORIGINALFILESIZE),0) FROM ZASSET z LEFT JOIN ZADDITIONALASSETATTRIBUTES a ON a.ZASSET = z.Z_PK WHERE z.ZTRASHEDSTATE = 1",
            "SELECT COUNT(*), COALESCE(SUM(a.ZORIGINALFILESIZE),0) FROM ZGENERICASSET z LEFT JOIN ZADDITIONALASSETATTRIBUTES a ON a.ZASSET = z.Z_PK WHERE z.ZTRASHEDSTATE = 1",
        ]
        for sql in queries {
            if let row = db.rows(sql).first, row.count == 2, let count = Int(row[0] ?? "") {
                return (count, Int64(row[1] ?? "0") ?? 0)
            }
        }
        return nil
    }
}
