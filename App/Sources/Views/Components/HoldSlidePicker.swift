import SwiftUI

/// Hold, then slide to pick. After a short hold the options pop up right above the control;
/// sliding the finger up walks through them (a tick per step) and letting go picks the one
/// under the finger. Letting go without sliding picks nothing. A plain tap still runs `onTap`.
struct HoldSlidePicker<Label: View>: View {
    /// Bottom to top: the first option sits closest to the finger.
    let options: [String]
    var step: CGFloat = 32
    let onTap: () -> Void
    let onPick: (Int) -> Void
    @ViewBuilder var label: () -> Label

    @State private var isActive = false
    @State private var index: Int?

    var body: some View {
        label()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.18)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        isActive = true
                        if let drag { index = pick(drag.translation.height) }
                    }
                    .onEnded { value in
                        if case .second(true, _) = value, let index { onPick(index) }
                        isActive = false
                        index = nil
                    }
            )
            .overlay(alignment: .top) {
                if isActive {
                    strip
                        .fixedSize()
                        .alignmentGuide(.top) { $0[.bottom] + 10 }
                        .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.16), value: isActive)
            .sensoryFeedback(.selection, trigger: index)
            .sensoryFeedback(.impact(weight: .light), trigger: isActive) { _, new in new }
    }

    private func pick(_ translation: CGFloat) -> Int? {
        let travelled = -translation - 8
        guard travelled >= 0 else { return nil }
        return min(Int(travelled / step), options.count - 1)
    }

    private var strip: some View {
        VStack(spacing: 0) {
            ForEach(options.indices.reversed(), id: \.self) { option in
                Text(options[option])
                    .font(.callout.weight(option == index ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(option == index ? Color.white : Color.primary)
                    .frame(minWidth: 60)
                    .frame(height: step - 4)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(option == index ? Color.accentColor : Color.clear))
                    .frame(height: step)
            }
        }
        .padding(6)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .allowsHitTesting(false)
    }
}
