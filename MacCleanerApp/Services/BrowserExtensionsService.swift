import Foundation

/// An extension installed in a browser.
struct BrowserExtension: Identifiable {
    var id: String { browser.rawValue + ":" + identifier + ":" + (location?.path ?? "") }
    var browser: BrowserID
    var identifier: String
    var name: String
    var version: String
    /// Folder (Chromium) or .xpi file (Firefox). nil for Safari app extensions.
    var location: URL?
    var enabled: Bool
    var parentApp: String?

    /// How this extension is removed.
    var removalAction: RemovalAction {
        if let location { return .remove(location) }
        return .disablePlugin(identifier: identifier)
    }
}

/// Lists extensions for Safari, Chromium browsers and Firefox.
enum BrowserExtensionsService {

    static func all() -> [BrowserExtension] {
        var result: [BrowserExtension] = []
        for browser in BrowserID.allCases where browser.isInstalled {
            switch browser.engine {
            case .chromium: result += chromium(browser)
            case .firefox: result += firefox(browser)
            case .webkit: result += safari()
            }
        }
        return result
    }

    // MARK: Chromium: <profile>/Extensions/<id>/<version>/manifest.json

    private static func chromium(_ browser: BrowserID) -> [BrowserExtension] {
        var result: [BrowserExtension] = []
        for profile in browser.profiles {
            let folder = profile.appendingPathComponent("Extensions")
            for extFolder in FileSize.children(of: folder) where FileSize.isDirectory(extFolder) {
                let versions = FileSize.children(of: extFolder).filter { FileSize.isDirectory($0) }
                guard let latest = versions.max(by: { VersionCompare.isNewer($1.lastPathComponent, than: $0.lastPathComponent) }),
                      let data = try? Data(contentsOf: latest.appendingPathComponent("manifest.json")),
                      let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let rawName = manifest["name"] as? String ?? extFolder.lastPathComponent
                let name = localized(rawName, folder: latest, defaultLocale: manifest["default_locale"] as? String)
                let profileName = profile.lastPathComponent == browser.dataRoot.lastPathComponent ? "" : " (\(profile.lastPathComponent))"
                result.append(BrowserExtension(browser: browser, identifier: extFolder.lastPathComponent,
                                               name: name, version: manifest["version"] as? String ?? latest.lastPathComponent,
                                               location: extFolder, enabled: true,
                                               parentApp: browser.name + profileName))
            }
        }
        return result
    }

    /// Resolves "__MSG_appName__" using _locales/<locale>/messages.json.
    private static func localized(_ value: String, folder: URL, defaultLocale: String?) -> String {
        guard value.hasPrefix("__MSG_"), value.hasSuffix("__") else { return value }
        let key = String(value.dropFirst(6).dropLast(2)).lowercased()
        for locale in [defaultLocale, "en", "en_US", "en_GB"].compactMap({ $0 }) {
            let file = folder.appendingPathComponent("_locales/\(locale)/messages.json")
            guard let data = try? Data(contentsOf: file),
                  let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (k, v) in messages where k.lowercased() == key {
                if let message = (v as? [String: Any])?["message"] as? String { return message }
            }
        }
        return value
    }

    // MARK: Firefox: <profile>/extensions.json

    private static func firefox(_ browser: BrowserID) -> [BrowserExtension] {
        var result: [BrowserExtension] = []
        for profile in browser.profiles {
            guard let data = try? Data(contentsOf: profile.appendingPathComponent("extensions.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let addons = json["addons"] as? [[String: Any]] else { continue }
            for addon in addons where (addon["type"] as? String) == "extension" && (addon["location"] as? String) == "app-profile" {
                let id = addon["id"] as? String ?? "?"
                let name = (addon["defaultLocale"] as? [String: Any])?["name"] as? String ?? id
                let path = (addon["path"] as? String).map { URL(fileURLWithPath: $0) }
                    ?? profile.appendingPathComponent("extensions/\(id).xpi")
                result.append(BrowserExtension(browser: browser, identifier: id, name: name,
                                               version: addon["version"] as? String ?? "",
                                               location: path, enabled: addon["active"] as? Bool ?? true,
                                               parentApp: "Firefox (\(profile.lastPathComponent))"))
            }
        }
        return result
    }

    // MARK: Safari: app extensions registered with PlugInKit

    private static func safari() -> [BrowserExtension] {
        let entries = PluginKit.list(protocols: ["com.apple.Safari.web-extension", "com.apple.Safari.extension",
                                                 "com.apple.Safari.content-blocker"])
        return entries.filter { !$0.identifier.hasPrefix("com.apple.") }.map { entry in
            BrowserExtension(browser: .safari, identifier: entry.identifier,
                             name: entry.displayName.isEmpty ? (entry.parentName ?? entry.identifier) : entry.displayName,
                             version: entry.version, location: nil, enabled: entry.enabled,
                             parentApp: entry.parentName ?? entry.parentBundle?.lastPathComponent)
        }
    }
}

/// Reads app extensions registered with PlugInKit (`pluginkit -mAvvv -p <protocol>`).
enum PluginKit {
    struct Entry {
        var identifier: String
        var version: String
        var path: URL?
        var displayName: String
        var parentName: String?
        var parentBundle: URL?
        var enabled: Bool
    }

    static func list(protocols: [String]) -> [Entry] {
        var entries: [Entry] = []
        for proto in protocols {
            let output = Shell.run("/usr/bin/pluginkit", ["-mAvvv", "-p", proto], timeout: 20).output
            var current: Entry?
            for rawLine in output.components(separatedBy: "\n") {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty {
                    if let entry = current { entries.append(entry) }
                    current = nil
                    continue
                }
                if line.contains(" = "), current != nil {
                    let parts = line.components(separatedBy: " = ")
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts.dropFirst().joined(separator: " = ")
                    switch key {
                    case "Path": current?.path = URL(fileURLWithPath: value)
                    case "Display Name": current?.displayName = value
                    case "Parent Name": current?.parentName = value
                    case "Parent Bundle": current?.parentBundle = URL(fileURLWithPath: value)
                    default: break
                    }
                } else if !line.hasPrefix("("), let open = line.firstIndex(of: "("), line.hasSuffix(")") {
                    // ("(no matches)" starts with a parenthesis and is skipped.)
                    if let entry = current { entries.append(entry) }
                    // A leading "-" means the user disabled it, "+" means enabled.
                    let enabled = !rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("-")
                    var id = String(line[..<open]).trimmingCharacters(in: .whitespaces)
                    if id.hasPrefix("+") || id.hasPrefix("-") || id.hasPrefix("!") || id.hasPrefix("=") {
                        id = String(id.dropFirst()).trimmingCharacters(in: .whitespaces)
                    }
                    let version = String(line[line.index(after: open)..<line.index(before: line.endIndex)])
                    current = Entry(identifier: id, version: version, path: nil, displayName: id,
                                    parentName: nil, parentBundle: nil, enabled: enabled)
                }
            }
            if let entry = current { entries.append(entry) }
        }
        // The same extension may be listed for several protocols.
        var seen = Set<String>()
        return entries.filter { seen.insert($0.identifier).inserted }
    }
}
