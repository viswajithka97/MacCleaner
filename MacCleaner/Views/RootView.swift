import SwiftUI

struct RootView: View {
    @State private var selection: AppModule = .smartCare
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: Theme.sidebarWidth, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(selection.title)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .smartCare: SmartCareView()
        case .systemJunk: GenericCleanView(module: .systemJunk)
        case .mailAttachments: GenericCleanView(module: .mailAttachments)
        case .trashBins: GenericCleanView(module: .trashBins)
        case .malware: GenericCleanView(module: .malware)
        case .privacy: PrivacyView()
        case .optimization: OptimizationView()
        case .maintenance: MaintenanceView()
        case .uninstaller: UninstallerView()
        case .updater: UpdaterView()
        case .extensions: GenericCleanView(module: .extensions)
        case .spaceLens: SpaceLensView()
        case .largeOldFiles: LargeOldFilesView()
        case .duplicates: DuplicatesView()
        case .similarPhotos: SimilarPhotosView()
        case .shredder: ShredderView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

struct SidebarView: View {
    @Binding var selection: AppModule
    var body: some View {
        List(selection: $selection) {
            ForEach(SidebarGroup.allCases, id: \.rawValue) { group in
                Section(group.rawValue) {
                    ForEach(group.modules) { module in
                        NavigationLink(value: module) {
                            Label(module.title, systemImage: module.symbol)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct GenericCleanView: View {
    @StateObject private var model: CleaningFlowViewModel
    init(module: AppModule) {
        _model = StateObject(wrappedValue: CleaningFlowViewModel(module: module))
    }
    var body: some View { ModuleFlowView(model: model) }
}
