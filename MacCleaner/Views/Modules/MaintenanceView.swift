import SwiftUI

struct MaintenanceView: View {
    @State private var selected: Set<String> = Set(MaintenanceService.tasks.map(\.id))
    @State private var outputs: [String: String] = [:]
    @State private var running: String?
    @State private var summary: CleanupSummary?
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading) {
            FDABanner().padding()
            Text("Maintenance").font(.largeTitle.bold()).padding(.horizontal)
            Text("Each task explains why it needs permission before it runs. Output appears under the task.")
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            List {
                ForEach(MaintenanceService.tasks) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { selected.contains(task.id) },
                                set: { if $0 { selected.insert(task.id) } else { selected.remove(task.id) } }
                            )) { EmptyView() }
                            .labelsHidden()
                            VStack(alignment: .leading) {
                                Text(task.title).font(.headline)
                                Text(task.detail).font(.caption).foregroundStyle(.secondary)
                                Text(task.explanation).font(.caption2).foregroundStyle(.orange)
                            }
                            Spacer()
                            Button(running == task.id ? "Running…" : "Run") {
                                Task { await run(task) }
                            }
                            .disabled(running != nil)
                        }
                        if let out = outputs[task.id], !out.isEmpty {
                            ScrollView {
                                Text(out).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 120)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                Spacer()
                Button("Run selected") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(running != nil)
            }
            .padding()
        }
        .background(Theme.background)
        .confirmationDialog("Run maintenance tasks?", isPresented: $confirm) {
            Button("Run") {
                Task {
                    for task in MaintenanceService.tasks where selected.contains(task.id) {
                        await run(task)
                    }
                    let summary = CleanupSummary(module: .maintenance, removedCount: selected.count, bytesFreed: 0, skipped: [], notes: ["Maintenance tasks completed."])
                    self.summary = summary
                    HistoryStore.shared.append(summary)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(MaintenanceService.tasks.filter { selected.contains($0.id) }.map(\.title).joined(separator: "\n"))
        }
    }

    private func run(_ task: MaintenanceTask) async {
        running = task.id
        let output = await MaintenanceService.run(task)
        outputs[task.id] = output
        running = nil
    }
}
