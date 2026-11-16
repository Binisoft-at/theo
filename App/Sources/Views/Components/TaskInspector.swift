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
                        .padding(.vertical, 10)
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

    /// Nothing selected: today's numbers and what's coming.
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
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(stats.open) open today · \(PowerHours.number(stats.openHours)) PH left", systemImage: "sun.max")
                    Label("\(stats.doneToday) done · \(PowerHours.format(stats.doneTodayHours))", systemImage: "checkmark.circle")
                    if stats.overdue > 0 {
                        Label("\(stats.overdue) overdue", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
                .theoFont(.subheadline)
                if !upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Coming Up")
                            .theoFont(.headline)
                        ForEach(Array(upcoming), id: \.uuid) { task in
                            Button {
                                // Its page, with the row selected and its details here.
                                app.reveal(task)
                            } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(task.trimmedTitle)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if let due = task.dueDate {
                                        Text(DateText.due(due, hasTime: task.dueHasTime, today: today))
                                            .foregroundStyle(DateText.dayDelta(due, today: today) < 0 ? Color.red : Color.secondary)
                                    }
                                }
                                .theoFont(.subheadline)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Select a task to see and change everything about it here. Right-click a task for quick actions.")
                    .theoFont(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
