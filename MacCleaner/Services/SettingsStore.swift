import Foundation
import Combine
import ServiceManagement

/// Loads and saves Settings as JSON in Application Support.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings {
        didSet { save() }
    }

    let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MacCleaner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func isExcluded(_ path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        for exclusion in settings.exclusions {
            let ex = (exclusion as NSString).standardizingPath
            if standardized == ex || standardized.hasPrefix(ex + "/") {
                return true
            }
        }
        return false
    }

    func addExclusion(_ path: String) {
        let standardized = (path as NSString).standardizingPath
        if !settings.exclusions.contains(standardized) {
            settings.exclusions.append(standardized)
        }
    }

    func removeExclusion(_ path: String) {
        settings.exclusions.removeAll { $0 == path }
    }

    func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login failed: \(error)")
        }
    }
}
