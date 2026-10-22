import Foundation
import CryptoKit

/// SHA-256 hashing of files, used by the Duplicates finder.
enum Hashing {

    /// Hashes the first `limit` bytes of a file (a cheap "partial hash").
    static func partialHash(_ url: URL, limit: Int = 64 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit) else { return nil }
        return SHA256.hash(data: data).hex
    }

    /// Hashes the entire file in 1 MB chunks so large files don't fill memory.
    static func fullHash(_ url: URL, progress: ScanProgress? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if progress?.isCancelled == true { return nil }
            let chunk: Data?
            do { chunk = try handle.read(upToCount: 1024 * 1024) } catch { return nil }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().hex
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
