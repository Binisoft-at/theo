import SwiftUI
import SwiftData

/// Full editor for one task.
struct TaskDetailView: View {
    @Bindable var task: TaskItem

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @State private var newTag = ""

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
                    Toggle(isOn: deferredBinding) {
                        Label("Hide from Today until…", systemImage: "moon.zzz")
                    }
                    if let deferred = task.deferredUntil {
                        DatePicker(
                            "Show again on",
                            selection: Binding(
                                get: { deferred },
                                set: { task.deferredUntil = DayBoundary().start(of: $0); task.touch() }
                            ),
                            displayedComponents: [.date]
                        )
                    }
                }

                Section("Organize") {
                    Picker(selection: groupBinding) {
                        Label("Quick Entry", systemImage: "tray.and.arrow.down").tag(UUID?.none)
                        ForEach(groups) { group in
                            Label(group.displayName, systemImage: group.symbol).tag(UUID?.some(group.uuid))
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
                        let days = DayBoundary().days(from: task.createdAt, to: app.dayStart)
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

    private func addTag() {
        let tag = Tags.clean(newTag)
        guard !tag.isEmpty else { return }
        task.tags = task.tags + [tag]
        task.touch()
        newTag = ""
    }

    private var priorityBinding: Binding<Priority> {
        Binding(get: { task.priority }, set: { task.priority = $0; task.touch() })
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

    private var deferredBinding: Binding<Bool> {
        Binding(
            get: { task.deferredUntil != nil },
            set: { on in
                task.deferredUntil = on ? DayBoundary().dayStart(byAdding: 1, to: app.dayStart) : nil
                task.touch()
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
