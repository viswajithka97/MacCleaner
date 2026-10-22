import Foundation
import Combine

/// Tracks folders we could not read, to show the Full Disk Access banner.
@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    /// A few example paths that failed (shown in the banner).
    @Published private(set) var deniedPaths: [String] = []
    @Published private(set) var hasFullDiskAccess: Bool = PermissionCenter.checkFullDiskAccess()
    @Published var bannerDismissed = false

    var shouldShowBanner: Bool { !bannerDismissed && !hasFullDiskAccess && !deniedPaths.isEmpty }

    private init() {}

    func refresh() {
        hasFullDiskAccess = Self.checkFullDiskAccess()
        if hasFullDiskAccess { deniedPaths = [] }
    }

    fileprivate func add(_ path: String) {
        guard deniedPaths.count < 20, !deniedPaths.contains(path) else { return }
        deniedPaths.append(path)
        bannerDismissed = false
    }

    // MARK: - Background-safe API

    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var reportedCount = 0

    /// Called by scanners when reading a path fails. Only permission errors count.
    nonisolated static func noteError(_ error: Error, at url: URL) {
        guard isPermissionError(error) else { return }
        lock.lock()
        let shouldReport = reportedCount < 20
        reportedCount += 1
        lock.unlock()
        guard shouldReport else { return }
        let path = url.tildePath
        Task { @MainActor in PermissionCenter.shared.add(path) }
    }

    nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError || ns.code == NSFileWriteNoPermissionError {
            return true
        }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EPERM) || ns.code == Int(EACCES) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isPermissionError(underlying) }
        return false
    }

    /// Full Disk Access lets us open the (always present) user TCC database.
    nonisolated static func checkFullDiskAccess() -> Bool {
        let tcc = URL.home("Library/Application Support/com.apple.TCC/TCC.db")
        if let handle = try? FileHandle(forReadingFrom: tcc) {
            try? handle.close()
            return true
        }
        return (try? FileManager.default.contentsOfDirectory(atPath: URL.home("Library/Safari").path)) != nil
    }
}
