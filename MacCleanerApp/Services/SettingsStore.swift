import Foundation
import ServiceManagement
import Combine

/// All user preferences, saved in UserDefaults.
///
/// Views bind to the published properties. Background code (which must not
/// touch this MainActor object) reads `SettingsStore.snapshot()` instead.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// The UserDefaults keys, in one place.
    enum Key {
        static let moveToTrash = "moveToTrash"
        static let exclusions = "exclusions"
        static let largeFileMB = "largeFileMB"
        static let oldFileDays = "oldFileDays"
        static let notifyLowDisk = "notifyLowDisk"
        static let lowDiskGB = "lowDiskGB"
        static let notifyMemoryPressure = "notifyMemoryPressure"
        static let notifyTrashSize = "notifyTrashSize"
        static let trashSizeGB = "trashSizeGB"
        static let weeklyReminder = "weeklyReminder"
        static let showMenuBar = "showMenuBar"
        static let disabledLoginItems = "disabledLoginItems"
    }

    private let defaults = UserDefaults.standard

    @Published var moveToTrash: Bool { didSet { defaults.set(moveToTrash, forKey: Key.moveToTrash) } }
    @Published var exclusions: [String] { didSet { defaults.set(exclusions, forKey: Key.exclusions) } }
    @Published var largeFileMB: Int { didSet { defaults.set(largeFileMB, forKey: Key.largeFileMB) } }
    @Published var oldFileDays: Int { didSet { defaults.set(oldFileDays, forKey: Key.oldFileDays) } }
    @Published var notifyLowDisk: Bool { didSet { defaults.set(notifyLowDisk, forKey: Key.notifyLowDisk) } }
    @Published var lowDiskGB: Int { didSet { defaults.set(lowDiskGB, forKey: Key.lowDiskGB) } }
    @Published var notifyMemoryPressure: Bool { didSet { defaults.set(notifyMemoryPressure, forKey: Key.notifyMemoryPressure) } }
    @Published var notifyTrashSize: Bool { didSet { defaults.set(notifyTrashSize, forKey: Key.notifyTrashSize) } }
    @Published var trashSizeGB: Int { didSet { defaults.set(trashSizeGB, forKey: Key.trashSizeGB) } }
    @Published var weeklyReminder: Bool {
        didSet {
            defaults.set(weeklyReminder, forKey: Key.weeklyReminder)
            NotificationService.shared.updateWeeklyReminder(enabled: weeklyReminder)
        }
    }
    @Published var showMenuBar: Bool {
        didSet { if oldValue != showMenuBar { defaults.set(showMenuBar, forKey: Key.showMenuBar) } }
    }

    /// Mirrors SMAppService's state. Setting it registers/unregisters the login item.
    @Published var launchAtLogin: Bool = false
    @Published var launchAtLoginError: String?

    private init() {
        defaults.register(defaults: [
            Key.moveToTrash: true,
            Key.exclusions: [String](),
            Key.largeFileMB: 100,
            Key.oldFileDays: 365,
            Key.notifyLowDisk: true,
            Key.lowDiskGB: 10,
            Key.notifyMemoryPressure: true,
            Key.notifyTrashSize: true,
            Key.trashSizeGB: 5,
            Key.weeklyReminder: false,
            Key.showMenuBar: true,
        ])
        moveToTrash = defaults.bool(forKey: Key.moveToTrash)
        exclusions = defaults.stringArray(forKey: Key.exclusions) ?? []
        largeFileMB = defaults.integer(forKey: Key.largeFileMB)
        oldFileDays = defaults.integer(forKey: Key.oldFileDays)
        notifyLowDisk = defaults.bool(forKey: Key.notifyLowDisk)
        lowDiskGB = defaults.integer(forKey: Key.lowDiskGB)
        notifyMemoryPressure = defaults.bool(forKey: Key.notifyMemoryPressure)
        notifyTrashSize = defaults.bool(forKey: Key.notifyTrashSize)
        trashSizeGB = defaults.integer(forKey: Key.trashSizeGB)
        weeklyReminder = defaults.bool(forKey: Key.weeklyReminder)
        showMenuBar = defaults.bool(forKey: Key.showMenuBar)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters MacCleaner as a login item using SMAppService.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            launchAtLoginError = "Approve MacCleaner in System Settings → General → Login Items."
        }
    }

    func addExclusion(_ path: String) {
        guard !exclusions.contains(path) else { return }
        exclusions.append(path)
    }

    func removeExclusion(_ path: String) {
        exclusions.removeAll { $0 == path }
    }

    // MARK: - Thread-safe access for background code

    struct Snapshot {
        var moveToTrash: Bool
        var exclusions: [String]
        var largeFileMB: Int
        var oldFileDays: Int
    }

    /// Reads the current settings directly from UserDefaults (safe from any thread).
    nonisolated static func snapshot() -> Snapshot {
        let d = UserDefaults.standard
        return Snapshot(
            moveToTrash: d.object(forKey: Key.moveToTrash) as? Bool ?? true,
            exclusions: d.stringArray(forKey: Key.exclusions) ?? [],
            largeFileMB: d.object(forKey: Key.largeFileMB) as? Int ?? 100,
            oldFileDays: d.object(forKey: Key.oldFileDays) as? Int ?? 365)
    }

    // MARK: - Login items the user switched off in Optimization

    /// Login items that were "toggled off" (removed from System Events but remembered
    /// here so they can be switched back on).
    nonisolated static func disabledLoginItems() -> [LoginItem] {
        guard let raw = UserDefaults.standard.array(forKey: Key.disabledLoginItems) as? [[String: Any]] else { return [] }
        return raw.compactMap { dict in
            guard let name = dict["name"] as? String, let path = dict["path"] as? String else { return nil }
            return LoginItem(name: name, path: path, hidden: dict["hidden"] as? Bool ?? false, enabled: false)
        }
    }

    nonisolated static func setDisabledLoginItems(_ items: [LoginItem]) {
        let raw = items.map { ["name": $0.name, "path": $0.path, "hidden": $0.hidden] as [String: Any] }
        UserDefaults.standard.set(raw, forKey: Key.disabledLoginItems)
    }
}
