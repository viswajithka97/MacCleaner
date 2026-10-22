import Foundation

/// The tune-up tasks in the Maintenance module.
enum MaintenanceTask: String, CaseIterable, Identifiable {
    case freeRAM, freePurgeable, flushDNS, periodicScripts, reindexSpotlight
    case rebuildLaunchServices, repairPermissions, thinSnapshots, speedUpMail, verifyDisk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeRAM: return "Free up RAM"
        case .freePurgeable: return "Free up purgeable space"
        case .flushDNS: return "Flush DNS cache"
        case .periodicScripts: return "Run maintenance scripts"
        case .reindexSpotlight: return "Reindex Spotlight"
        case .rebuildLaunchServices: return "Rebuild Launch Services"
        case .repairPermissions: return "Repair home folder permissions"
        case .thinSnapshots: return "Thin Time Machine snapshots"
        case .speedUpMail: return "Speed up Mail"
        case .verifyDisk: return "Verify startup disk"
        }
    }

    var symbol: String {
        switch self {
        case .freeRAM: return "memorychip"
        case .freePurgeable: return "internaldrive"
        case .flushDNS: return "network"
        case .periodicScripts: return "calendar.badge.clock"
        case .reindexSpotlight: return "magnifyingglass"
        case .rebuildLaunchServices: return "square.stack.3d.up"
        case .repairPermissions: return "lock.shield"
        case .thinSnapshots: return "clock.arrow.2.circlepath"
        case .speedUpMail: return "envelope"
        case .verifyDisk: return "checkmark.seal"
        }
    }

    var description: String {
        switch self {
        case .freeRAM:
            return "Asks macOS to drop inactive memory and disk cache (purge) so apps get free RAM right away."
        case .freePurgeable:
            return "Temporarily fills free space with a big file so macOS deletes purgeable data (old snapshots, caches of cloud files), then removes the file."
        case .flushDNS:
            return "Clears the list of website addresses your Mac remembers. Fixes sites that won't load after moving or DNS changes."
        case .periodicScripts:
            return "Runs the daily, weekly and monthly system scripts that rotate logs and clean temporary files."
        case .reindexSpotlight:
            return "Erases and rebuilds the Spotlight index of the startup disk. Search may be slow for a while afterwards."
        case .rebuildLaunchServices:
            return "Rebuilds the database of apps and file types. Fixes duplicate entries in \"Open With\" menus."
        case .repairPermissions:
            return "Resets the permissions of files in your home folder to their defaults (diskutil resetUserPermissions)."
        case .thinSnapshots:
            return "Deletes local Time Machine snapshots stored on the startup disk to free space."
        case .speedUpMail:
            return "Compacts (vacuums) Mail's message index database. Mail must be closed."
        case .verifyDisk:
            return "Checks the startup disk's file system for errors (read-only check)."
        }
    }

    var requiresAdmin: Bool {
        switch self {
        case .freeRAM, .flushDNS, .periodicScripts, .reindexSpotlight, .repairPermissions, .thinSnapshots:
            return true
        default:
            return false
        }
    }

    /// The plain-language explanation shown before asking for the password.
    var adminExplanation: String {
        switch self {
        case .freeRAM: return "Runs `purge`, which tells macOS to empty its disk cache. This needs administrator rights."
        case .flushDNS: return "Runs `dscacheutil -flushcache` and restarts the DNS responder (mDNSResponder). Both are system services, so administrator rights are needed."
        case .periodicScripts: return "Runs `periodic daily weekly monthly`, the system maintenance scripts that normally run as root."
        case .reindexSpotlight: return "Runs `mdutil -E /` to erase and rebuild the Spotlight index of your startup disk."
        case .repairPermissions: return "Runs `diskutil resetUserPermissions / <your user id>` to reset permissions in your home folder."
        case .thinSnapshots: return "Runs `tmutil deletelocalsnapshots` for each local Time Machine snapshot. Your Time Machine backup disk is not touched."
        default: return description
        }
    }
}
