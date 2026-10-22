import SwiftUI

struct SpaceLensView: View {
    @ObservedObject var vm: SpaceLensViewModel
    @State private var hovered: UUID?
    @State private var previewURL: URL?

    var body: some View {
        Group {
            if vm.isBusy {
                ScanningView(module: .spaceLens, title: vm.root == nil ? "Building the map…" : "Removing…",
                             snapshot: vm.snapshot, onCancel: vm.cancelTask)
            } else if let current = vm.current {
                map(current)
            } else {
                ModuleIntroView(module: .spaceLens, buttonTitle: "Scan Home", onStart: { vm.scan(URL.home()) }) {
                    HStack {
                        Button("Choose Folder…") { if let url = FolderPicker.choose(multiple: false).first { vm.scan(url) } }
                        Menu("Scan a Drive") {
                            ForEach(vm.volumes, id: \.self) { volume in
                                Button(volume.path == "/" ? "Startup Disk" : volume.lastPathComponent) { vm.scan(volume) }
                            }
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $vm.showConfirmation) {
            ConfirmationSheet(title: "Remove \(vm.selectedNodes.count) item(s)?",
                              items: vm.selectedNodes.map { CleanItem(name: $0.name, url: $0.url, size: $0.size, action: .remove($0.url)) },
                              onConfirm: vm.confirmRemove, onCancel: { vm.showConfirmation = false })
        }
    }

    private func map(_ current: SpaceNode) -> some View {
        VStack(spacing: 0) {
            // Breadcrumbs
            HStack(spacing: 4) {
                ForEach(Array(vm.path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    Button(node.name) { vm.current = node }
                        .buttonStyle(.borderless)
                        .fontWeight(node === current ? .bold : .regular)
                }
                Spacer()
                Text(current.size.formattedBytes).font(.headline.monospacedDigit())
                Button("New Scan") { vm.root = nil; vm.current = nil }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            if let result = vm.result, !result.failures.isEmpty || result.removedCount > 0 {
                InfoBanner(text: "Removed \(result.removedCount) item(s), freed \(result.freedBytes.formattedBytes)." +
                           (result.failures.isEmpty ? "" : " \(result.failures.count) couldn't be removed: \(result.failures.first?.reason ?? "")"))
                    .padding(.horizontal, 16)
            }
            HSplitView {
                BubbleMap(node: current, selected: vm.selected, hovered: $hovered,
                          onOpen: { vm.open($0) }, onToggle: { vm.toggleSelection($0) }, onPreview: { previewURL = $0 })
                    .frame(minWidth: 420)
                sideList(current).frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            }
        }
    }

    private func sideList(_ current: SpaceNode) -> some View {
        VStack(spacing: 0) {
            List(current.children) { child in
                HStack {
                    Toggle("", isOn: Binding(get: { vm.selected.contains(child.url) }, set: { _ in vm.toggleSelection(child) }))
                        .toggleStyle(.checkbox).labelsHidden().disabled(child.isAggregate)
                    Image(systemName: child.isAggregate ? "ellipsis.circle" : (child.isDirectory ? "folder.fill" : "doc.fill"))
                        .foregroundStyle(child.isDirectory ? Color.accentColor : .secondary)
                    Text(child.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(child.size.formattedBytes).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .background(hovered == child.id ? Color.accentColor.opacity(0.12) : .clear)
                .onTapGesture(count: 2) { vm.open(child) }
                .contextMenu { nodeMenu(child) }
            }
            Divider()
            HStack {
                Text("\(vm.selected.count) selected · \(vm.selectedSize.formattedBytes)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Remove") { vm.showConfirmation = true }
                    .buttonStyle(.borderedProminent).tint(AppModule.spaceLens.tint)
                    .disabled(vm.selected.isEmpty)
            }
            .padding(10)
        }
    }

    @ViewBuilder private func nodeMenu(_ node: SpaceNode) -> some View {
        if !node.isAggregate {
            if node.canDrillDown { Button("Open") { vm.open(node) } }
            Button(vm.selected.contains(node.url) ? "Deselect" : "Select") { vm.toggleSelection(node) }
            Button("Reveal in Finder") { SystemLinks.reveal(node.url) }
            Button("Quick Look") { previewURL = node.url }
        }
    }
}

/// Interactive bubble chart: bubble area is proportional to size.
private struct BubbleMap: View {
    var node: SpaceNode
    var selected: Set<URL>
    @Binding var hovered: UUID?
    var onOpen: (SpaceNode) -> Void
    var onToggle: (SpaceNode) -> Void
    var onPreview: (URL) -> Void

    var body: some View {
        GeometryReader { geo in
            let children = Array(node.children.filter { $0.size > 0 }.prefix(40))
            let layout = BubbleLayout.pack(sizes: children.map { Double($0.size) }, in: geo.size)
            ZStack {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    if index < layout.count {
                        bubble(child, index: index, circle: layout[index])
                    }
                }
                if let id = hovered, let child = children.first(where: { $0.id == id }) {
                    VStack {
                        Spacer()
                        Text("\(child.name) — \(child.size.formattedBytes)")
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                            .padding(10)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: node.id)
        }
        .padding(8)
    }

    private func bubble(_ child: SpaceNode, index: Int, circle: BubbleLayout.Circle) -> some View {
        let isSelected = selected.contains(child.url)
        let palette = AppModule.spaceLens.gradientColors
        let hue = Double(index % 8) / 8.0
        return ZStack {
            Circle()
                .fill(LinearGradient(colors: child.isDirectory
                                     ? [Color(hue: 0.55 + hue * 0.2, saturation: 0.6, brightness: 0.9), palette[1]]
                                     : [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(hovered == child.id ? 1 : 0.85)
            Circle().stroke(isSelected ? Color.orange : Color.white.opacity(0.4), lineWidth: isSelected ? 4 : 1)
            if circle.r > 28 {
                VStack(spacing: 1) {
                    Text(child.name).font(.system(size: max(9, min(14, circle.r / 5)), weight: .semibold)).lineLimit(1)
                    Text(child.size.formattedBytes).font(.system(size: max(8, min(12, circle.r / 6))))
                }
                .foregroundStyle(.white)
                .padding(4)
                .frame(width: circle.r * 1.6)
            }
        }
        .frame(width: circle.r * 2, height: circle.r * 2)
        .position(x: circle.x, y: circle.y)
        .onHover { inside in hovered = inside ? child.id : (hovered == child.id ? nil : hovered) }
        .onTapGesture { if child.canDrillDown { onOpen(child) } else { onToggle(child) } }
        .contextMenu {
            if !child.isAggregate {
                if child.canDrillDown { Button("Open") { onOpen(child) } }
                Button(isSelected ? "Deselect" : "Select for Removal") { onToggle(child) }
                Button("Reveal in Finder") { SystemLinks.reveal(child.url) }
                Button("Quick Look") { onPreview(child.url) }
            }
        }
        .help("\(child.name) — \(child.size.formattedBytes)")
    }
}

/// Simple greedy circle packing: biggest first, each new circle goes to the free
/// spot closest to the centre. Fast enough for the ~40 bubbles we show.
enum BubbleLayout {
    struct Circle { var x: Double; var y: Double; var r: Double }

    static func pack(sizes: [Double], in size: CGSize) -> [Circle] {
        guard !sizes.isEmpty, let maxSize = sizes.max(), maxSize > 0 else { return [] }
        let radii = sizes.map { max(4, sqrt($0 / maxSize) * 100) }
        var placed: [Circle] = []
        for r in radii {
            if placed.isEmpty { placed.append(Circle(x: 0, y: 0, r: r)); continue }
            var best: Circle?
            var bestDistance = Double.greatestFiniteMagnitude
            for anchor in placed {
                for step in 0..<36 {
                    let angle = Double(step) / 36 * 2 * .pi
                    let d = anchor.r + r + 2
                    let candidate = Circle(x: anchor.x + cos(angle) * d, y: anchor.y + sin(angle) * d, r: r)
                    let distance = hypot(candidate.x, candidate.y)
                    guard distance < bestDistance else { continue }
                    if placed.allSatisfy({ hypot($0.x - candidate.x, $0.y - candidate.y) >= $0.r + r + 1.5 }) {
                        best = candidate
                        bestDistance = distance
                    }
                }
            }
            placed.append(best ?? Circle(x: 0, y: 0, r: r))
        }
        // Scale and centre into the available area.
        let minX = placed.map { $0.x - $0.r }.min()!, maxX = placed.map { $0.x + $0.r }.max()!
        let minY = placed.map { $0.y - $0.r }.min()!, maxY = placed.map { $0.y + $0.r }.max()!
        let scale = min(Double(size.width) / (maxX - minX), Double(size.height) / (maxY - minY)) * 0.96
        let offsetX = Double(size.width) / 2 - (minX + maxX) / 2 * scale
        let offsetY = Double(size.height) / 2 - (minY + maxY) / 2 * scale
        return placed.map { Circle(x: $0.x * scale + offsetX, y: $0.y * scale + offsetY, r: $0.r * scale) }
    }
}
