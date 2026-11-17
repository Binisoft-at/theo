import SwiftUI

/// A pick in progress on the circular picker: what's offered, where the control sits and where
/// the finger is (both in global coordinates).
struct RadialPick: Equatable {
    var id = UUID()
    var title: String
    var options: [String]
    var origin: CGPoint
    var location: CGPoint
    /// The visible part of the window when the pick started (above the keyboard).
    var bounds: CGRect
    var selection: Int?

    var layout: RadialLayout { RadialLayout(origin: origin, bounds: bounds, count: options.count) }
}

/// Where the options of a circular pick sit: on an arc above the control, from the left going
/// over the top to the right, cut down to the side with room near a screen edge (a quarter
/// circle next to the send button). Angles in degrees: 0 = right, 90 = up, 180 = left.
struct RadialLayout: Equatable {
    var origin: CGPoint
    var radius: CGFloat
    /// The first option's angle (the left end) and the last one's.
    var startAngle: Double
    var endAngle: Double
    var count: Int

    /// The finger has to move this far from the control before anything is picked.
    static let deadZone: CGFloat = 30

    init(origin: CGPoint, bounds: CGRect, count: Int) {
        let n = max(1, count)
        // Room for half an option's label at the screen edges; next to an edge this goes
        // negative, which tilts the arc's end away from the edge.
        let margin: Double = 44
        let left = Double(origin.x - bounds.minX) - margin
        let right = Double(bounds.maxX - origin.x) - margin
        let up = max(60, Double(origin.y - bounds.minY) - 30)
        var radius = 100.0
        var start = 180.0
        var end = 0.0
        // Grow the arc until neighbouring options are at least 46 points apart, as far as the
        // room above allows.
        while true {
            start = acos(min(1, max(-1, -left / radius))) * 180 / Double.pi
            end = acos(min(1, max(-1, right / radius))) * 180 / Double.pi
            let spacing = (start - end) * Double.pi / 180 * radius / Double(max(1, n - 1))
            if spacing >= 46 || radius + 10 > min(up, 260) { break }
            radius += 10
        }
        self.origin = origin
        self.count = n
        self.radius = CGFloat(radius)
        startAngle = start
        endAngle = end
    }

    func angle(of index: Int) -> Double {
        guard count > 1 else { return (startAngle + endAngle) / 2 }
        return startAngle - (startAngle - endAngle) * Double(index) / Double(count - 1)
    }

    func position(of index: Int) -> CGPoint {
        let radians = angle(of: index) * .pi / 180
        return CGPoint(x: origin.x + radius * CGFloat(cos(radians)), y: origin.y - radius * CGFloat(sin(radians)))
    }

    /// The option the finger points at: the nearest one by direction, once it's past the dead
    /// zone. Pointing well below the control picks nothing.
    func selection(at location: CGPoint) -> Int? {
        let dx = location.x - origin.x
        let dy = origin.y - location.y
        guard (dx * dx + dy * dy).squareRoot() >= Self.deadZone, dy > -24 else { return nil }
        let angle = atan2(Double(dy), Double(dx)) * 180 / .pi
        let clamped = min(startAngle, max(endAngle, angle < -90 ? 180 : angle))
        return (0..<count).min { abs(self.angle(of: $0) - clamped) < abs(self.angle(of: $1) - clamped) }
    }
}

/// Hold, then slide to pick. After a short hold the options fan out on an arc above the control;
/// the finger points at one (a tick per step), and letting go picks it. Letting go next to the
/// control picks nothing; a plain tap still runs `onTap`. The arc is drawn above everything and
/// kept inside the visible area, so the keyboard never covers it.
struct HoldSlidePicker<Label: View>: View {
    /// In order around the arc, from the left end to the right end.
    let options: [String]
    /// Shown in the middle of the arc, e.g. "Power Hours".
    var title = ""
    let onTap: () -> Void
    let onPick: (Int) -> Void
    @ViewBuilder var label: () -> Label

    @Environment(AppModel.self) private var app
    @State private var center: CGPoint = .zero
    @State private var pickID: UUID?

    var body: some View {
        label()
            .contentShape(Rectangle())
            .onGeometryChange(for: CGPoint.self) { proxy in
                let frame = proxy.frame(in: .global)
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { center = $0 }
            .onTapGesture(perform: onTap)
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.18)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        if pickID == nil || app.radialPick?.id != pickID { start() }
                        if let drag { update(drag.location) }
                    }
                    .onEnded { value in
                        let ours = pickID != nil && app.radialPick?.id == pickID
                        let selection = ours ? app.radialPick?.selection : nil
                        if ours { app.radialPick = nil }
                        pickID = nil
                        if case .second(true, _) = value, let selection { onPick(selection) }
                    }
            )
            .onDisappear {
                if pickID != nil, app.radialPick?.id == pickID { app.radialPick = nil }
                pickID = nil
            }
    }

    private func start() {
        let bounds = app.visibleFrame.isEmpty ? CGRect(x: 0, y: 0, width: 400, height: 800) : app.visibleFrame
        let pick = RadialPick(title: title, options: options, origin: center, location: center, bounds: bounds)
        pickID = pick.id
        app.radialPick = pick
    }

    private func update(_ location: CGPoint) {
        guard var pick = app.radialPick, pick.id == pickID else { return }
        pick.location = location
        pick.selection = pick.layout.selection(at: location)
        if pick != app.radialPick { app.radialPick = pick }
    }
}

/// The arc of a pick in progress, over the whole window. The options fan out from the control
/// into a soft channel along the arc; the channel fills in the tint up to the option pointed at,
/// which lights up (a tick for each step), and the value reads in the middle of the arc.
struct RadialPickerOverlay: View {
    let pick: RadialPick
    /// False for the first moment: the options start at the control and spread out along the
    /// arc from there, so it's clear where they come from.
    @State private var fanned = false

    /// The channel the options sit in, a little wider than they are.
    private static let channelWidth: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            arc(offset: geo.frame(in: .global).origin, size: geo.size)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .sensoryFeedback(.selection, trigger: pick.selection)
        .sensoryFeedback(.impact(weight: .light), trigger: fanned) { _, new in new }
        .transition(.opacity)
        .onAppear { fanned = true }
    }

    /// Everything in the overlay's own coordinates (`offset` is its global origin).
    private func arc(offset: CGPoint, size: CGSize) -> some View {
        let layout = pick.layout
        let control = CGPoint(x: layout.origin.x - offset.x, y: layout.origin.y - offset.y)
        return ZStack {
            // Dims the page a little so the options read clearly over it.
            Rectangle()
                .fill(Color.black.opacity(0.16))
                .frame(width: size.width, height: size.height)
                .position(x: size.width / 2, y: size.height / 2)
            track(layout, at: control)
            ForEach(pick.options.indices, id: \.self) { index in
                option(index, layout: layout, offset: offset)
            }
            readout(layout, offset: offset)
        }
        .animation(Motion.resolved(Motion.tap), value: pick.selection)
    }

    /// The channel along the arc, and its part from the first option up to the one pointed at,
    /// filled in the tint: how far up the scale the pick is.
    private func track(_ layout: RadialLayout, at control: CGPoint) -> some View {
        let start = Self.outlineFraction(layout.startAngle)
        let end = Self.outlineFraction(layout.endAngle)
        let reach: CGFloat = pick.selection.map { Self.outlineFraction(layout.angle(of: $0)) } ?? start
        let side: CGFloat = layout.radius * 2
        let stroke = StrokeStyle(lineWidth: Self.channelWidth, lineCap: .round)
        return ZStack {
            Circle()
                .trim(from: start, to: end)
                .stroke(Color.primary.opacity(0.1), style: stroke)
            Circle()
                .trim(from: start, to: reach)
                .stroke(TintShapeStyle.tint.opacity(0.25), style: stroke)
                .opacity(pick.selection == nil ? 0 : 1)
        }
        .frame(width: side, height: side)
        .position(control)
    }

    /// Where an angle of the arc (degrees, counter-clockwise from the right) falls along a
    /// `Circle`'s outline, which starts on the right and runs clockwise on screen.
    private static func outlineFraction(_ angle: Double) -> CGFloat {
        CGFloat((360 - angle) / 360)
    }

    /// One option, flying out from the control to its place on the arc as the pick opens (one
    /// after the other, quickly); with Reduce Motion they fade in where they belong.
    private func option(_ index: Int, layout: RadialLayout, offset: CGPoint) -> some View {
        let spread = fanned || Motion.reduceMotion
        let point = spread ? layout.position(of: index) : layout.origin
        let stagger = Motion.resolved(Motion.tap).delay(Double(index) * 0.015)
        return RadialOptionLabel(text: pick.options[index], isSelected: pick.selection == index)
            .scaleEffect(spread ? 1 : 0.4)
            .opacity(fanned ? 1 : 0)
            .position(x: point.x - offset.x, y: point.y - offset.y)
            .animation(stagger, value: fanned)
    }

    /// The unit under the value, singular for exactly one: "1 Power Hour", "2 Power Hours".
    private static func unit(_ title: String, for value: String) -> String {
        guard value == "1", title.hasSuffix("s") else { return title }
        return String(title.dropLast())
    }

    /// What it will be, in the middle of the arc: the value (a word in full) over what's picked.
    private func readout(_ layout: RadialLayout, offset: CGPoint) -> some View {
        let middle: Double = (layout.startAngle + layout.endAngle) / 2 * Double.pi / 180
        let x: CGFloat = layout.origin.x + layout.radius * 0.45 * CGFloat(cos(middle)) - offset.x
        let y: CGFloat = layout.origin.y - layout.radius * 0.5 - offset.y
        let value: String = pick.selection.map { pick.options[$0] } ?? "–"
        return VStack(spacing: 2) {
            Text(value)
                .theoFont(.title2, weight: .bold, design: .rounded)
                .monospacedDigit()
                .contentTransition(.numericText())
            if !pick.title.isEmpty {
                Text(Self.unit(pick.title, for: value))
                    .theoFont(.caption2, weight: .medium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .position(x: x, y: y)
    }
}

/// One option on the arc: a glass circle (a capsule for longer numbers). The one pointed at fills
/// with the accent and grows a little. A word ("Custom…") would crowd its neighbours, so it shows
/// as … on the arc and reads in full in the middle.
private struct RadialOptionLabel: View {
    let text: String
    let isSelected: Bool

    @Environment(\.self) private var environment
    @AppStorage(Prefs.accent, store: UserDefaults.standard) private var accentRaw = AccentChoice.notes.rawValue

    private var accent: Color { (AccentChoice(rawValue: accentRaw) ?? .notes).color }

    var body: some View {
        let ink: Color = isSelected ? accent.onFillForeground(in: environment) : Color.primary
        return content
            .theoFont(.callout, weight: .semibold, design: .rounded)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(minWidth: 36, minHeight: 36)
            .background {
                Capsule()
                    .fill(accent.opacity(isSelected ? 1 : 0))
            }
            .glassEffect(.regular, in: .capsule)
            .scaleEffect(isSelected ? 1.2 : 1)
    }

    @ViewBuilder
    private var content: some View {
        if text.hasSuffix("…") {
            Image(systemName: "ellipsis")
        } else {
            Text(text)
        }
    }
}
