import SwiftUI
import SwiftData
import TheoCore

/// Everything you'd want to change from the wrist: done, Today or Tomorrow, priority, position,
/// deadline, group, delete.
struct WatchTaskDetailView: View {
    let task: TaskItem

    @Environment(WatchModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    /// Bumped when the task is checked off here, for the haptic.
    @State private var doneCount = 0
    /// Bumped by every deadline pick, for the haptic.
    @State private var pickCount = 0

    private var store: TaskStore { TaskStore(context: context) }
    private var isPlannedToday: Bool { task.isPlanned(for: model.dayStart) }
    private var tomorrow: Date { DayBoundary.current.dayStart(byAdding: 1, to: model.dayStart) }

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
            }

            Section {
                doneButton
                if !task.isDone {
                    planButton
                    Button {
                        Motion.animate { store.moveToEdge(task, top: true) }
                    } label: {
                        Label("Move to Top", systemImage: "arrow.up.to.line")
                    }
                }
            }

            Section("Priority") {
                Picker("Priority", selection: priority) {
                    ForEach(Priority.allCases.reversed()) { level in
                        Label {
                            Text(level.title)
                        } icon: {
                            Image(systemName: level.symbol)
                                .foregroundStyle(level.color)
                        }
                        .tag(level)
                    }
                }
            }

            Section("Deadline") {
                ForEach([QuickDate.today, .tomorrow, .nextWeek]) { quick in
                    deadlineButton(quick)
                }
                if task.dueDate != nil {
                    Button {
                        pickCount += 1
                        Motion.animate(Motion.tap) { store.setDue([task], nil) }
                    } label: {
                        Label("No Deadline", systemImage: "xmark.circle")
                    }
                }
            }

            Section("Group") {
                Picker("Group", selection: groupID) {
                    Label {
                        Text("Quick Entry")
                    } icon: {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .foregroundStyle(.secondary)
                    }
                    .tag(UUID?.none)
                    ForEach(groups) { group in
                        Label {
                            Text(group.displayName)
                        } icon: {
                            Image(systemName: group.symbol)
                                .foregroundStyle(group.color.color)
                        }
                        .tag(Optional(group.uuid))
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
        .sensoryFeedback(.success, trigger: doneCount)
        .sensoryFeedback(.selection, trigger: pickCount)
    }

    /// The title with its priority marks (struck through once done), the notes, then the
    /// details line.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleText
            if !task.notes.isEmpty {
                Text(task.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            WatchTaskMeta(task: task, today: model.dayStart, showGroup: true)
        }
    }

    private var titleText: Text {
        let title = task.trimmedTitle.isEmpty ? String(localized: "Untitled") : task.trimmedTitle
        let text: Text
        if task.priority != .normal, !task.isDone {
            let marks: Text = Text(task.priority.marks).fontWeight(.heavy).foregroundStyle(task.priority.color)
            text = Text("\(marks) \(title)")
        } else {
            text = Text(title)
        }
        return text
            .font(.headline)
            .strikethrough(task.isDone)
            .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
    }

    /// Checks it off (green check, a success tap on the wrist) or brings it back.
    private var doneButton: some View {
        Button {
            let finishing = !task.isDone
            if finishing { doneCount += 1 }
            Motion.animate { store.setDone([task], finishing) }
        } label: {
            Label {
                Text(task.isDone ? "Mark as Not Done" : "Mark as Done")
            } icon: {
                Image(systemName: task.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                    .foregroundStyle(task.isDone ? Color.secondary : Tint.done)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }

    /// Today's sun (orange) or Tomorrow's moon (indigo); the symbol morphs as it changes.
    private var planButton: some View {
        Button {
            Motion.animate(Motion.tap) {
                store.plan([task], for: isPlannedToday ? tomorrow : model.dayStart)
            }
        } label: {
            Label {
                Text(isPlannedToday ? "Tomorrow" : "Today")
            } icon: {
                Image(systemName: isPlannedToday ? "moon.zzz.fill" : "sun.max.fill")
                    .foregroundStyle(isPlannedToday ? Tint.tomorrow : Tint.today)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }

    /// One quick deadline, its symbol in the deadline blue; the chosen one gets a check.
    private func deadlineButton(_ quick: QuickDate) -> some View {
        let date = quick.date(from: model.dayStart)
        return Button {
            pickCount += 1
            Motion.animate(Motion.tap) { store.setDue([task], date) }
        } label: {
            HStack {
                Label {
                    Text(quick.title)
                } icon: {
                    Image(systemName: quick.symbol)
                        .foregroundStyle(Tint.deadline)
                }
                Spacer()
                if isDue(on: date) {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
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
