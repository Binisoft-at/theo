import SwiftUI
import SwiftData
import TheoCore

/// Floating Liquid Glass composer at the bottom of a page. Type, hit Return, keep typing.
///
/// - Typed shortcuts: `!!`, `#tag`, `@group` and natural dates, previewed as chips.
/// - Buttons above the field set priority, deadline and group without typing.
/// - A leading "- " files the line as a subtask of the task added just before.
/// - Pasting several lines adds several tasks and keeps their indentation as subtasks.
/// - Every add can be undone from the confirmation line.
struct QuickEntryBar: View {
    /// Where new tasks go when no `@group` is typed (nil = Quick Entry).
    var defaultGroupID: UUID?
    var placeholder = "Add a task"

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @AppStorage(Prefs.newTaskPlacement) private var placementRaw = NewTaskPlacement.bottom.rawValue

    @State private var text = ""
    @State private var disabled: QuickParser.Options = []
    @State private var priorityChoice: Priority?
    @State private var dueChoice: DueChoice = .fromText
    @State private var groupChoice: GroupChoice = .fromText
    @State private var subtaskOff = false
    /// The last top-level task added here; "- " lines go under it.
    @State private var lastParent: TaskItem?
    @State private var confirmation: Confirmation?
    @State private var addedCount = 0
    @FocusState private var focused: Bool

    enum DueChoice: Equatable {
        case fromText
        case cleared
        case date(Date)
    }

    enum GroupChoice: Equatable {
        case fromText
        case quickEntry
        case group(UUID)
    }

    struct Confirmation: Identifiable {
        let id = UUID()
        let message: String
        let tasks: [TaskItem]
    }

    // MARK: - What the entry will create

    private var options: QuickParser.Options { QuickParser.Options.all.subtracting(disabled) }

    private var groupRefs: [QuickParser.GroupRef] {
        groups.map { QuickParser.GroupRef(id: $0.uuid, name: $0.displayName) }
    }

    private var isMultiline: Bool { text.trimmingCharacters(in: .newlines).contains(where: \.isNewline) }

    private var liveParent: TaskItem? {
        guard let lastParent, lastParent.modelContext != nil, !lastParent.isDeleted, lastParent.deletedAt == nil else { return nil }
        return lastParent
    }

    /// Set while the text starts with "- " and there's a task to file it under.
    private var subtaskParent: TaskItem? {
        guard !subtaskOff, !isMultiline, Composer.subtaskBody(text) != nil else { return nil }
        return liveParent
    }

    private var parsed: ParsedEntry {
        let source = subtaskParent != nil ? (Composer.subtaskBody(text) ?? text) : text
        return QuickParser.parse(source, groups: groupRefs, options: options, now: Date())
    }

    private var effectivePriority: Priority { priorityChoice ?? parsed.priority }

    private var effectiveDue: (date: Date, hasTime: Bool)? {
        switch dueChoice {
        case .fromText: parsed.due.map { (date: $0, hasTime: parsed.dueHasTime) }
        case .cleared: nil
        case .date(let date): (date: date, hasTime: false)
        }
    }

    /// Group chosen with the button, or the page's group.
    private var baseGroupID: UUID? {
        switch groupChoice {
        case .fromText: defaultGroupID
        case .quickEntry: nil
        case .group(let id): id
        }
    }

    private var targetGroupID: UUID? {
        if case .fromText = groupChoice, let typed = parsed.groupID { return typed }
        return baseGroupID
    }

    private func groupName(_ id: UUID?) -> String {
        groups.first(where: { $0.uuid == id })?.displayName ?? "Quick Entry"
    }

    // MARK: - Views

    var body: some View {
        VStack(spacing: 8) {
            if let confirmation {
                confirmationRow(confirmation)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if focused {
                controls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            field
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.25), value: text.isEmpty)
        .animation(.snappy(duration: 0.25), value: focused)
        .animation(.snappy(duration: 0.25), value: confirmation?.id)
        .onChange(of: app.wantsQuickEntryFocus) { _, wants in
            if wants { focusNow() }
        }
        .onAppear {
            if app.wantsQuickEntryFocus { focusNow() }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused && text.isEmpty { groupChoice = .fromText }
        }
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty {
                disabled = []
                subtaskOff = false
            }
            // Return in the multi-line field arrives as a trailing line break.
            if newValue.hasSuffix("\n") {
                text = String(newValue.dropLast())
                add()
            }
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: subtaskParent != nil ? "arrow.turn.down.right" : "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: addedCount)
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($focused)
                .onSubmit(add)
                #if os(iOS)
                .submitLabel(.done)
                #endif
            if !text.isEmpty {
                Button(action: add) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.return, modifiers: .command)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(isMultiline ? "Add \(Composer.lines(text).count) Tasks" : "Add Task")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }

    /// One-tap priority, deadline, group and subtask, plus what was understood from the text.
    private var controls: some View {
        let entry = parsed
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if isMultiline {
                    chipLabel("\(Composer.lines(text).count) tasks", symbol: "list.bullet.indent", color: .accentColor, active: true)
                } else {
                    subtaskChip
                }
                priorityChip
                dueChip
                if subtaskParent == nil {
                    groupChip
                }
                ForEach(entry.tags, id: \.self) { tag in
                    removableChip("#" + tag, color: TheoColor.forTag(tag).color) { disabled.insert(.tags) }
                }
                if text.isEmpty {
                    Text(liveParent == nil ? "Try “tomorrow 9am !! #home”" : "Start with “- ” for a subtask")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var subtaskChip: some View {
        if let parent = subtaskParent {
            Button {
                subtaskOff = true
            } label: {
                chipLabel("Under “\(parent.trimmedTitle)”", symbol: "arrow.turn.down.right", color: .accentColor, active: true, removable: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds it as a normal task instead")
        } else if let parent = liveParent, Composer.subtaskBody(text) == nil {
            Button {
                subtaskOff = false
                text = "- " + text
            } label: {
                chipLabel("Subtask", symbol: "arrow.turn.down.right", color: .accentColor, active: false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds it under “\(parent.trimmedTitle)”")
        }
    }

    private var priorityChip: some View {
        let level = effectivePriority
        return Menu {
            ForEach(Priority.allCases.reversed()) { option in
                Button {
                    priorityChoice = option
                } label: {
                    Label(option.title, systemImage: option == level ? "checkmark" : option.symbol)
                }
            }
        } label: {
            chipLabel(level == .normal ? "Priority" : level.marks, symbol: level == .normal ? "exclamationmark" : nil, color: level.color, active: level != .normal)
        } primaryAction: {
            priorityChoice = level.next
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Priority")
        .accessibilityValue(level.title)
        .accessibilityHint("Tap to raise, touch and hold to choose")
    }

    private var dueChip: some View {
        let due = effectiveDue
        return Menu {
            ForEach(QuickDate.allCases) { quick in
                Button {
                    dueChoice = .date(quick.date(from: app.dayStart))
                } label: {
                    Label(quick.title, systemImage: quick.symbol)
                }
            }
            if due != nil {
                Divider()
                Button(role: .destructive) {
                    dueChoice = .cleared
                } label: {
                    Label("No Deadline", systemImage: "calendar.badge.minus")
                }
            }
        } label: {
            chipLabel(
                due.map { DateText.due($0.date, hasTime: $0.hasTime, today: app.dayStart) } ?? "Date",
                symbol: "calendar",
                color: .orange,
                active: due != nil
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Deadline")
    }

    private var groupChip: some View {
        let id = targetGroupID
        let group = groups.first { $0.uuid == id }
        return Menu {
            Button {
                groupChoice = .quickEntry
                disabled.insert(.group)
            } label: {
                Label("Quick Entry", systemImage: "tray.and.arrow.down")
            }
            ForEach(groups) { option in
                Button {
                    groupChoice = .group(option.uuid)
                    disabled.insert(.group)
                } label: {
                    Label(option.displayName, systemImage: option.symbol)
                }
            }
        } label: {
            chipLabel(
                groupName(id),
                symbol: group?.symbol ?? "tray.and.arrow.down",
                color: group?.color.color ?? .secondary,
                active: id != defaultGroupID
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Group")
    }

    private func removableChip(_ title: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        Button(action: onRemove) {
            chipLabel(title, symbol: nil, color: color, active: true, removable: true)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, symbol: String?, color: Color, active: Bool, removable: Bool = false) -> some View {
        let glass: Glass = active ? Glass.regular.tint(color.opacity(0.15)).interactive() : Glass.regular.interactive()
        return HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(title)
                .lineLimit(1)
            if removable { Image(systemName: "xmark").imageScale(.small).opacity(0.6) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(active ? color : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(glass, in: .capsule)
    }

    private func confirmationRow(_ confirmation: Confirmation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
            Text(confirmation.message)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Undo") {
                undo(confirmation)
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Actions

    private func focusNow() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focused = true
            app.wantsQuickEntryFocus = false
        }
    }

    private func add() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            focused = false
            return
        }
        let created: [TaskItem]
        let message: String
        if raw.contains(where: \.isNewline) {
            created = addLines(Composer.lines(raw))
            message = created.count == 1 ? "Added 1 task" : "Added \(created.count) tasks"
        } else {
            var entry = parsed
            guard !entry.title.isEmpty else { return }
            entry.priority = effectivePriority
            entry.due = effectiveDue?.date
            entry.dueHasTime = effectiveDue?.hasTime ?? false
            if let parent = subtaskParent {
                let task = withAnimation(.snappy) { app.store.addSubtask(entry, to: parent) }
                if app.collapsedTaskIDs.contains(parent.uuid) { app.toggleSubtasks(parent) }
                created = [task]
                message = "Added under “\(parent.trimmedTitle)”"
            } else {
                let groupID = targetGroupID
                entry.groupID = groupID
                let placement = NewTaskPlacement(rawValue: placementRaw) ?? .bottom
                let task = withAnimation(.snappy) { app.store.addTask(entry, defaultGroupID: groupID, placement: placement) }
                lastParent = task
                created = [task]
                message = "Added to \(groupName(groupID))"
            }
        }
        guard !created.isEmpty else { return }
        for task in created {
            if let group = task.group, group.isCollapsed { app.store.setCollapsed(group, false) }
        }
        show(Confirmation(message: message, tasks: created))
        addedCount += 1
        text = ""
        disabled = []
        priorityChoice = nil
        dueChoice = .fromText
        subtaskOff = false
        // The group stays picked while adding several tasks; keep the keyboard up for rapid entry.
        focused = true
    }

    /// A pasted list: each line is a task, indented lines become subtasks of the line above.
    private func addLines(_ lines: [Composer.Line]) -> [TaskItem] {
        var created: [TaskItem] = []
        var parents: [TaskItem] = []
        withAnimation(.snappy) {
            for line in lines {
                var entry = QuickParser.parse(line.title, groups: groupRefs, options: options)
                guard !entry.title.isEmpty else { continue }
                if let priorityChoice { entry.priority = priorityChoice }
                if case .date(let date) = dueChoice {
                    entry.due = date
                    entry.dueHasTime = false
                }
                let task: TaskItem
                if line.level > 0, line.level <= parents.count {
                    task = app.store.addSubtask(entry, to: parents[line.level - 1])
                } else {
                    let groupID = entry.groupID ?? baseGroupID
                    entry.groupID = groupID
                    task = app.store.addTask(entry, defaultGroupID: groupID, placement: .bottom)
                }
                parents = Array(parents.prefix(line.level)) + [task]
                created.append(task)
            }
        }
        if let first = created.first(where: { $0.indent == 0 }) { lastParent = first }
        return created
    }

    private func show(_ confirmation: Confirmation) {
        self.confirmation = confirmation
        let id = confirmation.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if self.confirmation?.id == id { self.confirmation = nil }
        }
    }

    private func undo(_ confirmation: Confirmation) {
        withAnimation(.snappy) { app.store.purge(confirmation.tasks) }
        if let lastParent, confirmation.tasks.contains(where: { $0 === lastParent }) { self.lastParent = nil }
        self.confirmation = nil
    }
}
