import SwiftUI
import SwiftData
import TheoCore

/// The column on the right of a wide Mac (or iPad) window: the selected task's details, editable
/// in place, so changing a task never needs a sheet. With several selected, the quick actions for
/// all of them; with none, the day at a glance.
struct TaskInspector: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil })
    private var groups: [TaskGroup]

    var body: some View {
        let selected = app.selectedTasks
        Group {
            if selected.count == 1, let task = selected.first {
                TaskDetailView(task: task, embedded: true)
                    .id(task.uuid)
            } else if selected.count > 1 {
                ScrollView {
                    TaskActionPanel(tasks: selected)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                glance
            }
        }
    }

    /// Nothing selected: today's numbers and what's coming.
    private var glance: some View {
        let today = app.dayStart
        let live = tasks.activeOnly(groups)
        let planned = live.filter { PageBuilder.isOnToday($0, dayStart: today) }
        let stats = TaskStats(planned, today: today)
        let upcoming = live.filter { !$0.isDone && $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(8)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(DateText.pageTitle(today))
                    .theoFont(.title3, weight: .bold)
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(stats.open) open today · \(PowerHours.format(stats.openHours))", systemImage: "sun.max")
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
                                app.selectedRowIDs = [task.rowID]
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
