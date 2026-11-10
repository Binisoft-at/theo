import SwiftUI
import SwiftData
import TheoCore

/// Full editor for one task.
struct TaskDetailView: View {
    @Bindable var task: TaskItem

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

    /// Subtasks in page order, with their depth below this task.
    private var subtasks: [(task: TaskItem, depth: Int)] {
        let groupID = task.groupID
        let layout = SectionLayout(liveTasks.filter { $0.groupID == groupID })
        guard let index = layout.index(of: task) else { return [] }
        let end = layout.blockEnd(after: index)
        let base = layout.depths[index]
        return (index + 1..<end).map { (task: layout.items[$0], depth: layout.depths[$0] - base - 1) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        CheckCircle(done: task.isDone, priority: task.priority) {
                            withAnimation(.snappy) { app.store.toggle(task) }
                        }
                        TextField("Title", text: $task.title, axis: .vertical)
                            .font(.title3.weight(.semibold))
                            .textFieldStyle(.plain)
                    }
                    TextField("Notes", text: $task.notes, axis: .vertical)
                        .lineLimit(3...12)
                }

                if task.traitProposalGroupID != nil, let proposal = app.store.traitProposal(for: task) {
                    Section {
                        Text(proposal.traits.summary.joined(separator: " · "))
                            .font(.subheadline)
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

                Section {
                    Picker("Priority", selection: priorityBinding) {
                        ForEach(Priority.allCases) { priority in
                            Text(priority == .normal ? "None" : priority.marks).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Stepper(value: importanceLevelBinding, in: 1...Matrix.levels) {
                        LabeledContent("Importance", value: "\(task.importanceLevel) of \(Matrix.levels)")
                    }
                } header: {
                    Text("Importance")
                }

                Section("Deadline") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(QuickDate.allCases) { quick in
                                let date = quick.date(from: app.dayStart)
                                ChipButton(title: quick.title, symbol: quick.symbol, color: .orange, isOn: isDue(on: date)) {
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
                        Toggle(isOn: $task.dueHasTime) {
                            Label("Time", systemImage: "clock")
                        }
                    }
                    Toggle(isOn: plannedBinding) {
                        Label("Planned", systemImage: "calendar.badge.plus")
                    }
                    if let planned = task.plannedDay {
                        DatePicker(
                            "For",
                            selection: Binding(
                                get: { planned },
                                set: { app.store.plan([task], for: $0) }
                            ),
                            displayedComponents: [.date]
                        )
                    }
                }

                TaskPlanningSections(task: task)

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

                Section {
                    LabeledContent("Created", value: task.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let completed = task.completedAt {
                        LabeledContent("Completed", value: completed.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        let days = DayBoundary.current.days(from: task.createdAt, to: app.dayStart)
                        if days > 0 {
                            LabeledContent("Carried over", value: days == 1 ? "1 day" : "\(days) days")
                        }
                    }
                }
                .foregroundStyle(.secondary)

                Section {
                    Button(role: .destructive) {
                        let target = task
                        dismiss()
                        app.delete([target])
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)
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
        #endif
    }

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
        let entry = QuickParser.parse(title, groups: [], options: [.priority, .tags, .dates])
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

    private var importanceLevelBinding: Binding<Int> {
        Binding(get: { task.importanceLevel }, set: { app.store.setImportance([task], Matrix.importance(forLevel: $0)) })
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

    private var plannedBinding: Binding<Bool> {
        Binding(get: { task.plannedDay != nil }, set: { app.store.plan([task], for: $0 ? app.dayStart : nil) })
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
                withAnimation(.snappy) { app.store.toggle(task) }
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
                        .font(.subheadline.weight(.medium))
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
