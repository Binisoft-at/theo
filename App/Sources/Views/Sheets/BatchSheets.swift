import SwiftUI
import SwiftData
import TheoCore

/// Move one or more tasks into a group (or back to Quick Entry).
struct MoveSheet: View {
    let batch: TaskBatch

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @State private var newGroupName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: "Quick Entry", symbol: "tray.and.arrow.down.fill", color: .teal, id: nil)
                    ForEach(GroupTree.ordered(groups), id: \.group.uuid) { item in
                        row(title: item.group.displayName, symbol: item.group.symbol, color: item.group.color.color, id: item.group.uuid)
                            .padding(.leading, CGFloat(item.level) * 16)
                    }
                }
                Section("New Group") {
                    HStack {
                        TextField("Group name", text: $newGroupName)
                            .onSubmit(createAndMove)
                        Button("Create", action: createAndMove)
                            .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle(batch.tasks.count == 1 ? "Move Task" : "Move \(batch.tasks.count) Tasks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func row(title: String, symbol: String, color: Color, id: UUID?) -> some View {
        let current = batch.tasks.allSatisfy { $0.groupID == id }
        return Button {
            withAnimation(.snappy) { app.store.move(batch.tasks, toGroup: id) }
            app.endSelection()
            app.show("Moved to \(title)", symbol: "folder.fill")
            dismiss()
        } label: {
            HStack {
                Label {
                    Text(title).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(color)
                }
                Spacer()
                if current {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func createAndMove() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let group = app.store.addGroup(name: name, symbol: "list.bullet", color: TheoColor.forTag(name.lowercased()))
        withAnimation(.snappy) { app.store.move(batch.tasks, toGroup: group.uuid) }
        app.endSelection()
        dismiss()
    }
}

/// Deadline picker with quick choices.
struct DateSheet: View {
    let batch: TaskBatch

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var withTime = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(QuickDate.allCases) { quick in
                                ChipButton(title: quick.title, symbol: quick.symbol, isOn: false) {
                                    apply(quick.date(from: app.dayStart), time: false)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: withTime ? [.date, .hourAndMinute] : [.date])
                        .datePickerStyle(.graphical)
                    Toggle(isOn: $withTime) {
                        Label("Include Time", systemImage: "clock")
                    }
                }
                if batch.tasks.contains(where: { $0.dueDate != nil }) {
                    Section {
                        Button(role: .destructive) {
                            app.store.setDue(batch.tasks, nil)
                            app.endSelection()
                            dismiss()
                        } label: {
                            Label("Remove Deadline", systemImage: "calendar.badge.minus")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Deadline")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") { apply(date, time: withTime) }
                }
            }
            .onAppear {
                if let existing = batch.tasks.first?.dueDate {
                    date = existing
                    withTime = batch.tasks.first?.dueHasTime ?? false
                } else {
                    date = Calendar.current.date(byAdding: .day, value: 1, to: app.dayStart) ?? Date()
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 520)
        #else
        .presentationDetents([.large])
        #endif
    }

    private func apply(_ date: Date, time: Bool) {
        app.store.setDue(batch.tasks, date, hasTime: time)
        app.endSelection()
        dismiss()
    }
}

/// Add or remove tags on tasks.
struct TagSheet: View {
    let batch: TaskBatch

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false })
    private var openTasks: [TaskItem]
    @State private var newTag = ""

    var body: some View {
        let known = Sections.tags(in: openTasks)
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "number").foregroundStyle(.secondary)
                        TextField("New tag", text: $newTag)
                            .onSubmit(addNew)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        Button("Add", action: addNew)
                            .disabled(Tags.clean(newTag).isEmpty)
                    }
                }
                if !known.isEmpty {
                    Section("Tags") {
                        ForEach(known, id: \.self) { tag in
                            let all = batch.tasks.allSatisfy { $0.tags.contains(tag) }
                            Button {
                                toggle(tag, on: !all)
                            } label: {
                                HStack {
                                    TagChip(tag: tag, compact: false)
                                    Spacer()
                                    if all { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        app.endSelection()
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 400)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func addNew() {
        let tag = Tags.clean(newTag)
        guard !tag.isEmpty else { return }
        toggle(tag, on: true)
        newTag = ""
    }

    private func toggle(_ tag: String, on: Bool) {
        for task in batch.tasks {
            task.tags = on ? task.tags + [tag] : task.tags.filter { $0 != tag }
            task.touch()
        }
        app.store.save()
    }
}
