import CryptoKit
import Foundation

enum Hashing {
    static func sha256(url: URL, limit: Int? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            let chunk = 1024 * 256
            let toRead = min(chunk, remaining)
            let data: Data
            do {
                guard let piece = try handle.read(upToCount: toRead) else { break }
                data = piece
            } catch {
                return nil
            }
            if data.isEmpty { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
