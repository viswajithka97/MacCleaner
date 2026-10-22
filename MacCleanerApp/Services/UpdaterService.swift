import AppKit

/// Checks for app updates from Sparkle appcasts, the Mac App Store and Homebrew.
enum UpdaterService {

    struct Outcome { var ok: Bool; var message: String }

    /// Checks every installed app. Runs up to 8 network checks at a time.
    static func checkAll(progress: ScanProgress) async -> [AppUpdate] {
        progress.setMessage("Reading installed apps…")
        let apps = AppCatalog.installedApps(progress: progress)
        var updates: [AppUpdate] = []
        var done = 0

        await withTaskGroup(of: AppUpdate?.self) { group in
            var iterator = apps.makeIterator()
            func addNext() -> Bool {
                guard let app = iterator.next() else { return false }
                group.addTask { await check(app) }
                return true
            }
            for _ in 0..<8 { if !addNext() { break } }
            while let result = await group.next() {
                done += 1
                progress.setFraction(Double(done) / Double(max(1, apps.count)) * 0.85)
                progress.setMessage("Checked \(done) of \(apps.count) apps")
                if let result { updates.append(result) }
                if progress.isCancelled { group.cancelAll(); break }
                _ = addNext()
            }
        }

        if !progress.isCancelled, let brew = Shell.which("brew") {
            progress.setMessage("Checking Homebrew casks…")
            progress.visit(brew)
            let casks = await homebrewOutdated(brew: brew)
            // Prefer the Homebrew entry when an app is managed by a cask (avoids duplicates).
            let caskNames = Set(casks.map { normalize($0.appName) })
            updates.removeAll { caskNames.contains(normalize($0.appName)) && !isAppStore($0) }
            updates += casks
        }
        progress.setFraction(1)
        return updates.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    private static func isAppStore(_ update: AppUpdate) -> Bool {
        if case .appStore = update.source { return true }
        return false
    }

    private static func normalize(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
    }

    /// Checks one app (App Store first, then Sparkle).
    static func check(_ app: InstalledApp) async -> AppUpdate? {
        if app.isAppStore, !app.bundleID.isEmpty {
            return await checkAppStore(app)
        }
        if let feed = Bundle(url: app.url)?.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           let url = URL(string: feed.trimmingCharacters(in: .whitespaces)) {
            return await checkSparkle(app, feed: url)
        }
        return nil
    }

    // MARK: - Mac App Store

    private static func checkAppStore(_ app: InstalledApp) async -> AppUpdate? {
        let country = Locale.current.region?.identifier.lowercased() ?? "us"
        for query in ["&country=\(country)", ""] {
            guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(app.bundleID)&entity=macSoftware\(query)"),
                  let data = try? await fetch(url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = (json["results"] as? [[String: Any]])?.first,
                  let version = result["version"] as? String else { continue }
            guard VersionCompare.isNewer(version, than: app.version) else { return nil }
            let page = (result["trackViewUrl"] as? String).flatMap { URL(string: $0.replacingOccurrences(of: "https://", with: "macappstore://")) }
                ?? URL(string: "macappstore://apps.apple.com/app/id\(result["trackId"] as? Int ?? 0)")!
            return AppUpdate(appName: app.name, bundleID: app.bundleID, appURL: app.url, currentVersion: app.version,
                             newVersion: version, releaseNotes: result["releaseNotes"] as? String ?? "",
                             source: .appStore(pageURL: page))
        }
        return nil
    }

    // MARK: - Sparkle

    private static func checkSparkle(_ app: InstalledApp, feed: URL) async -> AppUpdate? {
        guard let data = try? await fetch(feed) else { return nil }
        let parser = AppcastParser(data: data)
        let items = parser.parse()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"

        // Newest item that runs on this macOS and isn't a beta channel.
        let candidates = items.filter { item in
            item.channel == nil && (item.minimumSystemVersion.map { !VersionCompare.isNewer($0, than: os) } ?? true)
        }
        guard let best = candidates.max(by: { VersionCompare.isNewer($1.version, than: $0.version) }) else { return nil }

        // Sparkle compares sparkle:version with CFBundleVersion.
        let current = app.buildVersion.isEmpty ? app.version : app.buildVersion
        let newer = VersionCompare.isNewer(best.version, than: current)
            || (best.shortVersion.map { VersionCompare.isNewer($0, than: app.version) } ?? false)
        guard newer else { return nil }
        // Avoid false positives when only the build number format differs.
        if let short = best.shortVersion, short == app.version { return nil }

        var notes = best.notes
        if notes.isEmpty, let link = best.releaseNotesLink, let data = try? await fetch(link) {
            notes = String(decoding: data, as: UTF8.self)
        }
        return AppUpdate(appName: app.name, bundleID: app.bundleID, appURL: app.url, currentVersion: app.version,
                         newVersion: best.shortVersion ?? best.version, releaseNotes: stripHTML(notes),
                         source: .sparkle(downloadURL: best.downloadURL))
    }

    // MARK: - Homebrew

    private static func homebrewOutdated(brew: String) async -> [AppUpdate] {
        // Refresh formula data first so results are current (time-limited).
        _ = await Shell.runAsync(brew, ["update", "--quiet"], environment: ["HOMEBREW_NO_ENV_HINTS": "1"], timeout: 120)
        let result = await Shell.runAsync(brew, ["outdated", "--cask", "--json=v2"],
                                          environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"], timeout: 120)
        guard let json = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]] else { return [] }
        return casks.compactMap { cask in
            guard let name = cask["name"] as? String else { return nil }
            let installed = (cask["installed_versions"] as? [String])?.first ?? "?"
            let current = cask["current_version"] as? String ?? "?"
            return AppUpdate(appName: name, bundleID: nil, appURL: nil, currentVersion: installed, newVersion: current,
                             releaseNotes: "Homebrew cask \"\(name)\". Updated with `brew upgrade --cask \(name)`.",
                             source: .homebrew(cask: name))
        }
    }

    // MARK: - Install

    static func install(_ update: AppUpdate) async -> Outcome {
        switch update.source {
        case .appStore(let page):
            await MainActor.run { _ = NSWorkspace.shared.open(page) }
            return Outcome(ok: true, message: "Opened \(update.appName) in the App Store. Click Update there.")

        case .homebrew(let cask):
            guard let brew = Shell.which("brew") else { return Outcome(ok: false, message: "Homebrew not found") }
            let result = await Shell.runAsync(brew, ["upgrade", "--cask", cask],
                                              environment: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"],
                                              timeout: 1800)
            return Outcome(ok: result.succeeded, message: String(result.combinedOutput.suffix(800)))

        case .sparkle(let downloadURL):
            guard let downloadURL else { return Outcome(ok: false, message: "The appcast has no download link.") }
            do {
                let (temp, response) = try await URLSession.shared.download(from: downloadURL)
                let name = response.suggestedFilename ?? downloadURL.lastPathComponent
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL.home("Downloads")
                var destination = downloads.appendingPathComponent(name)
                var counter = 1
                while FileManager.default.fileExists(atPath: destination.path) {
                    let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
                    destination = downloads.appendingPathComponent("\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)"))
                    counter += 1
                }
                try FileManager.default.moveItem(at: temp, to: destination)
                let target = destination
                await MainActor.run {
                    NSWorkspace.shared.open(target)            // mounts the DMG / unzips the archive
                    SystemLinks.reveal(target)
                }
                return Outcome(ok: true, message: "Downloaded \(name) to Downloads and opened it. Quit \(update.appName), then replace it in Applications.")
            } catch {
                return Outcome(ok: false, message: "Download failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("MacCleaner/1.0 Sparkle/2", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Release notes are often HTML; show them as plain text.
    static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<br ?/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</(p|li|h[1-6]|div)>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li>", with: "• ", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
        for (entity, char) in entities { text = text.replacingOccurrences(of: entity, with: char) }
        text = text.replacingOccurrences(of: "\n\\s*\n+", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Parses a Sparkle appcast (an RSS feed with sparkle: extensions).
final class AppcastParser: NSObject, XMLParserDelegate {
    struct Item {
        var title = ""
        var version = ""
        var shortVersion: String?
        var notes = ""
        var releaseNotesLink: URL?
        var downloadURL: URL?
        var minimumSystemVersion: String?
        var channel: String?
    }

    private let data: Data
    private var items: [Item] = []
    private var current: Item?
    private var text = ""

    init(data: Data) { self.data = data }

    func parse() -> [Item] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items.filter { !$0.version.isEmpty || $0.shortVersion != nil }.map { item in
            var copy = item
            if copy.version.isEmpty { copy.version = copy.shortVersion ?? "" }
            return copy
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        if elementName == "item" { current = Item() }
        if elementName == "enclosure", current != nil {
            if let url = attributes["url"] { current?.downloadURL = URL(string: url) }
            if let v = attributes["sparkle:version"] { current?.version = v }
            if let s = attributes["sparkle:shortVersionString"] { current?.shortVersion = s }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current != nil else { return }
        switch elementName {
        case "title": current?.title = value
        case "sparkle:version": current?.version = value
        case "sparkle:shortVersionString": current?.shortVersion = value
        case "description": current?.notes = value
        case "sparkle:releaseNotesLink": current?.releaseNotesLink = URL(string: value)
        case "sparkle:minimumSystemVersion": current?.minimumSystemVersion = value
        case "sparkle:channel": current?.channel = value
        case "item":
            if let item = current { items.append(item) }
            current = nil
        default: break
        }
        text = ""
    }
}
