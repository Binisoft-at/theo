import SwiftUI
import SwiftData
import TheoCore

/// Everything you'd want to change from the wrist: done, Not Today, priority, position,
/// deadline, group, delete.
struct WatchTaskDetailView: View {
    let task: TaskItem

    @Environment(WatchModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    private var store: TaskStore { TaskStore(context: context) }
    private var isPlannedToday: Bool { task.isPlanned(for: model.dayStart) }
    private var tomorrow: Date { DayBoundary.current.dayStart(byAdding: 1, to: model.dayStart) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.trimmedTitle.isEmpty ? String(localized: "Untitled") : task.trimmedTitle)
                        .font(.headline)
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    WatchTaskMeta(task: task, today: model.dayStart, showGroup: true)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    withAnimation { store.setDone([task], !task.isDone) }
                } label: {
                    Label(task.isDone ? "Mark as Not Done" : "Mark as Done",
                          systemImage: task.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                }
                if !task.isDone {
                    Button {
                        store.plan([task], for: isPlannedToday ? tomorrow : model.dayStart)
                    } label: {
                        Label(isPlannedToday ? "Not Today" : "Do Today", systemImage: isPlannedToday ? "moon.zzz" : "sun.max")
                    }
                    Button {
                        store.moveToEdge(task, top: true)
                    } label: {
                        Label("Move to Top", systemImage: "arrow.up.to.line")
                    }
                }
            }

            Section("Priority") {
                Picker("Priority", selection: priority) {
                    ForEach(Priority.allCases.reversed()) { level in
                        Label(level.title, systemImage: level.symbol)
                            .tag(level)
                    }
                }
            }

            Section("Deadline") {
                ForEach([QuickDate.today, .tomorrow, .nextWeek]) { quick in
                    let date = quick.date(from: model.dayStart)
                    Button {
                        store.setDue([task], date)
                    } label: {
                        HStack {
                            Label(quick.title, systemImage: quick.symbol)
                            Spacer()
                            if isDue(on: date) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                if task.dueDate != nil {
                    Button {
                        store.setDue([task], nil)
                    } label: {
                        Label("No Deadline", systemImage: "xmark.circle")
                    }
                }
            }

            Section("Group") {
                Picker("Group", selection: groupID) {
                    Text("Quick Entry").tag(UUID?.none)
                    ForEach(groups) { group in
                        Text(group.displayName).tag(Optional(group.uuid))
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    store.delete([task])
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Task")
    }

    private var priority: Binding<Priority> {
        Binding(get: { task.priority }, set: { store.setPriority([task], $0) })
    }

    private var groupID: Binding<UUID?> {
        Binding(get: { task.groupID }, set: { store.move([task], toGroup: $0) })
    }

    private func isDue(on date: Date) -> Bool {
        guard let due = task.dueDate else { return false }
        return Calendar.current.isDate(due, inSameDayAs: date)
    }
}
