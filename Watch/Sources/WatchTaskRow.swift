import SwiftUI
import SwiftData
import TheoCore

/// One task. Tap checks it off (it sinks away after a short beat, like Notes); swipe right for
/// Done / Not Today, swipe left for Details / Delete.
struct WatchTaskRow: View {
    let task: TaskItem
    var depth: Int = 0
    var showGroup: Bool = false

    @Environment(WatchModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var checkedPreview = false

    private var store: TaskStore { TaskStore(context: context) }
    private var displayDone: Bool { task.isDone || checkedPreview }

    var body: some View {
        Button(action: tapCheck) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: displayDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(displayDone ? Color.accentColor : task.priority.color)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                        .lineLimit(3)
                    WatchTaskMeta(task: task, today: model.dayStart, showGroup: showGroup)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(min(depth, 3)) * 12)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if task.isDone {
                Button {
                    withAnimation { store.setDone([task], false) }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .tint(.gray)
            } else {
                Button {
                    checkedPreview = true
                    withAnimation { store.setDone([task], true) }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.green)
                Button {
                    withAnimation { store.deferTasks([task], until: DayBoundary.current.dayStart(byAdding: 1, to: model.dayStart)) }
                } label: {
                    Label("Not Today", systemImage: "moon.zzz")
                }
                .tint(.indigo)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                model.show(.task(task))
            } label: {
                Label("Details", systemImage: "ellipsis")
            }
            .tint(.gray)
            Button(role: .destructive) {
                withAnimation { _ = store.delete([task]) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sensoryFeedback(.success, trigger: checkedPreview) { _, new in new }
        .accessibilityValue(task.isDone ? Text("Done") : Text("Open"))
        .accessibilityHint(task.isDone ? Text("Double-tap to mark as not done") : Text("Double-tap to mark as done"))
    }

    private var titleText: Text {
        let title = task.trimmedTitle.isEmpty ? String(localized: "Untitled") : task.trimmedTitle
        let text: Text
        if task.priority != .normal, !displayDone {
            text = Text("\(Text(task.priority.marks).foregroundStyle(task.priority.color)) \(title)")
        } else {
            text = Text(title)
        }
        return text
            .strikethrough(displayDone)
            .foregroundStyle(displayDone ? Color.secondary : Color.primary)
    }

    private func tapCheck() {
        if task.isDone {
            withAnimation { store.setDone([task], false) }
            return
        }
        guard !checkedPreview else { return }
        checkedPreview = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation { store.setDone([task], true) }
            checkedPreview = false
        }
    }
}

/// Deadline, "Not Today", group and tags in one small line.
struct WatchTaskMeta: View {
    let task: TaskItem
    let today: Date
    var showGroup: Bool = false

    var body: some View {
        if let line {
            line
                .font(.footnote)
                .lineLimit(1)
        }
    }

    private var line: Text? {
        var parts: [Text] = []
        if let due = task.dueDate {
            let delta = DateText.dayDelta(due, today: today)
            let color: Color = task.isDone ? .secondary : (delta < 0 ? .red : (delta == 0 ? .orange : .secondary))
            let label = DateText.due(due, hasTime: task.dueHasTime, today: today)
            parts.append(Text("\(Image(systemName: "calendar")) \(label)").foregroundStyle(color))
        }
        if !task.isDone, let deferred = task.deferredUntil, deferred > today {
            parts.append(Text("\(Image(systemName: "moon.zzz")) \(DateText.shortDay(deferred))").foregroundStyle(Color.indigo))
        }
        if showGroup, let group = task.group, group.deletedAt == nil {
            parts.append(Text(group.displayName).foregroundStyle(group.color.color))
        }
        if !task.tags.isEmpty {
            parts.append(Text(task.tags.map { "#" + $0 }.joined(separator: " ")).foregroundStyle(Color.secondary))
        }
        guard var result = parts.first else { return nil }
        for part in parts.dropFirst() {
            result = Text("\(result)  \(part)")
        }
        return result
    }
}

/// "Add Task": dictate, scribble or type. Understands the same shortcuts as the iPhone entry bar
/// ("tomorrow 5pm", "!!", "#tag", "@group").
struct WatchAddTaskRow: View {
    let groupID: UUID?

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        TextFieldLink(prompt: Text("New task")) {
            Label("Add Task", systemImage: "plus.circle.fill")
                .foregroundStyle(.tint)
        } onSubmit: { text in
            add(text)
        }
    }

    private func add(_ text: String) {
        let refs = groups.map { QuickParser.GroupRef(id: $0.uuid, name: $0.displayName) }
        let entry = QuickParser.parse(text, groups: refs)
        guard !entry.title.isEmpty else { return }
        let placement = NewTaskPlacement(rawValue: UserDefaults.standard.string(forKey: Prefs.newTaskPlacement) ?? "") ?? .bottom
        withAnimation {
            _ = TaskStore(context: context).addTask(entry, defaultGroupID: groupID, placement: placement)
        }
    }
}
