import SwiftUI

/// The dropdown shown from the menu bar icon.
struct MenuBarView: View {
    @ObservedObject var monitor = SystemMonitor.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(AppModule.smartCare.gradient)
                Text("MacCleaner").font(.headline)
                Spacer()
                Button("Open") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
            }

            metric("CPU", "cpu", String(format: "%.0f%%", monitor.cpuTotal * 100), value: monitor.cpuTotal,
                   detail: String(format: "User %.0f%% · System %.0f%%", monitor.cpuUser * 100, monitor.cpuSystem * 100))

            let mem = monitor.memory
            metric("Memory", "memorychip", "\(mem.used.formattedBytes) of \(mem.total.formattedBytes)",
                   value: Double(mem.used) / Double(max(1, mem.total)),
                   detail: "Pressure: \(mem.pressureText) · Compressed \(mem.compressed.formattedBytes)",
                   color: mem.pressureLevel >= 4 ? .red : (mem.pressureLevel >= 2 ? .orange : .green))

            let disk = monitor.disk
            metric("Disk", "internaldrive", "\(disk.availableForImportantUsage.formattedBytes) free",
                   value: 1 - Double(disk.availableForImportantUsage) / Double(max(1, disk.total)),
                   detail: "of \(disk.total.formattedBytes)")

            if let battery = monitor.battery {
                metric("Battery", battery.isCharging ? "battery.100.bolt" : "battery.75", "\(battery.chargePercent)%",
                       value: Double(battery.chargePercent) / 100,
                       detail: [battery.healthPercent.map { "Health \($0)%" }, battery.cycleCount.map { "\($0) cycles" },
                                battery.condition, battery.onAC ? "On power" : "On battery"].compactMap { $0 }.joined(separator: " · "))
            }

            HStack {
                Label("Network", systemImage: "network").frame(width: 100, alignment: .leading)
                Spacer()
                Label(speed(monitor.downloadSpeed), systemImage: "arrow.down").monospacedDigit()
                Label(speed(monitor.uploadSpeed), systemImage: "arrow.up").monospacedDigit()
            }
            .font(.callout)

            Divider()
            Text("Top memory").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(monitor.topApps) { app in
                HStack {
                    if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                    else { Image(systemName: "gearshape").frame(width: 16) }
                    Text(app.name).lineLimit(1)
                    Spacer()
                    Text(app.memory.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            Divider()
            HStack {
                Button {
                    monitor.freeRAM()
                } label: {
                    if monitor.freeingRAM { ProgressView().controlSize(.small) } else { Label("Free up RAM", systemImage: "memorychip") }
                }
                .disabled(monitor.freeingRAM)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            if let result = monitor.lastRAMResult {
                Text(result).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { monitor.start() }
    }

    private func metric(_ title: String, _ symbol: String, _ text: String, value: Double, detail: String, color: Color = .accentColor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Text(text).monospacedDigit()
            }
            .font(.callout)
            ProgressView(value: min(1, max(0, value))).tint(color)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func speed(_ bytesPerSecond: Double) -> String {
        Int64(bytesPerSecond).formattedBytes + "/s"
    }
}
