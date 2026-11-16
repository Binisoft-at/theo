import SwiftUI
import SwiftData
import TheoCore
#if os(iOS)
import UIKit
#endif

/// Full editor for one task.
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
                withAnimation(.snappy) { app.toast = nil }
            }
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    #endif

    /// Every field of the task, editable in place.
    private var form: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    CheckCircle(done: task.isDone, priority: task.priority) {
                        withAnimation(.snappy) { app.check(task) }
                    }
                    TextField("Title", text: $task.title, axis: .vertical)
                        .theoFont(.title3, weight: .semibold)
                        .textFieldStyle(.plain)
                }
                TextField("Description", text: $task.notes, axis: .vertical)
                    .lineLimit(3...12)
            }

            planSection

            if task.traitProposalGroupID != nil, let proposal = app.store.traitProposal(for: task) {
                Section {
                    Text(proposal.traits.summary.joined(separator: " · "))
                        .theoFont(.subheadline)
                    HStack {
                        Button("Apply") {
                            withAnimation(.snappy) { app.store.acceptProposal(task, proposal.traits) }
                        }
                        .buttonStyle(.glassProminent)
                        Button("Keep Mine") {
                            withAnimation(.snappy) { app.store.dismissProposal(task) }
                        }
                        .buttonStyle(.glass)
                    }
                } header: {
                    Label("\(proposal.group.displayName) suggests", systemImage: "wand.and.stars")
                } footer: {
                    Text("This group gives its tasks these values. This task already had its own, so nothing was changed.")
                }
            }

            subtaskSection

            Section("Priority") {
                Picker("Priority", selection: priorityBinding) {
                    ForEach(Priority.allCases) { priority in
                        Text(priority == .normal ? "None" : priority.marks).tag(priority)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Deadline") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(QuickDate.allCases) { quick in
                            let date = quick.date(from: app.dayStart)
                            ChipButton(title: quick.title, symbol: quick.symbol, color: .blue, isOn: isDue(on: date)) {
                                app.store.setDue([task], isDue(on: date) ? nil : date)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
                Toggle(isOn: hasDueBinding) {
                    Label("Deadline", systemImage: "calendar")
                }
                if task.dueDate != nil {
                    DatePicker(
                        "Date",
                        selection: dueBinding,
                        displayedComponents: task.dueHasTime ? [.date, .hourAndMinute] : [.date]
                    )
                    Toggle(isOn: hasTimeBinding) {
                        Label("Time", systemImage: "clock")
                    }
                }
            }

            // Repeat & reminders, estimate and focus, and the folded ranking.
            TaskPlanningSections(task: task, embedded: embedded)

            Section {
                Toggle(isOn: Binding(
                    get: { task.isOngoing },
                    set: { app.store.setOngoing([task], $0) }
                )) {
                    Label("Ongoing", systemImage: "infinity")
                }
                if task.isOngoing, let last = task.lastDoneAt {
                    LabeledContent("Last done", value: last.formatted(date: .abbreviated, time: .shortened))
                }
            } footer: {
                Text("For work that never ends, like checking the account or answering mail: checking it off logs it for the day (with its Power Hours) and the task stays. Give it a deadline and a repeat to have it come back on its own.")
            }

            Section("Organize") {
                Picker(selection: groupBinding) {
                    Label("Quick Entry", systemImage: "tray.and.arrow.down").tag(UUID?.none)
                    ForEach(GroupTree.ordered(groups), id: \.group.uuid) { item in
                        Label(GroupTree.path(of: item.group, in: groups), systemImage: item.group.symbol).tag(UUID?.some(item.group.uuid))
                    }
                } label: {
                    Label("Group", systemImage: "folder")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tags", systemImage: "number")
                    if !task.tags.isEmpty {
                        FlowTags(tags: task.tags) { tag in
                            task.tags = task.tags.filter { $0 != tag }
                            task.touch()
                        }
                    }
                    TextField("Add tag", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTag)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                }
            }

            recordSections
        }
        .formStyle(.grouped)
        // The Mac's rows follow Theo's text size (the inspector and the sheet).
        .theoBodyFont()
    }

    /// When it was created, finished or first planned, and Delete.
    @ViewBuilder private var recordSections: some View {
        Section {
            LabeledContent("Created", value: task.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let completed = task.completedAt {
                LabeledContent("Completed", value: completed.formatted(date: .abbreviated, time: .shortened))
            } else if task.plannedDay != nil, let since = task.plannedSince {
                // When its current run of plans began (carrying it over keeps the day).
                LabeledContent("Planned since", value: since.formatted(date: .abbreviated, time: .omitted))
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
                    ChipButton(title: "Today", symbol: "sun.max.fill", color: .orange, isOn: choice == .today) {
                        guard choice != .today else { return }
                        picksDay = false
                        withAnimation(.snappy) { app.plan([task], for: app.dayStart) }
                    }
                    ChipButton(title: "Tomorrow", symbol: "moon.zzz.fill", color: .indigo, isOn: choice == .tomorrow) {
                        guard choice != .tomorrow else { return }
                        picksDay = false
                        withAnimation(.snappy) { app.deferToTomorrow([task]) }
                    }
                    ChipButton(title: QuickDate.nextWeek.title, symbol: QuickDate.nextWeek.symbol, color: .indigo, isOn: nextWeekOn) {
                        guard !nextWeekOn else { return }
                        picksDay = false
                        withAnimation(.snappy) { app.plan([task], for: nextWeekKey) }
                    }
                    ChipButton(title: "Pick…", symbol: "calendar", color: .indigo, isOn: choice == .other) {
                        guard choice != .other else { return }
                        withAnimation(.snappy) { picksDay.toggle() }
                    }
                    ChipButton(title: "Off Plan", symbol: "calendar.badge.minus", color: .gray, isOn: choice == .off) {
                        guard choice != .off else { return }
                        picksDay = false
                        withAnimation(.snappy) { app.plan([task], for: nil) }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            if picksDay || choice == .other {
                DatePicker("Plan for", selection: pickedDayBinding, in: min(task.plannedDay ?? todayKey, todayKey)..., displayedComponents: [.date])
            }
        } header: {
            Text("Plan")
        } footer: {
            if let age = planAge {
                Text(age)
            }
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
                withAnimation(.snappy) { app.plan([task], for: key) }
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
        Section {
            ForEach(subtasks, id: \.task.uuid) { item in
                SubtaskLine(task: item.task, depth: item.depth)
            }
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .foregroundStyle(.tint)
                    .frame(width: 22)
                TextField("Add subtask", text: $newSubtask)
                    .textFieldStyle(.plain)
                    .focused($subtaskFieldFocused)
                    .onSubmit(addSubtask)
                    #if os(iOS)
                    .submitLabel(.next)
                    #endif
            }
        } header: {
            Text(subtasks.isEmpty ? "Subtasks" : "Subtasks · \(subtasks.filter { $0.task.isDone }.count)/\(subtasks.count)")
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
        withAnimation(.snappy) { _ = app.store.addSubtask(entry, to: task) }
        newSubtask = ""
        subtaskFieldFocused = true
    }

    private func isDue(on date: Date) -> Bool {
        guard let due = task.dueDate else { return false }
        return Calendar.current.isDate(due, inSameDayAs: date)
    }

    private func addTag() {
        let tag = Tags.clean(newTag)
        guard !tag.isEmpty else { return }
        task.tags = task.tags + [tag]
        task.touch()
        newTag = ""
    }

    private var priorityBinding: Binding<Priority> {
        Binding(get: { task.priority }, set: { app.store.setPriority([task], $0) })
    }

    private var hasDueBinding: Binding<Bool> {
        Binding(
            get: { task.dueDate != nil },
            set: { on in
                task.dueDate = on ? Calendar.current.startOfDay(for: app.dayStart) : nil
                if !on { task.dueHasTime = false }
                task.touch()
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
                if on, let due = task.dueDate {
                    let suggested = DeadlineTime.suggested(for: due, today: app.dayStart, now: Date())
                    if suggested != due { task.dueDate = suggested }
                }
                task.dueHasTime = on
                task.touch()
                app.store.save()
            }
        )
    }

    private var groupBinding: Binding<UUID?> {
        Binding(
            get: { task.groupID },
            set: { newValue in
                guard newValue != task.groupID else { return }
                app.store.move([task], toGroup: newValue)
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
                withAnimation(.snappy) { app.check(task) }
            }
            TextField("Subtask", text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                .onChange(of: task.title) { _, _ in task.touch() }
        }
        .padding(.leading, CGFloat(depth) * 22)
        .swipeActions {
            Button(role: .destructive) {
                app.delete([task])
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Wrapping tag chips with a remove button.
struct FlowTags: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        onRemove(tag)
                    } label: {
                        HStack(spacing: 4) {
                            Text("#" + tag)
                            Image(systemName: "xmark.circle.fill")
                                .imageScale(.small)
                                .opacity(0.6)
                        }
                        .theoFont(.subheadline, weight: .medium)
                        .foregroundStyle(TheoColor.forTag(tag).color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(TheoColor.forTag(tag).color.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
