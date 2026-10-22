import SwiftUI

struct OptimizationView: View {
    @State private var loginItems: [CleanableItem] = []
    @State private var agents: [LaunchAgentInfo] = []
    @State private var hung: [ProcessInfoRow] = []
    @State private var heavy: [ProcessInfoRow] = []
    @State private var timer: Timer?
    @State private var scanning = false
    @State private var progress = 0.0
    @State private var path = ""
    @State private var phase: ScanPhase = .intro
    @State private var summary: CleanupSummary?

    var body: some View {
        VStack {
            switch phase {
            case .intro:
                IntroPane(module: .optimization, onScan: scan)
            case .scanning:
                ScanningPane(module: .optimization, progress: progress, path: path, onCancel: { phase = .intro })
            case .results:
                results
            case .summary:
                if let summary { SummaryPane(summary: summary) { phase = .intro } }
            }
        }
        .background(Theme.background)
        .onDisappear { timer?.invalidate() }
    }

    private var results: some View {
        List {
            Section("Login items") {
                ForEach(loginItems) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Button("Disable") { OptimizationService.setLoginItem(item.name, enabled: false); refreshLogin() }
                        Button("Remove", role: .destructive) { OptimizationService.removeLoginItem(item.name); refreshLogin() }
                    }
                }
            }
            Section("Launch agents") {
                ForEach(agents) { agent in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(agent.name)
                            Text(agent.path).font(.caption).foregroundStyle(.secondary)
                            Text(agent.signer).font(.caption2)
                        }
                        Spacer()
                        Toggle("Enabled", isOn: Binding(
                            get: { agent.enabled },
                            set: { OptimizationService.setLaunchAgent(path: agent.path, label: agent.name, enabled: $0); refreshAgents() }
                        ))
                    }
                }
            }
            Section("Hung applications") {
                ForEach(hung) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Button("Force Quit", role: .destructive) {
                            OptimizationService.quit(pid: row.pid, force: true)
                            hung.removeAll { $0.pid == row.pid }
                        }
                    }
                }
            }
            Section("Heavy consumers (refreshes every 2s)") {
                ForEach(heavy.prefix(15)) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(String(format: "%.1f%% CPU", row.cpu)).monospacedDigit()
                        Text(ByteFormatting.string(Int64(row.memoryBytes))).monospacedDigit()
                        Button("Quit") { OptimizationService.quit(pid: row.pid, force: false) }
                        Button("Force Quit", role: .destructive) { OptimizationService.quit(pid: row.pid, force: true) }
                    }
                }
            }
        }
    }

    private func scan() {
        phase = .scanning
        progress = 0.2
        path = "Login items"
        Task.detached {
            let login = OptimizationService.loginItems()
            let agents = OptimizationService.launchAgents()
            let hung = OptimizationService.hungApplications()
            await MainActor.run {
                self.loginItems = login
                self.agents = agents
                self.hung = hung
                self.heavy = OptimizationService.heavyConsumers()
                self.phase = .results
                self.timer?.invalidate()
                self.timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                    self.heavy = OptimizationService.heavyConsumers()
                    self.hung = OptimizationService.hungApplications()
                }
            }
        }
    }

    private func refreshLogin() { loginItems = OptimizationService.loginItems() }
    private func refreshAgents() { agents = OptimizationService.launchAgents() }
}
