import SwiftUI
import SwiftData
import TheoCore

/// Everything you'd change on a task, one tap each, in colour: right-click a task on the Mac
/// (or Quick Edit from the long-press menu on iPhone) and it opens right above the line.
/// Changes apply at once; the panel stays open for the next one.
struct TaskActionPanel: View {
    let tasks: [TaskItem]
    var onClose: () -> Void = {}

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    private var single: TaskItem? { tasks.count == 1 ? tasks.first : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(single.map { $0.trimmedTitle.isEmpty ? "New Task" : $0.trimmedTitle } ?? "\(tasks.count) tasks")
                .font(.headline)
                .lineLimit(2)

            HStack(alignment: .top, spacing: 8) {
                let done = tasks.allSatisfy(\.isDone)
                big(done ? "Reopen" : "Done", "checkmark", .green) {
                    withAnimation(.snappy) { app.store.setDone(tasks, !done) }
                    onClose()
                }
                let today = tasks.allSatisfy { $0.isPlanned(for: app.dayStart) }
                big(today ? "Not Today" : "Today", "sun.max.fill", .orange) {
                    withAnimation(.snappy) { app.plan(tasks, for: today ? nil : app.dayStart) }
                }
                big("Tomorrow", "moon.zzz.fill", .indigo) {
                    withAnimation(.snappy) { app.deferToTomorrow(tasks) }
                }
                if let single {
                    big("Subtask", "arrow.turn.down.right", .purple) {
                        onClose()
                        withAnimation(.snappy) { app.addSubtask(to: single) }
                    }
                }
                let ongoing = tasks.allSatisfy(\.isOngoing)
                big(ongoing ? "Not Ongoing" : "Ongoing", "infinity", .teal) {
                    withAnimation(.snappy) { app.store.setOngoing(tasks, !ongoing) }
                }
                if let single, !single.isDone {
                    big("Focus", "scope", .pink) {
                        onClose()
                        app.startFocus(on: single)
                    }
                }
                if let single {
                    big("Details", "info.circle.fill", .blue) {
                        onClose()
                        showDetails(single)
                    }
                }
                big("Delete", "trash.fill", .red) {
                    onClose()
                    app.delete(tasks)
                }
            }

            row("Priority") {
                ForEach([Priority.normal, .low, .medium, .high]) { level in
                    let on = tasks.allSatisfy { $0.priority == level }
                    chip(level == .normal ? "None" : level.marks, color: level == .normal ? .secondary : level.color, on: on) {
                        app.store.setPriority(tasks, level)
                    }
                }
            }

            row("Deadline") {
                ForEach(QuickDate.allCases) { quick in
                    let date = quick.date(from: app.dayStart)
                    let on = tasks.allSatisfy { task in task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }
                    chip(quick.title, color: .orange, on: on) {
                        app.store.setDue(tasks, date)
                    }
                }
                chip("None", color: .secondary, on: tasks.allSatisfy { $0.dueDate == nil }) {
                    app.store.setDue(tasks, nil)
                }
            }

            row("Power Hours") {
                ForEach([0.25, 0.5, 1.0, 2.0, 4.0], id: \.self) { value in
                    chip(PowerHours.number(value), color: .teal, on: tasks.allSatisfy { abs($0.estimate - value) < 0.001 }) {
                        app.store.setEstimate(tasks, value)
                    }
                }
                chip("None", color: .secondary, on: tasks.allSatisfy { $0.estimate <= 0 }) {
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
        .frame(width: 470)
    }

    private func showDetails(_ task: TaskItem) {
        #if os(macOS)
        app.selectedRowIDs = [task.rowID]
        app.showInspector = true
        #else
        app.detailTask = task
        #endif
    }

    /// A round, coloured action with its name underneath.
    private func big(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(color.gradient))
                    .shadow(color: color.opacity(0.35), radius: 4, y: 2)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    /// A tinted capsule; filled when it's the task's current value.
    private func chip(_ title: String, color: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(on ? Color.white : color)
                .background(Capsule().fill(on ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.14))))
        }
        .buttonStyle(.plain)
    }
}
