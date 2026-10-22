import Foundation

/// A thread-safe "progress board" that background scans write to and the UI reads from.
///
/// Scans run on background threads and may visit tens of thousands of files per
/// second. Pushing every update to the main thread would freeze the UI, so the
/// scan just writes here and the view model polls a snapshot ~10 times a second.
final class ScanProgress: @unchecked Sendable {
    struct Snapshot {
        var fraction: Double?      // nil = indeterminate
        var currentPath: String
        var message: String
        var itemsScanned: Int
    }

    private let lock = NSLock()
    private var fraction: Double?
    private var currentPath = ""
    private var message = ""
    private var itemsScanned = 0
    private var cancelled = false

    /// Records the file or folder currently being looked at.
    func visit(_ path: String) {
        lock.lock()
        currentPath = path
        itemsScanned += 1
        lock.unlock()
    }

    func setFraction(_ value: Double?) {
        lock.lock()
        fraction = value.map { min(1, max(0, $0)) }
        lock.unlock()
    }

    func setMessage(_ value: String) {
        lock.lock()
        message = value
        lock.unlock()
    }

    /// Marks the scan as cancelled (the Cancel button calls this).
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// Scans check this often and stop early when it becomes true.
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled || Task.isCancelled
    }

    var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(fraction: fraction, currentPath: currentPath, message: message, itemsScanned: itemsScanned)
    }

    /// Helper for scans made of several steps: step 2 of 5 -> 40%.
    func step(_ index: Int, of total: Int, _ title: String) {
        setFraction(total > 0 ? Double(index) / Double(total) : nil)
        setMessage(title)
    }
}
