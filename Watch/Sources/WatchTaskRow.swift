import SwiftUI
import SwiftData
import TheoCore

/// One task. Tap checks it off: the circle fills with a small bounce, then the line sinks away
/// after a short beat, like Notes. Swipe right for Done / Today or Tomorrow, swipe left for
/// Details / Delete.
struct WatchTaskRow: View {
    let task: TaskItem
    var depth: Int = 0
    var showGroup: Bool = false

    @Environment(WatchModel.self) private var model
    @Environment(\.modelContext) private var context
    /// Ticked while a tap's short beat runs, before the task is really done.
    @State private var checkedPreview = false
    /// Bumped by every check-off (tap or swipe) for the haptic.
    @State private var checkCount = 0

    private var store: TaskStore { TaskStore(context: context) }
    private var displayDone: Bool { task.isDone || checkedPreview }

    var body: some View {
        Button(action: tapCheck) {
            HStack(alignment: .top, spacing: 10) {
                // A subtask's circle is a little smaller, centred in the same column.
                WatchCheckCircle(done: displayDone, priority: task.priority, diameter: depth > 0 ? 18 : 22)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                        .lineLimit(3)
                    WatchTaskMeta(task: task, today: model.dayStart, showGroup: showGroup)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(min(depth, 3)) * 12)
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if task.isDone {
                Button {
                    Motion.animate { store.setDone([task], false) }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .tint(.gray)
            } else {
                Button {
                    // No preview tick here: the row may stay (an ongoing task, a group page),
                    // and a stuck tick would hide that the task is open.
                    checkCount += 1
                    Motion.animate { store.setDone([task], true) }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(Tint.done)
                if task.isPlanned(for: model.dayStart) {
                    Button {
                        Motion.animate { store.plan([task], for: DayBoundary.current.dayStart(byAdding: 1, to: model.dayStart)) }
                    } label: {
                        Label("Tomorrow", systemImage: "moon.zzz.fill")
                    }
                    .tint(Tint.tomorrow)
                } else {
                    Button {
                        Motion.animate { store.plan([task], for: model.dayStart) }
                    } label: {
                        Label("Today", systemImage: "sun.max.fill")
                    }
                    .tint(Tint.today)
                }
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
                Motion.animate { _ = store.delete([task]) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sensoryFeedback(.success, trigger: checkCount)
        .onChange(of: task.isDone) {
            checkedPreview = false
        }
        .accessibilityValue(task.isDone ? Text("Done") : Text("Open"))
        .accessibilityHint(task.isDone ? Text("Double-tap to mark as not done") : Text("Double-tap to mark as done"))
    }

    private var titleText: Text {
        let title = task.trimmedTitle.isEmpty ? String(localized: "Untitled") : task.trimmedTitle
        let text: Text
        if task.priority != .normal, !displayDone {
            let marks: Text = Text(task.priority.marks).fontWeight(.heavy).foregroundStyle(task.priority.color)
            text = Text("\(marks) \(title)")
        } else {
            text = Text(title)
        }
        return text
            .strikethrough(displayDone)
            .foregroundStyle(displayDone ? Color.secondary : Color.primary)
    }

    private func tapCheck() {
        if task.isDone {
            Motion.animate { store.setDone([task], false) }
            return
        }
        guard !checkedPreview else { return }
        checkCount += 1
        // The circle fills and the title greys out at once; the line leaves a beat later.
        Motion.animate(Motion.tap) { checkedPreview = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            Motion.animate { store.setDone([task], true) }
            checkedPreview = false
        }
    }
}

/// The round check, drawn like the iPhone's: a ring in the priority's colour (grey without one)
/// that fills with the accent and a white check once the task is done. The fill springs in with a small
/// bounce, and goes back quietly when the task is reopened.
struct WatchCheckCircle: View {
    let done: Bool
    let priority: Priority
    var diameter: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(priority == .normal ? Color.secondary : priority.color, lineWidth: 2)
                .opacity(done ? 0 : 1)
            Circle()
                .fill(.tint)
                .scaleEffect(done ? 1 : 0.4)
                .opacity(done ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: diameter * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .scaleEffect(done ? 1 : 0.4)
                .opacity(done ? 1 : 0)
        }
        .frame(width: diameter, height: diameter)
        .animation(Motion.resolved(done ? Motion.celebrate : Motion.tap), value: done)
        .accessibilityHidden(true)
    }
}

/// Deadline, a later plan day, "logged today" for an ongoing task, group and tags in one small
/// grey line. Colour only where it means something: the deadline (orange today or once it has
/// passed, blue later), a later plan day (indigo), a logged ongoing task (green) and the group's
/// icon.
struct WatchTaskMeta: View {
    let task: TaskItem
    let today: Date
    var showGroup: Bool = false

    var body: some View {
        if let line {
            line
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var line: Text? {
        var parts: [Text] = []
        if let due = task.dueDate {
            parts.append(dueText(due))
        }
        if !task.isDone, let planned = task.plannedDay, planned > today {
            parts.append(Text("\(Image(systemName: "calendar.badge.checkmark")) \(DateText.shortDay(planned))").foregroundStyle(Tint.planned))
        }
        // An ongoing task stays open when it's checked off; this confirms it was logged.
        if task.isOngoing, let logged = task.lastDoneAt, logged >= today, logged < DayBoundary.current.end(ofDayStarting: today) {
            parts.append(Text("\(Image(systemName: "checkmark")) logged today").foregroundStyle(Tint.done))
        }
        if showGroup, let group = task.group, group.deletedAt == nil {
            // The group's colour goes on its icon; the name stays grey like the rest of the line.
            let icon: Text = Text(Image(systemName: group.symbol)).foregroundStyle(group.color.color)
            parts.append(Text("\(icon) \(group.displayName)"))
        }
        if !task.tags.isEmpty {
            parts.append(Text(task.tags.map { "#" + $0 }.joined(separator: " ")))
        }
        guard var result = parts.first else { return nil }
        for part in parts.dropFirst() {
            result = Text("\(result)  \(part)")
        }
        return result
    }

    /// Calm even when it has passed (orange, as on iPhone): it's ranked at the top anyway.
    private func dueText(_ due: Date) -> Text {
        let delta = DateText.dayDelta(due, today: today)
        let color: Color
        if task.isDone {
            color = .secondary
        } else if delta < 0 {
            color = Tint.overdue
        } else if delta == 0 {
            color = Tint.today
        } else {
            color = Tint.deadline
        }
        let label = DateText.due(due, hasTime: task.dueHasTime, today: today)
        return Text("\(Image(systemName: "calendar")) \(label)").foregroundStyle(color)
    }
}

/// "Add Task": dictate, scribble or type. Understands the same shortcuts as the iPhone entry bar
/// ("tomorrow 5pm", "morgen 9 Uhr", "!!", "#tag", "@group"), read on the logical day.
struct WatchAddTaskRow: View {
    let groupID: UUID?
    /// On Today, new tasks are planned for today.
    var plansFor: Date?

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
        let refs = groups.map { QuickParser.GroupRef(id: $0.uuid, name: $0.displayName, parentID: $0.parentUUID) }
        let entry = QuickParser.parse(text, groups: refs, now: DayBoundary.current.start(of: Date()))
        guard !entry.title.isEmpty else { return }
        let placement = NewTaskPlacement(rawValue: UserDefaults.standard.string(forKey: Prefs.newTaskPlacement) ?? "") ?? .bottom
        Motion.animate {
            let store = TaskStore(context: context)
            let task = store.addTask(entry, defaultGroupID: groupID, placement: placement)
            if let plansFor { store.plan([task], for: plansFor) }
        }
    }
}
