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
                    .font(.caption2.weight(.medium))
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
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
            }
        }
    }
}

/// A task on the grid.
struct MatrixDot: View {
    let point: CGPoint
    let color: Color
    var title: String?
    var isSelected = false
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .overlay(Circle().strokeBorder(.white.opacity(0.95), lineWidth: isSelected ? 3 : 1.5))
                .frame(width: isSelected ? size + 8 : size, height: isSelected ? size + 8 : size)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .position(point)
            if let title {
                Text(title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 130)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .position(x: point.x, y: max(point.y - 18, 10))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Full-screen grid while a task is dragged from the composer's handle. The drag belongs to
/// the handle; this shows where it would land, snapping cell by cell.
struct MatrixDropOverlay: View {
    let drag: MatrixDrag
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text(drag.title.isEmpty ? "Drop to set when it's due and how important it is" : drag.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                MatrixBoard { size in
                    GeometryReader { geo in
                        let frame = geo.frame(in: .global)
                        let inside = frame.contains(drag.location)
                        let cell = MatrixGeometry.cell(at: CGPoint(x: drag.location.x - frame.minX, y: drag.location.y - frame.minY), in: size)
                        ZStack {
                            if inside {
                                let center = MatrixGeometry.center(of: cell, in: size)
                                MatrixDot(point: center, color: Color.accentColor, isSelected: true, size: 18)
                                    .animation(.spring(response: 0.2, dampingFraction: 0.65), value: cell.key)
                                Text(MatrixGeometry.describe(cell))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial, in: Capsule())
                                    .position(x: min(max(center.x, 80), size.width - 80), y: max(center.y - 36, 14))
                                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: cell.key)
                            }
                        }
                        .sensoryFeedback(.selection, trigger: inside ? cell.key : -1)
                        .onAppear { app.matrixCanvasFrame = frame }
                        .onChange(of: frame) { _, newFrame in app.matrixCanvasFrame = newFrame }
                    }
                }
                .aspectRatio(1.1, contentMode: .fit)
                .frame(maxWidth: 620)
                Text("Let go outside to cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

/// Places an existing task: touch, slide to the right cell, let go.
struct MatrixPlacementOverlay: View {
    let task: TaskItem
    @Environment(AppModel.self) private var app
    @State private var cell: MatrixGeometry.Cell?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(task.trimmedTitle.isEmpty ? "Task" : task.trimmedTitle)
                        .font(.headline)
                        .lineLimit(2)
                    Text(MatrixGeometry.describe(cell ?? MatrixGeometry.cell(of: task, today: app.dayStart)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .multilineTextAlignment(.center)
                MatrixBoard { size in
                    let current = cell ?? MatrixGeometry.cell(of: task, today: app.dayStart)
                    MatrixDot(point: MatrixGeometry.center(of: current, in: size), color: Color.accentColor, isSelected: true, size: 18)
                        .animation(.spring(response: 0.2, dampingFraction: 0.65), value: current.key)
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in cell = MatrixGeometry.cell(at: value.location, in: size) }
                                .onEnded { value in
                                    let target = MatrixGeometry.cell(at: value.location, in: size)
                                    withAnimation(.snappy) {
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
        withAnimation(.snappy) { app.matrixTask = nil }
    }
}

/// The Matrix page: every task on the grid (drag a dot to move it, or drop a task from the
/// strip), and below it the list in rank order.
struct MatrixPageView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false }, sort: \TaskItem.sortOrder)
    private var openTasks: [TaskItem]
    @AppStorage("matrixScope") private var onlyToday = false
    @State private var selectedID: UUID?
    @State private var dragging: (id: UUID, cell: MatrixGeometry.Cell)?

    private var scoped: [TaskItem] {
        onlyToday ? openTasks.filter { $0.isOnPage(of: app.dayStart) } : openTasks
    }

    var body: some View {
        let tasks = scoped.sorted { $0.matrixScore(today: app.dayStart) > $1.matrixScore(today: app.dayStart) }
        VStack(spacing: 0) {
            grid(tasks: tasks)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            tray(tasks: tasks)
            TaskListView(
                rows: PageBuilder.rankedRows(tasks, options: PageBuilder.Options(style: RowStyle(showGroup: true), rankDay: app.dayStart)),
                allowsReorder: false
            )
        }
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

    private func grid(tasks: [TaskItem]) -> some View {
        MatrixBoard { size in
            // Tasks sharing a cell fan out a little so each stays visible.
            let cells = Dictionary(grouping: tasks.indices, by: { MatrixGeometry.cell(of: tasks[$0], today: app.dayStart).key })
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // With a task picked in the strip, a tap places it.
                    guard let id = selectedID, let task = tasks.first(where: { $0.uuid == id }) else { return }
                    let target = MatrixGeometry.cell(at: location, in: size)
                    withAnimation(.snappy) { app.store.placeOnMatrix(task, days: target.days, level: target.level, today: app.dayStart) }
                }
                .dropDestination(for: String.self) { items, location in
                    guard let id = items.first.flatMap(UUID.init(uuidString:)), let task = app.store.task(id: id) else { return false }
                    let target = MatrixGeometry.cell(at: location, in: size)
                    withAnimation(.snappy) { app.store.placeOnMatrix(task, days: target.days, level: target.level, today: app.dayStart) }
                    selectedID = id
                    return true
                }
            ForEach(Array(tasks.enumerated()), id: \.element.uuid) { index, task in
                let isDragging = dragging?.id == task.uuid
                let cell = isDragging ? (dragging?.cell ?? MatrixGeometry.cell(of: task, today: app.dayStart)) : MatrixGeometry.cell(of: task, today: app.dayStart)
                let siblings = cells[cell.key] ?? []
                let slot = siblings.firstIndex(of: index) ?? 0
                let base = MatrixGeometry.center(of: cell, in: size)
                let point = isDragging ? base : CGPoint(x: base.x + CGFloat(slot % 3 - 1) * 5, y: base.y + CGFloat(slot / 3) * 5)
                MatrixDot(
                    point: point,
                    color: Matrix.color(forScore: task.matrixScore(today: app.dayStart)),
                    title: index < 5 || selectedID == task.uuid || isDragging ? task.trimmedTitle : nil,
                    isSelected: selectedID == task.uuid || isDragging
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: cell.key)
                Circle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: 30, height: 30)
                    .position(point)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in dragging = (task.uuid, MatrixGeometry.cell(at: value.location, in: size)) }
                            .onEnded { value in
                                let target = MatrixGeometry.cell(at: value.location, in: size)
                                withAnimation(.snappy) {
                                    app.store.placeOnMatrix(task, days: target.days, level: target.level, today: app.dayStart)
                                }
                                dragging = nil
                                selectedID = task.uuid
                            }
                    )
                    .simultaneousGesture(TapGesture().onEnded { selectedID = selectedID == task.uuid ? nil : task.uuid })
                    .accessibilityElement()
                    .accessibilityLabel(task.trimmedTitle)
                    .accessibilityValue(MatrixGeometry.describe(cell))
            }
        }
        .sensoryFeedback(.selection, trigger: dragging?.cell.key)
        .aspectRatio(1.3, contentMode: .fit)
        .frame(maxWidth: 680, maxHeight: 380)
    }

    /// Tasks to pick (tap, then tap the grid) or drag onto the grid.
    private func tray(tasks: [TaskItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tasks.prefix(40), id: \.uuid) { task in
                    Button {
                        selectedID = selectedID == task.uuid ? nil : task.uuid
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Matrix.color(forScore: task.matrixScore(today: app.dayStart)))
                                .frame(width: 7, height: 7)
                            Text(task.trimmedTitle)
                                .lineLimit(1)
                                .frame(maxWidth: 160)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selectedID == task.uuid ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .draggable(task.uuid.uuidString)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
