import SwiftUI
import SwiftData
import TheoCore

/// Classic Eisenhower layout: urgent on the left, important at the top.
enum MatrixGeometry {
    static func point(urgency: Double, importance: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: (1 - Matrix.clamp(urgency)) * size.width, y: (1 - Matrix.clamp(importance)) * size.height)
    }

    static func position(of point: CGPoint, in size: CGSize) -> (urgency: Double, importance: Double) {
        (Matrix.clamp(1 - point.x / max(size.width, 1)), Matrix.clamp(1 - point.y / max(size.height, 1)))
    }

    /// "Do First · 82" — quadrant and score (0–100).
    static func describe(urgency: Double, importance: Double) -> String {
        let quadrant = Matrix.quadrant(urgency: urgency, importance: importance)
        return "\(quadrant.title) · \(Int((Matrix.score(urgency: urgency, importance: importance) * 100).rounded()))"
    }
}

/// The four quadrants, labelled.
struct MatrixBackground: View {
    var compact = false

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                cell(.doFirst)
                cell(.schedule)
            }
            HStack(spacing: 2) {
                cell(.delegate)
                cell(.later)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 22, style: .continuous))
        .overlay(alignment: .bottom) {
            if !compact {
                Text("← more urgent")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
    }

    private func cell(_ quadrant: Matrix.Quadrant) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(quadrant.color.opacity(0.12))
            VStack(alignment: .leading, spacing: 1) {
                Label(quadrant.title, systemImage: quadrant.symbol)
                    .font((compact ? Font.caption2 : Font.caption).weight(.bold))
                    .foregroundStyle(quadrant.color)
                if !compact {
                    Text(quadrant.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(compact ? 6 : 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A dot on the canvas, with a faint ring where priority and deadline push it.
struct MatrixDot: View {
    let urgency: Double
    let importance: Double
    var effective: (urgency: Double, importance: Double)?
    var title: String?
    var isSelected = false
    let size: CGSize

    var body: some View {
        let point = MatrixGeometry.point(urgency: urgency, importance: importance, in: size)
        let quadrant = Matrix.quadrant(urgency: effective?.urgency ?? urgency, importance: effective?.importance ?? importance)
        ZStack {
            if let effective, abs(effective.urgency - urgency) > 0.01 || abs(effective.importance - importance) > 0.01 {
                let target = MatrixGeometry.point(urgency: effective.urgency, importance: effective.importance, in: size)
                Path { path in
                    path.move(to: point)
                    path.addLine(to: target)
                }
                .stroke(quadrant.color.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                Circle()
                    .strokeBorder(quadrant.color.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .position(target)
            }
            Circle()
                .fill(quadrant.color)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: isSelected ? 3 : 1.5))
                .frame(width: isSelected ? 20 : 14, height: isSelected ? 20 : 14)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .position(point)
            if let title {
                Text(title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 120)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .position(x: min(max(point.x + 50, 60), size.width - 60), y: max(point.y - 14, 10))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Full-screen canvas while a task is dragged from the composer's handle. The drag itself
/// belongs to the handle; this only draws where the task would land.
struct MatrixDropOverlay: View {
    let drag: MatrixDrag
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text(drag.title.isEmpty ? "Drop to set urgency and importance" : drag.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                GeometryReader { geo in
                    let frame = geo.frame(in: .global)
                    let local = CGPoint(x: drag.location.x - frame.minX, y: drag.location.y - frame.minY)
                    let inside = frame.contains(drag.location)
                    let position = MatrixGeometry.position(of: local, in: geo.size)
                    ZStack {
                        MatrixBackground()
                        if inside {
                            Circle()
                                .fill(Matrix.quadrant(urgency: position.urgency, importance: position.importance).color)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                                .shadow(radius: 4)
                                .position(local)
                            Text(MatrixGeometry.describe(urgency: position.urgency, importance: position.importance))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.regularMaterial, in: Capsule())
                                .position(x: min(max(local.x, 70), geo.size.width - 70), y: max(local.y - 34, 14))
                        }
                    }
                    .onAppear { app.matrixCanvasFrame = frame }
                    .onChange(of: frame) { _, newFrame in app.matrixCanvasFrame = newFrame }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 560)
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

/// Places an existing task: tap or drag on the canvas, it saves when you let go.
struct MatrixPlacementOverlay: View {
    let task: TaskItem
    @Environment(AppModel.self) private var app
    @State private var point: CGPoint?

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
                    Text("Tap or drag where it belongs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                GeometryReader { geo in
                    let current = point.map { MatrixGeometry.position(of: $0, in: geo.size) } ?? (urgency: task.urgency, importance: task.importance)
                    ZStack {
                        MatrixBackground()
                        MatrixDot(
                            urgency: current.urgency,
                            importance: current.importance,
                            effective: (urgency: Matrix.effectiveUrgency(current.urgency, due: task.dueDate, today: app.dayStart),
                                        importance: Matrix.effectiveImportance(current.importance, priority: task.priority)),
                            isSelected: true,
                            size: geo.size
                        )
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in point = value.location }
                            .onEnded { value in
                                let position = MatrixGeometry.position(of: value.location, in: geo.size)
                                app.store.setMatrix(task, urgency: position.urgency, importance: position.importance)
                                close()
                            }
                    )
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 560)
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

/// The Matrix page: open tasks as dots you can drag, a strip of tasks to drop in, and the
/// ranked list (highest score first) below.
struct MatrixPageView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false }, sort: \TaskItem.sortOrder)
    private var openTasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @AppStorage("matrixScope") private var onlyToday = true
    @State private var selectedID: UUID?
    @State private var dragging: (id: UUID, point: CGPoint)?

    private var scoped: [TaskItem] {
        onlyToday ? openTasks.filter { $0.isOnPage(of: app.dayStart) } : openTasks
    }

    var body: some View {
        let tasks = scoped
        let ranked = tasks.sorted { $0.matrixScore(today: app.dayStart) > $1.matrixScore(today: app.dayStart) }
        VStack(spacing: 0) {
            canvas(tasks: ranked)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            tray(tasks: ranked)
            TaskListView(
                rows: PageBuilder.labeled(Sections.byMatrix(tasks, today: app.dayStart), options: PageBuilder.Options(style: RowStyle(showGroup: true))),
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

    private func canvas(tasks: [TaskItem]) -> some View {
        GeometryReader { geo in
            ZStack {
                MatrixBackground()
                ForEach(Array(tasks.enumerated()), id: \.element.uuid) { index, task in
                    let isDragging = dragging?.id == task.uuid
                    let raw: (urgency: Double, importance: Double) = isDragging
                        ? MatrixGeometry.position(of: dragging?.point ?? .zero, in: geo.size)
                        : (urgency: task.urgency, importance: task.importance)
                    MatrixDot(
                        urgency: raw.urgency,
                        importance: raw.importance,
                        effective: (urgency: Matrix.effectiveUrgency(raw.urgency, due: task.dueDate, today: app.dayStart),
                                    importance: Matrix.effectiveImportance(raw.importance, priority: task.priority)),
                        title: index < 8 || selectedID == task.uuid || isDragging ? task.trimmedTitle : nil,
                        isSelected: selectedID == task.uuid || isDragging,
                        size: geo.size
                    )
                }
                // One invisible hit target per dot, so dots can be dragged and tapped.
                ForEach(tasks, id: \.uuid) { task in
                    let point = MatrixGeometry.point(urgency: task.urgency, importance: task.importance, in: geo.size)
                    Circle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 34, height: 34)
                        .position(point)
                        .gesture(
                            DragGesture(minimumDistance: 2, coordinateSpace: .named("matrix"))
                                .onChanged { value in dragging = (task.uuid, value.location) }
                                .onEnded { value in
                                    let position = MatrixGeometry.position(of: value.location, in: geo.size)
                                    withAnimation(.snappy) {
                                        app.store.setMatrix(task, urgency: position.urgency, importance: position.importance)
                                    }
                                    dragging = nil
                                    selectedID = task.uuid
                                }
                        )
                        .simultaneousGesture(TapGesture().onEnded { selectedID = selectedID == task.uuid ? nil : task.uuid })
                        .accessibilityElement()
                        .accessibilityLabel(task.trimmedTitle)
                        .accessibilityValue(MatrixGeometry.describe(urgency: task.urgency, importance: task.importance))
                }
            }
            .coordinateSpace(.named("matrix"))
            .contentShape(Rectangle())
            .onTapGesture { location in
                // With a task picked in the strip below, a tap places it.
                guard let id = selectedID, let task = tasks.first(where: { $0.uuid == id }) else { return }
                let position = MatrixGeometry.position(of: location, in: geo.size)
                withAnimation(.snappy) { app.store.setMatrix(task, urgency: position.urgency, importance: position.importance) }
            }
            .dropDestination(for: String.self) { items, location in
                guard let id = items.first.flatMap(UUID.init(uuidString:)), let task = app.store.task(id: id) else { return false }
                let position = MatrixGeometry.position(of: location, in: geo.size)
                withAnimation(.snappy) { app.store.setMatrix(task, urgency: position.urgency, importance: position.importance) }
                selectedID = id
                return true
            }
        }
        .aspectRatio(1.25, contentMode: .fit)
        .frame(maxWidth: 640, maxHeight: 360)
    }

    /// Tasks to pick (tap, then tap the matrix) or drag onto the matrix.
    private func tray(tasks: [TaskItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tasks.prefix(40), id: \.uuid) { task in
                    let quadrant = Matrix.quadrant(urgency: task.matrixPosition(today: app.dayStart).urgency, importance: task.matrixPosition(today: app.dayStart).importance)
                    Button {
                        selectedID = selectedID == task.uuid ? nil : task.uuid
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(quadrant.color).frame(width: 7, height: 7)
                            Text(task.trimmedTitle)
                                .lineLimit(1)
                                .frame(maxWidth: 160)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selectedID == task.uuid ? quadrant.color.opacity(0.25) : Color.secondary.opacity(0.12)))
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
