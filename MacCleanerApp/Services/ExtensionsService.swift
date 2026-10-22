import Foundation

/// Lists extensions and plugins of every kind for the Extensions module.
enum ExtensionsService {

    static func scan(progress: ScanProgress) -> [CleanCategory] {
        var categories: [CleanCategory] = []

        // Browser extensions
        progress.step(0, of: 6, "Browser extensions…")
        let browserItems = BrowserExtensionsService.all().map { ext -> CleanItem in
            progress.visit(ext.location?.path ?? ext.identifier)
            let size = ext.location.map { FileSize.of($0) } ?? 0
            let how = ext.location == nil ? "Disable" : "Remove"
            return CleanItem(name: ext.name, url: ext.location, size: size, isSelected: false,
                             subtitle: "\(ext.parentApp ?? ext.browser.name) · v\(ext.version)\(ext.enabled ? "" : " · disabled") · \(how)",
                             symbol: "puzzlepiece.extension", action: ext.removalAction)
        }
        if !browserItems.isEmpty {
            categories.append(CleanCategory(id: "browser", title: "Browser Extensions", symbol: "globe",
                                            summary: "Extensions in Safari, Chrome, Firefox, Edge, Brave, Arc and Opera.",
                                            items: browserItems.sorted { $0.name < $1.name },
                                            note: "Safari extensions are disabled (they live inside their app). Quit the browser before removing others; synced browsers may reinstall them."))
        }

        // Plugins stored as bundles in Library folders
        let bundleKinds: [(String, String, String, String, [String])] = [
            ("spotlight", "Spotlight Plugins", "magnifyingglass", "Teach Spotlight to index more file types.", ["Spotlight"]),
            ("quicklook", "QuickLook Plugins", "eye", "Generate previews for more file types.", ["QuickLook"]),
            ("prefpanes", "Preference Panes", "gearshape", "Third-party panes in System Settings.", ["PreferencePanes"]),
            ("internet", "Internet Plugins", "network", "Legacy browser plugins (NPAPI).", ["Internet Plug-Ins"]),
        ]
        for (index, kind) in bundleKinds.enumerated() {
            if progress.isCancelled { return categories }
            progress.step(index + 1, of: 6, "\(kind.1)…")
            var items: [CleanItem] = []
            for sub in kind.4 {
                for root in [URL.home("Library/" + sub), URL(fileURLWithPath: "/Library/" + sub)] {
                    for bundle in FileSize.children(of: root) where !bundle.lastPathComponent.hasPrefix(".") {
                        progress.visit(bundle.path)
                        let name = Bundle(url: bundle)?.object(forInfoDictionaryKey: "CFBundleName") as? String
                            ?? bundle.deletingPathExtension().lastPathComponent
                        items.append(CleanItem(name: name, url: bundle, size: FileSize.of(bundle), isSelected: false,
                                               subtitle: root.path.hasPrefix(NSHomeDirectory()) ? "For you only" : "For all users",
                                               symbol: kind.2, action: UninstallerService.removal(for: bundle)))
                    }
                }
            }
            // Modern QuickLook extensions are app extensions registered with PlugInKit.
            if kind.0 == "quicklook" {
                for entry in PluginKit.list(protocols: ["com.apple.quicklook.preview", "com.apple.quicklook.thumbnail"])
                where !entry.identifier.hasPrefix("com.apple.") {
                    items.append(CleanItem(name: entry.parentName.map { "\($0) — \(entry.displayName)" } ?? entry.displayName,
                                           url: entry.path, size: 0, isSelected: false,
                                           subtitle: "App extension\(entry.enabled ? "" : " · disabled") · Disable",
                                           symbol: "eye", action: .disablePlugin(identifier: entry.identifier)))
                }
            }
            if !items.isEmpty {
                categories.append(CleanCategory(id: kind.0, title: kind.1, symbol: kind.2, summary: kind.3, items: items))
            }
        }

        // Login items
        progress.step(5, of: 6, "Login items…")
        let login = LoginItemsService.list()
        let loginItems = login.items.filter(\.enabled).map { item in
            CleanItem(name: item.name, url: URL(fileURLWithPath: item.path), size: 0, isSelected: false,
                      subtitle: item.exists ? item.path : "Missing: \(item.path)", symbol: "person.crop.circle",
                      action: .removeLoginItem(name: item.name, path: item.path))
        }
        if !loginItems.isEmpty || login.error != nil {
            categories.append(CleanCategory(id: "login", title: "Login Items", symbol: "person.crop.circle",
                                            summary: "Apps that open when you log in.", items: loginItems,
                                            warning: login.error))
        }
        progress.setFraction(1)
        return categories
    }
}
