import Foundation

/// Measures and clears browser data (history, cookies, ...) for each browser.
///
/// Browsers must be closed first: they keep their databases locked and would
/// overwrite our changes when they quit.
enum BrowserDataService {

    struct Outcome {
        var freed: Int64 = 0
        var failures: [CleanupFailure] = []
    }

    /// Why a data kind can't be cleared for a browser (nil = supported).
    static func unsupportedReason(_ browser: BrowserID, _ kind: BrowserDataKind) -> String? {
        if browser == .safari && kind == .passwords {
            return "Safari passwords live in your Keychain (Passwords app). MacCleaner never touches the Keychain."
        }
        return nil
    }

    // MARK: - Which files hold each kind of data

    /// SQLite files involved (we edit them in place) and plain files (we delete them).
    private struct Targets {
        var databases: [(URL, [String])] = []   // file + SQL statements to run
        var files: [URL] = []                   // deleted entirely
        var folderContents: [URL] = []         // emptied
    }

    private static func targets(_ browser: BrowserID, _ kind: BrowserDataKind) -> Targets {
        var t = Targets()
        let fm = FileManager.default
        func existing(_ urls: [URL]) -> [URL] { urls.filter { fm.fileExists(atPath: $0.path) } }

        switch browser.engine {
        case .webkit:
            let safari = URL.home("Library/Safari")
            switch kind {
            case .history:
                t.files = existing(["History.db", "History.db-wal", "History.db-shm", "History.db-lock",
                                    "HistoryIndex.sk", "RecentlyClosedTabs.plist"].map { safari.appendingPathComponent($0) })
            case .downloads:
                t.files = existing([safari.appendingPathComponent("Downloads.plist")])
            case .cookies:
                t.files = existing([
                    .home("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"),
                    .home("Library/Cookies/Cookies.binarycookies"),
                ])
            case .autofill:
                t.files = existing([safari.appendingPathComponent("Form Values")])
            case .cache:
                t.folderContents = existing(browser.cacheRoots)
            case .passwords:
                break
            }

        case .chromium:
            for profile in browser.profiles {
                func f(_ name: String) -> URL { profile.appendingPathComponent(name) }
                switch kind {
                case .history:
                    t.databases.append((f("History"), [
                        "DELETE FROM visits", "DELETE FROM urls", "DELETE FROM keyword_search_terms",
                        "DELETE FROM segments", "DELETE FROM segment_usage", "DELETE FROM visit_source",
                        "DELETE FROM clusters", "DELETE FROM clusters_and_visits", "DELETE FROM content_annotations",
                        "DELETE FROM context_annotations",
                    ]))
                    t.files += existing(["Visited Links", "Top Sites", "Top Sites-journal", "Shortcuts",
                                         "Shortcuts-journal", "History-journal"].map(f))
                case .downloads:
                    t.databases.append((f("History"), [
                        "DELETE FROM downloads", "DELETE FROM downloads_url_chains", "DELETE FROM downloads_slices",
                    ]))
                case .cookies:
                    for path in ["Cookies", "Network/Cookies"] {
                        t.databases.append((f(path), ["DELETE FROM cookies"]))
                    }
                case .autofill:
                    t.databases.append((f("Web Data"), [
                        "DELETE FROM autofill", "DELETE FROM autofill_profiles", "DELETE FROM autofill_profile_names",
                        "DELETE FROM autofill_profile_emails", "DELETE FROM autofill_profile_phones",
                        "DELETE FROM autofill_profile_addresses", "DELETE FROM local_addresses",
                        "DELETE FROM local_addresses_type_tokens", "DELETE FROM contact_info",
                        "DELETE FROM contact_info_type_tokens", "DELETE FROM credit_cards",
                    ]))
                case .cache:
                    t.folderContents += existing([f("GPUCache"), f("Code Cache")])
                case .passwords:
                    for name in ["Login Data", "Login Data For Account"] {
                        t.databases.append((f(name), ["DELETE FROM logins", "DELETE FROM stats"]))
                    }
                }
            }
            if kind == .cache { t.folderContents += existing(browser.cacheRoots) }

        case .firefox:
            for profile in browser.profiles {
                func f(_ name: String) -> URL { profile.appendingPathComponent(name) }
                switch kind {
                case .history:
                    t.databases.append((f("places.sqlite"), [
                        "DELETE FROM moz_historyvisits",
                        "DELETE FROM moz_inputhistory",
                        "DELETE FROM moz_places WHERE id NOT IN (SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL) AND id NOT IN (SELECT place_id FROM moz_annos)",
                        "UPDATE moz_places SET visit_count = 0, last_visit_date = NULL",
                    ]))
                case .downloads:
                    t.databases.append((f("places.sqlite"), [
                        "DELETE FROM moz_annos WHERE anno_attribute_id IN (SELECT id FROM moz_anno_attributes WHERE name LIKE 'downloads/%')",
                    ]))
                case .cookies:
                    t.databases.append((f("cookies.sqlite"), ["DELETE FROM moz_cookies"]))
                case .autofill:
                    t.databases.append((f("formhistory.sqlite"), ["DELETE FROM moz_formhistory"]))
                    t.files += existing([f("autofill-profiles.json")])
                case .cache:
                    break
                case .passwords:
                    t.files += existing([f("logins.json"), f("logins-backup.json")])
                }
            }
            if kind == .cache {
                for root in browser.cacheRoots {
                    for profileCache in FileSize.children(of: root) {
                        t.folderContents += existing([profileCache.appendingPathComponent("cache2"),
                                                      profileCache.appendingPathComponent("thumbnails")])
                    }
                }
            }
        }
        t.databases = t.databases.filter { fm.fileExists(atPath: $0.0.path) }
        return t
    }

    // MARK: - Size

    /// Approximate disk space used by this kind of data.
    static func size(_ browser: BrowserID, _ kind: BrowserDataKind) -> Int64 {
        let t = targets(browser, kind)
        var total: Int64 = 0
        for (db, _) in t.databases { total += FileSize.of(file: db) }
        for file in t.files { total += FileSize.of(file) }
        for folder in t.folderContents { total += FileSize.of(folder) }
        return total
    }

    /// True if there's anything to clear for this browser/kind.
    static func hasData(_ browser: BrowserID, _ kind: BrowserDataKind) -> Bool {
        let t = targets(browser, kind)
        return !t.databases.isEmpty || !t.files.isEmpty || !t.folderContents.isEmpty
    }

    // MARK: - Clear

    static func clear(_ browser: BrowserID, _ kind: BrowserDataKind) -> Outcome {
        var outcome = Outcome()
        if let reason = unsupportedReason(browser, kind) {
            outcome.failures.append(CleanupFailure(path: browser.name, reason: reason))
            return outcome
        }
        let t = targets(browser, kind)

        for (dbURL, statements) in t.databases {
            if let reason = PathSafety.reasonToSkip(dbURL) {
                outcome.failures.append(CleanupFailure(path: dbURL.path, reason: reason))
                continue
            }
            let before = FileSize.of(file: dbURL)
            guard let db = SQLiteDB(path: dbURL.path) else {
                outcome.failures.append(CleanupFailure(path: dbURL.path, reason: "Could not open the database (is \(browser.name) still running?)"))
                continue
            }
            for sql in statements {
                // Tables differ between browser versions; "no such table" is expected and ignored.
                let r = db.execute(sql)
                if !r.ok, let error = r.error, !error.contains("no such table"), !error.contains("no such column") {
                    outcome.failures.append(CleanupFailure(path: dbURL.lastPathComponent, reason: error))
                }
            }
            db.execute("VACUUM")
            let after = FileSize.of(file: dbURL)
            outcome.freed += max(0, before - after)
        }

        for file in t.files {
            if let reason = PathSafety.reasonToSkip(file) {
                outcome.failures.append(CleanupFailure(path: file.path, reason: reason))
                continue
            }
            let size = FileSize.of(file)
            do {
                try FileManager.default.removeItem(at: file)
                outcome.freed += size
            } catch {
                outcome.failures.append(CleanupFailure(path: file.path, reason: error.localizedDescription))
            }
        }

        for folder in t.folderContents {
            for child in FileSize.children(of: folder) {
                if PathSafety.reasonToSkip(child) != nil { continue }
                let size = FileSize.of(child)
                do {
                    try FileManager.default.removeItem(at: child)
                    outcome.freed += size
                } catch {
                    if outcome.failures.count < 10 {
                        outcome.failures.append(CleanupFailure(path: child.path, reason: error.localizedDescription))
                    }
                }
            }
        }
        return outcome
    }
}
