import SwiftUI
import Combine

struct SystemJunkView: View {
    @ObservedObject var vm: CleanupFlowViewModel

    var body: some View {
        CleanupFlowView(vm: vm) {
            InfoBanner(text: "Nothing is removed until you review the results and confirm. Old iOS backups are never selected automatically.")
        } accessory: {
            EmptyView()
        }
    }
}

struct MailAttachmentsView: View {
    @ObservedObject var vm: CleanupFlowViewModel

    var body: some View {
        CleanupFlowView(vm: vm) {
            InfoBanner(text: "Only local downloaded copies are removed. Your emails are never touched, and attachments can be downloaded again from the mail server when you open the message.")
        } accessory: {
            InfoBanner(text: "Click ⋯ on any file to preview it with Quick Look or reveal it in Finder.")
        }
    }
}

struct TrashBinsView: View {
    @ObservedObject var vm: CleanupFlowViewModel

    var body: some View {
        CleanupFlowView(vm: vm) {
            EmptyView()
        } accessory: {
            InfoBanner(style: .warning, text: "Emptying the Trash deletes files permanently.")
        }
    }
}

struct MalwareView: View {
    @ObservedObject var vm: CleanupFlowViewModel
    private let disclaimer = "This is a heuristic scanner. It checks for known adware, code-signing problems and suspicious launch items, but it is not a replacement for a full antivirus product. Review each finding before removing it."

    var body: some View {
        CleanupFlowView(vm: vm) {
            InfoBanner(style: .warning, text: disclaimer, symbol: "shield.lefthalf.filled")
        } accessory: {
            VStack(alignment: .leading, spacing: 8) {
                InfoBanner(style: .warning, text: disclaimer, symbol: "shield.lefthalf.filled")
                Text("Threat = matches known adware or has a broken signature (selected). Suspicious = hidden or missing program (selected). Low risk = unsigned (not selected). Launch agents are unloaded with launchctl, then moved to the Trash.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ExtensionsView: View {
    @ObservedObject var vm: CleanupFlowViewModel

    var body: some View {
        CleanupFlowView(vm: vm, scanTitle: "Find", singleActionTitle: { item in
            if case .disablePlugin = item.action { return "Disable" }
            return "Remove"
        }) {
            EmptyView()
        } accessory: {
            InfoBanner(text: "Nothing is selected automatically. Use the buttons on each row, or check items and click Remove. Items in /Library need your administrator password.")
        }
    }
}

/// Privacy = the generic flow plus running-browser warnings and the permissions overview.
struct PrivacyView: View {
    @ObservedObject var vm: CleanupFlowViewModel
    @State private var permissions: [PrivacyService.PermissionGroup] = []
    @State private var runningBrowsers: [BrowserID] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        CleanupFlowView(vm: vm) {
            permissionsPanel
        } accessory: {
            VStack(alignment: .leading, spacing: 10) {
                runningPanel
                InfoBanner(style: .warning, text: "Saved passwords are never selected automatically. Clearing them permanently deletes every password saved in that browser.")
                permissionsPanel
            }
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in runningBrowsers = BrowserID.allCases.filter(\.isRunning) }
    }

    private func refresh() {
        runningBrowsers = BrowserID.allCases.filter(\.isRunning)
        Task.detached {
            let groups = PrivacyService.permissions()
            await MainActor.run { permissions = groups }
        }
    }

    @ViewBuilder private var runningPanel: some View {
        if !runningBrowsers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Quit these browsers before clearing their data:", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                HStack {
                    ForEach(runningBrowsers) { browser in
                        Button("Quit \(browser.name)") { browser.runningApp?.terminate() }
                    }
                }
            }
            .card()
        }
    }

    private var permissionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("App permissions").font(.headline)
                Spacer()
                Button("Refresh", action: refresh).controlSize(.small)
            }
            ForEach(permissions) { group in
                HStack(alignment: .top) {
                    Image(systemName: group.symbol).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title).font(.subheadline.bold())
                        if !group.accessible {
                            Text("Not readable — grant MacCleaner Full Disk Access to see this list").font(.caption).foregroundStyle(.secondary)
                        } else if group.apps.isEmpty {
                            Text("No apps").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(group.apps.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Open Settings") { SystemLinks.open(group.pane) }.controlSize(.small)
                }
            }
        }
        .card()
        .frame(maxWidth: 620)
    }
}
