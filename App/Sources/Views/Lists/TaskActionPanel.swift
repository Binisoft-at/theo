import SwiftUI
import SwiftData
import TheoCore

/// Everything you'd change on a task, one tap each, in colour: right-click a task on the Mac
/// (or Quick Edit from the long-press menu on iPhone) and it opens right above the line.
/// Changes apply at once; the panel stays open for the next one. In the Mac inspector (several
/// tasks selected) it fills the column instead.
struct TaskActionPanel: View {
    let tasks: [TaskItem]
    let onClose: () -> Void
    /// Fills the width it's given (the Mac inspector) instead of sizing itself like a popover.
    let fillsWidth: Bool

    @Environment(AppModel.self) private var app
    @Environment(\.self) private var environment
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    /// Counts chip taps, for the iPhone's selection tick.
    @State private var feedbackTick = 0

    init(tasks: [TaskItem], onClose: @escaping () -> Void = {}, fillsWidth: Bool = false) {
        self.tasks = tasks
        self.onClose = onClose
        self.fillsWidth = fillsWidth
    }

    /// The widest the panel gets as a popover.
    private static let maxWidth: CGFloat = 470

    private var single: TaskItem? { tasks.count == 1 ? tasks.first : nil }

    /// What the popover asks for: 470 pt, but never wider than the window (an iPhone is about
    /// 400 pt), so the panel is laid out, and its height measured, at the width it really gets.
    private var popoverWidth: CGFloat {
        #if os(iOS)
        let window = app.visibleFrame.width
        if window > 0 { return min(Self.maxWidth, max(260, window - 40)) }
        #endif
        return Self.maxWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(single.map { $0.trimmedTitle.isEmpty ? "New Task" : $0.trimmedTitle } ?? "\(tasks.count) tasks")
                .font(.headline)
                .lineLimit(2)

            TaskQuickActions(tasks: tasks, showsDetails: true, onClose: onClose)

            row("Priority") {
                ForEach([Priority.normal, .low, .medium, .high]) { level in
                    let on = tasks.allSatisfy { $0.priority == level }
                    chip(level == .normal ? "None" : level.marks, color: level == .normal ? .secondary : level.color, on: on,
                         label: level == .normal ? "No priority" : "\(level.title) priority") {
                        app.store.setPriority(tasks, level)
                    }
                }
            }

            row("Deadline") {
                ForEach(QuickDate.allCases) { quick in
                    let date = quick.date(from: app.dayStart)
                    let on = tasks.allSatisfy { task in task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }
                    chip(quick.title, color: .blue, on: on, label: "Due \(quick.title.lowercased())") {
                        app.store.setDue(tasks, date)
                    }
                }
                chip("None", color: .secondary, on: tasks.allSatisfy { $0.dueDate == nil }, label: "No deadline") {
                    app.store.setDue(tasks, nil)
                }
            }

            row("Power Hours") {
                ForEach([0.25, 0.5, 1.0, 2.0, 4.0], id: \.self) { value in
                    chip(PowerHours.number(value), color: .teal, on: tasks.allSatisfy { abs($0.estimate - value) < 0.001 },
                         label: PowerHours.format(value)) {
                        app.store.setEstimate(tasks, value)
                    }
                }
                chip("None", color: .secondary, on: tasks.allSatisfy { $0.estimate <= 0 }, label: "No estimate") {
                    app.store.setEstimate(tasks, 0)
                }
            }

            row("Move to") {
                chip("Quick Entry", color: .teal, on: tasks.allSatisfy { $0.groupID == nil }) {
                    app.move(tasks, toGroup: nil)
                }
                ForEach(GroupTree.ordered(groups), id: \.group.uuid) { item in
                    chip(item.group.displayName, color: item.group.color.color, on: tasks.allSatisfy { $0.groupID == item.group.uuid }) {
                        app.move(tasks, toGroup: item.group.uuid)
                    }
                }
            }
        }
        .padding(16)
        // A popover asks for its ideal width; the chip rows scroll within what's visible.
        .frame(idealWidth: fillsWidth ? nil : popoverWidth, maxWidth: fillsWidth ? CGFloat.infinity : popoverWidth, alignment: .leading)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: feedbackTick)
        #endif
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    content()
                }
            }
        }
    }

    /// A tinted capsule; filled when it's the task's current value. `label` is what VoiceOver
    /// reads when the title alone says too little ("!!", "0,5").
    private func chip(_ title: String, color: Color, on: Bool, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
            feedbackTick += 1
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(on ? color.onFillForeground(in: environment) : color)
                .background(Capsule().fill(on ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.14))))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The round, coloured one-click actions: Done, Today (Off Plan once it's on today), Tomorrow,
/// Subtask, Ongoing, Focus, Details and Delete. One row when there's room, otherwise rows of
/// four (iPhone, the Mac's narrow inspector). Used by the panel and above the Mac inspector's
/// form for a single selected task.
struct TaskQuickActions: View {
    let tasks: [TaskItem]
    /// Offers Details (not in the inspector, which already shows them).
    let showsDetails: Bool
    /// Offers Today / Off Plan and Tomorrow (the inspector's form has its own Plan section).
    let showsPlanning: Bool
    let onClose: () -> Void

    @Environment(AppModel.self) private var app

    init(tasks: [TaskItem], showsDetails: Bool, showsPlanning: Bool = true, onClose: @escaping () -> Void = {}) {
        self.tasks = tasks
        self.showsDetails = showsDetails
        self.showsPlanning = showsPlanning
        self.onClose = onClose
    }

    private var single: TaskItem? { tasks.count == 1 ? tasks.first : nil }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                buttons(compact: false)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
                buttons(compact: true)
            }
        }
    }

    @ViewBuilder
    private func buttons(compact: Bool) -> some View {
        let done = tasks.allSatisfy(\.isDone)
        big(done ? "Reopen" : "Done", done ? "arrow.uturn.backward" : "checkmark", .green, compact: compact) {
            withAnimation(.snappy) { app.markDone(tasks, !done) }
            onClose()
        }
        if showsPlanning {
            let today = tasks.allSatisfy { $0.isPlanned(for: app.dayStart) }
            if today {
                big("Off Plan", "calendar.badge.minus", .gray, compact: compact) {
                    withAnimation(.snappy) { app.plan(tasks, for: nil) }
                }
            } else {
                big("Today", "sun.max.fill", .orange, compact: compact) {
                    withAnimation(.snappy) { app.plan(tasks, for: app.dayStart) }
                }
            }
            big("Tomorrow", "moon.zzz.fill", .indigo, compact: compact) {
                withAnimation(.snappy) { app.deferToTomorrow(tasks) }
            }
        }
        if let single {
            big("Subtask", "arrow.turn.down.right", .purple, compact: compact) {
                onClose()
                withAnimation(.snappy) { app.addSubtask(to: single) }
            }
        }
        let ongoing = tasks.allSatisfy(\.isOngoing)
        big(ongoing ? "Not Ongoing" : "Ongoing", "infinity", .teal, compact: compact) {
            withAnimation(.snappy) { app.store.setOngoing(tasks, !ongoing) }
        }
        if let single, !single.isDone {
            big("Focus", "scope", .pink, compact: compact) {
                onClose()
                app.startFocus(on: single)
            }
        }
        if showsDetails, let single {
            big("Details", "info.circle.fill", .blue, compact: compact) {
                onClose()
                app.showDetails(single)
            }
        }
        big("Delete", "trash.fill", .red, compact: compact) {
            onClose()
            app.delete(tasks)
        }
    }

    /// A round, coloured action with its name underneath. In the grid the name shrinks a little
    /// rather than pushing the columns apart.
    private func big(_ title: String, _ symbol: String, _ color: Color, compact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(color.gradient))
                    .shadow(color: color.opacity(0.35), radius: 4, y: 2)
                caption(title, compact: compact)
            }
            .frame(minWidth: compact ? nil : 46, maxWidth: compact ? CGFloat.infinity : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func caption(_ title: String, compact: Bool) -> some View {
        let text = Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
        if compact {
            text.minimumScaleFactor(0.75)
        } else {
            text.fixedSize()
        }
    }
}

extension AppModel {
    /// Done / Reopen from the panel, the inspector and the context menu. One task behaves like
    /// its checkbox (with Undo when finishing it reaches beyond the line); several are finished
    /// together with one Undo. Reopening stays silent, like unchecking.
    func markDone(_ tasks: [TaskItem], _ done: Bool) {
        if tasks.count == 1, let task = tasks.first {
            if task.isDone != done { check(task) }
        } else if !done {
            store.setDone(tasks, false)
        } else if tasks.contains(where: { !$0.isDone && !$0.isOngoing }) {
            complete(tasks)
        } else {
            // Only ongoing tasks are left open: each one is logged for today, as its checkbox does.
            store.setDone(tasks.filter(\.isOngoing), true)
        }
    }
}
