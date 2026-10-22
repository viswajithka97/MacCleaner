import SwiftUI

struct SpaceLensView: View {
    @State private var phase: ScanPhase = .intro
    @State private var progress = 0.0
    @State private var path = ""
    @State private var root: DiskNode?
    @State private var stack: [DiskNode] = []
    @State private var selected = Set<URL>()
    @State private var folder = FileScanSupport.home()
    @State private var cancelled = false
    @State private var confirm = false
    @State private var summary: CleanupSummary?
    @State private var hoverName = ""

    var current: DiskNode? { stack.last ?? root }

    var body: some View {
        VStack {
            switch phase {
            case .intro:
                VStack(spacing: 16) {
                    IntroPane(module: .spaceLens, onScan: scan)
                    HStack {
                        Text(folder.path).lineLimit(1)
                        Button("Choose folder…") { pickFolder() }
                    }
                    .padding(.bottom, 40)
                }
            case .scanning:
                ScanningPane(module: .spaceLens, progress: progress, path: path, onCancel: { cancelled = true; phase = .intro })
            case .results:
                results
            case .summary:
                if let summary { SummaryPane(summary: summary) { phase = .intro } }
            }
        }
        .background(Theme.background)
        .confirmationDialog("Move selected items to Trash?", isPresented: $confirm) {
            Button("Move to Trash", role: .destructive) { Task { await trashSelected() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(selected.map(\.path).prefix(20).joined(separator: "\n"))
        }
    }

    private var results: some View {
        VStack {
            HStack {
                ForEach(Array(stack.enumerated()), id: \.offset) { index, node in
                    Button(node.name) { stack = Array(stack.prefix(index + 1)) }
                    if index < stack.count - 1 { Text("/") }
                }
                if stack.isEmpty, let root { Text(root.name).bold() }
                Spacer()
                Text(hoverName).foregroundStyle(.secondary)
                Button("Reveal in Finder") {
                    if let url = selected.first { FinderReveal.reveal(url.path) }
                    else if let current { FinderReveal.reveal(current.url.path) }
                }
                Button("Quick Look") {
                    QuickLookPreview.shared.preview(paths: selected.map(\.path))
                }
                Button("Move to Trash (\(selected.count))") { confirm = true }
                    .disabled(selected.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            if let current {
                GeometryReader { geo in
                    BubbleCanvas(node: current, selected: $selected, hoverName: $hoverName) { child in
                        if child.isDirectory { stack.append(child) }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            folder = url
        }
    }

    private func scan() {
        cancelled = false
        phase = .scanning
        Task {
            let callbacks = ScanCallbacks(
                progress: { v, p in Task { @MainActor in progress = v; path = p } },
                isCancelled: { cancelled }
            )
            let node = await SpaceLensService.scan(root: folder, callbacks: callbacks)
            if cancelled { return }
            root = node
            stack = [node]
            phase = .results
        }
    }

    private func trashSelected() async {
        let items = selected.map { CleanableItem(name: $0.lastPathComponent, path: $0.path, size: FileSizing.allocatedSize(at: $0)) }
        let outcome = await DeletionService.remove(items: items, settings: SettingsStore.shared.settings)
        let summary = CleanupSummary(module: .spaceLens, removedCount: outcome.removed, bytesFreed: outcome.bytes, skipped: outcome.skipped, notes: [])
        HistoryStore.shared.append(summary)
        self.summary = summary
        phase = .summary
    }
}

struct BubbleCanvas: View {
    let node: DiskNode
    @Binding var selected: Set<URL>
    @Binding var hoverName: String
    var onDrill: (DiskNode) -> Void

    var body: some View {
        Canvas { context, size in
            let bubbles = layout(node: node, in: CGRect(origin: .zero, size: size))
            for bubble in bubbles {
                let color = Color.accentColor.opacity(0.25 + min(0.5, Double(bubble.node.size) / Double(max(node.size, 1))))
                context.fill(Path(ellipseIn: bubble.rect), with: .color(selected.contains(bubble.node.url) ? Color.red.opacity(0.45) : color))
                context.stroke(Path(ellipseIn: bubble.rect), with: .color(.primary.opacity(0.2)), lineWidth: 1)
                let name = Text(bubble.node.name).font(.caption2)
                context.draw(name, at: CGPoint(x: bubble.rect.midX, y: bubble.rect.midY))
            }
        }
        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
            let bubbles = layout(node: node, in: CGRect(origin: .zero, size: CGSize(width: 800, height: 600)))
            _ = bubbles
        })
        .overlay(BubbleHitView(node: node, selected: $selected, hoverName: $hoverName, onDrill: onDrill))
    }

    struct Bubble { var node: DiskNode; var rect: CGRect }

    func layout(node: DiskNode, in rect: CGRect) -> [Bubble] {
        let children = node.children.filter { $0.size > 0 }
        guard !children.isEmpty else { return [Bubble(node: node, rect: rect.insetBy(dx: 20, dy: 20))] }
        let total = max(children.reduce(0) { $0 + $1.size }, 1)
        var bubbles: [Bubble] = []
        var angle: Double = 0
        let cx = rect.midX
        let cy = rect.midY
        let maxR = min(rect.width, rect.height) / 2 - 8
        for child in children {
            let share = Double(child.size) / Double(total)
            let r = max(18, sqrt(share) * maxR * 0.55)
            let orbit = maxR * 0.55
            let x = cx + Foundation.cos(angle) * orbit - r
            let y = cy + Foundation.sin(angle) * orbit - r
            bubbles.append(Bubble(node: child, rect: CGRect(x: x, y: y, width: r * 2, height: r * 2)))
            angle += share * .pi * 2
        }
        return bubbles
    }
}

struct BubbleHitView: View {
    let node: DiskNode
    @Binding var selected: Set<URL>
    @Binding var hoverName: String
    var onDrill: (DiskNode) -> Void
    var body: some View {
        GeometryReader { geo in
            let layout = BubbleCanvas(node: node, selected: $selected, hoverName: $hoverName, onDrill: onDrill)
                .layout(node: node, in: CGRect(origin: .zero, size: geo.size))
            ZStack {
                ForEach(layout, id: \.node.id) { bubble in
                    Circle()
                        .fill(Color.clear)
                        .frame(width: bubble.rect.width, height: bubble.rect.height)
                        .position(x: bubble.rect.midX, y: bubble.rect.midY)
                        .onHover { inside in
                            if inside { hoverName = "\(bubble.node.name) — \(ByteFormatting.string(bubble.node.size))" }
                        }
                        .onTapGesture(count: 2) { onDrill(bubble.node) }
                        .onTapGesture {
                            if selected.contains(bubble.node.url) { selected.remove(bubble.node.url) }
                            else { selected.insert(bubble.node.url) }
                        }
                        .contextMenu {
                            Button("Reveal in Finder") { FinderReveal.reveal(bubble.node.url.path) }
                            Button("Quick Look") { QuickLookPreview.shared.preview(paths: [bubble.node.url.path]) }
                            Button("Select") { selected.insert(bubble.node.url) }
                        }
                }
            }
        }
    }
}

import AppKit
