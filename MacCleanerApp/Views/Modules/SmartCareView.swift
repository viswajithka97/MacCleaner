import SwiftUI

struct SmartCareView: View {
    @ObservedObject var vm: SmartCareViewModel
    private let module = AppModule.smartCare

    var body: some View {
        Group {
            switch vm.phase {
            case .intro:
                ModuleIntroView(module: module, onStart: vm.scan) {
                    InfoBanner(text: "Safe by design: installed apps, Homebrew packages and developer tools are never removed.",
                               symbol: "lock.shield.fill")
                }
            case .scanning:
                ScanningView(module: module, title: "Running Smart Care scan…", snapshot: vm.snapshot, onCancel: vm.cancelTask)
            case .results:
                dashboard
            case .cleaning:
                ScanningView(module: module, title: "Running…", snapshot: vm.snapshot, onCancel: vm.cancelTask)
            case .summary:
                SummaryView(module: module, result: vm.result) { vm.reset() }
            }
        }
        .animation(.easeInOut, value: vm.phase)
        .sheet(item: $vm.reviewing) { area in reviewSheet(area) }
        .sheet(isPresented: $vm.showConfirmation) {
            ConfirmationSheet(title: "Run Smart Care?", items: vm.allSelectedItems,
                              message: "Caches, logs and Trash items are removed, confirmed adware is removed, recommended tasks run and selected apps are updated (updates download the new version; nothing is uninstalled). Installed apps, Homebrew and developer tools are never removed.",
                              confirmTitle: "Run",
                              onConfirm: vm.confirmRun, onCancel: { vm.showConfirmation = false })
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    Text("Here's what Smart Care found").font(.title.bold()).padding(.top, 20)
                    InfoBanner(text: "Smart Care never uninstalls or modifies installed apps, Homebrew packages or developer tools. It only removes caches, logs, Trash contents and confirmed adware. Language files, brew cleanup and suspicious-but-unconfirmed items are left for you to review in their own sections.",
                               symbol: "lock.shield.fill")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(SmartCareArea.allCases) { area in card(area) }
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Button("Start Over") { vm.reset() }
                Spacer()
                BigActionButton(title: "Run", subtitle: vm.totalSelectedSize > 0 ? vm.totalSelectedSize.formattedBytes : nil,
                                module: module, disabled: vm.allSelectedItems.isEmpty) { vm.requestRun() }
                    .scaleEffect(0.7)
                    .frame(height: 100)
                Spacer()
                Text("\(vm.allSelectedItems.count) action(s)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
        }
    }

    private func card(_ area: SmartCareArea) -> some View {
        let included = vm.included.contains(area)
        let count = vm.selectedItems(area).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: area.symbol).font(.title).foregroundStyle(module.gradient)
                Text(area.title).font(.title3.bold())
                Spacer()
                Toggle("", isOn: Binding(get: { included }, set: { on in
                    if on { vm.included.insert(area) } else { vm.included.remove(area) }
                }))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            Text(vm.headline(area)).font(.headline)
            Text(count == 0 ? "No actions selected" : "\(count) action(s) selected"
                 + (vm.selectedSize(area) > 0 ? " · \(vm.selectedSize(area).formattedBytes)" : ""))
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Review details") { vm.reviewing = area }
                .disabled(vm.categories(area).isEmpty)
        }
        .frame(minHeight: 150, alignment: .topLeading)
        .card()
        .opacity(included ? 1 : 0.55)
    }

    private func reviewSheet(_ area: SmartCareArea) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(area.title).font(.title2.bold())
                Spacer()
                Button("Done") { vm.reviewing = nil }.keyboardShortcut(.defaultAction)
            }
            if area == .protection {
                InfoBanner(style: .warning, text: "Heuristic scan only — not a replacement for a full antivirus product.")
            }
            ScrollView {
                ReviewList(vm: vm, area: area)
            }
        }
        .padding(20)
        .frame(width: 720, height: 560)
    }
}

/// The editable category list inside the Smart Care review sheet.
private struct ReviewList: View {
    @ObservedObject var vm: SmartCareViewModel
    var area: SmartCareArea
    @State private var expanded: Set<String> = []

    var body: some View {
        CategoryListView(categories: vm.categories(area), showItems: false, expanded: $expanded,
                         onToggleCategory: { vm.setCategory(area, $0.id, selected: $0.selectionState != .all) },
                         onToggleItem: { vm.toggleItem(area, $0.id, $1.id) })
    }
}
