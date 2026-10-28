import SwiftUI

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
            .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background {
                Capsule().fill(isOn ? AnyShapeStyle(color) : AnyShapeStyle(Color.secondary.opacity(0.12)))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isOn)
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
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
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
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
