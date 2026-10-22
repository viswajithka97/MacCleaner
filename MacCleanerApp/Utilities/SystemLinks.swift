import AppKit

/// Opening Finder windows and System Settings panes.
enum SystemLinks {

    /// Settings panes we link to from the UI.
    enum Pane: String {
        case fullDiskAccess = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case camera = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        case microphone = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case location = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        case screenRecording = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case automation = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case photos = "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
        case loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        case notifications = "x-apple.systempreferences:com.apple.preference.notifications"
    }

    static func open(_ pane: Pane) {
        if let url = URL(string: pane.rawValue) { NSWorkspace.shared.open(url) }
    }

    /// Shows the file selected in a Finder window.
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    /// The Finder icon for a file, app or folder.
    static func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
