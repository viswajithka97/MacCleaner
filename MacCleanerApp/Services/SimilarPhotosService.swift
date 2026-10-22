import AppKit
import Vision
import Photos
import ImageIO
import UniformTypeIdentifiers

/// One photo being compared.
struct PhotoCandidate: Identifiable, Hashable {
    enum Source: Hashable { case file(URL), library(String) }
    let id = UUID()
    var source: Source
    var name: String
    var pixelWidth: Int
    var pixelHeight: Int
    var sharpness: Double
    var size: Int64
    var date: Date?
    var isSelected = false

    var pixels: Int { pixelWidth * pixelHeight }
    /// Higher is better: resolution first, sharpness to break ties.
    var qualityScore: Double { Double(pixels) * (1 + sharpness / 1000) }

    static func == (a: PhotoCandidate, b: PhotoCandidate) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct PhotoGroup: Identifiable {
    let id = UUID()
    var photos: [PhotoCandidate]
    /// The photo suggested to keep.
    var bestID: UUID? { photos.max(by: { $0.qualityScore < $1.qualityScore })?.id }
}

/// Finds visually similar photos using Vision feature prints.
enum SimilarPhotosService {

    /// Feature print + metadata for one image.
    private struct Analyzed {
        var candidate: PhotoCandidate
        var print: VNFeaturePrintObservation
    }

    static func requestPhotosAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// - Parameter threshold: feature-print distance under which two photos count as similar.
    static func scan(folders: [URL], includeLibrary: Bool, threshold: Float, progress: ScanProgress) async -> [PhotoGroup] {
        var analyzed: [Analyzed] = []

        // 1. Image files in the chosen folders
        progress.setMessage("Finding images…")
        let files = imageFiles(in: folders, progress: progress)
        if progress.isCancelled { return [] }
        for (index, url) in files.enumerated() {
            if progress.isCancelled { return [] }
            progress.visit(url.path)
            progress.setFraction(Double(index) / Double(max(1, files.count)) * (includeLibrary ? 0.45 : 0.9))
            guard let cg = thumbnail(url), let print = featurePrint(cg) else { continue }
            let props = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } as? [CFString: Any]
            let width = props?[kCGImagePropertyPixelWidth] as? Int ?? cg.width
            let height = props?[kCGImagePropertyPixelHeight] as? Int ?? cg.height
            let candidate = PhotoCandidate(source: .file(url), name: url.lastPathComponent, pixelWidth: width, pixelHeight: height,
                                           sharpness: sharpness(cg), size: FileSize.of(file: url), date: FileSize.modified(url))
            analyzed.append(Analyzed(candidate: candidate, print: print))
        }

        // 2. Photos library (read-only analysis; deletion later goes through PhotoKit)
        if includeLibrary, await requestPhotosAccess() {
            progress.setMessage("Analyzing your Photos library…")
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let assets = PHAsset.fetchAssets(with: .image, options: options)
            let manager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            requestOptions.deliveryMode = .fastFormat
            requestOptions.resizeMode = .fast
            requestOptions.isNetworkAccessAllowed = false
            for index in 0..<assets.count {
                if progress.isCancelled { return [] }
                let asset = assets.object(at: index)
                progress.visit("Photos: \(asset.creationDate.map { ByteFormat.dateTime($0) } ?? asset.localIdentifier)")
                progress.setFraction(0.45 + 0.45 * Double(index) / Double(max(1, assets.count)))
                var image: NSImage?
                manager.requestImage(for: asset, targetSize: CGSize(width: 512, height: 512), contentMode: .aspectFit,
                                     options: requestOptions) { result, _ in image = result }
                guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil), let print = featurePrint(cg) else { continue }
                let resources = PHAssetResource.assetResources(for: asset)
                let bytes = (resources.first?.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
                let name = resources.first?.originalFilename ?? "Photo"
                let candidate = PhotoCandidate(source: .library(asset.localIdentifier), name: name,
                                               pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
                                               sharpness: sharpness(cg), size: bytes, date: asset.creationDate)
                analyzed.append(Analyzed(candidate: candidate, print: print))
            }
        }

        // 3. Group: compare each photo with its neighbours in time (similar shots are taken close
        //    together); all pairs when the set is small.
        progress.setMessage("Grouping similar photos…")
        analyzed.sort { ($0.candidate.date ?? .distantPast) < ($1.candidate.date ?? .distantPast) }
        let n = analyzed.count
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        let window = n <= 1500 ? n : 40
        for i in 0..<n {
            if progress.isCancelled { return [] }
            if i % 50 == 0 { progress.setFraction(0.9 + 0.1 * Double(i) / Double(max(1, n))) }
            for j in (i + 1)..<min(n, i + 1 + window) {
                var distance: Float = 0
                if (try? analyzed[i].print.computeDistance(&distance, to: analyzed[j].print)) != nil, distance < threshold {
                    parent[find(j)] = find(i)
                }
            }
        }
        var buckets: [Int: [PhotoCandidate]] = [:]
        for i in 0..<n { buckets[find(i), default: []].append(analyzed[i].candidate) }
        progress.setFraction(1)
        return buckets.values.filter { $0.count > 1 }.map { photos in
            var group = PhotoGroup(photos: photos)
            let best = group.bestID
            for index in group.photos.indices { group.photos[index].isSelected = group.photos[index].id != best }
            return group
        }.sorted { $0.photos.count > $1.photos.count }
    }

    /// Every image file under the folders (Photos libraries are skipped; they're read through PhotoKit).
    private static func imageFiles(in folders: [URL], progress: ScanProgress) -> [URL] {
        let exclusions = SettingsStore.snapshot().exclusions
        var files: [URL] = []
        for folder in folders {
            guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if progress.isCancelled { return files }
                progress.visit(url.path)
                if url.pathExtension == "photoslibrary" { e.skipDescendants(); continue }
                if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                   !PathSafety.isExcluded(url.path, exclusions: exclusions) {
                    files.append(url)
                }
            }
        }
        return files
    }

    /// A small version of the image (fast to analyze).
    private static func thumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 512,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func featurePrint(_ image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        // Pinned so distances are comparable on every macOS: near-duplicates measure ~5–10,
        // different scenes 15+.
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return request.results?.first
    }

    /// Variance of the Laplacian on a 256px grayscale copy: higher = sharper.
    static func sharpness(_ image: CGImage) -> Double {
        let side = 256
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var sum = 0.0, sumSquares = 0.0, count = 0.0
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let i = y * side + x
                let value = 4 * Double(pixels[i]) - Double(pixels[i - 1]) - Double(pixels[i + 1])
                    - Double(pixels[i - side]) - Double(pixels[i + side])
                sum += value; sumSquares += value * value; count += 1
            }
        }
        let mean = sum / count
        return sumSquares / count - mean * mean
    }

    /// Thumbnail for display.
    static func image(for candidate: PhotoCandidate, side: CGFloat = 220) -> NSImage? {
        switch candidate.source {
        case .file(let url):
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                            kCGImageSourceThumbnailMaxPixelSize: side * 2,
                                                                            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        case .library(let id):
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.deliveryMode = .opportunistic
            var image: NSImage?
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side * 2, height: side * 2),
                                                  contentMode: .aspectFill, options: options) { result, _ in image = result }
            return image
        }
    }
}
