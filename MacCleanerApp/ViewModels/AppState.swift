import Foundation
import Combine

/// App-wide state: the selected sidebar module and one view model per module
/// (kept alive so results survive switching between sections).
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selection: AppModule? = .smartCare

    lazy var systemJunk = CleanupFlowViewModel(module: .systemJunk, actionTitle: "Clean") { SystemJunkService.scan(progress: $0) }
    lazy var mailAttachments = CleanupFlowViewModel(module: .mailAttachments, actionTitle: "Remove") { MailAttachmentsService.scan(progress: $0) }
    lazy var trashBins = CleanupFlowViewModel(module: .trashBins, actionTitle: "Empty") { TrashService.scan(progress: $0) }
    lazy var malware = CleanupFlowViewModel(module: .malware, actionTitle: "Remove") { MalwareService.scan(progress: $0) }
    lazy var privacy = CleanupFlowViewModel(module: .privacy, actionTitle: "Remove") { PrivacyService.scan(progress: $0) }
    lazy var extensions = CleanupFlowViewModel(module: .extensions, actionTitle: "Remove") { ExtensionsService.scan(progress: $0) }

    lazy var smartCare = SmartCareViewModel()
    lazy var optimization = OptimizationViewModel()
    lazy var maintenance = MaintenanceViewModel()
    lazy var uninstaller = UninstallerViewModel()
    lazy var updater = UpdaterViewModel()
    lazy var spaceLens = SpaceLensViewModel()
    lazy var largeOldFiles = LargeOldFilesViewModel()
    lazy var duplicates = DuplicatesViewModel()
    lazy var similarPhotos = SimilarPhotosViewModel()
    lazy var shredder = ShredderViewModel()

    private init() {}
}
