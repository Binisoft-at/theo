import SwiftUI

/// Theo's own text size (Settings → Appearance, or ⌘+ / ⌘− / ⌘0 on the Mac). On iPhone and iPad
/// it overrides Dynamic Type unless left on "System"; on the Mac, where SwiftUI's text styles
/// don't grow with Dynamic Type, the lists, rows, headers, sidebar and entry bar scale with it.
enum TextSizeChoice: String, CaseIterable, Identifiable {
    case system, small, standard, large, xLarge, huge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        case .xLarge: "Extra Large"
        case .huge: "Huge"
        }
    }

    /// The Mac's scale for text styles (1 = the system's 13 pt body).
    var macScale: CGFloat {
        switch self {
        case .small: 0.9
        case .system, .standard: 1
        case .large: 1.15
        case .xLarge: 1.3
        case .huge: 1.5
        }
    }

    #if os(iOS)
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: nil
        case .small: .small
        case .standard: .large
        case .large: .xLarge
        case .xLarge: .xxLarge
        case .huge: .xxxLarge
        }
    }
    #endif

    /// The Mac starts one step up: its standard text is small for a task list.
    static var platformDefault: TextSizeChoice {
        #if os(macOS)
        .large
        #else
        .system
        #endif
    }

    static var current: TextSizeChoice {
        UserDefaults.standard.string(forKey: Prefs.textSize).flatMap(TextSizeChoice.init(rawValue:)) ?? platformDefault
    }

    /// ⌘+ / ⌘−: one step bigger or smaller.
    static func step(_ delta: Int) {
        let steps: [TextSizeChoice] = [.small, .standard, .large, .xLarge, .huge]
        let now = steps.firstIndex(of: current == .system ? .standard : current) ?? 1
        let next = steps[min(steps.count - 1, max(0, now + delta))]
        UserDefaults.standard.set(next.rawValue, forKey: Prefs.textSize)
    }

    static func reset() {
        UserDefaults.standard.set(platformDefault.rawValue, forKey: Prefs.textSize)
    }
}

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// How much bigger than standard Theo's text is (the Mac's text size setting).
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

/// A text style that follows Theo's text size on the Mac (and Dynamic Type elsewhere).
private struct TheoFont: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?

    @Environment(\.textScale) private var scale

    func body(content: Content) -> some View {
        #if os(macOS)
        content.font(.system(size: Self.macSize(style) * scale, weight: weight ?? (style == .headline ? .semibold : .regular)))
        #else
        if let weight {
            content.font(.system(style, weight: weight))
        } else {
            content.font(.system(style))
        }
        #endif
    }

    /// The Mac's standard sizes for each text style.
    private static func macSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption: 10
        case .caption2: 10
        default: 13
        }
    }
}

extension View {
    func theoFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(TheoFont(style: style, weight: weight))
    }

    /// Applies the text size setting to everything below.
    func theoTextSize(_ choice: TextSizeChoice) -> some View {
        #if os(macOS)
        environment(\.textScale, choice.macScale)
        #else
        Group {
            if let size = choice.dynamicTypeSize {
                self.dynamicTypeSize(size)
            } else {
                self
            }
        }
        #endif
    }
}
