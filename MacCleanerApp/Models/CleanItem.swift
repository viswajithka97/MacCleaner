import Foundation

/// How an item gets removed when the user clicks the action button.
/// The `CleanupExecutor` service knows how to perform each of these.
enum RemovalAction {
    /// Nothing to do: the item is shown for information only.
    case none
    /// Move to Trash or delete permanently, depending on Settings.
    case remove(URL)
    /// Same as `.remove`, for several paths shown as one row (e.g. an app's unused languages).
    case removeMany([URL])
    /// Delete everything *inside* a folder but keep the folder (used for caches).
    case removeContents(URL)
    /// Delete permanently regardless of Settings (used when emptying a Trash).
    case deletePermanently(URL)
    /// Delete with administrator rights (system logs, files in /Library).
    case adminRemove(URL)
    /// Run a command-line tool, e.g. `brew cleanup`.
    case command(ShellCommand)
    /// Remove a login item via System Events.
    case removeLoginItem(name: String, path: String)
    /// Unload a launch agent/daemon with launchctl and move its plist to the Trash.
    case removeLaunchItem(plist: URL, label: String, isSystem: Bool)
    /// Clear one kind of browser data.
    case browserData(BrowserID, BrowserDataKind)
    /// Clear one list of recent items.
    case recentItems(RecentItemsKind)
    /// Forget a saved Wi-Fi network.
    case wifiNetwork(interface: String, ssid: String)
    /// Reset the QuickLook thumbnail cache.
    case quickLookCache
    /// Ask Mail to erase the messages in its Trash.
    case mailTrash
    /// Delete photos from the Photos library through PhotoKit.
    case photoAsset(localIdentifier: String)
    /// Disable a PlugInKit extension (Safari / QuickLook app extensions).
    case disablePlugin(identifier: String)
    /// Force quit a process (hung apps).
    case forceQuit(pid: Int32)
    /// Run a maintenance task (used by Smart Care).
    case maintenance(MaintenanceTask)
    /// Install an app update (used by Smart Care).
    case update(AppUpdate)
    /// Forget an installer package receipt (`pkgutil --forget`).
    case forgetReceipt(String)

    var isInfoOnly: Bool {
        if case .none = self { return true }
        return false
    }

    /// True when the action needs the administrator password.
    var requiresAdmin: Bool {
        switch self {
        case .adminRemove, .wifiNetwork, .forgetReceipt: return true
        case .command(let command): return command.requiresAdmin
        case .removeLaunchItem(_, _, let isSystem): return isSystem
        case .maintenance(let task): return task.requiresAdmin
        default: return false
        }
    }
}

/// A command line tool invocation, with a plain-language explanation shown before admin commands.
struct ShellCommand {
    var executable: String
    var arguments: [String]
    var requiresAdmin: Bool = false
    var explanation: String
    var environment: [String: String]? = nil

    /// The command as a single shell string (used for admin commands).
    var shellLine: String {
        ([executable] + arguments).map(Shell.quote).joined(separator: " ")
    }
}

/// One row in a results list: a file, a folder, a login item, a browser data type...
struct CleanItem: Identifiable {
    let id = UUID()
    var name: String
    var url: URL?
    var size: Int64
    var isSelected: Bool = true
    var subtitle: String? = nil
    var date: Date? = nil
    var warning: String? = nil
    var symbol: String? = nil
    var action: RemovalAction
    /// Set by the malware scanner when the item matches the known-adware database.
    var knownThreat = false

    /// Path shown under the name.
    var displayPath: String? { url?.tildePath }
}

/// Tri-state for "select all" checkboxes.
enum SelectionState {
    case none, some, all
}

/// A group of items, e.g. "User cache files".
struct CleanCategory: Identifiable {
    let id: String
    var title: String
    var symbol: String
    var summary: String
    var items: [CleanItem]
    /// Warning shown in orange (e.g. language files may break auto-updates).
    var warning: String? = nil
    /// Extra explanation shown in grey.
    var note: String? = nil
    /// Category is shown for information only (cannot be cleaned).
    var infoOnly: Bool = false
    /// Category starts deselected (e.g. iOS backups, saved passwords).
    var offByDefault: Bool = false

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedItems: [CleanItem] { infoOnly ? [] : items.filter { $0.isSelected && !$0.action.isInfoOnly } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var requiresAdmin: Bool { items.contains { $0.action.requiresAdmin } }

    var selectionState: SelectionState {
        let selectable = items.filter { !$0.action.isInfoOnly }
        let count = selectable.filter(\.isSelected).count
        if infoOnly || count == 0 { return .none }
        return count == selectable.count ? .all : .some
    }

    mutating func setAll(_ selected: Bool) {
        for index in items.indices where !items[index].action.isInfoOnly {
            items[index].isSelected = selected
        }
    }

    /// Applies `offByDefault` to the items. Call after building a category.
    func applyingDefaults() -> CleanCategory {
        var copy = self
        if offByDefault || infoOnly { copy.setAll(false) }
        return copy
    }
}

/// One problem that happened while cleaning.
struct CleanupFailure: Identifiable {
    let id = UUID()
    var path: String
    var reason: String
}

/// What happened after the action button was pressed.
struct CleanupResult {
    var removedCount = 0
    var freedBytes: Int64 = 0
    var removedNames: [String] = []
    var failures: [CleanupFailure] = []
    var messages: [String] = []

    mutating func merge(_ other: CleanupResult) {
        removedCount += other.removedCount
        freedBytes += other.freedBytes
        removedNames += other.removedNames
        failures += other.failures
        messages += other.messages
    }

    mutating func success(_ name: String, bytes: Int64) {
        removedCount += 1
        freedBytes += bytes
        removedNames.append(name)
    }

    mutating func fail(_ path: String, _ reason: String) {
        failures.append(CleanupFailure(path: path, reason: reason))
    }
}
