import SwiftUI

/// Every sidebar destination. Keep raw values stable — they are stored in History JSON.
enum AppModule: String, CaseIterable, Identifiable, Hashable {
    case smartCare
    case systemJunk
    case mailAttachments
    case trashBins
    case malware
    case privacy
    case optimization
    case maintenance
    case uninstaller
    case updater
    case extensions
    case spaceLens
    case largeOldFiles
    case duplicates
    case similarPhotos
    case shredder
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartCare: return "Smart Care"
        case .systemJunk: return "System Junk"
        case .mailAttachments: return "Mail Attachments"
        case .trashBins: return "Trash Bins"
        case .malware: return "Malware Removal"
        case .privacy: return "Privacy"
        case .optimization: return "Optimization"
        case .maintenance: return "Maintenance"
        case .uninstaller: return "Uninstaller"
        case .updater: return "Updater"
        case .extensions: return "Extensions"
        case .spaceLens: return "Space Lens"
        case .largeOldFiles: return "Large & Old Files"
        case .duplicates: return "Duplicates"
        case .similarPhotos: return "Similar Photos"
        case .shredder: return "Shredder"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .smartCare: return "One-click health check for junk, trash, malware, speed, and updates."
        case .systemJunk: return "Caches, logs, language files, Xcode and browser leftovers."
        case .mailAttachments: return "Local Mail download copies. Emails on the server stay untouched."
        case .trashBins: return "User Trash, Mail trash, Photos Recently Deleted, and volume trash."
        case .malware: return "Heuristic scan of launch items, apps, and known adware families."
        case .privacy: return "Browser data, recents, Wi-Fi history, Quick Look, and TCC grants."
        case .optimization: return "Login items, launch agents, hung apps, and heavy processes."
        case .maintenance: return "RAM, DNS, Spotlight, permissions, snapshots, and disk checks."
        case .uninstaller: return "Remove an app and every leftover file we can find."
        case .updater: return "Sparkle, Mac App Store, and Homebrew cask updates."
        case .extensions: return "Browser extensions, plugins, preference panes, and login items."
        case .spaceLens: return "Interactive disk map of any folder or drive."
        case .largeOldFiles: return "Find huge or long-forgotten files."
        case .duplicates: return "Exact duplicate files by size and SHA-256."
        case .similarPhotos: return "Visually similar shots using Vision feature prints."
        case .shredder: return "Overwrite then delete. On SSDs this is not a guarantee."
        case .history: return "Every cleanup you have run, with space freed."
        case .settings: return "Deletion mode, exclusions, thresholds, and launch at login."
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: return "sparkles.rectangle.stack"
        case .systemJunk: return "trash.slash"
        case .mailAttachments: return "paperclip"
        case .trashBins: return "trash"
        case .malware: return "checkmark.shield"
        case .privacy: return "eye.slash"
        case .optimization: return "speedometer"
        case .maintenance: return "wrench.and.screwdriver"
        case .uninstaller: return "rectangle.stack.badge.minus"
        case .updater: return "arrow.triangle.2.circlepath"
        case .extensions: return "puzzlepiece.extension"
        case .spaceLens: return "circle.hexagongrid"
        case .largeOldFiles: return "doc.badge.ellipsis"
        case .duplicates: return "doc.on.doc"
        case .similarPhotos: return "photo.stack"
        case .shredder: return "xmark.seal"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    var accent: Color {
        switch self {
        case .smartCare: return Color(red: 0.35, green: 0.62, blue: 1.0)
        case .systemJunk: return Color(red: 0.29, green: 0.78, blue: 0.64)
        case .mailAttachments: return Color(red: 0.95, green: 0.55, blue: 0.30)
        case .trashBins: return Color(red: 0.55, green: 0.62, blue: 0.72)
        case .malware: return Color(red: 0.90, green: 0.28, blue: 0.35)
        case .privacy: return Color(red: 0.62, green: 0.45, blue: 0.95)
        case .optimization: return Color(red: 0.20, green: 0.72, blue: 0.90)
        case .maintenance: return Color(red: 0.95, green: 0.72, blue: 0.25)
        case .uninstaller: return Color(red: 0.95, green: 0.40, blue: 0.55)
        case .updater: return Color(red: 0.35, green: 0.75, blue: 0.45)
        case .extensions: return Color(red: 0.45, green: 0.55, blue: 0.95)
        case .spaceLens: return Color(red: 0.20, green: 0.78, blue: 0.82)
        case .largeOldFiles: return Color(red: 0.98, green: 0.60, blue: 0.20)
        case .duplicates: return Color(red: 0.40, green: 0.70, blue: 0.95)
        case .similarPhotos: return Color(red: 0.95, green: 0.45, blue: 0.70)
        case .shredder: return Color(red: 0.85, green: 0.20, blue: 0.25)
        case .history: return Color(red: 0.55, green: 0.60, blue: 0.70)
        case .settings: return Color(red: 0.50, green: 0.55, blue: 0.62)
        }
    }
}

enum SidebarGroup: String, CaseIterable {
    case care = "Smart Care"
    case cleanup = "Cleanup"
    case protection = "Protection"
    case speed = "Speed"
    case applications = "Applications"
    case files = "Files"
    case other = "Library"

    var modules: [AppModule] {
        switch self {
        case .care: return [.smartCare]
        case .cleanup: return [.systemJunk, .mailAttachments, .trashBins]
        case .protection: return [.malware, .privacy]
        case .speed: return [.optimization, .maintenance]
        case .applications: return [.uninstaller, .updater, .extensions]
        case .files: return [.spaceLens, .largeOldFiles, .duplicates, .similarPhotos, .shredder]
        case .other: return [.history, .settings]
        }
    }
}
