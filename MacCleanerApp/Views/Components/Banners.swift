import SwiftUI

/// Shown at the top of the window when a folder couldn't be read.
struct FullDiskAccessBanner: View {
    @ObservedObject var permissions = PermissionCenter.shared

    var body: some View {
        if permissions.shouldShowBanner {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MacCleaner couldn't read some folders").font(.headline)
                    Text("macOS protects places like Mail, Safari and the Trash. Give MacCleaner Full Disk Access in System Settings → Privacy & Security → Full Disk Access, then quit and reopen MacCleaner.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let example = permissions.deniedPaths.first {
                        Text("For example: \(example)").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                VStack(spacing: 6) {
                    Button("Open Full Disk Access") { SystemLinks.open(.fullDiskAccess) }.buttonStyle(.borderedProminent)
                    HStack {
                        Button("Check again") { permissions.refresh() }
                        Button("Dismiss") { permissions.bannerDismissed = true }
                    }
                    .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.12))
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

/// Explains an admin action and (once per session) asks for the password.
struct AdminSheet: View {
    @ObservedObject var admin = AdminService.shared
    var request: AdminRequest
    @State private var password = ""
    @State private var showCommands = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill").font(.largeTitle).foregroundStyle(.blue)
                Text(request.title).font(.title2.bold())
            }
            Text("What will happen").font(.headline)
            ScrollView {
                Text(request.explanation).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
            DisclosureGroup("Show exact commands", isExpanded: $showCommands) {
                ScrollView {
                    Text(request.commands.joined(separator: "\n"))
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            if request.needsPassword {
                Divider()
                Text("Why the password? These changes affect system files that only an administrator can modify. MacCleaner asks once and keeps the password in memory until you quit; it's never saved to disk.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SecureField("Password for \(NSUserName())", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { admin.approve(password: password) }
            }
            if let error = admin.errorMessage {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { admin.cancel() }.keyboardShortcut(.cancelAction)
                Button(request.needsPassword ? "Authorize & Continue" : "Continue") { admin.approve(password: password) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(admin.isValidating || (request.needsPassword && password.isEmpty))
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}
