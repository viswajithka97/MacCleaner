import AppKit
import Foundation
import Photos
import Security

struct DeletionOutcome {
    var removed: Int
    var bytes: Int64
    var skipped: [String]
}

enum DeletionService {
    @MainActor
    static func remove(items: [CleanableItem], settings: AppSettings, shred: Bool = false) async -> DeletionOutcome {
        var outcome = DeletionOutcome(removed: 0, bytes: 0, skipped: [])
        let store = SettingsStore.shared
        for item in items {
            if store.isExcluded(item.path) {
                outcome.skipped.append("Excluded: \(item.path)")
                continue
            }
            if PathSafety.isForbidden(item.path) {
                outcome.skipped.append("Protected path: \(item.path)")
                continue
            }
            if PathSafety.isOurOwnApp(item.path) {
                outcome.skipped.append("Refused to remove MacCleaner itself.")
                continue
            }
            if !item.removable {
                outcome.skipped.append("Informational only: \(item.name)")
                continue
            }

            if let assetId = item.photoAssetId {
                let ok = await deletePhotoAsset(assetId)
                if ok {
                    outcome.removed += 1
                    outcome.bytes += item.size
                } else {
                    outcome.skipped.append("Photos item needs confirmation or failed: \(item.name)")
                }
                continue
            }

            let url = URL(fileURLWithPath: item.path)
            if shred {
                do {
                    try ShredderEngine.overwriteThenRemove(url: url)
                    outcome.removed += 1
                    outcome.bytes += item.size
                } catch {
                    outcome.skipped.append("\(item.path): \(error.localizedDescription)")
                }
                continue
            }

            do {
                switch settings.deletionMode {
                case .moveToTrash:
                    var resulting: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                case .deletePermanently:
                    try FileManager.default.removeItem(at: url)
                }
                outcome.removed += 1
                outcome.bytes += item.size
            } catch {
                outcome.skipped.append("\(item.path): \(error.localizedDescription)")
            }
        }
        return outcome
    }

    private static func deletePhotoAsset(_ id: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
            guard assets.count > 0 else {
                continuation.resume(returning: false)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets)
            }, completionHandler: { success, _ in
                continuation.resume(returning: success)
            })
        }
    }
}

enum ShredderEngine {
    static func overwriteThenRemove(url: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw NSError(domain: "Shredder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing file"])
        }
        if isDir.boolValue {
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for child in children {
                try overwriteThenRemove(url: child)
            }
            try FileManager.default.removeItem(at: url)
            return
        }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        var remaining = size
        let chunk = 1024 * 1024
        try handle.seek(toOffset: 0)
        while remaining > 0 {
            let n = min(chunk, remaining)
            var bytes = [UInt8](repeating: 0, count: n)
            let status = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
            if status != errSecSuccess {
                throw NSError(domain: "Shredder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not generate random data"])
            }
            try handle.write(contentsOf: Data(bytes))
            remaining -= n
        }
        try handle.synchronize()
        try FileManager.default.removeItem(at: url)
    }
}
