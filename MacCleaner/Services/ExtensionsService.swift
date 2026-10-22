import Foundation

enum ExtensionsService {
    static func scan(callbacks: ScanCallbacks) async -> [CleanableCategory] {
        await Task.detached(priority: .userInitiated) {
            var cats: [CleanableCategory] = []
            cats.append(browserExtensions(callbacks: callbacks))
            cats.append(folderCategory(
                name: "Spotlight plugins",
                symbol: "magnifyingglass",
                roots: [
                    FileScanSupport.library().appendingPathComponent("Spotlight"),
                    URL(fileURLWithPath: "/Library/Spotlight")
                ],
                ext: "mdimporter",
                callbacks: callbacks
            ))
            cats.append(folderCategory(
                name: "Quick Look plugins",
                symbol: "eye",
                roots: [
                    FileScanSupport.library().appendingPathComponent("QuickLook"),
                    URL(fileURLWithPath: "/Library/QuickLook")
                ],
                ext: "qlgenerator",
                callbacks: callbacks
            ))
            cats.append(folderCategory(
                name: "Preference Panes",
                symbol: "switch.2",
                roots: [
                    FileScanSupport.library().appendingPathComponent("PreferencePanes"),
                    URL(fileURLWithPath: "/Library/PreferencePanes")
                ],
                ext: "prefPane",
                callbacks: callbacks
            ))
            cats.append(folderCategory(
                name: "Internet plugins",
                symbol: "globe",
                roots: [
                    FileScanSupport.library().appendingPathComponent("Internet Plug-Ins"),
                    URL(fileURLWithPath: "/Library/Internet Plug-Ins")
                ],
                ext: "",
                callbacks: callbacks
            ))
            let login = OptimizationService.loginItems()
            cats.append(CleanableCategory(name: "Login items", symbol: "person.crop.circle", items: login))
            return cats
        }.value
    }

    private static func browserExtensions(callbacks: ScanCallbacks) -> CleanableCategory {
        var items: [CleanableItem] = []
        let lib = FileScanSupport.library()
        let chromeLike: [(String, URL)] = [
            ("Chrome", lib.appendingPathComponent("Application Support/Google/Chrome/Default/Extensions")),
            ("Edge", lib.appendingPathComponent("Application Support/Microsoft Edge/Default/Extensions")),
            ("Brave", lib.appendingPathComponent("Application Support/BraveSoftware/Brave-Browser/Default/Extensions")),
            ("Arc", lib.appendingPathComponent("Application Support/Arc/User Data/Default/Extensions")),
            ("Opera", lib.appendingPathComponent("Application Support/com.operasoftware.Opera/Default/Extensions"))
        ]
        for (browser, dir) in chromeLike {
            for ext in FileScanSupport.listChildren(of: dir) {
                callbacks.progress(0.3, ext.path)
                let versions = FileScanSupport.listChildren(of: ext)
                let manifest = versions.first?.appendingPathComponent("manifest.json")
                var name = ext.lastPathComponent
                if let manifest, let data = try? Data(contentsOf: manifest),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    name = (json["name"] as? String) ?? name
                }
                items.append(FileScanSupport.item(name: "\(browser): \(name)", url: ext, subtitle: ext.path))
            }
        }
        let safari = lib.appendingPathComponent("Safari/Extensions")
        for ext in FileScanSupport.listChildren(of: safari) {
            items.append(FileScanSupport.item(name: "Safari: \(ext.lastPathComponent)", url: ext))
        }
        let firefox = lib.appendingPathComponent("Application Support/Firefox/Profiles")
        for profile in FileScanSupport.listChildren(of: firefox) {
            let extDir = profile.appendingPathComponent("extensions")
            for ext in FileScanSupport.listChildren(of: extDir) {
                items.append(FileScanSupport.item(name: "Firefox: \(ext.lastPathComponent)", url: ext))
            }
        }
        return CleanableCategory(name: "Browser extensions", symbol: "puzzlepiece.extension", items: items)
    }

    private static func folderCategory(name: String, symbol: String, roots: [URL], ext: String, callbacks: ScanCallbacks) -> CleanableCategory {
        var items: [CleanableItem] = []
        for root in roots {
            for child in FileScanSupport.listChildren(of: root) {
                callbacks.progress(0.5, child.path)
                if ext.isEmpty || child.pathExtension == ext || child.lastPathComponent.contains(ext) {
                    items.append(FileScanSupport.item(name: child.lastPathComponent, url: child, subtitle: child.path))
                }
            }
        }
        return CleanableCategory(name: name, symbol: symbol, items: items)
    }
}
