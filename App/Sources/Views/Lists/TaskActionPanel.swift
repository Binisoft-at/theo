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

    #if os(iOS)
    /// Room around each chip that still counts as the chip, so it's easy to hit on iPhone
    /// without looking bigger.
    private static let chipMargin: CGFloat = 8
    #else
    private static let chipMargin: CGFloat = 2
    #endif

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
            title
            TaskQuickActions(tasks: tasks, showsDetails: true, onClose: onClose)
            // The chips carry their own margin, so the rows sit closer to keep the same rhythm.
            VStack(alignment: .leading, spacing: 14 - Self.chipMargin) {
                priorityRow
                deadlineRow
                powerHoursRow
                moveRow
            }
        }
        .padding(16)
        // A popover asks for its ideal width; the chip rows scroll within what's visible.
        .frame(idealWidth: fillsWidth ? nil : popoverWidth, maxWidth: fillsWidth ? CGFloat.infinity : popoverWidth, alignment: .leading)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: feedbackTick)
        #endif
    }

    /// The task's title, or how many are selected (the count rolls as the selection grows).
    @ViewBuilder private var title: some View {
        if let single {
            Text(single.trimmedTitle.isEmpty ? "New Task" : single.trimmedTitle)
                .theoFont(.headline)
                .lineLimit(2)
        } else {
            Text("\(tasks.count) tasks")
                .theoFont(.headline)
                .rollingNumber(tasks.count)
        }
    }

    // MARK: - Rows

    private var priorityRow: some View {
        row("Priority", symbol: "exclamationmark", color: Tint.priority) {
            ForEach([Priority.normal, .low, .medium, .high]) { level in
                let on = tasks.allSatisfy { $0.priority == level }
                let none = level == .normal
                let color: Color = none ? Color.secondary : level.color
                let label: String = none ? "No priority" : level.title + " priority"
                // The marks keep their colour, as on the line.
                chip(none ? "None" : level.marks, color: color, on: on, label: label, keepsColor: !none) {
                    app.store.setPriority(tasks, level)
                }
            }
        }
    }

    private var deadlineRow: some View {
        row("Deadline", symbol: "calendar", color: Tint.deadline) {
            ForEach(QuickDate.allCases) { quick in
                let date = quick.date(from: app.dayStart)
                chip(quick.title, color: Tint.deadline, on: allDue(on: date), label: "Due \(quick.title.lowercased())") {
                    app.store.setDue(tasks, date)
                }
            }
            chip("None", color: .secondary, on: tasks.allSatisfy { $0.dueDate == nil }, label: "No deadline") {
                app.store.setDue(tasks, nil)
            }
        }
    }

    private var powerHoursRow: some View {
        row("Power Hours", symbol: "timer", color: Tint.powerHours) {
            ForEach([0.25, 0.5, 1.0, 2.0, 4.0], id: \.self) { value in
                chip(PowerHours.number(value), color: Tint.powerHours, on: tasks.allSatisfy { abs($0.estimate - value) < 0.001 },
                     label: PowerHours.format(value)) {
                    app.store.setEstimate(tasks, value)
                }
            }
            chip("None", color: .secondary, on: tasks.allSatisfy { $0.estimate <= 0 }, label: "No estimate") {
                app.store.setEstimate(tasks, 0)
            }
        }
    }

    /// Each group's colour on its icon; the names stay calm until one is picked.
    private var moveRow: some View {
        row("Move to", symbol: "folder", color: Tint.move) {
            chip("Quick Entry", symbol: "tray.and.arrow.down.fill", color: .teal, on: tasks.allSatisfy { $0.groupID == nil }) {
                app.move(tasks, toGroup: nil)
            }
            ForEach(GroupTree.ordered(groups), id: \.group.uuid) { item in
                chip(item.group.displayName, symbol: item.group.symbol, color: item.group.color.color,
                     on: tasks.allSatisfy { $0.groupID == item.group.uuid }) {
                    app.move(tasks, toGroup: item.group.uuid)
                }
            }
        }
    }

    /// Every task is due on that day.
    private func allDue(on date: Date) -> Bool {
        tasks.allSatisfy { task in task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }
    }

    /// A row of chips under a small label whose symbol says, in its colour, what they set.
    private func row<Content: View>(_ title: String, symbol: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: max(0, 8 - Self.chipMargin)) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(title)
            }
            .theoFont(.caption, weight: .semibold)
            .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    content()
                }
            }
            .scrollClipDisabled()
        }
    }

    /// One value of a row (see `QuickActionPanelChip`). `label` is what VoiceOver reads when the
    /// title alone says too little ("!!", "0,5").
    private func chip(_ title: String, symbol: String? = nil, color: Color, on: Bool, label: String? = nil,
                      keepsColor: Bool = false, action: @escaping () -> Void) -> some View {
        QuickActionPanelChip(title: title, symbol: symbol, color: color, on: on, keepsColor: keepsColor,
                             margin: Self.chipMargin) {
            Motion.animate(Motion.list) { action() }
            feedbackTick += 1
        }
        .accessibilityLabel(label ?? title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A capsule for one value in the panel, filled in its colour when it's the current one.
/// Otherwise it stays calm (the row's symbol says what it sets), except priority marks, which
/// keep their colour; under the Mac's pointer its fill deepens a little. `margin`: room above
/// and below that still counts as the chip.
private struct QuickActionPanelChip: View {
    let title: String
    let symbol: String?
    let color: Color
    let on: Bool
    let keepsColor: Bool
    let margin: CGFloat
    let action: () -> Void

    @Environment(\.self) private var environment
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            face
                .padding(.vertical, margin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }

    private var face: some View {
        let text: Color = on ? color.onFillForeground(in: environment) : (keepsColor ? color : Color.primary)
        let fill: AnyShapeStyle = on ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.secondary.opacity(hovering ? 0.2 : 0.12))
        return HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(on ? text : color)
            }
            Text(title)
                .foregroundStyle(text)
        }
        .theoFont(.caption, weight: .semibold)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(fill))
        .animation(Motion.resolved(Motion.tap), value: on)
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
    /// Counts the picks that keep the panel open (plan, ongoing), for the iPhone's tick.
    @State private var pickTick = 0

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
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: pickTick)
        #endif
    }

    /// Each button stays in its place when it turns into its opposite (Done and Reopen, Today
    /// and Off Plan, Ongoing and Not Ongoing), so its symbol morphs instead of popping.
    @ViewBuilder
    private func buttons(compact: Bool) -> some View {
        let done = tasks.allSatisfy(\.isDone)
        QuickActionRoundButton(title: done ? "Reopen" : "Done", symbol: done ? "arrow.uturn.backward" : "checkmark",
                               color: Tint.done, compact: compact) {
            Motion.animate(Motion.list) { app.markDone(tasks, !done) }
            onClose()
        }
        if showsPlanning {
            let today = tasks.allSatisfy { $0.isPlanned(for: app.dayStart) }
            QuickActionRoundButton(title: today ? "Off Plan" : "Today", symbol: today ? "calendar.badge.minus" : "sun.max.fill",
                                   color: today ? Tint.offPlan : Tint.today, compact: compact) {
                pickTick += 1
                Motion.animate(Motion.list) { app.plan(tasks, for: today ? nil : app.dayStart) }
            }
            QuickActionRoundButton(title: "Tomorrow", symbol: "moon.zzz.fill", color: Tint.tomorrow, compact: compact) {
                pickTick += 1
                Motion.animate(Motion.list) { app.deferToTomorrow(tasks) }
            }
        }
        if let single {
            QuickActionRoundButton(title: "Subtask", symbol: "arrow.turn.down.right", color: .gray, compact: compact) {
                onClose()
                Motion.animate(Motion.list) { app.addSubtask(to: single) }
            }
        }
        let ongoing = tasks.allSatisfy(\.isOngoing)
        QuickActionRoundButton(title: ongoing ? "Not Ongoing" : "Ongoing", symbol: ongoing ? "infinity.circle" : "infinity",
                               color: Tint.ongoing, compact: compact) {
            pickTick += 1
            Motion.animate(Motion.list) { app.store.setOngoing(tasks, !ongoing) }
        }
        if let single, !single.isDone {
            QuickActionRoundButton(title: "Focus", symbol: "scope", color: .pink, compact: compact) {
                onClose()
                app.startFocus(on: single)
            }
        }
        if showsDetails, let single {
            QuickActionRoundButton(title: "Details", symbol: "info.circle", color: .gray, compact: compact) {
                onClose()
                app.showDetails(single)
            }
        }
        QuickActionRoundButton(title: "Delete", symbol: "trash.fill", color: Tint.delete, compact: compact) {
            onClose()
            Motion.animate(Motion.list) { app.delete(tasks) }
        }
    }
}

/// A round, coloured action with its name underneath, like the selection bar's. It gives way
/// under the finger, lights up a little under the Mac's pointer, and its symbol morphs when the
/// action turns into its opposite. In the grid the name shrinks a little rather than pushing
/// the columns apart.
private struct QuickActionRoundButton: View {
    let title: String
    let symbol: String
    let color: Color
    let compact: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(color.gradient))
                    .brightness(hovering ? 0.06 : 0)
                caption
            }
            .frame(minWidth: compact ? nil : 46, maxWidth: compact ? CGFloat.infinity : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var caption: some View {
        let text = Text(title)
            .theoFont(.caption2, weight: .medium)
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
