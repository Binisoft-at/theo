import SwiftUI
import TheoCore

/// One task line. Shows plain text until tapped, then turns into an inline editor
/// (Return creates the next line, just like a checklist in Notes).
struct TaskRowView: View {
    let task: TaskItem
    let depth: Int
    let style: RowStyle
    let today: Date
    let isEditing: Bool
    var focus: FocusState<String?>.Binding
    var onToggle: () -> Void
    var onBeginEdit: () -> Void
    /// Called with the text that followed a line break (empty string = plain Return).
    var onSplit: ([String]) -> Void
    var onInfo: () -> Void
    /// Tab / Shift-Tab on a hardware keyboard.
    var onIndent: (Int) -> Void = { _ in }
    /// Folds or unfolds this line's subtasks.
    var onToggleSubtasks: () -> Void = {}

    @AppStorage(Prefs.showAge) private var showAge = true
    @AppStorage(Prefs.showNotesPreview) private var showNotesPreview = true
    @State private var checkedPreview = false

    private var displayDone: Bool { task.isDone || checkedPreview }

    /// A line with subtasks reads like a small group: bolder, with its progress underneath.
    private var isParent: Bool { style.subtaskCount > 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CheckCircle(done: displayDone, priority: task.priority, action: tapCheck)
                .scaleEffect(depth > 0 ? 0.86 : 1, anchor: .center)
                .padding(.top, -3)
                .padding(.leading, -4)

            VStack(alignment: .leading, spacing: 3) {
                titleLine
                if isEditing {
                    // The description, right under the title while the line is being edited.
                    TextField("Description", text: notesBinding, axis: .vertical)
                        .textFieldStyle(.plain)
                        .theoFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1...8)
                        .focused(focus, equals: Self.notesFocusID(task))
                } else if showNotesPreview, let preview = task.notesPreview {
                    Text(preview)
                        .theoFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TaskMetaLine(task: task, style: style, today: today, showAge: showAge)
                if isParent && !task.isDone {
                    SubtaskProgress(done: style.subtasksDone, total: style.subtaskCount)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            #if os(iOS)
            .onTapGesture { if !isEditing { onBeginEdit() } }
            #endif

            if style.subtaskCount > 0 {
                SubtaskBadge(done: style.subtasksDone, total: style.subtaskCount, folded: style.subtasksFolded, action: onToggleSubtasks)
            }

            if isEditing {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Details")
            }
        }
        // Subtasks step in by one circle's width per level: the hierarchy shows in the indent alone.
        .padding(.leading, CGFloat(depth) * 30)
        // The row has no insets of its own (see TaskListView), so its edges are the divider lines.
        .padding(.vertical, depth > 0 ? 6 : 9)
        // The divider starts where the text does and runs to the end, the same span the
        // insert line uses.
        .alignmentGuide(.listRowSeparatorLeading) { _ in Self.textLeading(depth: depth) }
        .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }
        .opacity(task.isDone && !isEditing ? 0.75 : 1)
        .animation(.snappy(duration: 0.25), value: displayDone)
    }

    @ViewBuilder
    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if task.priority != .normal {
                Text(task.priority.marks)
                    .theoFont(.body, weight: .heavy)
                    .foregroundStyle(task.priority.color)
            }
            if isEditing {
                TextField("New Task", text: titleBinding, axis: .vertical)
                    .textFieldStyle(.plain)
                    .theoFont(isParent ? .body : (depth > 0 ? .callout : .body), weight: isParent ? .semibold : nil)
                    .focused(focus, equals: task.rowID)
                    .onSubmit { onSplit([""]) }
                    .onKeyPress(.tab, phases: .down) { press in
                        onIndent(press.modifiers.contains(.shift) ? -1 : 1)
                        return .handled
                    }
                    // ⇧Return: on to the description.
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.shift) else { return .ignored }
                        focus.wrappedValue = Self.notesFocusID(task)
                        return .handled
                    }
                    #if os(iOS)
                    .submitLabel(.next)
                    #endif
            } else {
                Text(task.title.isEmpty ? "New Task" : task.title)
                    .theoFont(isParent ? .body : (depth > 0 ? .callout : .body), weight: isParent ? .semibold : nil)
                    .strikethrough(displayDone, color: .secondary)
                    .foregroundStyle(displayDone || task.title.isEmpty ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Where a row's text (and its divider) starts: past the indent and the check circle.
    static func textLeading(depth: Int) -> CGFloat { 34 + CGFloat(depth) * 30 }

    /// Focus ID of a task's description field (the title's is `rowID`).
    static func notesFocusID(_ task: TaskItem) -> String { "n-" + task.uuid.uuidString }

    private var notesBinding: Binding<String> {
        Binding(
            get: { task.notes },
            set: { newValue in
                guard newValue != task.notes else { return }
                task.notes = newValue
                task.touch()
            }
        )
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { task.title },
            set: { newValue in
                if newValue.contains(where: \.isNewline) {
                    let parts = newValue.components(separatedBy: CharacterSet.newlines)
                    task.title = parts.first ?? ""
                    task.touch()
                    onSplit(Array(parts.dropFirst()))
                } else if newValue != task.title {
                    task.title = newValue
                    task.touch()
                }
            }
        )
    }

    private func tapCheck() {
        if task.isDone || checkedPreview {
            checkedPreview = false
            if task.isDone { onToggle() }
            return
        }
        // Show the check first, then let the line sink to the bottom (like Notes).
        checkedPreview = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard checkedPreview else { return }
            withAnimation(.snappy) {
                onToggle()
            }
            checkedPreview = false
        }
    }
}

/// Secondary information under a task title: deadline, deferral, tags, carried-over age, group.
struct TaskMetaLine: View {
    let task: TaskItem
    let style: RowStyle
    let today: Date
    let showAge: Bool

    @Environment(AppModel.self) private var app

    private var ageDays: Int {
        guard !task.isDone else { return 0 }
        return DayBoundary.current.days(from: task.createdAt, to: today)
    }

    private var hasContent: Bool {
        task.dueDate != nil || !task.tags.isEmpty || (showAge && ageDays >= 1) || task.estimate > 0 || task.focusSeconds >= 60
            || (style.showGroup && task.group != nil) || plannedToShow != nil || task.traitProposalGroupID != nil
            || task.isOngoing
    }

    /// "Ongoing · yesterday": an ongoing task and when it was last checked off.
    private var ongoingText: String {
        guard let last = task.lastDoneAt else { return "Ongoing" }
        let days = -DateText.dayDelta(last, today: today)
        switch days {
        case ...0: return "Ongoing · done today"
        case 1: return "Ongoing · yesterday"
        default: return "Ongoing · \(days)d ago"
        }
    }

    /// The day it's planned for, unless that's also the deadline's day (the deadline says it).
    private var plannedToShow: Date? {
        guard style.showDeferred, !task.isDone, let planned = task.plannedDay else { return nil }
        if let due = task.dueDate, DateText.dayDelta(due, today: planned) == 0 { return nil }
        return planned
    }

    /// "0,5 PH", or "0,2 / 0,5 PH" once focus time has been booked on it. A line with
    /// subtasks shows the total of everything still open in it: "Σ 1,5 PH".
    private var estimateText: String? {
        if style.subtaskCount > 0, style.blockEstimate > 0, !task.isDone {
            return "Σ " + PowerHours.format(style.blockEstimate)
        }
        let focused = task.focusSeconds / (PowerHours.minutesPerPH * 60)
        switch (task.estimate > 0, focused >= 0.05) {
        case (true, true): return PowerHours.number(focused) + " / " + PowerHours.format(task.estimate)
        case (true, false): return PowerHours.format(task.estimate)
        case (false, true): return PowerHours.format(focused) + " focused"
        case (false, false): return nil
        }
    }

    var body: some View {
        if hasContent {
            HStack(spacing: 10) {
                if let due = task.dueDate {
                    dueLabel(due)
                    if task.recurrence != nil {
                        Image(systemName: "repeat")
                            .accessibilityLabel(task.recurrence?.title ?? "Repeats")
                    }
                    if task.dueHasTime && !task.isDone && !task.reminderOffsets.isEmpty {
                        Image(systemName: "bell.fill")
                            .accessibilityLabel("Reminder on")
                    }
                }
                if task.isOngoing && !task.isDone {
                    Label(ongoingText, systemImage: "infinity")
                        .foregroundStyle(Color.teal)
                        .help("Ongoing: checking it off logs it for the day, the task stays")
                }
                if let estimateText {
                    Label(estimateText, systemImage: "timer")
                        .foregroundStyle(task.estimate > 0 && task.focusSeconds / 60 >= task.estimate * PowerHours.minutesPerPH ? Color.green : Color.secondary)
                }
                if let planned = plannedToShow {
                    if DateText.dayDelta(planned, today: today) == 0 {
                        // Planned for today: just the sun, the word would only crowd the line.
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.indigo)
                            .accessibilityLabel("Planned for today")
                    } else {
                        Label(DateText.due(planned, hasTime: false, today: today), systemImage: "calendar.badge.checkmark")
                            .foregroundStyle(.indigo)
                            .accessibilityLabel("Planned for " + DateText.due(planned, hasTime: false, today: today))
                    }
                }
                if style.showGroup, let group = task.group, group.deletedAt == nil {
                    Label(group.displayName, systemImage: group.symbol)
                        .foregroundStyle(group.color.color)
                }
                ForEach(task.tags, id: \.self) { tag in
                    TagChip(tag: tag)
                }
                if showAge, ageDays >= 1 {
                    Label("\(ageDays)d", systemImage: "arrow.uturn.forward")
                        .foregroundStyle(ageDays >= 3 ? Color.orange : Color.secondary)
                        .help("Carried over for \(ageDays) day\(ageDays == 1 ? "" : "s")")
                }
                if task.traitProposalGroupID != nil, let proposal = app.store.traitProposal(for: task) {
                    Menu {
                        TraitProposalMenu(task: task, group: proposal.group, traits: proposal.traits)
                    } label: {
                        Label("Suggested", systemImage: "wand.and.stars")
                            .foregroundStyle(Color.purple)
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityHint("\(proposal.group.displayName) suggests other values")
                }
            }
            .theoFont(.caption, weight: .medium)
            .labelStyle(CompactLabelStyle())
            .lineLimit(1)
            .foregroundStyle(.secondary)
        }
    }

    /// Overdue stays calm: "was due Mon" with a tap to move it, ranked at the top anyway.
    @ViewBuilder
    private func dueLabel(_ due: Date) -> some View {
        let delta = DateText.dayDelta(due, today: today)
        if !task.isDone && delta < 0 {
            Menu {
                Button("Today") { app.store.postpone([task], days: 0, today: today) }
                Button("Tomorrow") { app.store.postpone([task], days: 1, today: today) }
                Button("In 3 Days") { app.store.postpone([task], days: 3, today: today) }
                Button("Next Week") { app.store.postpone([task], days: 7, today: today) }
                Divider()
                Button("No Deadline", role: .destructive) { app.store.setDue([task], nil) }
            } label: {
                Label("was due " + DateText.due(due, hasTime: false, today: today), systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(Color.orange.opacity(0.85))
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityHint("Move the deadline")
        } else {
            let lateToday = !task.isDone && delta == 0 && task.dueHasTime && due < Date()
            let color: Color = task.isDone ? .secondary : (delta == 0 ? .orange : .secondary)
            Label(DateText.due(due, hasTime: task.dueHasTime, today: today), systemImage: lateToday ? "clock.badge.exclamationmark" : "calendar")
                .foregroundStyle(color)
        }
    }
}

/// "2/5 ›" on a parent line: subtask progress, and a tap folds or unfolds the subtasks.
struct SubtaskBadge: View {
    let done: Int
    let total: Int
    let folded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("\(done)/\(total)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .rotationEffect(.degrees(folded ? 0 : 90))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(done == total ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .padding(.top, 1)
        .animation(.snappy(duration: 0.2), value: folded)
        .accessibilityLabel(folded ? "Show \(total) subtasks" : "Hide \(total) subtasks")
        .accessibilityValue("\(done) of \(total) done")
    }
}

/// Thin vertical lines that show which parent a nested line belongs to.
/// A thin bar under a parent line: how much of its subtasks is done.
struct SubtaskProgress: View {
    let done: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: total > 0 ? geo.size.width * CGFloat(done) / CGFloat(total) : 0)
            }
        }
        .frame(maxWidth: 160)
        .frame(height: 3)
        .animation(.snappy, value: done)
        .accessibilityHidden(true)
    }
}

struct IndentGuides: View {
    let depth: Int

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<depth, id: \.self) { level in
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 1.5)
                    .offset(x: CGFloat(level) * 26 + 10)
            }
        }
        .padding(.vertical, -6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// What a group suggests for a task that already had values of its own: take all of it, one
/// part, or keep the task as it is.
struct TraitProposalMenu: View {
    let task: TaskItem
    let group: TaskGroup
    let traits: GroupTraits

    @Environment(AppModel.self) private var app

    var body: some View {
        Section("\(group.displayName) suggests") {
            Button {
                withAnimation(.snappy) { app.store.acceptProposal(task, traits) }
            } label: {
                Label("Apply All", systemImage: "wand.and.stars")
            }
            ForEach(parts.indices, id: \.self) { index in
                let part = parts[index]
                Button(part.title) {
                    withAnimation(.snappy) { app.store.acceptProposal(task, part.traits) }
                }
            }
            Button(role: .destructive) {
                withAnimation(.snappy) { app.store.dismissProposal(task) }
            } label: {
                Label("Keep Mine", systemImage: "xmark")
            }
        }
    }

    /// Each suggested value on its own.
    private var parts: [(title: String, traits: GroupTraits)] {
        var result: [(title: String, traits: GroupTraits)] = []
        if let importance = traits.importance {
            let one = GroupTraits(importance: importance)
            result.append((one.summary.first ?? "Importance", one))
        }
        if let estimate = traits.estimate {
            let one = GroupTraits(estimate: estimate)
            result.append((one.summary.first ?? "Power Hours", one))
        }
        if let dueDays = traits.dueDays {
            let one = GroupTraits(dueDays: dueDays)
            result.append((one.summary.first ?? "Deadline", one))
        }
        return result.count > 1 ? result : []
    }
}
