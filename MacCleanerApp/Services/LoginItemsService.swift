import Foundation

/// Reads and changes login items through System Events (AppleScript).
///
/// The first call makes macOS ask "MacCleaner wants to control System Events".
/// Click OK, or enable it later in System Settings → Privacy & Security → Automation.
enum LoginItemsService {

    struct Outcome { var ok: Bool; var message: String }

    /// Lists the user's login items, plus the ones MacCleaner switched off.
    static func list() -> (items: [LoginItem], error: String?) {
        let script = """
        set out to ""
        tell application "System Events"
            repeat with li in login items
                set out to out & (name of li) & "\t" & (POSIX path of (path of li as text)) & "\t" & (hidden of li) & linefeed
            end repeat
        end tell
        return out
        """
        let result = Shell.run("/usr/bin/osascript", ["-e", script], timeout: 30)
        var items: [LoginItem] = []
        var error: String?
        if result.succeeded {
            for line in result.output.split(separator: "\n") {
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 3 else { continue }
                items.append(LoginItem(name: parts[0], path: normalize(parts[1]), hidden: parts[2] == "true", enabled: true))
            }
        } else {
            error = explain(result.combinedOutput)
        }
        // Add the items the user switched off (unless they were re-added meanwhile).
        for disabled in SettingsStore.disabledLoginItems() where !items.contains(where: { $0.path == disabled.path }) {
            items.append(disabled)
        }
        return (items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, error)
    }

    /// Removes a login item permanently.
    static func remove(name: String) -> Outcome {
        let script = "tell application \"System Events\" to delete login item \"\(AdminService.appleScriptEscape(name))\""
        let result = Shell.run("/usr/bin/osascript", ["-e", script], timeout: 30)
        // Also forget it if it was in our "switched off" list.
        SettingsStore.setDisabledLoginItems(SettingsStore.disabledLoginItems().filter { $0.name != name })
        return Outcome(ok: result.succeeded, message: explain(result.combinedOutput))
    }

    /// "Toggle off": removes the item from System Events but remembers it so it can be re-enabled.
    static func disable(_ item: LoginItem) -> Outcome {
        let outcome = remove(name: item.name)
        if outcome.ok {
            var disabled = SettingsStore.disabledLoginItems().filter { $0.path != item.path }
            disabled.append(LoginItem(name: item.name, path: item.path, hidden: item.hidden, enabled: false))
            SettingsStore.setDisabledLoginItems(disabled)
        }
        return outcome
    }

    /// "Toggle on": adds the app back as a login item.
    static func enable(_ item: LoginItem) -> Outcome {
        let script = "tell application \"System Events\" to make login item at end with properties {path:\"\(AdminService.appleScriptEscape(item.path))\", hidden:\(item.hidden)}"
        let result = Shell.run("/usr/bin/osascript", ["-e", script], timeout: 30)
        if result.succeeded {
            SettingsStore.setDisabledLoginItems(SettingsStore.disabledLoginItems().filter { $0.path != item.path })
        }
        return Outcome(ok: result.succeeded, message: explain(result.combinedOutput))
    }

    /// Login items whose app no longer exists.
    static func brokenItems() -> [LoginItem] {
        list().items.filter { $0.enabled && !$0.exists }
    }

    private static func normalize(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    private static func explain(_ text: String) -> String {
        if text.contains("-1743") || text.localizedCaseInsensitiveContains("not allowed") {
            return "MacCleaner isn't allowed to control System Events. Enable it in System Settings → Privacy & Security → Automation."
        }
        return text
    }
}
