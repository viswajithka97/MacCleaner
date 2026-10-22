import Foundation

/// Sidebar groups, mirroring CleanMyMac's layout.
enum ModuleSection: String, CaseIterable, Identifiable {
    case top = ""
    case cleanup = "Cleanup"
    case protection = "Protection"
    case speed = "Speed"
    case applications = "Applications"
    case files = "Files"
    case other = "MacCleaner"

    var id: String { rawValue }
    var modules: [AppModule] { AppModule.allCases.filter { $0.section == self } }
}

/// Every screen in the app. The sidebar is built from this list.
enum AppModule: String, CaseIterable, Identifiable, Hashable {
    case smartCare
    case systemJunk, mailAttachments, trashBins
    case malware, privacy
    case optimization, maintenance
    case uninstaller, updater, extensions
    case spaceLens, largeOldFiles, duplicates, similarPhotos, shredder
    case history, settings

    var id: String { rawValue }

    var section: ModuleSection {
        switch self {
        case .smartCare: return .top
        case .systemJunk, .mailAttachments, .trashBins: return .cleanup
        case .malware, .privacy: return .protection
        case .optimization, .maintenance: return .speed
        case .uninstaller, .updater, .extensions: return .applications
        case .spaceLens, .largeOldFiles, .duplicates, .similarPhotos, .shredder: return .files
        case .history, .settings: return .other
        }
    }

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

    /// SF Symbol shown in the sidebar and on the intro screen.
    var symbol: String {
        switch self {
        case .smartCare: return "sparkles"
        case .systemJunk: return "trash.circle"
        case .mailAttachments: return "paperclip"
        case .trashBins: return "trash"
        case .malware: return "shield.lefthalf.filled"
        case .privacy: return "hand.raised"
        case .optimization: return "slider.horizontal.3"
        case .maintenance: return "wrench.and.screwdriver"
        case .uninstaller: return "xmark.app"
        case .updater: return "arrow.down.app"
        case .extensions: return "puzzlepiece.extension"
        case .spaceLens: return "circle.hexagongrid"
        case .largeOldFiles: return "doc.badge.clock"
        case .duplicates: return "doc.on.doc"
        case .similarPhotos: return "photo.on.rectangle.angled"
        case .shredder: return "scissors"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    /// One-line description for the intro screen.
    var tagline: String {
        switch self {
        case .smartCare: return "Clean, protect and speed up your Mac in one click."
        case .systemJunk: return "Remove caches, logs and leftovers that pile up over time."
        case .mailAttachments: return "Free space taken by downloaded copies of email attachments."
        case .trashBins: return "Empty every Trash on your Mac and connected drives."
        case .malware: return "Look for adware, suspicious launch agents and broken signatures."
        case .privacy: return "Clear browsing traces, recent items and saved networks."
        case .optimization: return "Control what runs at login and what slows your Mac down."
        case .maintenance: return "Run the tune-up tasks macOS doesn't run often enough."
        case .uninstaller: return "Remove apps completely, including every leftover file."
        case .updater: return "Find newer versions of the apps you already have."
        case .extensions: return "See and manage plugins and extensions from every source."
        case .spaceLens: return "See what's taking up space with an interactive map."
        case .largeOldFiles: return "Find big files and files you haven't opened in ages."
        case .duplicates: return "Find identical files and keep only one copy."
        case .similarPhotos: return "Find near-identical shots and keep the best one."
        case .shredder: return "Overwrite and delete sensitive files."
        case .history: return "Everything MacCleaner has cleaned."
        case .settings: return "Preferences, exclusions and notifications."
        }
    }

    /// Bullet points for the intro screen.
    var features: [String] {
        switch self {
        case .smartCare:
            return ["System junk and Trash", "Malware check", "Speed recommendations", "App updates"]
        case .systemJunk:
            return ["User & system caches and logs", "Unused languages, Xcode & developer junk",
                    "Browser caches, broken preferences and login items", "Old iOS backups and updates"]
        case .mailAttachments:
            return ["Lists local attachment copies by size, type and date",
                    "Never touches your emails", "Attachments can be re-downloaded from the mail server"]
        case .trashBins:
            return ["Your Trash", "Mail trash", "Photos \"Recently Deleted\" info", "Trash on external drives"]
        case .malware:
            return ["Launch agents and daemons", "Login items and browser extensions",
                    "Code signature checks", "Known adware database"]
        case .privacy:
            return ["Browser history, cookies, downloads, autofill", "Recent items and Finder recents",
                    "Wi-Fi network history", "App permissions overview"]
        case .optimization:
            return ["Login items", "Launch agents", "Hung applications", "Heavy CPU and memory consumers"]
        case .maintenance:
            return ["Free RAM and purgeable space", "Flush DNS, reindex Spotlight",
                    "Maintenance scripts, Launch Services", "Time Machine snapshots, Mail speed-up"]
        case .uninstaller:
            return ["Complete removal or reset", "Finds leftovers by bundle ID", "Leftovers of deleted apps"]
        case .updater:
            return ["Sparkle appcasts", "Mac App Store", "Homebrew casks"]
        case .extensions:
            return ["Browser extensions", "Spotlight & QuickLook plugins", "Preference panes, Internet plugins",
                    "Login items"]
        case .spaceLens:
            return ["Bubble map of your disk", "Drill down and go back", "Reveal, preview and remove"]
        case .largeOldFiles:
            return ["Size and age thresholds", "Filter by kind", "Remove or shred"]
        case .duplicates:
            return ["Size, partial hash, then SHA-256", "Auto-select keeps one copy", "Previews"]
        case .similarPhotos:
            return ["Folders and Photos library", "Vision feature prints", "Suggests the best shot"]
        case .shredder:
            return ["Drag & drop", "Random-data overwrite", "Cannot be undone"]
        case .history, .settings:
            return []
        }
    }
}
