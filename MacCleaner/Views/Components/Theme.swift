import SwiftUI

enum Theme {
    static let sidebarWidth: CGFloat = 240

    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.accentColor.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardFill(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.18), color.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct CardBackground: ViewModifier {
    var tint: Color = .accentColor
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(tint.opacity(0.25), lineWidth: 1)
                    )
            )
    }
}

extension View {
    func macCard(_ tint: Color = .accentColor) -> some View {
        modifier(CardBackground(tint: tint))
    }
}

struct FDABanner: View {
    var body: some View {
        if !FullDiskAccess.isGranted() {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full Disk Access is off")
                        .font(.headline)
                    Text("Mail, Safari, TCC, and some Library folders cannot be scanned until you allow MacCleaner in System Settings → Privacy & Security → Full Disk Access.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Full Disk Access") { FullDiskAccess.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
        }
    }
}
