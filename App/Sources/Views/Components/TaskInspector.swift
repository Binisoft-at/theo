import SwiftUI
import SwiftData
import TheoCore

/// The column on the right of the Mac window: the selected task's details, editable in place,
/// with the round quick actions on top, so changing a task never needs a sheet. With several
/// selected, the quick actions for all of them; with none, the day at a glance.
struct TaskInspector: View {
    @Environment(AppModel.self) private var app
    /// Open tasks, plus the ones finished in the last day and a half: all the glance needs,
    /// without fetching every finished task and log ever made.
    @Query private var openTasks: [TaskItem]
    @Query private var recentlyDone: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil })
    private var groups: [TaskGroup]

    init() {
        // Whole hours, so the window redrawing doesn't hand the queries a new date each time.
        let hour = (Date().timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600
        let since = Date(timeIntervalSinceReferenceDate: hour - 36 * 3600)
        let past = Date.distantPast
        _openTasks = Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false })
        _recentlyDone = Query(filter: #Predicate<TaskItem> { task in
            task.deletedAt == nil && task.isDone == true && (task.completedAt ?? past) >= since
        })
    }

    var body: some View {
        let selected = app.selectedTasks
        Group {
            if selected.count == 1, let task = selected.first {
                VStack(spacing: 0) {
                    // Done, Subtask, Ongoing, Focus and Delete one click away; planning is in
                    // the form's own Plan section.
                    TaskQuickActions(tasks: [task], showsDetails: false, showsPlanning: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    Divider()
                    TaskDetailView(task: task, embedded: true)
                }
                .id(task.uuid)
            } else if selected.count > 1 {
                ScrollView {
                    TaskActionPanel(tasks: selected, fillsWidth: true)
                }
            } else {
                glance
            }
        }
    }

    /// Nothing selected: today's numbers and what's coming. The day's title, two figures side
    /// by side (open and done, each with its Power Hours) whose numbers roll as the day goes,
    /// what's overdue, then the deadlines ahead with their dates lined up on the right.
    private var glance: some View {
        let today = app.dayStart
        let live = (openTasks + recentlyDone).activeOnly(groups)
        let planned = live.filter { PageBuilder.isOnToday($0, dayStart: today) }
        let stats = TaskStats(planned, today: today)
        let upcoming = openTasks.activeOnly(groups).filter { $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(8)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(DateText.pageTitle(today))
                    .theoFont(.title3, weight: .bold)
                HStack(spacing: 8) {
                    GlanceFigure(title: "Open today", symbol: "sun.max.fill", tint: Tint.today, value: stats.open,
                                 hours: stats.openHours, detail: "\(PowerHours.number(stats.openHours)) PH left")
                    GlanceFigure(title: "Done", symbol: "checkmark", tint: Tint.done, value: stats.doneToday,
                                 hours: stats.doneTodayHours, detail: PowerHours.format(stats.doneTodayHours))
                }
                if stats.overdue > 0 {
                    // Calm, like the lines themselves: they're at the top of their pages anyway.
                    Label("\(stats.overdue) overdue", systemImage: "clock.arrow.circlepath")
                        .theoFont(.subheadline, weight: .medium)
                        .foregroundStyle(Tint.overdue)
                        .transition(.opacity)
                }
                if !upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Coming Up")
                            .theoFont(.headline)
                            .padding(.bottom, 4)
                        ForEach(Array(upcoming), id: \.uuid) { task in
                            GlanceLine(task: task, today: today) {
                                // Its page, with the row selected and its details here.
                                app.reveal(task)
                            }
                        }
                    }
                }
                Text("Select a task to see and change everything about it here. Right-click a task for quick actions.")
                    .theoFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(Motion.resolved(Motion.list), value: stats.overdue > 0)
        }
    }
}

/// One of the glance's figures: what it counts (its symbol in its colour), the number in large
/// rounded digits that roll when it changes, and its Power Hours underneath.
private struct GlanceFigure: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    let value: Int
    let hours: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
            .theoFont(.caption, weight: .semibold)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Text("\(value)")
                .theoFont(.title2, weight: .bold, design: .rounded)
                .rollingNumber(value)
            Text(detail)
                .theoFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .rollingNumber(hours)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A line under "Coming Up": the title, and its deadline lined up on the right (orange when
/// it's today or has passed). It takes a soft fill under the pointer; a click opens the task's
/// page with the line selected.
private struct GlanceLine: View {
    let task: TaskItem
    let today: Date
    let action: () -> Void

    @State private var isHovered = false

    private var dueColor: Color {
        guard let due = task.dueDate else { return .secondary }
        let delta = DateText.dayDelta(due, today: today)
        if delta < 0 { return Tint.overdue }
        return delta == 0 ? Tint.today : Color.secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.trimmedTitle)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let due = task.dueDate {
                    // The date never shortens; the title gives way first.
                    Text(DateText.due(due, hasTime: task.dueHasTime, today: today))
                        .monospacedDigit()
                        .foregroundStyle(dueColor)
                        .fixedSize()
                }
            }
            .theoFont(.subheadline)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(isHovered ? 0.1 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            Motion.animate(Motion.hover) { isHovered = inside }
        }
        // The fill reaches a little past the column; the text stays in line with the title.
        .padding(.horizontal, -8)
    }
}
