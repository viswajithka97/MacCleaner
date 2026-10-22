import AppKit
import Foundation

struct AppUpdate: Identifiable, Hashable {
    var id: String { path + (newVersion ?? "") }
    var name: String
    var path: String
    var currentVersion: String
    var newVersion: String?
    var releaseNotes: String
    var source: Source
    var actionURL: String?
    var caskName: String?

    enum Source: String {
        case sparkle, appStore, homebrew
    }
}

enum UpdaterService {
    static func scan(apps: [InstalledApp], callbacks: ScanCallbacks) async -> [AppUpdate] {
        var updates: [AppUpdate] = []
        let casks = await homebrewOutdated()
        for app in apps {
            if callbacks.isCancelled() { break }
            callbacks.progress(0.4, app.path)
            if let sparkle = await sparkleUpdate(for: app) {
                updates.append(sparkle)
                continue
            }
            if app.source == "App Store", let mas = await masUpdate(for: app) {
                updates.append(mas)
                continue
            }
            if let cask = casks[app.name.lowercased()] ?? casks[app.bundleId.lowercased()] {
                updates.append(cask)
            }
        }
        return updates
    }

    private static func sparkleUpdate(for app: InstalledApp) async -> AppUpdate? {
        let info = Bundle(path: app.path)?.infoDictionary ?? [:]
        guard let feed = info["SUFeedURL"] as? String ?? info["SUFeedURL"] as? String, let url = URL(string: feed) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let xml = String(data: data, encoding: .utf8) ?? ""
        let version = firstXML(xml, tag: "sparkle:shortVersionString") ?? firstXML(xml, tag: "sparkle:version") ?? firstXML(xml, tag: "title")
        let notes = firstXML(xml, tag: "description") ?? firstXML(xml, tag: "sparkle:releaseNotesLink") ?? ""
        let enclosure = attribute(xml, tag: "enclosure", attribute: "url")
        guard let version, isNewer(version, than: app.version) else { return nil }
        return AppUpdate(name: app.name, path: app.path, currentVersion: app.version, newVersion: version, releaseNotes: stripHTML(notes), source: .sparkle, actionURL: enclosure)
    }

    private static func masUpdate(for app: InstalledApp) async -> AppUpdate? {
        guard !app.bundleId.isEmpty,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(app.bundleId)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first else { return nil }
        let version = first["version"] as? String ?? ""
        let notes = first["releaseNotes"] as? String ?? ""
        let track = first["trackViewUrl"] as? String
        guard isNewer(version, than: app.version) else { return nil }
        return AppUpdate(name: app.name, path: app.path, currentVersion: app.version, newVersion: version, releaseNotes: notes, source: .appStore, actionURL: track)
    }

    private static func homebrewOutdated() async -> [String: AppUpdate] {
        guard let brew = ProcessRunner.which("brew") else { return [:] }
        guard let result = try? ProcessRunner.run(brew, arguments: ["outdated", "--cask", "--json=v2"]) else { return [:] }
        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]] else { return [:] }
        var map: [String: AppUpdate] = [:]
        for cask in casks {
            let name = cask["name"] as? String ?? cask["token"] as? String ?? ""
            let token = cask["token"] as? String ?? name
            let current = (cask["installed_versions"] as? [String])?.first ?? ""
            let latest = cask["current_version"] as? String ?? ""
            let update = AppUpdate(name: name, path: token, currentVersion: current, newVersion: latest, releaseNotes: "Homebrew cask \(token)", source: .homebrew, caskName: token)
            map[name.lowercased()] = update
            map[token.lowercased()] = update
        }
        return map
    }

    static func apply(_ update: AppUpdate) {
        switch update.source {
        case .appStore:
            if let s = update.actionURL, let url = URL(string: s) { NSWorkspace.shared.open(url) }
        case .sparkle:
            if let s = update.actionURL, let url = URL(string: s) { NSWorkspace.shared.open(url) }
        case .homebrew:
            if let brew = ProcessRunner.which("brew"), let cask = update.caskName {
                DispatchQueue.global().async {
                    _ = try? ProcessRunner.run(brew, arguments: ["upgrade", "--cask", cask], timeout: 600)
                }
            }
        }
    }

    private static func isNewer(_ new: String, than old: String) -> Bool {
        new.compare(old, options: .numeric) == .orderedDescending
    }

    private static func firstXML(_ xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(xml.startIndex..., in: xml)
        guard let match = regex.firstMatch(in: xml, range: range), let r = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attribute(_ xml: String, tag: String, attribute: String) -> String? {
        let pattern = "<\(tag)[^>]*\(attribute)=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(xml.startIndex..., in: xml)
        guard let match = regex.firstMatch(in: xml, range: range), let r = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[r])
    }

    private static func stripHTML(_ string: String) -> String {
        string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
