import AppKit
import CoreServices

/// Finds installed applications and reads their details.
enum AppCatalog {

    /// Folders searched for apps. Vendor sub-folders (e.g. "/Applications/Adobe X/") are searched one level deep.
    static let roots: [URL] = [URL(fileURLWithPath: "/Applications"), .home("Applications")]

    /// Every .app bundle in /Applications and ~/Applications.
    static func appBundles() -> [URL] {
        var result: [URL] = []
        for root in roots {
            for child in FileSize.children(of: root) {
                if child.pathExtension == "app" {
                    result.append(child)
                } else if FileSize.isDirectory(child) {
                    for grandchild in FileSize.children(of: child) where grandchild.pathExtension == "app" {
                        result.append(grandchild)
                    }
                }
            }
        }
        return result
    }

    /// Reads name, version, bundle ID, source and last-opened date (size is filled in later).
    static func info(for url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let bundleID = bundle.bundleIdentifier ?? ""
        // The file name is what people see in Finder; fall back to the bundle's name.
        let fileName = url.deletingPathExtension().lastPathComponent
        let name = fileName.isEmpty ? (info["CFBundleName"] as? String ?? "App") : fileName
        let isAppStore = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
        let isApple = bundleID.hasPrefix("com.apple.")
        return InstalledApp(url: url,
                            name: name,
                            bundleID: bundleID,
                            version: info["CFBundleShortVersionString"] as? String ?? "",
                            buildVersion: info["CFBundleVersion"] as? String ?? "",
                            size: nil,
                            lastOpened: lastUsedDate(url),
                            isAppStore: isAppStore,
                            isApple: isApple)
    }

    static func installedApps(progress: ScanProgress? = nil) -> [InstalledApp] {
        let bundles = appBundles()
        var apps: [InstalledApp] = []
        for (index, url) in bundles.enumerated() {
            if progress?.isCancelled == true { break }
            progress?.visit(url.path)
            progress?.setFraction(Double(index) / Double(max(1, bundles.count)))
            if let app = info(for: url) { apps.append(app) }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Spotlight's "Last opened" date for a file or app.
    static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// The app's icon (main thread only).
    @MainActor
    static func icon(_ url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
