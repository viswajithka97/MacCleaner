import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

/// Editable list of folders to scan.
struct FolderListEditor: View {
    @Binding var folders: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Folders to scan").font(.headline)
            ForEach(folders, id: \.self) { folder in
                HStack {
                    Image(systemName: "folder")
                    Text(folder.tildePath).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { folders.removeAll { $0 == folder } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button("Add Folder…") {
                for url in FolderPicker.choose() where !folders.contains(url) { folders.append(url) }
            }
        }
        .card()
    }
}

/// A row for a found file (Large & Old Files, Duplicates).
private struct FoundFileRow: View {
    var file: FoundFile
    var onToggle: () -> Void
    var onPreview: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { file.isSelected }, set: { _ in onToggle() })).toggleStyle(.checkbox).labelsHidden()
            Image(nsImage: SystemLinks.icon(for: file.url)).resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).lineLimit(1).truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().tildePath).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(file.size.formattedBytes).monospacedDigit()
                Text("Opened \(ByteFormat.relative(file.lastOpened))").font(.caption).foregroundStyle(.secondary)
            }
            Button(action: onPreview) { Image(systemName: "eye") }.buttonStyle(.borderless).help("Quick Look")
            Button { SystemLinks.reveal(file.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Reveal in Finder")
        }
    }
}

struct LargeOldFilesView: View {
    @ObservedObject var vm: LargeOldFilesViewModel

    var body: some View {
        Group {
            if vm.isBusy {
                ScanningView(module: .largeOldFiles, snapshot: vm.snapshot, onCancel: vm.cancelTask)
            } else if let result = vm.result {
                SummaryView(module: .largeOldFiles, result: result, doneTitle: "Back to Results") { vm.result = nil }
            } else if !vm.scanned {
                ModuleIntroView(module: .largeOldFiles, onStart: vm.scan) { options }
            } else {
                results
            }
        }
        .quickLookPreview($vm.previewURL)
        .sheet(item: $vm.confirmMode) { mode in
            ConfirmationSheet(title: mode == .shred ? "Shred \(vm.selectedFiles.count) file(s)?" : "Remove \(vm.selectedFiles.count) file(s)?",
                              items: vm.selectedFiles.map { CleanItem(name: $0.name, url: $0.url, size: $0.size, action: .remove($0.url)) },
                              destructive: mode == .shred,
                              message: mode == .shred ? "Files are overwritten with random data and deleted. This cannot be undone." : nil,
                              confirmTitle: mode == .shred ? "Shred" : "Remove",
                              onConfirm: vm.confirm, onCancel: { vm.confirmMode = nil })
        }
    }

    private var options: some View {
        VStack(spacing: 12) {
            FolderListEditor(folders: $vm.folders)
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $vm.findLarge) {
                    Stepper("Large: at least \(vm.minSizeMB) MB", value: $vm.minSizeMB, in: 10...10_000, step: 50)
                }
                Toggle(isOn: $vm.findOld) {
                    Stepper("Old: not opened for \(vm.olderThanDays) days", value: $vm.olderThanDays, in: 30...3650, step: 30)
                }
                Text("Files matching either rule are listed. \"Old\" only considers files of 1 MB or more.").font(.caption).foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Kind", selection: $vm.kind) {
                    ForEach(FileKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 200)
                Picker("Sort", selection: $vm.sort) {
                    ForEach(LargeOldFilesViewModel.Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 200)
                Spacer()
                Button("New Scan") { vm.scanned = false }
            }
            .padding(12)
            List(vm.visibleFiles) { file in
                FoundFileRow(file: file, onToggle: { vm.toggle(file) }, onPreview: { vm.previewURL = file.url })
            }
            Divider()
            HStack {
                Text("\(vm.visibleFiles.count) files · \(vm.selectedFiles.count) selected").foregroundStyle(.secondary)
                Spacer()
                Button("Shred…") { vm.confirmMode = .shred }.disabled(vm.selectedFiles.isEmpty)
                Button("Remove \(vm.selectedSize.formattedBytes)") { vm.confirmMode = .remove }
                    .buttonStyle(.borderedProminent).tint(AppModule.largeOldFiles.tint)
                    .disabled(vm.selectedFiles.isEmpty)
            }
            .padding(12)
        }
    }
}

struct DuplicatesView: View {
    @ObservedObject var vm: DuplicatesViewModel

    var body: some View {
        Group {
            if vm.isBusy {
                ScanningView(module: .duplicates, snapshot: vm.snapshot, onCancel: vm.cancelTask)
            } else if let result = vm.result {
                SummaryView(module: .duplicates, result: result, doneTitle: "Back to Results") { vm.result = nil }
            } else if !vm.scanned {
                ModuleIntroView(module: .duplicates, onStart: vm.scan) {
                    VStack(spacing: 12) {
                        FolderListEditor(folders: $vm.folders)
                        Stepper("Ignore files smaller than \(vm.minSizeKB) KB", value: $vm.minSizeKB, in: 1...102_400, step: 50).card()
                    }
                }
            } else {
                results
            }
        }
        .quickLookPreview($vm.previewURL)
        .sheet(isPresented: $vm.showConfirmation) {
            ConfirmationSheet(title: "Remove \(vm.selectedFiles.count) duplicate(s)?",
                              items: vm.selectedFiles.map { CleanItem(name: $0.name, url: $0.url, size: $0.size, action: .remove($0.url)) },
                              onConfirm: vm.confirmRemove, onCancel: { vm.showConfirmation = false })
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(vm.groups.count) groups · \(vm.wasted.formattedBytes) in extra copies").font(.headline)
                Spacer()
                Picker("Keep", selection: $vm.keep) {
                    ForEach(DuplicatesViewModel.Keep.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 220)
                Button("Auto Select") { vm.autoSelect() }
                Button("New Scan") { vm.scanned = false }
            }
            .padding(12)
            if vm.hasGroupWithNothingKept {
                InfoBanner(style: .warning, text: "In at least one group every copy is selected — no copy would be kept.").padding(.horizontal, 12)
            }
            List {
                ForEach(vm.groups) { group in
                    Section {
                        ForEach(group.files) { file in
                            HStack {
                                Thumbnail(url: file.url).frame(width: 40, height: 40)
                                FoundFileRow(file: file, onToggle: { vm.toggle(group: group.id, file: file.id) },
                                             onPreview: { vm.previewURL = file.url })
                            }
                        }
                    } header: {
                        Text("\(group.files.first?.name ?? "") — \(group.files.count) copies of \(group.files.first?.size.formattedBytes ?? "")")
                    }
                }
            }
            Divider()
            HStack {
                Text("\(vm.selectedFiles.count) selected").foregroundStyle(.secondary)
                Spacer()
                Button("Remove \(vm.selectedSize.formattedBytes)") { vm.showConfirmation = true }
                    .buttonStyle(.borderedProminent).tint(AppModule.duplicates.tint)
                    .disabled(vm.selectedFiles.isEmpty)
            }
            .padding(12)
        }
    }
}

/// QuickLook thumbnail for a file, loaded in the background.
struct Thumbnail: View {
    var url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(nsImage: SystemLinks.icon(for: url)).resizable().scaledToFit().opacity(0.6) }
        }
        .task(id: url) {
            image = await ThumbnailLoader.load(url)
        }
    }
}


enum ThumbnailLoader {
    static func load(_ url: URL, side: CGFloat = 80) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: 2, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}

struct SimilarPhotosView: View {
    @ObservedObject var vm: SimilarPhotosViewModel

    var body: some View {
        Group {
            if vm.isBusy {
                ScanningView(module: .similarPhotos, title: "Analyzing photos…", snapshot: vm.snapshot, onCancel: vm.cancelTask)
            } else if let result = vm.result {
                SummaryView(module: .similarPhotos, result: result, doneTitle: "Back to Results") { vm.result = nil }
            } else if !vm.scanned {
                ModuleIntroView(module: .similarPhotos, onStart: vm.scan) {
                    VStack(spacing: 12) {
                        FolderListEditor(folders: $vm.folders)
                        VStack(alignment: .leading) {
                            Toggle("Include my Photos library (read-only analysis; asks for permission)", isOn: $vm.includeLibrary)
                            HStack {
                                Text("Strict")
                                Slider(value: $vm.threshold, in: 6...15)
                                Text("Loose")
                            }
                            Text("Looser settings group more photos together.").font(.caption).foregroundStyle(.secondary)
                        }
                        .card()
                    }
                }
            } else {
                results
            }
        }
        .sheet(isPresented: $vm.showConfirmation) {
            ConfirmationSheet(title: "Delete \(vm.selectedPhotos.count) photo(s)?",
                              items: vm.selectedPhotos.map { photo in
                                  switch photo.source {
                                  case .file(let url): return CleanItem(name: photo.name, url: url, size: photo.size, action: .remove(url))
                                  case .library(let id): return CleanItem(name: photo.name + " (Photos library)", url: nil, size: photo.size, symbol: "photo", action: .photoAsset(localIdentifier: id))
                                  }
                              },
                              message: "Files go to the Trash (or are deleted, per Settings). Photos library items are deleted through Photos, which asks you to confirm and keeps them in Recently Deleted for 30 days.",
                              onConfirm: vm.confirmDelete, onCancel: { vm.showConfirmation = false })
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(vm.groups.count) groups of similar photos").font(.headline)
                Spacer()
                Button("New Scan") { vm.scanned = false }
            }
            .padding(12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(vm.groups) { group in
                        VStack(alignment: .leading) {
                            Text("\(group.photos.count) similar photos").font(.subheadline.bold())
                            ScrollView(.horizontal) {
                                HStack(spacing: 10) {
                                    ForEach(group.photos) { photo in
                                        PhotoTile(photo: photo, isBest: photo.id == group.bestID) {
                                            vm.toggle(group: group.id, photo: photo.id)
                                        }
                                    }
                                }
                            }
                        }
                        .card()
                    }
                }
                .padding(12)
            }
            Divider()
            HStack {
                Text("\(vm.selectedPhotos.count) selected · the best shot in each group is kept by default").foregroundStyle(.secondary)
                Spacer()
                Button("Delete \(vm.selectedSize.formattedBytes)") { vm.showConfirmation = true }
                    .buttonStyle(.borderedProminent).tint(AppModule.similarPhotos.tint)
                    .disabled(vm.selectedPhotos.isEmpty)
            }
            .padding(12)
        }
    }
}

/// Carries an NSImage from a background task to the main thread.
private final class ImageBox: @unchecked Sendable {
    let image: NSImage?
    init(_ image: NSImage?) { self.image = image }
}

private struct PhotoTile: View {
    var photo: PhotoCandidate
    var isBest: Bool
    var onToggle: () -> Void
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image { Image(nsImage: image).resizable().scaledToFill() } else { Color.secondary.opacity(0.15) }
                }
                .frame(width: 150, height: 150)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(photo.isSelected ? Color.red : (isBest ? Color.green : .clear), lineWidth: 3))
                Image(systemName: photo.isSelected ? "trash.circle.fill" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, photo.isSelected ? Color.red : Color.green)
                    .padding(6)
            }
            .onTapGesture(perform: onToggle)
            Text(photo.name).font(.caption).lineLimit(1).frame(width: 150)
            Text("\(photo.pixelWidth)×\(photo.pixelHeight)\(isBest ? " · Best" : "")").font(.caption2).foregroundStyle(.secondary)
        }
        .task(id: photo.id) {
            let candidate = photo
            // NSImage is only Sendable on macOS 14+, so it crosses threads inside a small box.
            image = await Task.detached { ImageBox(SimilarPhotosService.image(for: candidate)) }.value.image
        }
    }
}

struct ShredderView: View {
    @ObservedObject var vm: ShredderViewModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .shredder)
            if vm.isBusy {
                ScanningView(module: .shredder, title: "Shredding…", snapshot: vm.snapshot, onCancel: vm.cancelTask)
            } else if let result = vm.result {
                SummaryView(module: .shredder, result: result) { vm.result = nil }
            } else {
                VStack(spacing: 14) {
                    InfoBanner(style: .warning, text: "On SSDs (every modern Mac), overwriting can't guarantee the old data is gone, because the drive spreads writes around (wear leveling). FileVault disk encryption is the real protection — make sure it's on in System Settings → Privacy & Security.")
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundStyle(targeted ? AppModule.shredder.tint : .secondary)
                            .background(RoundedRectangle(cornerRadius: 16).fill(targeted ? AppModule.shredder.tint.opacity(0.08) : .clear))
                        if vm.items.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "scissors").font(.system(size: 44)).foregroundStyle(AppModule.shredder.gradient)
                                Text("Drop files or folders here").font(.title3)
                                Button("Choose…") { vm.add(FolderPicker.choose(filesToo: true)) }
                            }
                        } else {
                            List {
                                ForEach(vm.items, id: \.self) { url in
                                    HStack {
                                        Image(nsImage: SystemLinks.icon(for: url)).resizable().frame(width: 22, height: 22)
                                        Text(url.tildePath).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Button { vm.items.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle") }
                                            .buttonStyle(.borderless)
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                        for provider in providers {
                            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                                if let url { Task { @MainActor in vm.add([url]) } }
                            }
                        }
                        return true
                    }
                    HStack {
                        Button("Add…") { vm.add(FolderPicker.choose(filesToo: true)) }
                        Button("Clear") { vm.items = [] }.disabled(vm.items.isEmpty)
                        Spacer()
                        Button("Shred \(vm.items.count) item(s)") { vm.showConfirmation = true }
                            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                            .disabled(vm.items.isEmpty)
                    }
                }
                .padding(20)
            }
        }
        .alert("Shred permanently?", isPresented: $vm.showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Shred", role: .destructive) { vm.confirmShred() }
        } message: {
            Text("This CANNOT be undone. \(vm.items.count) item(s) (\(vm.totalSize.formattedBytes)) will be overwritten with random data and deleted:\n\n"
                 + vm.items.prefix(15).map(\.tildePath).joined(separator: "\n")
                 + (vm.items.count > 15 ? "\n…and \(vm.items.count - 15) more" : ""))
        }
    }
}
