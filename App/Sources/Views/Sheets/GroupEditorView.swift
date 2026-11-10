import SwiftUI
import SwiftData
import TheoCore

/// Create or edit a group: name, icon, color, project settings.
struct GroupEditorView: View {
    let target: GroupEditorTarget

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    @State private var name = ""
    @State private var symbol = "list.bullet"
    @State private var color: TheoColor = .blue
    @State private var isProject = false
    @State private var hasDue = false
    @State private var due = Date()
    @State private var notes = ""
    @State private var parentID: UUID?
    @State private var isActive = true
    /// Traits: 0 / -1 / "" mean none.
    @State private var traitLevel = 0
    @State private var traitEstimate = -1.0
    @State private var traitTags = ""
    @State private var traitDueDays = -1
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private var existing: TaskGroup? {
        if case .edit(let group) = target { return group }
        return nil
    }

    /// Groups this one can sit inside: anything but itself and its own subprojects.
    private var parentOptions: [(group: TaskGroup, level: Int)] {
        guard let existing else { return GroupTree.ordered(groups) }
        let excluded = Set([existing.uuid] + GroupTree.descendants(of: existing.uuid, in: groups).map(\.uuid))
        return GroupTree.ordered(groups).filter { !excluded.contains($0.group.uuid) }
    }

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: symbol)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(color.color.gradient))
                        TextField("Group name", text: $name)
                            .font(.title3.weight(.semibold))
                            .textFieldStyle(.plain)
                            .focused($nameFocused)
                            .onSubmit(save)
                    }
                    .padding(.vertical, 4)
                }

                Section("Color") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(TheoColor.allCases) { option in
                            Button {
                                color = option
                            } label: {
                                Circle()
                                    .fill(option.color.gradient)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if option == color {
                                            Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 2.5).padding(-4)
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(GroupSymbols.all, id: \.self) { option in
                            Button {
                                symbol = option
                            } label: {
                                Image(systemName: option)
                                    .font(.body)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(option == symbol ? Color.white : Color.primary)
                                    .background(Circle().fill(option == symbol ? AnyShapeStyle(color.color) : AnyShapeStyle(Color.secondary.opacity(0.12))))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker(selection: $parentID) {
                        Text("Top Level").tag(UUID?.none)
                        ForEach(parentOptions, id: \.group.uuid) { option in
                            Text(String(repeating: "   ", count: option.level) + option.group.displayName)
                                .tag(UUID?.some(option.group.uuid))
                        }
                    } label: {
                        Label("Inside", systemImage: "folder")
                    }
                } footer: {
                    Text("Put a group inside another one to make it a subproject.")
                }

                Section {
                    Toggle(isOn: $isActive) {
                        Label("On", systemImage: isActive ? "play.circle" : "pause.circle")
                    }
                } footer: {
                    Text("Switched off, its tasks (and its subgroups') stay out of Today, Plan, Upcoming and the other lists until you switch it back on. They stay on its own page.")
                }

                traitsSection

                Section {
                    Toggle(isOn: $isProject) {
                        Label("Project", systemImage: "chart.bar.fill")
                    }
                    if isProject {
                        Toggle(isOn: $hasDue) {
                            Label("Deadline", systemImage: "flag.checkered")
                        }
                        if hasDue {
                            DatePicker("Date", selection: $due, displayedComponents: [.date])
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                } footer: {
                    Text("Projects show a progress bar and an optional deadline.")
                }

                if let existing {
                    Section {
                        Button(role: .destructive) {
                            dismiss()
                            app.store.deleteGroup(existing, keepTasks: true)
                            if app.selection == .group(existing.uuid) { app.go(.today) }
                            let model = app
                            model.show("Group deleted · tasks moved to Quick Entry", symbol: "trash.fill") {
                                model.store.restoreGroup(existing)
                            }
                        } label: {
                            Label("Delete Group (Keep Tasks)", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing != nil ? "Edit Group" : (parentID == nil ? "New Group" : "New Subproject"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Create" : "Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 600)
        #endif
    }

    /// Traits new and moved tasks inherit.
    private var traitsSection: some View {
        Section {
            Picker(selection: $traitLevel) {
                Text("None").tag(0)
                ForEach((1...Matrix.levels).reversed(), id: \.self) { level in
                    Text(Self.levelTitle(level)).tag(level)
                }
            } label: {
                Label("Importance", systemImage: "exclamationmark.3")
            }
            Picker(selection: $traitEstimate) {
                Text("None").tag(-1.0)
                Text("No estimate").tag(0.0)
                ForEach(PowerHours.presets, id: \.self) { value in
                    Text(PowerHours.format(value)).tag(value)
                }
            } label: {
                Label("Power Hours", systemImage: "timer")
            }
            Picker(selection: $traitDueDays) {
                Text("None").tag(-1)
                Text("Today").tag(0)
                Text("Tomorrow").tag(1)
                ForEach([2, 3, 5, 7, 14], id: \.self) { days in
                    Text("In \(days) days").tag(days)
                }
            } label: {
                Label("Deadline", systemImage: "calendar")
            }
            HStack {
                Label("Tags", systemImage: "number")
                TextField("e.g. work, calls", text: $traitTags)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }
            if let parent = groups.first(where: { $0.uuid == parentID }) {
                let inherited = app.store.traits(of: parent)
                if !inherited.isEmpty {
                    Label("Inherits from \(parent.displayName): " + inherited.summary.joined(separator: " · "), systemImage: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let existing, !existing.liveTasks.filter({ !$0.isDone }).isEmpty, !currentTraits.isEmpty {
                Button {
                    applyToExisting(existing)
                } label: {
                    Label("Apply to the \(existing.liveTasks.filter { !$0.isDone }.count) Open Tasks Here", systemImage: "wand.and.stars")
                }
            }
        } header: {
            Text("Tasks Placed Here Get")
        } footer: {
            Text("New and moved tasks take these where they have nothing of their own. Where a task already has something else, it shows a suggestion instead and keeps its own. Subgroups inherit these unless they set their own.")
        }
    }

    /// "8  !!".
    private static func levelTitle(_ level: Int) -> String {
        let marks = Matrix.priority(forImportance: Matrix.importance(forLevel: level)).marks
        return marks.isEmpty ? "\(level)" : "\(level)  \(marks)"
    }

    private var currentTraits: GroupTraits {
        GroupTraits(
            importance: traitLevel > 0 ? Matrix.importance(forLevel: traitLevel) : nil,
            estimate: traitEstimate >= 0 ? traitEstimate : nil,
            tags: traitTags.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased() }
                .filter { !$0.isEmpty },
            dueDays: traitDueDays >= 0 ? traitDueDays : nil
        )
    }

    private func applyToExisting(_ group: TaskGroup) {
        save(dismissing: false)
        let tasks = group.liveTasks.filter { !$0.isDone }
        for task in tasks { app.store.applyTraits(to: task, propose: true) }
        app.store.save()
        app.show("Applied to \(tasks.count) task\(tasks.count == 1 ? "" : "s") · differences are suggested", symbol: "wand.and.stars")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            isActive = existing.isActive
            let traits = existing.ownTraits
            traitLevel = traits.importance.map { Matrix.level(forImportance: $0) } ?? 0
            traitEstimate = traits.estimate ?? -1
            traitTags = traits.tags.joined(separator: ", ")
            traitDueDays = traits.dueDays ?? -1
            name = existing.name
            symbol = existing.symbol
            color = existing.color
            isProject = existing.isProject
            notes = existing.notes
            if let date = existing.dueDate {
                hasDue = true
                due = date
            }
            parentID = existing.parentUUID
        } else {
            if case .subgroup(let parent) = target { parentID = parent.uuid }
            color = TheoColor.allCases.randomElement() ?? .blue
            nameFocused = true
        }
    }

    private func save() {
        save(dismissing: true)
    }

    private func save(dismissing: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let group = existing ?? app.store.addGroup(name: trimmed, symbol: symbol, color: color, parent: parentID)
        app.store.setParent(group, parentID)
        group.name = trimmed
        group.symbol = symbol
        group.color = color
        group.isProject = isProject
        group.dueDate = isProject && hasDue ? Calendar.current.startOfDay(for: due) : nil
        group.notes = notes
        group.isActive = isActive
        group.ownTraits = currentTraits
        group.touch()
        app.store.save()
        if dismissing { dismiss() }
    }
}
