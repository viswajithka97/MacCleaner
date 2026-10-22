import Foundation
import Photos

enum TrashBinsService {
    static func scan(callbacks: ScanCallbacks) async -> [CleanableCategory] {
        await Task.detached(priority: .userInitiated) {
            var categories: [CleanableCategory] = []
            let userTrash = FileScanSupport.home().appendingPathComponent(".Trash")
            callbacks.progress(0.2, userTrash.path)
            var trashItems: [CleanableItem] = []
            for child in FileScanSupport.listChildren(of: userTrash) {
                trashItems.append(FileScanSupport.item(name: child.lastPathComponent, url: child))
            }
            categories.append(CleanableCategory(name: "User Trash", symbol: "trash", detail: "~/.Trash", items: trashItems))

            callbacks.progress(0.4, "Mail trash")
            categories.append(CleanableCategory(
                name: "Mail trash",
                symbol: "envelope.badge.trash",
                detail: "Empties Mail’s Trash mailbox through AppleScript. Mail message files are not deleted as loose files.",
                items: [
                    CleanableItem(
                        name: "Empty Mail Trash",
                        path: "mail://empty-trash",
                        size: 0,
                        subtitle: "tell application \"Mail\" to empty the trash / junk",
                        extra: ["mailEmpty": "true"]
                    )
                ]
            ))

            callbacks.progress(0.6, "Photos Recently Deleted")
            let photoSize = photosRecentlyDeletedSize()
            categories.append(CleanableCategory(
                name: "Photos Recently Deleted",
                symbol: "photo",
                detail: "Size of items in Recently Deleted. Emptying uses PhotoKit and asks Photos for confirmation.",
                items: [
                    CleanableItem(
                        name: "Recently Deleted album",
                        path: "photos://recently-deleted",
                        size: photoSize,
                        extra: ["photosRecentlyDeleted": "true"]
                    )
                ]
            ))

            callbacks.progress(0.8, "/Volumes")
            var volumeItems: [CleanableItem] = []
            let volumes = URL(fileURLWithPath: "/Volumes")
            for volume in FileScanSupport.listChildren(of: volumes) {
                let trash = volume.appendingPathComponent(".Trashes")
                if FileScanSupport.exists(trash.path) {
                    volumeItems.append(FileScanSupport.item(name: "\(volume.lastPathComponent) trash", url: trash, subtitle: trash.path))
                }
            }
            categories.append(CleanableCategory(name: "External drive trash", symbol: "externaldrive.badge.trash", items: volumeItems, requiresAdmin: true))
            return categories
        }.value
    }

    static func photosRecentlyDeletedSize() -> Int64 {
        let status = PHPhotoLibrary.authorizationStatus()
        guard status == .authorized || status == .limited else { return 0 }
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumRecentlyDeleted, options: nil)
        var total: Int64 = 0
        albums.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            assets.enumerateObjects { asset, _, _ in
                let resources = PHAssetResource.assetResources(for: asset)
                for resource in resources {
                    if let n = resource.value(forKey: "fileSize") as? Int64 {
                        total += n
                    }
                }
            }
        }
        return total
    }

    static func emptyMailTrash() throws {
        _ = try ProcessRunner.run("/usr/bin/osascript", arguments: [
            "-e", "tell application \"Mail\" to activate",
            "-e", "tell application \"Mail\" to empty junk messages",
            "-e", "tell application \"Mail\" to empty deleted messages"
        ])
    }

    static func emptyPhotosRecentlyDeleted() async {
        let status = await requestPhotos()
        guard status == .authorized || status == .limited else { return }
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumRecentlyDeleted, options: nil)
        albums.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets)
            }, completionHandler: { _, _ in })
        }
    }

    static func requestPhotos() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
