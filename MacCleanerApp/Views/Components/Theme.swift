import SwiftUI

/// Colors and gradients. Each sidebar group gets its own gradient, like CleanMyMac.
extension AppModule {
    var gradientColors: [Color] {
        switch section {
        case .top: return [Color(red: 0.55, green: 0.30, blue: 0.95), Color(red: 0.95, green: 0.35, blue: 0.65)]
        case .cleanup: return [Color(red: 0.10, green: 0.65, blue: 0.55), Color(red: 0.15, green: 0.45, blue: 0.85)]
        case .protection: return [Color(red: 0.90, green: 0.30, blue: 0.35), Color(red: 0.95, green: 0.55, blue: 0.25)]
        case .speed: return [Color(red: 0.95, green: 0.55, blue: 0.15), Color(red: 0.95, green: 0.30, blue: 0.45)]
        case .applications: return [Color(red: 0.20, green: 0.50, blue: 0.95), Color(red: 0.45, green: 0.30, blue: 0.90)]
        case .files: return [Color(red: 0.25, green: 0.70, blue: 0.95), Color(red: 0.20, green: 0.40, blue: 0.80)]
        case .other: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var tint: Color { gradientColors[0] }
}

/// The big round gradient button used for Scan / Clean / Run.
struct BigActionButton: View {
    var title: String
    var subtitle: String? = nil
    var module: AppModule
    var disabled = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold))
                if let subtitle { Text(subtitle).font(.caption).opacity(0.85) }
            }
            .foregroundStyle(.white)
            .frame(width: 128, height: 128)
            .background(Circle().fill(module.gradient))
            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 2).padding(5))
            .shadow(color: module.tint.opacity(hovering ? 0.55 : 0.3), radius: hovering ? 18 : 10, y: 4)
            .scaleEffect(hovering && !disabled ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3), value: hovering)
    }
}

/// A rounded card background that adapts to light and dark mode.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07)))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// Module icon in a gradient rounded square.
struct ModuleIcon: View {
    var module: AppModule
    var size: CGFloat = 64

    var body: some View {
        Image(systemName: module.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26).fill(module.gradient))
            .shadow(color: module.tint.opacity(0.35), radius: 8, y: 3)
    }
}

/// Title row at the top of every module.
struct ModuleHeader<Trailing: View>: View {
    var module: AppModule
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            ModuleIcon(module: module, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title).font(.title2.bold())
                Text(subtitle ?? module.tagline).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

extension ModuleHeader where Trailing == EmptyView {
    init(module: AppModule, subtitle: String? = nil) {
        self.init(module: module, subtitle: subtitle) { EmptyView() }
    }
}

/// An orange or blue information strip.
struct InfoBanner: View {
    enum Style { case info, warning, danger }
    var style: Style = .info
    var text: String
    var symbol: String? = nil

    var color: Color {
        switch style {
        case .info: return .blue
        case .warning: return .orange
        case .danger: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol ?? (style == .info ? "info.circle.fill" : "exclamationmark.triangle.fill"))
                .foregroundStyle(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)))
    }
}
