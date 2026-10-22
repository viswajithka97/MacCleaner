import SwiftUI

struct OptimizationView: View {
    @ObservedObject var vm: OptimizationViewModel

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .optimization) {
                Button("Refresh") { vm.loadAll() }.disabled(vm.isBusy)
            }
            Picker("", selection: $vm.tab) {
                ForEach(OptimizationViewModel.Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            if let message = vm.message {
                InfoBanner(text: message).padding(.horizontal, 20).padding(.top, 8)
                    .onTapGesture { vm.message = nil }
            }
            if vm.isBusy && !vm.loaded || (vm.isBusy && vm.launchItems.isEmpty) {
                ScanningView(module: .optimization, title: "Loading…", snapshot: vm.snapshot, onCancel: vm.cancelTask)
            } else {
                switch vm.tab {
                case .loginItems: loginItems
                case .launchAgents: launchAgents
                case .hungApps: hungApps
                case .heavy: heavy
                }
            }
        }
        .onAppear { if !vm.loaded { vm.loadAll() } }
        .onChange(of: vm.tab) { tab in
            if tab == .heavy { vm.startProcessUpdates() } else { vm.stopProcessUpdates() }
            if tab == .hungApps { vm.refreshHung() }
        }
        .onDisappear { vm.stopProcessUpdates() }
    }

    private var loginItems: some View {
        List {
            if let error = vm.loginError { InfoBanner(style: .warning, text: error) }
            if vm.loginItems.isEmpty { Text("No login items.").foregroundStyle(.secondary) }
            ForEach(vm.loginItems) { item in
                HStack {
                    Image(nsImage: SystemLinks.icon(for: URL(fileURLWithPath: item.path))).resizable().frame(width: 24, height: 24)
                    VStack(alignment: .leading) {
                        Text(item.name)
                        Text(item.exists ? item.path : "Missing: \(item.path)").font(.caption)
                            .foregroundStyle(item.exists ? Color.secondary : Color.orange).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { item.enabled }, set: { vm.setLoginItem(item, enabled: $0) }))
                        .toggleStyle(.switch).labelsHidden()
                    Button("Remove") { vm.removeLoginItem(item) }
                }
            }
            Section {
                Button("Open Login Items in System Settings") { SystemLinks.open(.loginItems) }
                Text("Turning an item off removes it from login items; MacCleaner remembers it so you can turn it back on here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var launchAgents: some View {
        Table(vm.launchItems) {
            TableColumn("Name") { item in
                VStack(alignment: .leading) {
                    Text(item.label).lineLimit(1)
                    Text(item.plist.tildePath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                .contextMenu { Button("Reveal in Finder") { SystemLinks.reveal(item.plist) } }
            }
            TableColumn("Type") { Text($0.domain.rawValue).foregroundStyle(.secondary) }.width(110)
            TableColumn("Signed by") { Text($0.signer).lineLimit(1).help($0.signer) }.width(min: 120, ideal: 200)
            TableColumn("Status") { item in
                Text(item.isDisabled ? "Disabled" : (item.isLoaded ? "Running" : "Enabled"))
                    .foregroundStyle(item.isDisabled ? Color.secondary : Color.green)
            }.width(80)
            TableColumn("On") { item in
                Toggle("", isOn: Binding(get: { !item.isDisabled }, set: { vm.setLaunchItem(item, enabled: $0) }))
                    .toggleStyle(.switch).labelsHidden()
            }.width(50)
        }
    }

    private var hungApps: some View {
        VStack {
            if vm.hungApps.isEmpty {
                Spacer()
                Image(systemName: "checkmark.circle").font(.system(size: 50)).foregroundStyle(.green)
                Text("All apps are responding.").font(.title3)
                Button("Check again") { vm.refreshHung() }
                Spacer()
            } else {
                List(vm.hungApps) { app in
                    HStack {
                        if let url = app.bundleURL { Image(nsImage: SystemLinks.icon(for: url)).resizable().frame(width: 28, height: 28) }
                        Text(app.name)
                        Text("Not responding").foregroundStyle(.red)
                        Spacer()
                        Button("Force Quit") { vm.forceQuit(app) }.tint(.red)
                    }
                }
            }
        }
    }

    private var heavy: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Sort by", selection: $vm.sortByMemory) {
                    Text("CPU").tag(false)
                    Text("Memory").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
                Text("Refreshes every 2 seconds").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            Table(vm.sortedProcesses) {
                TableColumn("Process") { Text($0.name).lineLimit(1) }
                TableColumn("CPU") { Text(String(format: "%.1f%%", $0.cpu)).monospacedDigit() }.width(70)
                TableColumn("Memory") { Text($0.memoryBytes.formattedBytes).monospacedDigit() }.width(90)
                TableColumn("User") { Text($0.user).foregroundStyle(.secondary) }.width(80)
                TableColumn("") { process in
                    HStack {
                        Button("Quit") { vm.quit(process, force: false) }
                        Button("Force Quit") { vm.quit(process, force: true) }.tint(.red)
                    }
                    .controlSize(.small)
                }.width(150)
            }
        }
    }
}

struct MaintenanceView: View {
    @ObservedObject var vm: MaintenanceViewModel

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .maintenance) {
                Button {
                    vm.runSelected()
                } label: {
                    Label("Run \(vm.selected.count) Selected", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppModule.maintenance.tint)
                .disabled(vm.selected.isEmpty || vm.runningAll)
            }
            ScrollView {
                VStack(spacing: 10) {
                    InfoBanner(text: "Tasks marked with a lock need your administrator password. Before each one runs, you'll see exactly what it does.")
                    ForEach(MaintenanceTask.allCases) { task in row(task) }
                }
                .padding(20)
            }
        }
    }

    private func row(_ task: MaintenanceTask) -> some View {
        let status = vm.status[task] ?? .idle
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: Binding(get: { vm.selected.contains(task) }, set: { on in
                    if on { vm.selected.insert(task) } else { vm.selected.remove(task) }
                }))
                .toggleStyle(.checkbox).labelsHidden()
                Image(systemName: task.symbol).font(.title2).foregroundStyle(AppModule.maintenance.gradient).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(task.title).font(.headline)
                        if task.requiresAdmin { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(task.description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if task == .speedUpMail && vm.mailRunning {
                        HStack {
                            Text("Mail is open — it must be quit first.").font(.caption).foregroundStyle(.orange)
                            Button("Quit Mail") { vm.quitMail() }.controlSize(.small)
                        }
                    }
                }
                Spacer()
                statusView(status, task)
                Button("Run") { Task { await vm.run(task) } }.disabled(status == .running || vm.runningAll)
            }
            if let output = vm.output[task], !output.isEmpty {
                ScrollView {
                    Text(output).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
        }
        .card()
    }

    @ViewBuilder private func statusView(_ status: MaintenanceViewModel.Status, _ task: MaintenanceTask) -> some View {
        switch status {
        case .idle: EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(vm.progressMessage[task] ?? "Running…").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        case .succeeded: Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Label("Failed", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
