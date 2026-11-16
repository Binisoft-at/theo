import SwiftUI
import SwiftData
import TheoCore

/// Move one or more tasks into a group (or back to Quick Entry). Each group shows its icon on a
/// small disc in its colour, like the lists in Reminders.
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
                        row(title: item.group.displayName, symbol: item.group.symbol, color: item.group.color.color, id: item.group.uuid,
                            adds: traits(of: item.group).summary)
                            .padding(.leading, CGFloat(item.level) * 16)
                    }
                } footer: {
                    if groups.isEmpty {
                        Text(batch.tasks.count == 1
                            ? "No groups yet. Name one below and the task moves into it."
                            : "No groups yet. Name one below and the tasks move into it.")
                    }
                }
                Section("New Group") {
                    Label {
                        HStack {
                            TextField("Group name", text: $newGroupName)
                                .onSubmit(createAndMove)
                            Button("Create", action: createAndMove)
                                .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } icon: {
                        MoveSheetGroupDisc(symbol: "plus", color: .gray)
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

    /// `adds`: what the group's traits give the tasks moved in (shown under its name).
    private func row(title: String, symbol: String, color: Color, id: UUID?, adds: [String] = []) -> some View {
        let current = batch.tasks.allSatisfy { $0.groupID == id }
        return Button {
            // app.move shows "Moved to …" with Undo.
            Motion.animate(Motion.list) { app.move(batch.tasks, toGroup: id) }
            // On the Mac the list moves the selection on to the next line itself.
            #if os(iOS)
            app.endSelection()
            #endif
            dismiss()
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).foregroundStyle(.primary)
                        if !adds.isEmpty && !current {
                            Text("Adds: " + adds.joined(separator: " · "))
                                .theoFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    MoveSheetGroupDisc(symbol: symbol, color: color)
                }
                Spacer()
                if current {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    /// A group's traits with what it inherits from the groups it sits in (like
    /// `TaskStore.traits(of:)`, from the groups this sheet already has).
    private func traits(of group: TaskGroup) -> GroupTraits {
        var result = group.ownTraits
        var seen: Set<UUID> = [group.uuid]
        var current = group
        while let parentID = current.parentUUID, !seen.contains(parentID), let parent = groups.first(where: { $0.uuid == parentID }) {
            result = result.inheriting(from: parent.ownTraits)
            seen.insert(parentID)
            current = parent
        }
        return result
    }

    private func createAndMove() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let group = app.store.addGroup(name: name, symbol: "list.bullet", color: TheoColor.forTag(name.lowercased()))
        Motion.animate(Motion.list) { app.move(batch.tasks, toGroup: group.uuid) }
        #if os(iOS)
        app.endSelection()
        #endif
        dismiss()
    }
}

/// A group's icon in white on a small disc in its colour.
private struct MoveSheetGroupDisc: View {
    let symbol: String
    let color: Color

    #if os(macOS)
    @Environment(\.textScale) private var textScale
    private var size: CGFloat { 20 * textScale }
    #else
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 28
    #endif

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.gradient))
            .accessibilityHidden(true)
    }
}

/// Deadline picker with quick choices. Blue, the deadline's colour everywhere.
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
                                let day = quick.date(from: app.dayStart)
                                ChipButton(title: quick.title, symbol: quick.symbol, color: Tint.deadline, isOn: allDue(on: day)) {
                                    apply(day, time: false)
                                }
                            }
                        }
                    }
                    .scrollClipDisabled()
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: withTime ? [.date, .hourAndMinute] : [.date])
                        .datePickerStyle(.graphical)
                        .tint(Tint.deadline)
                    Toggle(isOn: $withTime.animation(Motion.resolved(Motion.list))) {
                        SheetRowLabel("Include Time", symbol: "clock", color: Tint.deadline)
                    }
                }
                if batch.tasks.contains(where: { $0.dueDate != nil }) {
                    Section {
                        Button(role: .destructive) {
                            // The selection stays, so more changes can follow.
                            Motion.animate(Motion.list) { app.store.setDue(batch.tasks, nil) }
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

    /// Every task is already due that day: its chip shows it.
    private func allDue(on day: Date) -> Bool {
        guard !batch.tasks.isEmpty else { return false }
        return batch.tasks.allSatisfy { task in
            task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false
        }
    }

    private func apply(_ date: Date, time: Bool) {
        Motion.animate(Motion.list) { app.store.setDue(batch.tasks, date, hasTime: time) }
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
    /// Counts tag taps, for the iPhone's selection tick.
    @State private var pickTick = 0

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
                if known.isEmpty {
                    Section {
                        EmptyHint(symbol: "number", title: "No tags yet",
                                  message: "Add one above. The tags on your open tasks show up here, one tap to add or remove.")
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section("Tags") {
                        ForEach(known, id: \.self) { tag in
                            tagRow(tag)
                        }
                    }
                }
            }
            #if os(iOS)
            .sensoryFeedback(.selection, trigger: pickTick)
            #endif
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

    /// A tag in its colour, with a check when every task has it. A tap adds or removes it.
    private func tagRow(_ tag: String) -> some View {
        let all = batch.tasks.allSatisfy { $0.tags.contains(tag) }
        return Button {
            pickTick += 1
            Motion.animate(Motion.tap) { toggle(tag, on: !all) }
        } label: {
            HStack {
                TagChip(tag: tag, compact: false)
                Spacer()
                if all {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(all ? .isSelected : [])
    }

    private func addNew() {
        let tag = Tags.clean(newTag)
        guard !tag.isEmpty else { return }
        Motion.animate(Motion.list) { toggle(tag, on: true) }
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
