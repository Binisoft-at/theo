import SwiftUI
import SwiftData
import TheoCore

/// The grid: one column per day from today (left) to 14 days out, then "no date"; ten
/// importance rows, most important on top. Positions snap to cells.
enum MatrixGeometry {
    struct Cell: Equatable {
        var column: Int
        var level: Int

        var days: Int? { Matrix.days(forColumn: column) }
        var key: Int { column * 100 + level }
    }

    /// A dot under a finger snaps from cell to cell with this quick spring, the one curve of
    /// its own on the grid: it follows the finger, so it has to keep up. Everything that moves
    /// for any other reason uses `Motion`.
    static let follow: Animation = .spring(response: 0.2, dampingFraction: 0.7)

    /// Appearing or leaving in its own spot: a dot or a bubble grows out of the cell it belongs
    /// to (and shrinks back into it), instead of flying in from the middle of the grid.
    @MainActor
    static func pop(at point: CGPoint, in size: CGSize) -> AnyTransition {
        let anchor = UnitPoint(x: point.x / max(size.width, 1), y: point.y / max(size.height, 1))
        return AnyTransition.scale(scale: 0.4, anchor: anchor).combined(with: .opacity)
    }

    static func cell(at point: CGPoint, in size: CGSize) -> Cell {
        let width = max(size.width, 1) / CGFloat(Matrix.columns)
        let height = max(size.height, 1) / CGFloat(Matrix.levels)
        let column = min(Matrix.columns - 1, max(0, Int(point.x / width)))
        let level = min(Matrix.levels, max(1, Matrix.levels - Int(point.y / height)))
        return Cell(column: column, level: level)
    }

    static func center(of cell: Cell, in size: CGSize) -> CGPoint {
        let width = size.width / CGFloat(Matrix.columns)
        let height = size.height / CGFloat(Matrix.levels)
        return CGPoint(x: (CGFloat(cell.column) + 0.5) * width, y: (CGFloat(Matrix.levels - cell.level) + 0.5) * height)
    }

    static func cell(of task: TaskItem, today: Date) -> Cell {
        let days = task.isDone ? nil : Matrix.daysUntil(task.dueDate, today: today)
        return Cell(column: Matrix.column(forDays: days), level: task.importanceLevel)
    }

    static func dayLabel(_ days: Int?) -> String {
        switch days {
        case nil: "No date"
        case 0?: "Today"
        case 1?: "Tomorrow"
        case let days?: "In \(days) days"
        }
    }

    /// "Tomorrow · importance 7".
    static func describe(_ cell: Cell) -> String {
        "\(dayLabel(cell.days)) · importance \(cell.level)"
    }
}

/// The heat-shaded grid, with axis labels around it.
struct MatrixBoard<Content: View>: View {
    var compact = false
    /// Drawn on top of the grid, in the grid's own coordinates.
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if !compact {
                    VStack {
                        Text("10")
                        Spacer()
                        Text("Importance")
                            .rotationEffect(.degrees(-90))
                            .fixedSize()
                        Spacer()
                        Text("1")
                    }
                    .theoFont(.caption2, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                }
                GeometryReader { geo in
                    ZStack {
                        Canvas { context, size in
                            let width = size.width / CGFloat(Matrix.columns)
                            let height = size.height / CGFloat(Matrix.levels)
                            for column in 0..<Matrix.columns {
                                let urgency = Matrix.urgency(daysUntilDue: Matrix.days(forColumn: column))
                                let noDate = column > Matrix.horizonDays
                                for level in 1...Matrix.levels {
                                    let score = Matrix.score(importance: Matrix.importance(forLevel: level), urgency: urgency)
                                    let rect = CGRect(
                                        x: CGFloat(column) * width + (noDate ? 3 : 0),
                                        y: CGFloat(Matrix.levels - level) * height,
                                        width: width - (noDate ? 3 : 0),
                                        height: height
                                    ).insetBy(dx: 0.6, dy: 0.6)
                                    context.fill(
                                        Path(roundedRect: rect, cornerRadius: 3),
                                        with: .color(Matrix.color(forScore: score).opacity(noDate ? 0.12 : 0.28))
                                    )
                                }
                            }
                        }
                        content(geo.size)
                    }
                }
            }
            if !compact {
                HStack {
                    Text("Today")
                    Spacer()
                    Text("1 week")
                    Spacer()
                    Text("2 weeks")
                    Spacer()
                    Text("No date")
                }
                .theoFont(.caption2, weight: .medium)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
            }
        }
    }
}

/// A task on the grid. Picked (or dragged), it grows and lifts on a thicker white ring; under
/// the pointer it grows a little, so it's clear what a click takes.
struct MatrixDot: View {
    let point: CGPoint
    let color: Color
    var isSelected = false
    var size: CGFloat = 14
    /// The pointer is over it (Mac, iPad with a pointer).
    var isHovered = false

    var body: some View {
        let side: CGFloat = isSelected ? size + 8 : size
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(.white.opacity(0.95), lineWidth: isSelected ? 3 : 1.5))
            .frame(width: side, height: side)
            .scaleEffect(isHovered && !isSelected ? 1.25 : 1)
            .shadow(color: .black.opacity(isSelected ? 0.24 : 0.18), radius: isSelected ? 4 : 2, y: 1)
            .animation(Motion.resolved(Motion.tap), value: isSelected)
            .animation(Motion.resolved(Motion.hover), value: isHovered)
            .position(point)
            .allowsHitTesting(false)
    }
}

/// A task's title beside its dot. Drawn above every dot so no dot covers a title.
struct MatrixLabel: View {
    let point: CGPoint
    let title: String
    var isSelected = false
    var dotSize: CGFloat = 14
    var onRight = true

    var body: some View {
        let gap = (isSelected ? dotSize + 8 : dotSize) / 2 + 4
        Text(title)
            .theoFont(.caption2, weight: isSelected ? .bold : .medium)
            .lineLimit(1)
            .frame(maxWidth: 130)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: Capsule())
            .frame(width: 144, alignment: onRight ? .leading : .trailing)
            .position(x: onRight ? point.x + gap + 72 : point.x - gap - 72, y: point.y)
            .allowsHitTesting(false)
    }
}

/// Full-screen grid while a task is dragged from the composer's handle. The drag belongs to
/// the handle; this shows where it would land, snapping cell by cell.
struct MatrixDropOverlay: View {
    let drag: MatrixDrag
    @Environment(AppModel.self) private var app
    // The app's own defaults, also inside the tour (its practice page has a store of its own).
    @AppStorage(Prefs.accent, store: UserDefaults.standard) private var accentRaw = AccentChoice.notes.rawValue

    /// The chosen accent, like every other picked thing on the grid and in its strip.
    private var accent: Color { (AccentChoice(rawValue: accentRaw) ?? .notes).color }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text(drag.title.isEmpty ? "Drop to set when it's due and how important it is" : drag.title)
                    .theoFont(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                MatrixBoard { size in
                    GeometryReader { geo in
                        let frame = geo.frame(in: .global)
                        let inside = frame.contains(drag.location)
                        let cell = MatrixGeometry.cell(at: CGPoint(x: drag.location.x - frame.minX, y: drag.location.y - frame.minY), in: size)
                        landingSpot(cell, size: size, inside: inside)
                            .sensoryFeedback(.selection, trigger: inside ? cell.key : -1)
                            .onAppear { app.matrixCanvasFrame = frame }
                            .onChange(of: frame) { _, newFrame in app.matrixCanvasFrame = newFrame }
                    }
                }
                .aspectRatio(1.1, contentMode: .fit)
                .frame(maxWidth: 620)
                Text("Let go outside to cancel")
                    .theoFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    /// Where the task would land, following the finger cell by cell: the dot and a caption
    /// saying when it's due and how important it is. Both fade out when the finger leaves the
    /// grid and back in when it returns.
    private func landingSpot(_ cell: MatrixGeometry.Cell, size: CGSize, inside: Bool) -> some View {
        let center = MatrixGeometry.center(of: cell, in: size)
        let snap = Motion.resolved(MatrixGeometry.follow)
        return ZStack {
            if inside {
                MatrixDot(point: center, color: accent, isSelected: true, size: 18)
                    .animation(snap, value: cell.key)
                    .transition(MatrixGeometry.pop(at: center, in: size))
                Text(MatrixGeometry.describe(cell))
                    .theoFont(.caption, weight: .semibold)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .position(x: min(max(center.x, 80), size.width - 80), y: max(center.y - 36, 14))
                    .animation(snap, value: cell.key)
                    .transition(.opacity)
            }
        }
        .animation(Motion.resolved(Motion.hover), value: inside)
    }
}

/// Places an existing task: touch, slide to the right cell, let go.
struct MatrixPlacementOverlay: View {
    let task: TaskItem
    @Environment(AppModel.self) private var app
    // The app's own defaults, also inside the tour (its practice page has a store of its own).
    @AppStorage(Prefs.accent, store: UserDefaults.standard) private var accentRaw = AccentChoice.notes.rawValue
    @State private var cell: MatrixGeometry.Cell?

    /// The chosen accent, like every other picked thing on the grid and in its strip.
    private var accent: Color { (AccentChoice(rawValue: accentRaw) ?? .notes).color }

    var body: some View {
        let current = cell ?? MatrixGeometry.cell(of: task, today: app.dayStart)
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(task.trimmedTitle.isEmpty ? "Task" : task.trimmedTitle)
                        .theoFont(.headline)
                        .lineLimit(2)
                    Text(MatrixGeometry.describe(current))
                        .theoFont(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(Motion.resolved(Motion.tap), value: current.key)
                }
                .multilineTextAlignment(.center)
                MatrixBoard { size in
                    MatrixDot(point: MatrixGeometry.center(of: current, in: size), color: accent, isSelected: true, size: 18)
                        .animation(Motion.resolved(MatrixGeometry.follow), value: current.key)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in cell = MatrixGeometry.cell(at: value.location, in: size) }
                                .onEnded { value in
                                    let target = MatrixGeometry.cell(at: value.location, in: size)
                                    Motion.animate(Motion.list) {
                                        app.store.placeOnMatrix(task, days: target.days, level: target.level, today: app.dayStart)
                                    }
                                    close()
                                }
                        )
                }
                .sensoryFeedback(.selection, trigger: cell?.key)
                .aspectRatio(1.1, contentMode: .fit)
                .frame(maxWidth: 620)
                Button("Cancel") { close() }
                    .buttonStyle(.glass)
            }
            .padding(20)
        }
        .transition(.opacity)
    }

    private func close() {
        Motion.animate(Motion.layout) { app.matrixTask = nil }
    }
}

/// The Matrix page: every task on the grid (drag a dot to move it, or drop a task from the
/// strip), and below it the list in rank order. On the Mac, hovering a dot names it and a
/// click shows it in the details column; on iPhone a second tap on a picked dot opens it.
struct MatrixPageView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false }, sort: \TaskItem.sortOrder)
    private var allOpen: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil })
    private var groups: [TaskGroup]
    @AppStorage("matrixScope") private var onlyToday = false
    @State private var selectedID: UUID?
    @State private var dragging: (id: UUID, cell: MatrixGeometry.Cell)?
    /// The dot under the pointer (Mac, iPad with a pointer): its title shows beside it.
    @State private var hoveredID: UUID?
    /// A crowded spot that was tapped: its tasks, to pick one.
    @State private var cluster: MatrixCluster?

    private var scoped: [TaskItem] {
        let openTasks = allOpen.activeOnly(groups)
        return onlyToday ? openTasks.filter { $0.isOnPage(of: app.dayStart) } : openTasks
    }

    var body: some View {
        let tasks = scoped.sorted { $0.matrixScore(today: app.dayStart) > $1.matrixScore(today: app.dayStart) }
        let rows = PageBuilder.rankedRows(tasks, options: PageBuilder.Options(style: RowStyle(showGroup: true), rankDay: app.dayStart))
        VStack(spacing: 0) {
            grid(tasks: tasks, listed: Set(rows.map(\.id)))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            tray(tasks: tasks)
            TaskListView(
                rows: rows,
                allowsReorder: false
            )
        }
        #if os(macOS)
        .onChange(of: app.selectedRowIDs) { _, ids in
            // Another row picked in the list below lets go of the picked dot, so a click on
            // the grid never moves a task that isn't the selected one any more.
            if let id = selectedID, let task = allOpen.first(where: { $0.uuid == id }), !ids.contains(task.rowID) {
                Motion.animate(Motion.tap) { selectedID = nil }
            }
        }
        #endif
        .navigationTitle("Matrix")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Show", selection: $onlyToday) {
                    Text("Today").tag(true)
                    Text("All Open").tag(false)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    /// `listed`: the row IDs of the ranked list below the grid.
    private func grid(tasks: [TaskItem], listed: Set<String>) -> some View {
        MatrixBoard { size in
            let points = restingPoints(tasks, size: size)
            // Three or more tasks in one cell become one bubble with a count (the picked or
            // dragged task stays a dot of its own).
            let crowded = crowdedCells(tasks)
            let active = Set([selectedID, dragging?.id].compactMap { $0 })
            let hidden = Set(crowded.values.flatMap { $0 }.map(\.uuid)).subtracting(active)
            let sides = labelSides(tasks, points: points, size: size, skipping: hidden)
            let shown = Array(tasks.enumerated()).filter { !hidden.contains($0.element.uuid) }
            placementSurface(tasks: tasks, size: size)
            ForEach(crowded.keys.sorted(), id: \.self) { key in
                if let members = crowded[key], let first = members.first {
                    clusterBubble(key: key, members: members, first: first, active: active, size: size)
                }
            }
            ForEach(shown, id: \.element.uuid) { index, task in
                dot(task, point: shownPoint(task, resting: points[index], size: size), size: size, listed: listed)
            }
            ForEach(shown, id: \.element.uuid) { index, task in
                let isActive = selectedID == task.uuid || dragging?.id == task.uuid
                let isHovered = hoveredID == task.uuid
                let point = shownPoint(task, resting: points[index], size: size)
                // Picked, dragged and hovered tasks always show their title; the others only
                // when it fits.
                let side: Bool? = isActive || isHovered ? (sides[task.uuid] ?? (point.x < size.width * 0.55)) : sides[task.uuid]
                if let onRight = side {
                    MatrixLabel(point: point, title: Self.title(of: task), isSelected: isActive, onRight: onRight)
                        .animation(motion(for: task), value: shownCell(task).key)
                        .transition(.opacity)
                        .zIndex(isActive || isHovered ? 1 : 0)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: dragging?.cell.key)
        .animation(Motion.resolved(Motion.list), value: onlyToday)
        .aspectRatio(1.3, contentMode: .fit)
        .frame(maxWidth: 680, maxHeight: 380)
        .sheet(item: $cluster) { cluster in
            clusterSheet(cluster, tasks: tasks, listed: listed)
        }
    }

    /// The grid itself: with a task picked in the strip a tap places it, and a task from the
    /// strip can be dropped on it. Either way the dot glides to its new cell.
    private func placementSurface(tasks: [TaskItem], size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { location in
                // With a task picked in the strip, a tap places it.
                guard let id = selectedID, let task = tasks.first(where: { $0.uuid == id }) else { return }
                let target = MatrixGeometry.cell(at: location, in: size)
                Motion.animate(Motion.list) { app.store.placeOnMatrix(task, days: target.days, level: target.level, today: app.dayStart) }
            }
            .dropDestination(for: String.self) { items, location in
                guard let id = items.first.flatMap(UUID.init(uuidString:)), let task = app.store.task(id: id) else { return false }
                let target = MatrixGeometry.cell(at: location, in: size)
                Motion.animate(Motion.list) { app.store.placeOnMatrix(task, days: target.days, level: target.level, today: app.dayStart) }
                Motion.animate(Motion.tap) { selectedID = id }
                return true
            }
    }

    /// A crowded spot: one bubble with how many tasks it holds, ringed in the heat of its most
    /// pressing one. A tap lists them to pick from.
    private func clusterBubble(key: Int, members: [TaskItem], first: TaskItem, active: Set<UUID>, size: CGSize) -> some View {
        let cell = MatrixGeometry.cell(of: first, today: app.dayStart)
        let center = MatrixGeometry.center(of: cell, in: size)
        let best = members.map { $0.matrixScore(today: app.dayStart) }.max() ?? 0
        let others = members.filter { !active.contains($0.uuid) }
        return MatrixClusterBubble(count: others.count, color: Matrix.color(forScore: best))
            #if os(macOS)
            .help(Self.clusterHelp(others))
            #endif
            .position(center)
            .onTapGesture {
                cluster = MatrixCluster(id: key, cell: cell, taskIDs: members.map(\.uuid))
            }
            .accessibilityLabel("\(members.count) tasks, \(MatrixGeometry.describe(cell))")
            .accessibilityAddTraits(.isButton)
            .transition(MatrixGeometry.pop(at: center, in: size))
    }

    /// One task's dot, and the larger, invisible circle on top of it that the finger or the
    /// pointer grabs.
    @ViewBuilder
    private func dot(_ task: TaskItem, point: CGPoint, size: CGSize, listed: Set<String>) -> some View {
        let cell = shownCell(task)
        let isActive = selectedID == task.uuid || dragging?.id == task.uuid
        MatrixDot(
            point: point,
            color: Matrix.color(forScore: task.matrixScore(today: app.dayStart)),
            isSelected: isActive,
            isHovered: hoveredID == task.uuid
        )
        .animation(motion(for: task), value: cell.key)
        .transition(MatrixGeometry.pop(at: point, in: size))
        Circle()
            .fill(Color.white.opacity(0.001))
            .frame(width: 30, height: 30)
            #if os(macOS)
            .help(Self.title(of: task) + " · " + MatrixGeometry.describe(cell))
            #endif
            .onHover { inside in
                hover(task, inside)
            }
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        follow(task, to: MatrixGeometry.cell(at: value.location, in: size))
                    }
                    .onEnded { value in
                        let target = MatrixGeometry.cell(at: value.location, in: size)
                        Motion.animate(Motion.list) {
                            app.store.placeOnMatrix(task, days: target.days, level: target.level, today: app.dayStart)
                        }
                        dragging = nil
                        selectedID = task.uuid
                    }
            )
            .simultaneousGesture(TapGesture().onEnded { tapDot(task, listed: listed) })
            .accessibilityElement()
            .accessibilityLabel(task.trimmedTitle)
            .accessibilityValue(MatrixGeometry.describe(cell))
    }

    /// The dot under a finger keeps up with it (a quick spring, cell by cell); a dot that moves
    /// for any other reason (placed with a tap, dropped from the strip, ranked anew) glides.
    private func motion(for task: TaskItem) -> Animation {
        Motion.resolved(dragging?.id == task.uuid ? MatrixGeometry.follow : Motion.list)
    }

    /// A dot under the finger: picked up, it grows and its title fades in (instead of popping);
    /// from then on it follows the finger cell by cell.
    private func follow(_ task: TaskItem, to cell: MatrixGeometry.Cell) {
        if dragging == nil {
            Motion.animate(Motion.tap) { dragging = (task.uuid, cell) }
        } else {
            dragging = (task.uuid, cell)
        }
    }

    /// The pointer over a dot names it, with a quick fade.
    private func hover(_ task: TaskItem, _ inside: Bool) {
        Motion.animate(Motion.hover) {
            if inside {
                hoveredID = task.uuid
            } else if hoveredID == task.uuid {
                hoveredID = nil
            }
        }
    }

    /// The tasks of a crowded spot, to pick one.
    private func clusterSheet(_ cluster: MatrixCluster, tasks: [TaskItem], listed: Set<String>) -> some View {
        NavigationStack {
            List(tasks.filter { cluster.taskIDs.contains($0.uuid) }, id: \.uuid) { task in
                Button {
                    Motion.animate(Motion.tap) { selectedID = task.uuid }
                    self.cluster = nil
                    #if os(macOS)
                    showOnMac(task, listed: listed)
                    #endif
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.title(of: task))
                            .foregroundStyle(.primary)
                        TaskMetaLine(task: task, style: RowStyle(showGroup: true), today: app.dayStart, showAge: false)
                    }
                }
            }
            .navigationTitle(MatrixGeometry.describe(cluster.cell))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { self.cluster = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// A dot was tapped (not dragged). Mac: picks it and shows it in the details column, with
    /// its row selected in the list below; clicking it again lets go. (A dot picked by a drag
    /// or in the strip isn't shown yet, so a click shows it.) iPhone and iPad: the first tap
    /// picks it (bigger, titled), a second tap opens its details.
    private func tapDot(_ task: TaskItem, listed: Set<String>) {
        #if os(macOS)
        if selectedID == task.uuid && app.selectedRowIDs.contains(task.rowID) {
            Motion.animate(Motion.tap) { selectedID = nil }
            if app.selectedRowIDs == [task.rowID] { app.selectedRowIDs = [] }
        } else {
            Motion.animate(Motion.tap) { selectedID = task.uuid }
            showOnMac(task, listed: listed)
        }
        #else
        if selectedID == task.uuid {
            // Let go too, so a later tap on the grid doesn't move it by surprise.
            Motion.animate(Motion.tap) { selectedID = nil }
            app.showDetails(task)
        } else {
            Motion.animate(Motion.tap) { selectedID = task.uuid }
        }
        #endif
    }

    /// The details column shows the task: selected in the ranked list below when it's there,
    /// otherwise on a page that lists it.
    private func showOnMac(_ task: TaskItem, listed: Set<String>) {
        if listed.contains(task.rowID) {
            app.showDetails(task)
        } else {
            app.reveal(task)
        }
    }

    private static func title(of task: TaskItem) -> String {
        task.trimmedTitle.isEmpty ? "New Task" : task.trimmedTitle
    }

    /// A crowded spot's tooltip: the titles in it, highest ranked first.
    private static func clusterHelp(_ members: [TaskItem]) -> String {
        let shown = members.prefix(8).map { title(of: $0) }
        let more = members.count > shown.count ? ", and \(members.count - shown.count) more" : ""
        return shown.joined(separator: ", ") + more
    }

    /// Cells holding three or more tasks.
    private func crowdedCells(_ tasks: [TaskItem]) -> [Int: [TaskItem]] {
        Dictionary(grouping: tasks) { MatrixGeometry.cell(of: $0, today: app.dayStart).key }.filter { $0.value.count >= 3 }
    }

    /// The cell a task shows in: where it's being dragged, else where it ranks.
    private func shownCell(_ task: TaskItem) -> MatrixGeometry.Cell {
        if let dragging, dragging.id == task.uuid { return dragging.cell }
        return MatrixGeometry.cell(of: task, today: app.dayStart)
    }

    private func shownPoint(_ task: TaskItem, resting: CGPoint, size: CGSize) -> CGPoint {
        if let dragging, dragging.id == task.uuid { return MatrixGeometry.center(of: dragging.cell, in: size) }
        return resting
    }

    /// Where each dot sits; tasks sharing a cell fan out a little so each stays visible.
    private func restingPoints(_ tasks: [TaskItem], size: CGSize) -> [CGPoint] {
        let cells = Dictionary(grouping: tasks.indices, by: { MatrixGeometry.cell(of: tasks[$0], today: app.dayStart).key })
        return tasks.indices.map { index in
            let cell = MatrixGeometry.cell(of: tasks[index], today: app.dayStart)
            let slot = cells[cell.key]?.firstIndex(of: index) ?? 0
            let base = MatrixGeometry.center(of: cell, in: size)
            return CGPoint(x: base.x + CGFloat(slot % 3 - 1) * 5, y: base.y + CGFloat(slot / 3) * 5)
        }
    }

    /// Up to five of the top-ranked tasks get their title beside the dot, on whichever side fits
    /// inside the grid without covering another title or another task's dot. Higher-ranked tasks
    /// pick first; a title that fits nowhere is left out. The value is true for the right side.
    private func labelSides(_ tasks: [TaskItem], points: [CGPoint], size: CGSize, skipping hidden: Set<UUID> = []) -> [UUID: Bool] {
        var placed: [CGRect] = []
        var sides: [UUID: Bool] = [:]
        for (index, task) in tasks.enumerated().prefix(16) where sides.count < 5 && !hidden.contains(task.uuid) {
            let point = points[index]
            let width = min(142, CGFloat(task.trimmedTitle.count) * 6 + 12)
            let preferRight = point.x < size.width * 0.55
            for onRight in [preferRight, !preferRight] {
                let rect = CGRect(x: onRight ? point.x + 11 : point.x - 11 - width, y: point.y - 9, width: width, height: 18)
                guard rect.minX >= 0, rect.maxX <= size.width else { continue }
                let coversTitle = placed.contains { $0.intersects(rect.insetBy(dx: -2, dy: -1)) }
                // Dots fanned out in the same cell (a few points away) don't count.
                let coversDot = points.contains { other in
                    abs(other.x - point.x) + abs(other.y - point.y) > 12
                        && rect.intersects(CGRect(x: other.x - 7, y: other.y - 7, width: 14, height: 14))
                }
                guard !coversTitle, !coversDot else { continue }
                placed.append(rect)
                sides[task.uuid] = onRight
                break
            }
        }
        return sides
    }

    /// Tasks to pick (tap, then tap the grid) or drag onto the grid.
    private func tray(tasks: [TaskItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tasks.prefix(40), id: \.uuid) { task in
                    trayChip(task)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    /// A task in the strip: its heat as a small dot (ringed like the dots on the grid) and its
    /// title. Picked, it's washed and outlined in the accent, like the dot it stands for.
    private func trayChip(_ task: TaskItem) -> some View {
        let isPicked: Bool = selectedID == task.uuid
        return Button {
            Motion.animate(Motion.tap) { selectedID = isPicked ? nil : task.uuid }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(Matrix.color(forScore: task.matrixScore(today: app.dayStart)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                    .frame(width: 8, height: 8)
                Text(Self.title(of: task))
                    .lineLimit(1)
                    .frame(maxWidth: 160)
            }
            .theoFont(.caption, weight: isPicked ? .semibold : .medium)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                trayChipFill(isPicked)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .draggable(task.uuid.uuidString)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    @ViewBuilder
    private func trayChipFill(_ isPicked: Bool) -> some View {
        ZStack {
            Capsule()
                .fill(Color.secondary.opacity(0.12))
            Capsule()
                .fill(.tint)
                .opacity(isPicked ? 0.2 : 0)
            Capsule()
                .strokeBorder(.tint, lineWidth: 1.5)
                .opacity(isPicked ? 1 : 0)
        }
    }
}

/// A crowded spot on the grid, tapped open.
struct MatrixCluster: Identifiable {
    let id: Int
    let cell: MatrixGeometry.Cell
    let taskIDs: [UUID]
}

/// Several tasks in one cell: one bubble with their number, readable on any cell. The number
/// sits in rounded figures on the page's own background, ringed in the heat of the spot, so it
/// reads apart from the single dots and rolls when the count changes.
struct MatrixClusterBubble: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .theoFont(.caption, weight: .bold, design: .rounded)
            .foregroundStyle(.primary)
            .rollingNumber(count)
            .frame(width: 28, height: 28)
            .background(Circle().fill(.background))
            .overlay(Circle().strokeBorder(color, lineWidth: 3))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            .contentShape(Circle())
    }
}
