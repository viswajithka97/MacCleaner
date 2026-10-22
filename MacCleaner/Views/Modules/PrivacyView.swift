import SwiftUI

struct PrivacyView: View {
    @StateObject private var model = CleaningFlowViewModel(module: .privacy)
    @State private var grants: [TCCGrant] = []

    var body: some View {
        ModuleFlowView(
            model: model,
            extraResults: AnyView(privacyExtras)
        )
        .onAppear { grants = PrivacyService.tccGrants() }
    }

    private var privacyExtras: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Running browsers").font(.headline)
            HStack {
                ForEach(BrowserKind.allCases) { browser in
                    if browser.isInstalled() {
                        VStack {
                            Text(browser.displayName)
                            if browser.isRunning {
                                Button("Quit browser") { browser.quit() }
                                    .buttonStyle(.bordered)
                            } else {
                                Text("Not running").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                    }
                }
            }
            Text("Privacy grants (from TCC, when readable)").font(.headline)
            if grants.isEmpty {
                Text("TCC database is protected. Grant Full Disk Access, or use the buttons below to open System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(["Camera", "Microphone", "Location", "Screen Recording", "Full Disk Access"], id: \.self) { service in
                HStack {
                    Text(service).frame(width: 160, alignment: .leading)
                    let names = grants.filter { $0.service == service && $0.allowed }.map(\.client)
                    Text(names.isEmpty ? "—" : names.joined(separator: ", "))
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button("Open Settings") { PrivacyService.openPrivacyPane(service) }
                }
            }
        }
        .macCard(.purple)
    }
}
