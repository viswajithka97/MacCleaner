import AppKit
import Foundation
import Photos
import Vision

struct PhotoPairItem: Identifiable, Hashable {
    var id: UUID = UUID()
    var item: CleanableItem
    var width: Int
    var height: Int
    var sharpness: Float
    var isBest: Bool
}

struct SimilarPhotoGroup: Identifiable, Hashable {
    var id: UUID = UUID()
    var photos: [PhotoPairItem]
}

enum SimilarPhotosService {
    static func scan(folders: [URL], includePhotosLibrary: Bool, callbacks: ScanCallbacks) async -> [SimilarPhotoGroup] {
        var prints: [(CleanableItem, VNFeaturePrintObservation, Int, Int, Float)] = []

        await Task.detached(priority: .userInitiated) {
            let exts = Set(["jpg", "jpeg", "png", "heic", "tif", "tiff", "webp"])
            for folder in folders {
                FileScanSupport.collect(at: folder, skipPackages: true, callbacks: callbacks) { url, values in
                    guard values.isRegularFile == true else { return }
                    guard exts.contains(url.pathExtension.lowercased()) else { return }
                    if let result = featurePrint(url: url) {
                        let item = FileScanSupport.item(name: url.lastPathComponent, url: url, selected: false)
                        prints.append((item, result.0, result.1, result.2, result.3))
                    }
                }
            }
        }.value

        if includePhotosLibrary {
            let status = await TrashBinsService.requestPhotos()
            if status == .authorized || status == .limited {
                let assets = PHAsset.fetchAssets(with: .image, options: nil)
                let count = assets.count
                for index in 0..<min(count, 400) {
                    if callbacks.isCancelled() { break }
                    let asset = assets.object(at: index)
                    callbacks.progress(Double(index) / Double(max(count, 1)), "Photos library")
                    if let url = requestFileURL(asset: asset), let result = featurePrint(url: url) {
                        let item = CleanableItem(
                            name: asset.localIdentifier,
                            path: url.path,
                            size: FileSizing.allocatedSize(at: url),
                            selected: false,
                            subtitle: "Photos library",
                            photoAssetId: asset.localIdentifier
                        )
                        prints.append((item, result.0, result.1, result.2, result.3))
                    }
                }
            }
        }

        var used = Set<Int>()
        var groups: [SimilarPhotoGroup] = []
        let threshold: Float = 8
        for i in 0..<prints.count {
            if used.contains(i) { continue }
            var cluster = [i]
            for j in (i + 1)..<prints.count {
                if used.contains(j) { continue }
                var distance: Float = 0
                try? prints[i].1.computeDistance(&distance, to: prints[j].1)
                if distance < threshold {
                    cluster.append(j)
                    used.insert(j)
                }
            }
            if cluster.count > 1 {
                used.insert(i)
                var photos: [PhotoPairItem] = cluster.map { idx in
                    let p = prints[idx]
                    return PhotoPairItem(item: p.0, width: p.2, height: p.3, sharpness: p.4, isBest: false)
                }
                if let best = photos.indices.max(by: { a, b in
                    let la = photos[a].width * photos[a].height
                    let lb = photos[b].width * photos[b].height
                    if la == lb { return photos[a].sharpness < photos[b].sharpness }
                    return la < lb
                }) {
                    for i in photos.indices {
                        photos[i].isBest = i == best
                        photos[i].item.selected = i != best
                    }
                }
                groups.append(SimilarPhotoGroup(photos: photos))
            }
        }
        return groups
    }

    private static func featurePrint(url: URL) -> (VNFeaturePrintObservation, Int, Int, Float)? {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let sharpness = laplacian(cg)
            return (observation, cg.width, cg.height, sharpness)
        } catch {
            return nil
        }
    }

    private static func laplacian(_ image: CGImage) -> Float {
        // Cheap sharpness proxy: standard deviation of a downsampled grayscale buffer.
        guard let data = image.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return 0 }
        let length = CFDataGetLength(data)
        if length == 0 { return 0 }
        var sum: Float = 0
        var sumSq: Float = 0
        let step = max(length / 4000, 1)
        var n: Float = 0
        var i = 0
        while i < length {
            let v = Float(ptr[i])
            sum += v
            sumSq += v * v
            n += 1
            i += step
        }
        guard n > 0 else { return 0 }
        let mean = sum / n
        return max(sumSq / n - mean * mean, 0)
    }

    private static func requestFileURL(asset: PHAsset) -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first else { return nil }
        // PhotoKit does not always expose a filesystem path. We write a temp preview for Vision.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mc-\(UUID().uuidString).jpg")
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .fastFormat
        var resultURL: URL?
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            if let data {
                try? data.write(to: tmp)
                resultURL = tmp
            }
        }
        _ = resource
        return resultURL
    }
}
