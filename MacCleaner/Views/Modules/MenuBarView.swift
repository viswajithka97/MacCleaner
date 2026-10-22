import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var monitor: SystemMonitorService
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metric("CPU", String(format: "%.0f%%", monitor.cpu))
            metric("Memory", "\(ByteFormatting.string(Int64(monitor.memoryUsed))) / \(ByteFormatting.string(Int64(monitor.memoryTotal))) · \(monitor.memoryPressure)")
            metric("Disk", "\(ByteFormatting.string(monitor.diskFree)) free")
            metric("Battery", "\(monitor.battery.percent)% · \(monitor.battery.isCharging ? "Charging" : "Battery") · \(monitor.battery.cycleCount) cycles · \(monitor.battery.healthPercent)% health")
            metric("Network", "↑ \(ByteFormatting.string(Int64(monitor.network.up)))/s  ↓ \(ByteFormatting.string(Int64(monitor.network.down)))/s")
            Divider()
            Text("Top memory").font(.caption.bold())
            ForEach(monitor.topMemory.prefix(5)) { row in
                HStack {
                    Text(row.name)
                    Spacer()
                    Text(ByteFormatting.string(Int64(row.memoryBytes)))
                }
                .font(.caption)
            }
            Button("Free up RAM") { monitor.freeRAM() }
            Divider()
            Button("Open MacCleaner") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(8)
        .frame(width: 320)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }
}

import AppKit
