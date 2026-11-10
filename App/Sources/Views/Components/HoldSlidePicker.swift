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

/// The arc of a pick in progress, over the whole window.
struct RadialPickerOverlay: View {
    let pick: RadialPick

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let layout = pick.layout
            let local = { (point: CGPoint) in CGPoint(x: point.x - origin.x, y: point.y - origin.y) }
            ZStack {
                // Dims the page a little so the options read clearly over it.
                Rectangle()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: geo.size.width, height: geo.size.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                // A faint arc the options sit on, and the line to the one pointed at.
                Path { path in
                    path.addArc(center: local(layout.origin), radius: layout.radius,
                                startAngle: .degrees(-layout.startAngle), endAngle: .degrees(-layout.endAngle), clockwise: false)
                }
                .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 30, lineCap: .round))
                if let selection = pick.selection {
                    Path { path in
                        path.move(to: local(layout.origin))
                        path.addLine(to: local(layout.position(of: selection)))
                    }
                    .stroke(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
                }
                ForEach(pick.options.indices, id: \.self) { index in
                    let isSelected = pick.selection == index
                    Text(pick.options[index])
                        .font(.callout.weight(isSelected ? .bold : .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 34, minHeight: 34)
                        .background(Capsule().fill(isSelected ? Color.accentColor : Color.clear))
                        .glassEffect(.regular, in: .capsule)
                        .scaleEffect(isSelected ? 1.22 : 1)
                        .position(local(layout.position(of: index)))
                }
                // What it will be, in the middle of the arc.
                VStack(spacing: 2) {
                    Text(pick.selection.map { pick.options[$0] } ?? "–")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if !pick.title.isEmpty {
                        Text(pick.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .position(local(CGPoint(
                    x: layout.origin.x + layout.radius * 0.45 * CGFloat(cos((layout.startAngle + layout.endAngle) / 2 * .pi / 180)),
                    y: layout.origin.y - layout.radius * 0.5
                )))
            }
            .animation(.snappy(duration: 0.14), value: pick.selection)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .sensoryFeedback(.selection, trigger: pick.selection)
        .sensoryFeedback(.impact(weight: .light), trigger: pick.id)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}
