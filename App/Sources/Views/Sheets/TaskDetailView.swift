import SwiftUI
import SwiftData
import TheoCore
#if os(iOS)
import UIKit
#endif

/// Full editor for one task. Each row's symbol sits in a column of its own, coloured by what it
/// means (the deadline blue, Power Hours and ongoing teal, the group brown); the rest is grey.
struct TaskDetailView: View {
    @Bindable var task: TaskItem
    /// Shown inside another view (the Mac's inspector) rather than as its own sheet.
    var embedded = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    /// All live tasks, so the subtask list refreshes when lines are added or changed.
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var liveTasks: [TaskItem]
    @State private var newTag = ""
    @State private var newSubtask = ""
    @FocusState private var subtaskFieldFocused: Bool
    /// "Pick…" shows the day picker (it stays open while the task is planned for such a day).
    @State private var picksDay = false
    /// Counts the picks (plan, deadline, priority), for the iPhone's selection tick.
    @State private var pickTick = 0
    /// The accent chosen in Settings: the subtask ring takes a colour rather than the tint. The
    /// app's own defaults, also inside the tour (its practice page has a store of its own).
    @AppStorage(Prefs.accent, store: UserDefaults.standard) private var accentRaw = AccentChoice.notes.rawValue

    private var accent: Color { (AccentChoice(rawValue: accentRaw) ?? .notes).color }

    #if os(macOS)
    @Environment(\.textScale) private var textScale
    private var ringSize: CGFloat { 11 * textScale }
    #else
    @ScaledMetric(relativeTo: .footnote) private var ringSize: CGFloat = 12
    #endif

    /// The title row's checkbox (22 pt with its 4 pt margins) and the gap after it, so the
    /// description lines up with the title.
    private static let titleInset: CGFloat = 40

    /// Subtasks in page order, with their depth below this task. An ongoing subtask's logs
    /// (older ones still sit in the block) aren't steps of their own.
    private var subtasks: [(task: TaskItem, depth: Int)] {
        let groupID = task.groupID
        let layout = SectionLayout(liveTasks.filter { $0.groupID == groupID })
        guard let index = layout.index(of: task) else { return [] }
        let end = layout.blockEnd(after: index)
        let base = layout.depths[index]
        return (index + 1..<end)
            .filter { layout.items[$0].loggedFor == nil }
            .map { (task: layout.items[$0], depth: layout.depths[$0] - base - 1) }
    }

    var body: some View {
        if embedded {
            form
        } else {
            NavigationStack {
                form
                    .navigationTitle("Details")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                task.touch()
                                app.store.save()
                                dismiss()
                            }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 560)
            #else
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .overlay(alignment: .bottom) { phoneToast }
            #endif
        }
    }

    #if os(iOS)
    /// On iPhone the sheet covers the page's toast, so the Undo of a change made here
    /// (plan chips, check-offs) shows inside the sheet too.
    @ViewBuilder private var phoneToast: some View {
        if UIDevice.current.userInterfaceIdiom == .phone, let toast = app.toast {
            ToastView(toast: toast) {
                Motion.animate(Motion.layout) { app.toast = nil }
            }
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    #endif

    /// Every field of the task, editable in place.
    private var form: some View {
        Form {
            titleSection
            planSection
            proposalSection
            subtaskSection
            prioritySection
            deadlineSection
            // Repeat & reminders, estimate and focus, and the folded ranking.
            TaskPlanningSections(task: task, embedded: embedded)
            ongoingSection
            organizeSection
            recordSections
        }
        .formStyle(.grouped)
        // The Mac's rows follow Theo's text size (the inspector and the sheet).
        .theoBodyFont()
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: pickTick)
        #endif
    }

    /// The checkbox and the title, with the description lined up under the title.
    private var titleSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                CheckCircle(done: task.isDone, priority: task.priority) {
                    Motion.animate(Motion.tap) { app.check(task) }
                }
                TextField("Title", text: $task.title, axis: .vertical)
                    .theoFont(.title3, weight: .semibold)
                    .textFieldStyle(.plain)
            }
            TextField("Description", text: $task.notes, axis: .vertical)
                .lineLimit(3...12)
                #if os(iOS)
                .padding(.leading, Self.titleInset)
                #endif
        }
    }

    /// What the task's group would give it, when it already had values of its own. Purple, like
    /// the "Suggested" on its line.
    @ViewBuilder private var proposalSection: some View {
        if task.traitProposalGroupID != nil, let proposal = app.store.traitProposal(for: task) {
            Section {
                Text(proposal.traits.summary.joined(separator: " · "))
                    .theoFont(.subheadline)
                HStack(spacing: 8) {
                    Button("Apply") {
                        Motion.animate(Motion.list) { app.store.acceptProposal(task, proposal.traits) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    Button("Keep Mine") {
                        Motion.animate(Motion.list) { app.store.dismissProposal(task) }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.gray)
                }
            } header: {
                Label {
                    Text("\(proposal.group.displayName) suggests")
                } icon: {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(.purple)
                }
            } footer: {
                Text("This group gives its tasks these values. This task already had its own, so nothing was changed.")
            }
        }
    }

    /// When it was created, finished or first planned, and Delete.
    @ViewBuilder private var recordSections: some View {
        // Metadata: smaller and quieter than the fields above.
        Section {
            LabeledContent("Created", value: task.createdAt.formatted(date: .abbreviated, time: .shortened))
                .theoFont(.subheadline)
            if let completed = task.completedAt {
                LabeledContent("Completed", value: completed.formatted(date: .abbreviated, time: .shortened))
                    .theoFont(.subheadline)
            } else if task.plannedDay != nil, let since = task.plannedSince {
                // When its current run of plans began (carrying it over keeps the day).
                LabeledContent("Planned since", value: since.formatted(date: .abbreviated, time: .omitted))
                    .theoFont(.subheadline)
            }
        }
        .foregroundStyle(.secondary)

        Section {
            Button(role: .destructive) {
                let target = task
                if !embedded { dismiss() }
                app.delete([target])
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }

    // MARK: - Plan

    /// Which plan chip is on.
    private enum PlanChoice {
        case off, today, tomorrow, nextWeek, other
    }

    private var todayKey: Date { Calendar.current.startOfDay(for: app.dayStart) }
    private var tomorrowKey: Date { DayBoundary.current.dayStart(byAdding: 1, to: app.dayStart) }
    private var nextWeekKey: Date { QuickDate.nextWeek.date(from: app.dayStart) }

    private var planChoice: PlanChoice {
        guard let planned = task.plannedDay else { return .off }
        let calendar = Calendar.current
        if calendar.isDate(planned, inSameDayAs: todayKey) { return .today }
        if calendar.isDate(planned, inSameDayAs: tomorrowKey) { return .tomorrow }
        if calendar.isDate(planned, inSameDayAs: nextWeekKey) { return .nextWeek }
        return .other
    }

    /// The day it's on the plan for, one tap each, with the same colours as everywhere:
    /// orange Today, indigo for later days, grey Off Plan. Every change has Undo.
    private var planSection: some View {
        let choice = planChoice
        // On a Sunday next Monday is tomorrow: both chips are on then.
        let nextWeekOn = choice == .nextWeek
            || (choice == .tomorrow && Calendar.current.isDate(nextWeekKey, inSameDayAs: tomorrowKey))
        return Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChipButton(title: "Today", symbol: "sun.max.fill", color: Tint.today, isOn: choice == .today) {
                        guard choice != .today else { return }
                        planChip { app.plan([task], for: app.dayStart) }
                    }
                    ChipButton(title: "Tomorrow", symbol: "moon.zzz.fill", color: Tint.tomorrow, isOn: choice == .tomorrow) {
                        guard choice != .tomorrow else { return }
                        planChip { app.deferToTomorrow([task]) }
                    }
                    ChipButton(title: QuickDate.nextWeek.title, symbol: QuickDate.nextWeek.symbol, color: Tint.planned, isOn: nextWeekOn) {
                        guard !nextWeekOn else { return }
                        planChip { app.plan([task], for: nextWeekKey) }
                    }
                    ChipButton(title: "Pick…", symbol: "calendar.badge.plus", color: Tint.planned, isOn: choice == .other) {
                        guard choice != .other else { return }
                        pickTick += 1
                        Motion.animate(Motion.list) { picksDay.toggle() }
                    }
                    ChipButton(title: "Off Plan", symbol: "calendar.badge.minus", color: Tint.offPlan, isOn: choice == .off) {
                        guard choice != .off else { return }
                        planChip { app.plan([task], for: nil) }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            if picksDay || choice == .other {
                DatePicker("Plan for", selection: pickedDayBinding, in: min(task.plannedDay ?? todayKey, todayKey)..., displayedComponents: [.date])
                    .transition(.opacity)
            }
        } header: {
            Text("Plan")
        } footer: {
            if let age = planAge {
                Text(age)
            }
        }
    }

    /// A plan chip's change: the day picker folds away as the plan moves, with a tick.
    private func planChip(_ change: () -> Void) {
        pickTick += 1
        Motion.animate(Motion.list) {
            picksDay = false
            change()
        }
    }

    /// The day in the picker: the planned one, or today until a day is picked. Picking a day
    /// plans the task for it.
    private var pickedDayBinding: Binding<Date> {
        Binding(
            get: { task.plannedDay ?? todayKey },
            set: { day in
                let key = Calendar.current.startOfDay(for: day)
                guard key != task.plannedDay else { return }
                Motion.animate(Motion.list) { app.plan([task], for: key) }
            }
        )
    }

    /// "Planned since Mon (3 days)" once it's been on the plan for a day without being done.
    private var planAge: String? {
        guard task.plannedDay != nil, !task.isDone, let since = task.plannedSince else { return nil }
        return PlanAge.describe(since: since, today: app.dayStart)
    }

    // MARK: - Subtasks

    private var subtaskSection: some View {
        let items = subtasks
        let done = items.filter { $0.task.isDone }.count
        return Section {
            ForEach(items, id: \.task.uuid) { item in
                SubtaskLine(task: item.task, depth: item.depth)
            }
            HStack(spacing: 10) {
                // As wide as a subtask's checkbox, so what's typed lines up with the titles.
                Image(systemName: "plus")
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                TextField("Add subtask", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .focused($subtaskFieldFocused)
                    .onSubmit(addSubtask)
                    #if os(iOS)
                    .submitLabel(.next)
                    #endif
            }
        } header: {
            subtaskHeader(done: done, total: items.count)
        }
    }

    /// "Subtasks", and once there are some, a ring and "2/5" like the line's own badge.
    private func subtaskHeader(done: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            Text("Subtasks")
            if total > 0 {
                MiniRing(fraction: Double(done) / Double(total), tint: accent, lineWidth: max(1.5, ringSize * 0.15))
                    .frame(width: ringSize, height: ringSize)
                Text("\(done)/\(total)")
                    .rollingNumber(done * 1000 + total)
            }
        }
    }

    private func addSubtask() {
        let title = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            subtaskFieldFocused = false
            return
        }
        // Like the composer, minus the group: a subtask stays in its parent's group.
        let entry = QuickParser.parse(
            title,
            groups: [],
            options: [.priority, .tags, .dates, .estimate, .ongoing, .recurrence],
            now: app.dayStart
        )
        Motion.animate(Motion.list) { _ = app.store.addSubtask(entry, to: task) }
        newSubtask = ""
        subtaskFieldFocused = true
    }

    // MARK: - Priority and deadline

    private var prioritySection: some View {
        Section("Priority") {
            Picker("Priority", selection: priorityBinding) {
                ForEach(Priority.allCases) { priority in
                    Text(priority == .normal ? "None" : priority.marks).tag(priority)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// Quick days, or a date (and a time) of its own. The calendar turns orange once the day
    /// has passed, like the line's "was due".
    private var deadlineSection: some View {
        Section("Deadline") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(QuickDate.allCases) { quick in
                        let date = quick.date(from: app.dayStart)
                        ChipButton(title: quick.title, symbol: quick.symbol, color: Tint.deadline, isOn: isDue(on: date)) {
                            pickTick += 1
                            Motion.animate(Motion.list) { app.store.setDue([task], isDue(on: date) ? nil : date) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            Toggle(isOn: hasDueBinding) {
                SheetRowLabel("Deadline", symbol: "calendar", color: isOverdue ? Tint.overdue : Tint.deadline)
            }
            if task.dueDate != nil {
                DatePicker(selection: dueBinding, displayedComponents: task.dueHasTime ? [.date, .hourAndMinute] : [.date]) {
                    SheetRowLabel("Date")
                }
                Toggle(isOn: hasTimeBinding) {
                    SheetRowLabel("Time", symbol: "clock", color: Tint.deadline)
                }
            }
        }
    }

    /// Still open, and due on a day that has passed.
    private var isOverdue: Bool {
        guard !task.isDone, let due = task.dueDate else { return false }
        return DateText.dayDelta(due, today: app.dayStart) < 0
    }

    private func isDue(on date: Date) -> Bool {
        guard let due = task.dueDate else { return false }
        return Calendar.current.isDate(due, inSameDayAs: date)
    }

    // MARK: - Ongoing and organize

    private var ongoingSection: some View {
        Section {
            Toggle(isOn: ongoingBinding) {
                SheetRowLabel("Ongoing", symbol: "infinity", color: Tint.ongoing)
            }
            if task.isOngoing, let last = task.lastDoneAt {
                LabeledContent {
                    Text(last.formatted(date: .abbreviated, time: .shortened))
                } label: {
                    SheetRowLabel("Last done")
                }
            }
        } footer: {
            Text("For work that never ends, like checking the account or answering mail: checking it off logs it for the day (with its Power Hours) and the task stays. Give it a deadline and a repeat to have it come back on its own.")
        }
    }

    private var organizeSection: some View {
        Section("Organize") {
            Picker(selection: groupBinding) {
                Label("Quick Entry", systemImage: "tray.and.arrow.down").tag(UUID?.none)
                ForEach(GroupTree.ordered(groups), id: \.group.uuid) { item in
                    Label(GroupTree.path(of: item.group, in: groups), systemImage: item.group.symbol).tag(UUID?.some(item.group.uuid))
                }
            } label: {
                SheetRowLabel("Group", symbol: "folder", color: Tint.move)
            }
            tagsRow
        }
    }

    /// The task's tags (tap one to take it off) and a field for another, lined up with the
    /// "Tags" title.
    private var tagsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetRowLabel("Tags", symbol: "number")
            if !task.tags.isEmpty {
                Label {
                    FlowTags(tags: task.tags) { tag in removeTag(tag) }
                } icon: {
                    SheetRowIcon()
                }
                .transition(.opacity)
            }
            Label {
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .onSubmit(addTag)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
            } icon: {
                SheetRowIcon(action: "plus")
            }
        }
    }

    private func addTag() {
        let tag = Tags.clean(newTag)
        guard !tag.isEmpty else { return }
        Motion.animate(Motion.tap) {
            task.tags = task.tags + [tag]
            task.touch()
        }
        newTag = ""
    }

    private func removeTag(_ tag: String) {
        Motion.animate(Motion.tap) {
            task.tags = task.tags.filter { $0 != tag }
            task.touch()
        }
    }

    // MARK: - Bindings

    private var priorityBinding: Binding<Priority> {
        Binding(
            get: { task.priority },
            set: { level in
                pickTick += 1
                Motion.animate(Motion.tap) { app.store.setPriority([task], level) }
            }
        )
    }

    private var hasDueBinding: Binding<Bool> {
        Binding(
            get: { task.dueDate != nil },
            set: { on in
                Motion.animate(Motion.list) {
                    task.dueDate = on ? Calendar.current.startOfDay(for: app.dayStart) : nil
                    if !on { task.dueHasTime = false }
                    task.touch()
                }
            }
        )
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0; task.touch() })
    }

    /// Switching the time on while the deadline still sits at midnight (already past today)
    /// picks one that can remind: the next full hour today, 9:00 on other days. Switching it
    /// off keeps the day. Saved at once, so the reminders follow.
    private var hasTimeBinding: Binding<Bool> {
        Binding(
            get: { task.dueHasTime },
            set: { on in
                guard on != task.dueHasTime else { return }
                Motion.animate(Motion.list) {
                    if on, let due = task.dueDate {
                        let suggested = DeadlineTime.suggested(for: due, today: app.dayStart, now: Date())
                        if suggested != due { task.dueDate = suggested }
                    }
                    task.dueHasTime = on
                    task.touch()
                }
                app.store.save()
            }
        )
    }

    private var ongoingBinding: Binding<Bool> {
        Binding(
            get: { task.isOngoing },
            set: { on in
                Motion.animate(Motion.list) { app.store.setOngoing([task], on) }
            }
        )
    }

    private var groupBinding: Binding<UUID?> {
        Binding(
            get: { task.groupID },
            set: { newValue in
                guard newValue != task.groupID else { return }
                Motion.animate(Motion.list) { app.store.move([task], toGroup: newValue) }
            }
        )
    }
}

/// One subtask inside the details sheet: check it off or rename it in place.
struct SubtaskLine: View {
    @Bindable var task: TaskItem
    let depth: Int

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            CheckCircle(done: task.isDone, priority: task.priority, size: 20) {
                Motion.animate(Motion.tap) { app.check(task) }
            }
            TextField("Subtask", text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                .animation(Motion.resolved(Motion.tap), value: task.isDone)
                .onChange(of: task.title) { _, _ in task.touch() }
        }
        .padding(.leading, CGFloat(depth) * 22)
        .swipeActions {
            Button(role: .destructive) {
                Motion.animate(Motion.list) { app.delete([task]) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// The task's tags as chips in their colours; tapping one takes it off.
struct FlowTags: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    RemovableTagChip(tag: tag) { onRemove(tag) }
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

/// One of the task's tags, in its colour, with the × that takes it off. Under the Mac's pointer
/// its fill deepens a little.
private struct RemovableTagChip: View {
    let tag: String
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        let color = TheoColor.forTag(tag).color
        Button(action: onRemove) {
            HStack(spacing: 4) {
                Text("#" + tag)
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .opacity(hovering ? 0.9 : 0.6)
            }
            .theoFont(.subheadline, weight: .medium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(hovering ? 0.2 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .help("Remove #" + tag)
        .accessibilityHint("Removes the tag")
    }
}

/// The symbol at the start of a row in the details and the sheets. It sits in a column of its
/// own, so the titles beside it line up, in the colour of what it means (`Tint`); neutral rows
/// keep it grey. Without a symbol the column stays empty, for a row that belongs to the one
/// above. A symbol that changes morphs into the new one.
struct SheetRowIcon: View {
    private let symbol: String?
    private let style: AnyShapeStyle

    #if os(macOS)
    @Environment(\.textScale) private var textScale
    private var width: CGFloat { 21 * textScale }
    #else
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 28
    #endif

    /// An empty column.
    init() {
        symbol = nil
        style = AnyShapeStyle(HierarchicalShapeStyle.secondary)
    }

    /// `color`: what the row means (`Tint`); nil keeps a neutral row grey.
    init(_ symbol: String, color: Color? = nil) {
        self.symbol = symbol
        style = color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(HierarchicalShapeStyle.secondary)
    }

    /// In the accent, like the title beside it: a row that does something (add, start).
    init(action symbol: String) {
        self.symbol = symbol
        style = AnyShapeStyle(TintShapeStyle.tint)
    }

    var body: some View {
        Image(systemName: symbol ?? "circle")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(style)
            .contentTransition(.symbolEffect(.replace))
            .opacity(symbol == nil ? 0 : 1)
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

/// A row's title after its `SheetRowIcon`.
struct SheetRowLabel: View {
    private let title: String
    private let icon: SheetRowIcon

    /// No symbol of its own: the title still lines up with the others.
    init(_ title: String) {
        self.title = title
        icon = SheetRowIcon()
    }

    /// `color`: what the row means (`Tint`); nil keeps a neutral row grey.
    init(_ title: String, symbol: String, color: Color? = nil) {
        self.title = title
        icon = SheetRowIcon(symbol, color: color)
    }

    /// A row that does something: the symbol in the accent, like the title.
    init(_ title: String, action symbol: String) {
        self.title = title
        icon = SheetRowIcon(action: symbol)
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            icon
        }
    }
}
