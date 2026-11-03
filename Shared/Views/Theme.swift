import SwiftUI

/// Platform actions the shared views can trigger (open History, open Settings, quit).
struct AppActions {
    /// Opens Insights; with a section, jumps straight to it.
    var showInsights: (InsightsSection?) -> Void = { _ in }
    func showHistory() { showInsights(nil) }
    var showSettings: () -> Void = {}
    var quit: (() -> Void)? = nil
}

extension EnvironmentValues {
    @Entry var appActions = AppActions()
}

extension AppearanceMode {
    /// nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension Color {
    /// Solid black or white. `Color.primary` fills get vibrancy on glass and turn grey; ink stays crisp.
    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white : .black }
}

enum Pill {
    #if os(macOS)
    static let height: CGFloat = 30
    #else
    static let height: CGFloat = 44
    #endif
    static let spacing: CGFloat = 10
    static let morph = Animation.spring(duration: 0.4, bounce: 0.25)
}

/// A floating Liquid Glass capsule. Prominent pills are tinted with the label color,
/// so they read as solid black in light mode and solid white in dark mode.
struct PillStyle: ViewModifier {
    var prominent = false
    var square = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .font(.body.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : 14)
            .frame(minWidth: Pill.height, minHeight: Pill.height, maxHeight: Pill.height)
            .foregroundStyle(prominent ? (scheme == .dark ? Color.black : Color.white) : Color.primary)
            .contentShape(.capsule)
            .glassEffect(prominent ? .regular.tint(.primary).interactive() : .regular.interactive(), in: .capsule)
    }
}

extension View {
    func pill(prominent: Bool = false, square: Bool = false) -> some View {
        modifier(PillStyle(prominent: prominent, square: square))
    }
}
