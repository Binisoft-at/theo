import Foundation
import SwiftUI
import TheoCore

/// The round checkbox, Notes-style: hollow ring when open, filled with a check when done.
/// The ring picks up the priority color.
struct CheckCircle: View {
    let done: Bool
    let priority: Priority
    var size: CGFloat = 22
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if done {
                    Circle().fill(.tint)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(priority == .normal ? Color.secondary.opacity(0.6) : priority.color, lineWidth: 1.6)
                }
            }
            .frame(width: size, height: size)
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(done ? "Mark as not done" : "Mark as done")
        .sensoryFeedback(.success, trigger: done) { old, new in new && !old }
    }
}

/// Priority in one control: tap steps through none → ! → !! → !!!, touch and hold (or the menu
/// arrow on Mac) picks a level directly.
struct PriorityButton: View {
    let priority: Priority
    let onChange: (Priority) -> Void

    var body: some View {
        Menu {
            ForEach(Priority.allCases.reversed()) { level in
                Button {
                    onChange(level)
                } label: {
                    if level == priority {
                        Label(level.title, systemImage: "checkmark")
                    } else {
                        Label(level.title, systemImage: level.symbol)
                    }
                }
            }
        } label: {
            if priority == .normal {
                Image(systemName: "exclamationmark")
            } else {
                Text(priority.marks)
                    .fontWeight(.heavy)
                    .foregroundStyle(priority.color)
            }
        } primaryAction: {
            onChange(priority.next)
        }
        .accessibilityLabel("Priority")
        .accessibilityValue(priority.title)
        .accessibilityHint("Tap to raise, touch and hold to choose")
    }
}

/// A small ring used in the Today header.
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(progress, 1)))
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
        }
    }
}

struct TagChip: View {
    let tag: String
    var compact = true

    var body: some View {
        Text("#" + tag)
            .theoFont(compact ? .caption : .subheadline, weight: .medium)
            .foregroundStyle(TheoColor.forTag(tag).color)
    }
}

/// Selectable capsule used for filters and quick picks.
struct ChipButton: View {
    let title: String
    var symbol: String?
    var color: Color = .accentColor
    let isOn: Bool
    let action: () -> Void

    @Environment(\.self) private var environment
    @AppStorage(Prefs.accent) private var accentRaw = AccentChoice.notes.rawValue

    init(title: String, symbol: String? = nil, color: Color = .accentColor, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.color = color
        self.isOn = isOn
        self.action = action
    }

    /// The chosen accent itself when the chip uses the accent, so the text colour can be
    /// picked for the colour that's really shown.
    private var fill: Color {
        color == .accentColor ? (AccentChoice(rawValue: accentRaw) ?? .notes).color : color
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title)
            }
            .theoFont(.subheadline, weight: .medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? fill.onFillForeground(in: environment) : Color.primary)
            .background {
                Capsule().fill(isOn ? AnyShapeStyle(fill) : AnyShapeStyle(Color.secondary.opacity(0.12)))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.snappy(duration: 0.2), value: isOn)
    }
}

extension Color {
    /// Text on a fill of this colour: near-black on bright fills (Notes Yellow, yellow), white
    /// on the others. White on Notes Yellow has about 2:1 contrast, too faint for small text.
    /// Uses the WCAG relative luminance of the colour as it's shown here (light or dark mode,
    /// and the page behind a see-through fill).
    func onFillForeground(in environment: EnvironmentValues) -> Color {
        let resolved = resolve(in: environment)
        let alpha = min(max(Double(resolved.opacity), 0), 1)
        let page: Double = environment.colorScheme == .dark ? 0 : 1
        func linear(_ component: Float) -> Double {
            let shown = min(max(Double(component) * alpha + page * (1 - alpha), 0), 1)
            return shown <= 0.04045 ? shown / 12.92 : pow((shown + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(resolved.red) + 0.7152 * linear(resolved.green) + 0.0722 * linear(resolved.blue)
        return luminance > 0.45 ? Color.black.opacity(0.85) : Color.white
    }
}

/// Floating toast with optional Undo, in Liquid Glass.
struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .foregroundStyle(.tint)
            Text(toast.message)
                .theoFont(.subheadline, weight: .medium)
                .lineLimit(1)
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    dismiss()
                }
                .theoFont(.subheadline, weight: .semibold)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

/// Empty-state block used inside lists.
struct EmptyHint: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(.tint)
            Text(title).theoFont(.headline)
            Text(message)
                .theoFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
