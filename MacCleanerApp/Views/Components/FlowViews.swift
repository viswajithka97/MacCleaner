import SwiftUI
import QuickLook

/// Intro screen: icon, description, feature list and the big Scan button.
struct ModuleIntroView<Extra: View>: View {
    var module: AppModule
    var buttonTitle: String = "Scan"
    var onStart: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 30)
                ModuleIcon(module: module, size: 96)
                VStack(spacing: 6) {
                    Text(module.title).font(.largeTitle.bold())
                    Text(module.tagline).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if !module.features.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(module.features, id: \.self) { feature in
                            Label {
                                Text(feature)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(module.tint)
                            }
                        }
                    }
                    .font(.body)
                }
                extra
                BigActionButton(title: buttonTitle, module: module, action: onStart)
                    .padding(.top, 8)
                Spacer(minLength: 30)
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

extension ModuleIntroView where Extra == EmptyView {
    init(module: AppModule, buttonTitle: String = "Scan", onStart: @escaping () -> Void) {
        self.init(module: module, buttonTitle: buttonTitle, onStart: onStart) { EmptyView() }
    }
}

/// Animated "working" screen with progress bar, current path and Cancel.
struct ScanningView: View {
    var module: AppModule
    var title: String = "Scanning…"
    var snapshot: ScanProgress.Snapshot
    var onCancel: (() -> Void)?
    @State private var spin = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().stroke(module.tint.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(AngularGradient(colors: module.gradientColors + [module.gradientColors[0]], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                Image(systemName: module.symbol).font(.system(size: 40)).foregroundStyle(module.gradient)
            }
            .frame(width: 130, height: 130)
            .onAppear { spin = true }

            Text(snapshot.message.isEmpty ? title : snapshot.message).font(.title3.weight(.medium))
            Group {
                if let fraction = snapshot.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .frame(maxWidth: 420)
            .tint(module.tint)

            Text(snapshot.currentPath.isEmpty ? " " : snapshot.currentPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
            if snapshot.itemsScanned > 0 {
                Text("\(snapshot.itemsScanned) items checked").font(.caption).foregroundStyle(.tertiary)
            }
            if let onCancel {
                Button("Cancel", role: .cancel, action: onCancel).controlSize(.large)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Checkbox that can show a "mixed" state for categories.
struct TriStateCheckbox: View {
    var state: SelectionState
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .all ? "checkmark.square.fill" : (state == .some ? "minus.square.fill" : "square"))
                .font(.system(size: 16))
                .foregroundStyle(state == .none ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// One file/item row with checkbox, icon, name, path, size and quick actions.
struct ItemRow: View {
    var item: CleanItem
    var showCheckbox = true
    var onToggle: () -> Void
    var onPreview: ((URL) -> Void)?
    var singleActionTitle: String? = nil
    var onSingleAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            if showCheckbox && !item.action.isInfoOnly {
                TriStateCheckbox(state: item.isSelected ? .all : .none, action: onToggle)
            }
            icon.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else if let path = item.displayPath {
                    Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                if let warning = item.warning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if let date = item.date {
                Text(ByteFormat.date(date)).font(.caption).foregroundStyle(.secondary)
            }
            if item.size > 0 {
                Text(item.size.formattedBytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(minWidth: 70, alignment: .trailing)
            }
            if let url = item.url, FileManager.default.fileExists(atPath: url.path) {
                Menu {
                    Button("Reveal in Finder") { SystemLinks.reveal(url) }
                    if let onPreview { Button("Quick Look") { onPreview(url) } }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.path, forType: .string)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if let singleActionTitle, let onSingleAction, !item.action.isInfoOnly {
                Button(singleActionTitle, action: onSingleAction).controlSize(.small)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        if let url = item.url, FileManager.default.fileExists(atPath: url.path) {
            Image(nsImage: SystemLinks.icon(for: url)).resizable()
        } else {
            Image(systemName: item.symbol ?? "doc").foregroundStyle(.secondary)
        }
    }
}

/// The list of categories with checkboxes, sizes and expandable item lists.
struct CategoryListView: View {
    var categories: [CleanCategory]
    var showItems: Bool
    @Binding var expanded: Set<String>
    var onToggleCategory: (CleanCategory) -> Void
    var onToggleItem: (CleanCategory, CleanItem) -> Void
    var singleActionTitle: ((CleanItem) -> String)? = nil
    var onSingleAction: ((CleanItem) -> Void)? = nil
    @State private var previewURL: URL?

    var body: some View {
        LazyVStack(spacing: 10) {
            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TriStateCheckbox(state: category.selectionState, disabled: category.infoOnly) {
                            onToggleCategory(category)
                        }
                        Image(systemName: category.symbol).frame(width: 22).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.title).font(.headline)
                            Text(category.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(category.totalSize > 0 ? category.totalSize.formattedBytes : "\(category.items.count) items")
                                .font(.headline.monospacedDigit())
                            if !category.infoOnly && category.selectedSize != category.totalSize && category.totalSize > 0 {
                                Text("\(category.selectedSize.formattedBytes) selected").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expanded.contains(category.id) { expanded.remove(category.id) } else { expanded.insert(category.id) }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(expanded.contains(category.id) || showItems ? 90 : 0))
                        }
                        .buttonStyle(.borderless)
                    }
                    if let warning = category.warning { InfoBanner(style: .warning, text: warning) }
                    if let note = category.note, expanded.contains(category.id) || showItems {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    if expanded.contains(category.id) || showItems {
                        Divider()
                        ForEach(category.items.prefix(500)) { item in
                            ItemRow(item: item, showCheckbox: !category.infoOnly,
                                    onToggle: { onToggleItem(category, item) },
                                    onPreview: { previewURL = $0 },
                                    singleActionTitle: singleActionTitle?(item),
                                    onSingleAction: onSingleAction.map { action in { action(item) } })
                        }
                        if category.items.count > 500 {
                            Text("…and \(category.items.count - 500) more (all are included in the selection)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .card()
            }
        }
        .quickLookPreview($previewURL)
    }
}

/// Generic results screen (header with total, list, action button).
struct ResultsScreen<Accessory: View>: View {
    @ObservedObject var vm: CleanupFlowViewModel
    var singleActionTitle: ((CleanItem) -> String)? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading) {
                            Text(vm.categories.isEmpty ? "Nothing found" : "Scan complete").font(.title2.bold())
                            Text(vm.categories.isEmpty ? "Your Mac looks clean here." :
                                    "Found \(vm.totalSize.formattedBytes) in \(vm.categories.count) categories")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(vm.reviewDetails ? "Hide details" : "Review details") {
                            withAnimation { vm.reviewDetails.toggle() }
                        }
                        Menu("Select") {
                            Button("Select all") { vm.selectAll(true) }
                            Button("Deselect all") { vm.selectAll(false) }
                        }
                        .fixedSize()
                        Button("Rescan") { vm.scan() }
                    }
                    accessory
                    CategoryListView(categories: vm.categories, showItems: vm.reviewDetails, expanded: $vm.expanded,
                                     onToggleCategory: { vm.setCategory($0.id, selected: $0.selectionState != .all) },
                                     onToggleItem: { vm.toggleItem($0.id, $1.id) },
                                     singleActionTitle: singleActionTitle,
                                     onSingleAction: singleActionTitle == nil ? nil : { vm.requestSingle($0) })
                }
                .padding(20)
            }
            Divider()
            HStack {
                Button("Start Over") { vm.reset() }
                Spacer()
                Text("\(vm.selectedItems.count) item(s) selected").foregroundStyle(.secondary)
                Button {
                    vm.requestClean()
                } label: {
                    Text("\(vm.actionTitle) \(vm.selectedSize > 0 ? vm.selectedSize.formattedBytes : "")")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.module.tint)
                .controlSize(.large)
                .disabled(vm.selectedItems.isEmpty)
            }
            .padding(14)
        }
        .sheet(isPresented: $vm.showConfirmation) {
            ConfirmationSheet(title: "\(vm.actionTitle) \(vm.pendingItems.count) item(s)?",
                              items: vm.pendingItems,
                              onConfirm: { vm.confirmClean() },
                              onCancel: { vm.showConfirmation = false })
        }
    }
}

/// "Are you sure?" sheet listing exactly what will be removed.
struct ConfirmationSheet: View {
    var title: String
    var items: [CleanItem]
    var destructive = false
    var message: String? = nil
    var confirmTitle = "Continue"
    var onConfirm: () -> Void
    var onCancel: () -> Void
    @ObservedObject private var settings = SettingsStore.shared

    var total: Int64 { items.reduce(0) { $0 + $1.size } }
    var needsAdmin: Bool { items.contains { $0.action.requiresAdmin } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold())
            Text(message ?? (settings.moveToTrash
                             ? "Files will be moved to the Trash (change this in Settings). Emptied Trash items and system files are deleted permanently."
                             : "Files will be deleted permanently. This cannot be undone."))
                .foregroundStyle(destructive || !settings.moveToTrash ? .red : .secondary)
            if needsAdmin {
                InfoBanner(style: .info, text: "Some of these need your administrator password. You'll see what each command does before anything runs.",
                           symbol: "lock.fill")
            }
            List(items.prefix(1000)) { item in
                HStack {
                    Image(systemName: item.symbol ?? "doc").foregroundStyle(.secondary).frame(width: 18)
                    VStack(alignment: .leading) {
                        Text(item.name).lineLimit(1)
                        if let path = item.displayPath {
                            Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer()
                    if item.size > 0 { Text(item.size.formattedBytes).monospacedDigit().foregroundStyle(.secondary) }
                }
            }
            .frame(minHeight: 220)
            if items.count > 1000 { Text("…and \(items.count - 1000) more").font(.caption) }
            HStack {
                Text("Total: \(total.formattedBytes)").font(.headline)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(confirmTitle, role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(destructive ? .red : .accentColor)
            }
        }
        .padding(22)
        .frame(width: 600, height: 520)
    }
}

/// After cleaning: what was done and how much space was freed.
struct SummaryView: View {
    var module: AppModule
    var result: CleanupResult
    var doneTitle = "Done"
    var onDone: () -> Void
    @State private var showFailures = false
    @State private var appear = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 30)
                Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "checkmark.circle.badge.questionmark.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(module.gradient)
                    .scaleEffect(appear ? 1 : 0.4)
                    .animation(.spring(response: 0.45, dampingFraction: 0.6), value: appear)
                    .onAppear { appear = true }
                Text(result.freedBytes > 0 ? "\(result.freedBytes.formattedBytes) freed" : "All done").font(.largeTitle.bold())
                Text("\(result.removedCount) item(s) processed" + (result.failures.isEmpty ? "" : ", \(result.failures.count) skipped"))
                    .foregroundStyle(.secondary)
                if !result.messages.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.messages, id: \.self) { Text($0).font(.callout).textSelection(.enabled) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                if !result.failures.isEmpty {
                    DisclosureGroup("Skipped items (\(result.failures.count))", isExpanded: $showFailures) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(result.failures.prefix(300)) { failure in
                                VStack(alignment: .leading) {
                                    Text(failure.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                                    Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    }
                    .card()
                }
                Button(doneTitle, action: onDone).buttonStyle(.borderedProminent).tint(module.tint).controlSize(.large)
                Spacer(minLength: 30)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }
}

/// The complete generic module: intro → scanning → results → cleaning → summary.
struct CleanupFlowView<IntroExtra: View, Accessory: View>: View {
    @ObservedObject var vm: CleanupFlowViewModel
    var scanTitle = "Scan"
    var singleActionTitle: ((CleanItem) -> String)? = nil
    @ViewBuilder var introExtra: IntroExtra
    @ViewBuilder var accessory: Accessory

    var body: some View {
        Group {
            switch vm.phase {
            case .intro:
                ModuleIntroView(module: vm.module, buttonTitle: scanTitle, onStart: vm.scan) { introExtra }
            case .scanning:
                ScanningView(module: vm.module, snapshot: vm.snapshot, onCancel: vm.cancelTask)
            case .results:
                ResultsScreen(vm: vm, singleActionTitle: singleActionTitle) { accessory }
            case .cleaning:
                ScanningView(module: vm.module, title: "Cleaning…", snapshot: vm.snapshot, onCancel: vm.cancelTask)
            case .summary:
                SummaryView(module: vm.module, result: vm.result) { vm.scan() }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.phase)
    }
}
