import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading) {
                    Text("History").font(.largeTitle.bold())
                    Text("Total space freed: \(ByteFormatting.string(history.totalBytesFreed))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear log") { history.clear() }
            }
            .padding()
            List(history.entries) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.moduleTitle).font(.headline)
                        Text(entry.notes).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(entry.itemsRemoved) items")
                    Text(ByteFormatting.string(entry.bytesFreed)).bold()
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .background(Theme.background)
    }
}
