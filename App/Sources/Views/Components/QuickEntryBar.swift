import SwiftUI
import SwiftData
import TheoCore

/// Floating Liquid Glass composer at the bottom of a page. Type, hit Return, keep typing.
///
/// - Typed shortcuts: `!!`, `#tag`, `@group` and natural dates, previewed as chips.
/// - Buttons above the field set priority, deadline and group without typing.
/// - A leading "- " files the line as a subtask of the task added just before.
/// - Pasting several lines adds several tasks and keeps their indentation as subtasks.
/// - The ⊞ handle drags the task onto the Eisenhower matrix (urgency × importance); let go
///   to add it right there.
/// - Every add can be undone from the confirmation line.
struct QuickEntryBar: View {
    /// Where new tasks go when no `@group` is typed (nil = Quick Entry).
    var defaultGroupID: UUID?
    var placeholder = "Add a task"
    /// New tasks are planned for this day (Today, Plan).
    var plansFor: Date?

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
    /// nil = from the text ("0,5PH"), 0 = none.
    @State private var estimateChoice: Double?
    @State private var recurrenceChoice: RecurrenceChoice = .fromText
    @State private var matrixChoice: MatrixGeometry.Cell?
    /// 1...10 from holding the ! chip; overrides the priority marks.
    @State private var importanceChoice: Int?
    @State private var showCustomEstimate = false
    @State private var customEstimateText = ""
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

    enum RecurrenceChoice: Equatable {
        case fromText
        case never
        case set(Recurrence)
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

    /// Power Hours picked or typed (0 = explicitly none); nil leaves it to the default.
    private var chosenEstimate: Double? { estimateChoice ?? parsed.estimate }
    /// What the task will get: picked or typed, else its group's trait, else the default.
    private var effectiveEstimate: Double {
        chosenEstimate ?? targetTraits.estimate ?? PowerHours.defaultForNewTasks
    }
    /// Traits of the group the task will land in.
    private var targetTraits: GroupTraits {
        let groupID = subtaskParent?.groupID ?? targetGroupID
        return app.store.traits(of: groups.first(where: { $0.uuid == groupID }))
    }

    private var effectiveRecurrence: Recurrence? {
        switch recurrenceChoice {
        case .fromText: parsed.recurrence
        case .never: nil
        case .set(let recurrence): recurrence
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
        .alert("Estimate", isPresented: $showCustomEstimate) {
            TextField("Power Hours, e.g. 1,5", text: $customEstimateText)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Button("Set") {
                if let value = PowerHours.parse(customEstimateText) { estimateChoice = value }
                customEstimateText = ""
            }
            Button("Cancel", role: .cancel) { customEstimateText = "" }
        } message: {
            Text("1 PH = 50 minutes of focused work.")
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
            insertHandle
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($focused)
                .onSubmit(add)
                #if os(iOS)
                .submitLabel(.done)
                #endif
            matrixHandle
            if !text.isEmpty {
                // Tap adds; hold and point at a value on the arc picks the Power Hours, letting go
                // adds with them.
                HoldSlidePicker(options: Self.estimateOptions, title: "Power Hours", onTap: add) { index in
                    pickEstimate(index)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(isMultiline ? "Add \(Composer.lines(text).count) Tasks" : "Add Task")
                .accessibilityHint("Touch and hold, then slide toward a value to set the Power Hours")
                .accessibilityAddTraits(.isButton)
                .background {
                    Button("Add", action: add)
                        .keyboardShortcut(.return, modifiers: .command)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
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
                estimateChip
                if effectiveDue != nil || effectiveRecurrence != nil {
                    repeatChip
                }
                if let matrixChoice {
                    removableChip(MatrixGeometry.describe(matrixChoice), color: .accentColor) {
                        self.matrixChoice = nil
                    }
                }
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

    /// Tap steps through ! / !! / !!!; hold and slide picks an importance level 1–10.
    private var priorityChip: some View {
        let level = effectivePriority
        let title: String
        if let importanceChoice {
            title = "Importance \(importanceChoice)"
        } else {
            title = level == .normal ? "Priority" : level.marks
        }
        return HoldSlidePicker(options: (1...Matrix.levels).map(String.init), title: "Importance") {
            importanceChoice = nil
            priorityChoice = level.next
        } onPick: { index in
            importanceChoice = index + 1
        } label: {
            chipLabel(title, symbol: level == .normal && importanceChoice == nil ? "exclamationmark" : nil,
                      color: importanceChoice.map { Matrix.priority(forImportance: Matrix.importance(forLevel: $0)).color } ?? level.color,
                      active: level != .normal || importanceChoice != nil)
        }
        .accessibilityLabel("Priority")
        .accessibilityValue(importanceChoice.map { "Importance \($0)" } ?? level.title)
        .accessibilityHint("Tap to raise, touch and hold and slide toward a number to pick an importance from 1 to 10")
    }

    static let estimateOptions = PowerHours.presets.map { PowerHours.number($0) } + ["Custom…"]

    private func pickEstimate(_ index: Int) {
        guard index < PowerHours.presets.count else {
            showCustomEstimate = true
            return
        }
        estimateChoice = PowerHours.presets[index]
        add()
    }

    /// Drag the + up between two tasks to add one right there (what's typed, or an empty line to
    /// type into). It moves at once, no hold needed; a ghost follows the finger. A tap just
    /// starts typing.
    private var insertHandle: some View {
        Image(systemName: subtaskParent != nil ? "arrow.turn.down.right" : "plus.circle.fill")
            .font(.title2)
            .foregroundStyle(.tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: addedCount)
            .frame(minWidth: 30, minHeight: 30)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { drag in
                        if app.insertDragLocation == nil {
                            let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            app.insertDragTitle = isMultiline ? "" : (typed.isEmpty ? "" : parsed.title)
                        }
                        app.insertDragLocation = drag.location
                    }
                    .onEnded { drag in
                        app.insertDragLocation = nil
                        dropBetween(at: drag.location)
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: app.insertDragLocation != nil) { _, new in new }
            .accessibilityLabel("New task")
            .accessibilityHint("Drag up between two tasks to add one there")
    }

    private func dropBetween(at location: CGPoint) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var entry: ParsedEntry?
        if !typed.isEmpty, !isMultiline {
            var value = parsed
            value.priority = effectivePriority
            value.due = effectiveDue?.date
            value.dueHasTime = effectiveDue?.hasTime ?? false
            value.estimate = chosenEstimate
            value.recurrence = effectiveRecurrence
            entry = value
        }
        guard app.insertHandler?(location, entry) == true else { return }
        if entry != nil {
            text = ""
            resetChoices()
        }
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
            ForEach(GroupTree.ordered(groups), id: \.group.uuid) { item in
                Button {
                    groupChoice = .group(item.group.uuid)
                    disabled.insert(.group)
                } label: {
                    Label(GroupTree.path(of: item.group, in: groups), systemImage: item.group.symbol)
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

    private var estimateChip: some View {
        let value = effectiveEstimate
        return Menu {
            ForEach(PowerHours.presets, id: \.self) { preset in
                Button {
                    estimateChoice = preset
                } label: {
                    Label(PowerHours.format(preset), systemImage: preset == value ? "checkmark" : "timer")
                }
            }
            Button {
                showCustomEstimate = true
            } label: {
                Label("Custom…", systemImage: "slider.horizontal.3")
            }
            if value > 0 {
                Divider()
                Button(role: .destructive) {
                    estimateChoice = 0
                } label: {
                    Label("No Estimate", systemImage: "xmark.circle")
                }
            }
        } label: {
            // The default shows dimmed; a picked or typed estimate in colour.
            chipLabel(value > 0 ? PowerHours.format(value) : "No PH", symbol: "timer", color: .teal, active: chosenEstimate != nil && value > 0)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Estimate in Power Hours")
    }

    private var repeatChip: some View {
        let recurrence = effectiveRecurrence
        return Menu {
            ForEach(Recurrence.common, id: \.self) { option in
                Button {
                    recurrenceChoice = .set(option)
                } label: {
                    Label(option.title, systemImage: option == recurrence ? "checkmark" : "repeat")
                }
            }
            if recurrence != nil {
                Divider()
                Button(role: .destructive) {
                    recurrenceChoice = .never
                } label: {
                    Label("Don't Repeat", systemImage: "xmark.circle")
                }
            }
        } label: {
            chipLabel(recurrence?.title ?? "Repeat", symbol: "repeat", color: .indigo, active: recurrence != nil)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Repeat")
    }

    /// Drag it onto the full-screen grid; tapping only explains it, so it never gets in the way.
    private var matrixHandle: some View {
        Image(systemName: "square.grid.3x3")
            .font(.body.weight(.medium))
            .foregroundStyle(matrixChoice == nil ? Color.secondary.opacity(0.7) : Color.accentColor)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        let title = parsed.title.trimmingCharacters(in: .whitespaces)
                        app.matrixDrag = MatrixDrag(title: title, location: value.location)
                    }
                    .onEnded { value in
                        dropOnMatrix(at: value.location)
                    }
            )
            .onTapGesture {
                app.show("Drag the grid handle to set when it's due and how important it is", symbol: "square.grid.3x3")
            }
            .accessibilityLabel("Urgency and importance")
            .accessibilityHint("Drag onto the grid to set the deadline and importance")
    }

    private func dropOnMatrix(at location: CGPoint) {
        let frame = app.matrixCanvasFrame
        app.matrixDrag = nil
        guard frame.width > 0, frame.contains(location) else { return }
        matrixChoice = MatrixGeometry.cell(at: CGPoint(x: location.x - frame.minX, y: location.y - frame.minY), in: frame.size)
        // Dropping a typed task files it right away; without text it sets up the next one.
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { add() }
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
            entry.estimate = chosenEstimate
            entry.recurrence = effectiveRecurrence
            // Something that repeats needs a first date: today.
            if entry.recurrence != nil && entry.due == nil {
                entry.due = Calendar.current.startOfDay(for: app.dayStart)
            }
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
            if let matrixChoice {
                app.store.placeOnMatrix(task, days: matrixChoice.days, level: matrixChoice.level, today: app.dayStart)
            } else if let importanceChoice {
                app.store.setImportance([task], Matrix.importance(forLevel: importanceChoice))
            }
            if let plansFor { app.store.plan([task], for: plansFor) }
        }
        show(Confirmation(message: message, tasks: created))
        addedCount += 1
        text = ""
        resetChoices()
        // The group stays picked while adding several tasks; keep the keyboard up for rapid entry.
        focused = true
    }

    private func resetChoices() {
        disabled = []
        priorityChoice = nil
        importanceChoice = nil
        dueChoice = .fromText
        estimateChoice = nil
        recurrenceChoice = .fromText
        matrixChoice = nil
        subtaskOff = false
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
                if let estimateChoice { entry.estimate = estimateChoice > 0 ? estimateChoice : nil }
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
