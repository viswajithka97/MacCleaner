import SwiftUI

/// Main window: sidebar on the left, the selected module on the right.
struct RootView: View {
    @ObservedObject var state = AppState.shared
    @ObservedObject var admin = AdminService.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selection) {
                ForEach(ModuleSection.allCases) { section in
                    if section.rawValue.isEmpty {
                        rows(section)
                    } else {
                        Section(section.rawValue) { rows(section) }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .frame(minHeight: 0, idealHeight: 600, maxHeight: .infinity)
        } detail: {
            VStack(spacing: 0) {
                FullDiskAccessBanner()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(backgroundGradient)
            }
            // Without an explicit min/ideal height, AppKit sizes the column to the *content's* height
            // (e.g. a long scroll view), pushing the window's content off-screen.
            .frame(minWidth: 0, idealWidth: 900, maxWidth: .infinity, minHeight: 0, idealHeight: 600, maxHeight: .infinity)
        }
        .sheet(item: $admin.request) { request in AdminSheet(request: request) }
        .frame(minWidth: 980, minHeight: 640)
    }

    private func rows(_ section: ModuleSection) -> some View {
        ForEach(section.modules) { module in
            Label {
                Text(module.title)
            } icon: {
                Image(systemName: module.symbol).foregroundStyle(module.gradient)
            }
            .tag(module)
        }
    }

    /// A soft tint of the module's gradient behind the content (works in light and dark mode).
    private var backgroundGradient: some View {
        let module = state.selection ?? .smartCare
        return LinearGradient(colors: module.gradientColors.map { $0.opacity(0.07) }, startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }

    @ViewBuilder private var detail: some View {
        switch state.selection ?? .smartCare {
        case .smartCare: SmartCareView(vm: state.smartCare)
        case .systemJunk: SystemJunkView(vm: state.systemJunk)
        case .mailAttachments: MailAttachmentsView(vm: state.mailAttachments)
        case .trashBins: TrashBinsView(vm: state.trashBins)
        case .malware: MalwareView(vm: state.malware)
        case .privacy: PrivacyView(vm: state.privacy)
        case .optimization: OptimizationView(vm: state.optimization)
        case .maintenance: MaintenanceView(vm: state.maintenance)
        case .uninstaller: UninstallerView(vm: state.uninstaller)
        case .updater: UpdaterView(vm: state.updater)
        case .extensions: ExtensionsView(vm: state.extensions)
        case .spaceLens: SpaceLensView(vm: state.spaceLens)
        case .largeOldFiles: LargeOldFilesView(vm: state.largeOldFiles)
        case .duplicates: DuplicatesView(vm: state.duplicates)
        case .similarPhotos: SimilarPhotosView(vm: state.similarPhotos)
        case .shredder: ShredderView(vm: state.shredder)
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}
