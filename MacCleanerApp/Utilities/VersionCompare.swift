import Foundation

/// Compares version strings like "1.10.2" vs "1.9" the way humans expect.
enum VersionCompare {

    /// Splits "2.3b4 (512)" into numeric parts [2, 3, 4, 512].
    static func components(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    /// True if `candidate` is a newer version than `current`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        guard !a.isEmpty, !b.isEmpty else { return false }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
