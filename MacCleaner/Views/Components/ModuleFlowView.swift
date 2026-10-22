import SwiftUI

struct ModuleFlowView: View {
    @ObservedObject var model: CleaningFlowViewModel
    var extraResults: AnyView? = nil

    var body: some View {
        VStack(spacing: 0) {
            FDABanner().padding(.horizontal).padding(.top, 8)
            switch model.phase {
            case .intro:
                IntroPane(module: model.module, onScan: model.startScan)
            case .scanning:
                ScanningPane(module: model.module, progress: model.progress, path: model.currentPath, onCancel: model.cancel)
            case .results:
                ResultsPane(model: model, extra: extraResults)
            case .summary:
                if let summary = model.summary {
                    SummaryPane(summary: summary, onAgain: model.reset)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .confirmationDialog("Confirm removal", isPresented: $model.confirmVisible) {
            Button("Remove \(model.selectedItems.count) items (\(ByteFormatting.string(model.selectedSize)))", role: .destructive) {
                Task { await model.confirmCleanup() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.selectedItems.prefix(12).map(\.path).joined(separator: "\n") + (model.selectedItems.count > 12 ? "\n…" : ""))
        }
    }
}

struct IntroPane: View {
    let module: AppModule
    var onScan: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(Theme.cardFill(module.accent)).frame(width: 120, height: 120)
                Image(systemName: module.symbol)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(module.accent)
            }
            Text(module.title).font(.largeTitle.bold())
            Text(module.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button(action: onScan) {
                Label("Scan", systemImage: "bolt.horizontal.circle.fill")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(module.accent)
            .controlSize(.large)
            Spacer()
        }
        .padding()
    }
}

struct ScanningPane: View {
    let module: AppModule
    var progress: Double
    var path: String
    var onCancel: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView(value: min(max(progress, 0.05), 1))
                .progressViewStyle(.linear)
                .frame(maxWidth: 480)
            Text("Scanning \(module.title)…")
                .font(.title2.weight(.semibold))
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 560)
            Button("Cancel", action: onCancel)
            Spacer()
        }
        .padding()
    }
}

struct ResultsPane: View {
    @ObservedObject var model: CleaningFlowViewModel
    var extra: AnyView?
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(model.module.title).font(.title.bold())
                    Text("Select what to remove, then review details if you want a path-by-path look.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review details") { model.reviewing = true }
                Button {
                    model.performCleanup()
                } label: {
                    Text("Clean \(ByteFormatting.string(model.selectedSize))")
                }
                .buttonStyle(.borderedProminent)
                .tint(model.module.accent)
                .disabled(model.selectedItems.isEmpty)
            }
            .padding()

            if let extra { extra.padding(.horizontal) }

            List {
                ForEach($model.categories) { $category in
                    Section {
                        if expanded.contains(category.id) {
                            ForEach($category.items) { $item in
                                ItemRow(item: $item)
                            }
                        }
                    } header: {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { category.selected },
                                set: { model.toggleCategory(category.id, selected: $0) }
                            )) { EmptyView() }
                            .labelsHidden()
                            Image(systemName: category.symbol)
                            Text(category.name).font(.headline)
                            Spacer()
                            Text(ByteFormatting.string(category.size)).monospacedDigit()
                            Button(expanded.contains(category.id) ? "Hide" : "Show") {
                                if expanded.contains(category.id) { expanded.remove(category.id) } else { expanded.insert(category.id) }
                            }
                            .buttonStyle(.plain)
                        }
                        if !category.detail.isEmpty {
                            Text(category.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        if let warning = category.warning {
                            Text(warning).font(.caption).foregroundStyle(.orange)
                        }
                        if category.requiresAdmin {
                            Text("Administrator password required to remove these items.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $model.reviewing) {
            ReviewSheet(items: model.selectedItems)
        }
    }
}

struct ItemRow: View {
    @Binding var item: CleanableItem
    var body: some View {
        HStack {
            Toggle("", isOn: $item.selected)
                .disabled(!item.removable)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(item.subtitle.isEmpty ? item.path : item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let warning = item.warning {
                    Text(warning).font(.caption2).foregroundStyle(.orange)
                }
                if let reasons = item.extra["reasons"] {
                    Text(reasons).font(.caption2).foregroundStyle(.red)
                }
            }
            Spacer()
            Text(ByteFormatting.string(item.size)).monospacedDigit()
            Button {
                FinderReveal.reveal(item.path)
            } label: { Image(systemName: "folder") }
            .buttonStyle(.borderless)
            .disabled(item.path.contains("://"))
            Button {
                QuickLookPreview.shared.preview(paths: [item.path])
            } label: { Image(systemName: "eye") }
            .buttonStyle(.borderless)
            .disabled(item.path.contains("://"))
        }
    }
}

struct ReviewSheet: View {
    let items: [CleanableItem]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Review details").font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
            }
            List(items) { item in
                VStack(alignment: .leading) {
                    Text(item.name).font(.headline)
                    Text(item.path).font(.caption).textSelection(.enabled)
                    Text(ByteFormatting.string(item.size)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 640, height: 480)
    }
}

struct SummaryPane: View {
    let summary: CleanupSummary
    var onAgain: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("Finished").font(.largeTitle.bold())
            Text("Removed \(summary.removedCount) items")
            Text(ByteFormatting.string(summary.bytesFreed)).font(.system(size: 42, weight: .bold, design: .rounded))
            ForEach(summary.notes, id: \.self) { Text($0).foregroundStyle(.secondary) }
            if !summary.skipped.isEmpty {
                Text("Skipped \(summary.skipped.count) items").foregroundStyle(.orange)
            }
            Button("Scan again", action: onAgain)
            Spacer()
        }
        .padding()
    }
}
