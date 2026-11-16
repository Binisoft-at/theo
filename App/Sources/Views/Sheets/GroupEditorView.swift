import SwiftUI
import SwiftData
import TheoCore

/// Create or edit a group: name, icon, color, project settings. The group's icon sits large at
/// the top in its colour and changes as you pick, like a new list in Reminders.
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
    /// Counts colour and icon picks, for the iPhone's selection tick.
    @State private var pickTick = 0
    @FocusState private var nameFocused: Bool
    /// The selection ring and disc glide from one choice to the next.
    @Namespace private var pickerSpace

    private var existing: TaskGroup? {
        if case .edit(let group) = target { return group }
        return nil
    }

    /// Groups this one can sit inside: anything but itself and its own subgroups.
    private var parentOptions: [(group: TaskGroup, level: Int)] {
        guard let existing else { return GroupTree.ordered(groups) }
        let excluded = Set([existing.uuid] + GroupTree.descendants(of: existing.uuid, in: groups).map(\.uuid))
        return GroupTree.ordered(groups).filter { !excluded.contains($0.group.uuid) }
    }

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                colorSection
                iconSection
                parentSection
                activeSection
                traitsSection
                projectSection
                deleteSection
            }
            .formStyle(.grouped)
            .theoBodyFont()
            #if os(iOS)
            .sensoryFeedback(.selection, trigger: pickTick)
            #endif
            .navigationTitle(existing != nil ? "Edit Group" : (parentID == nil ? "New Group" : "New Subgroup"))
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

    // MARK: - Look

    /// The group as it will look: its icon in its colour, and its name.
    private var headerSection: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 80, height: 80)
                    .background(Circle().fill(color.color.gradient))
                    .shadow(color: color.color.opacity(0.3), radius: 8, y: 4)
                    .accessibilityHidden(true)
                TextField("Group name", text: $name)
                    .theoFont(.title3, weight: .semibold)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(save)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.1)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var colorSection: some View {
        Section("Color") {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(TheoColor.allCases) { option in
                    colorSwatch(option)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// A colour to pick; the ring around the chosen one glides to the next.
    private func colorSwatch(_ option: TheoColor) -> some View {
        let selected = option == color
        return Button {
            guard !selected else { return }
            pickTick += 1
            Motion.animate(Motion.tap) { color = option }
        } label: {
            ZStack {
                if selected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.55), lineWidth: 2.5)
                        .matchedGeometryEffect(id: "colorRing", in: pickerSpace)
                }
                Circle()
                    .fill(option.color.gradient)
                    .padding(4)
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var iconSection: some View {
        Section("Icon") {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(GroupSymbols.all, id: \.self) { option in
                    iconChoice(option)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// An icon to pick; the chosen one sits on a disc in the group's colour, which glides to
    /// the next.
    private func iconChoice(_ option: String) -> some View {
        let selected = option == symbol
        return Button {
            guard !selected else { return }
            pickTick += 1
            Motion.animate(Motion.tap) { symbol = option }
        } label: {
            Image(systemName: option)
                .font(.body)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 40, height: 40)
                .background {
                    ZStack {
                        Circle().fill(Color.secondary.opacity(0.12))
                        if selected {
                            Circle()
                                .fill(color.color.gradient)
                                .matchedGeometryEffect(id: "iconDisc", in: pickerSpace)
                        }
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Place

    private var parentSection: some View {
        Section {
            Picker(selection: $parentID.animation(Motion.resolved(Motion.list))) {
                Text("Top Level").tag(UUID?.none)
                ForEach(parentOptions, id: \.group.uuid) { option in
                    Text(String(repeating: "   ", count: option.level) + option.group.displayName)
                        .tag(UUID?.some(option.group.uuid))
                }
            } label: {
                SheetRowLabel("Inside", symbol: "folder", color: Tint.move)
            }
        } footer: {
            Text("Put a group inside another one to make it a subgroup.")
        }
    }

    private var activeSection: some View {
        Section {
            Toggle(isOn: $isActive.animation(Motion.resolved(Motion.tap))) {
                SheetRowLabel("On", symbol: isActive ? "play.circle" : "pause.circle")
            }
        } footer: {
            Text("Switched off, its tasks (and its subgroups') stay out of Today, Plan, Upcoming and the other lists until you switch it back on. They stay on its own page.")
        }
    }

    /// Traits new and moved tasks inherit.
    private var traitsSection: some View {
        Section {
            Picker(selection: $traitLevel.animation(Motion.resolved(Motion.list))) {
                Text("None").tag(0)
                ForEach((1...Matrix.levels).reversed(), id: \.self) { level in
                    Text(Self.levelTitle(level)).tag(level)
                }
            } label: {
                SheetRowLabel("Importance", symbol: "exclamationmark", color: Tint.priority)
            }
            Picker(selection: $traitEstimate.animation(Motion.resolved(Motion.list))) {
                Text("None").tag(-1.0)
                Text("No estimate").tag(0.0)
                ForEach(PowerHours.presets, id: \.self) { value in
                    Text(PowerHours.format(value)).tag(value)
                }
            } label: {
                SheetRowLabel("Power Hours", symbol: "timer", color: Tint.powerHours)
            }
            Picker(selection: $traitDueDays.animation(Motion.resolved(Motion.list))) {
                Text("None").tag(-1)
                Text("Today").tag(0)
                Text("Tomorrow").tag(1)
                ForEach([2, 3, 5, 7, 14], id: \.self) { days in
                    Text("In \(days) days").tag(days)
                }
            } label: {
                SheetRowLabel("Deadline", symbol: "calendar", color: Tint.deadline)
            }
            HStack {
                SheetRowLabel("Tags", symbol: "number")
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
                    Label {
                        Text("Inherits from \(parent.displayName): " + inherited.summary.joined(separator: " · "))
                    } icon: {
                        SheetRowIcon("arrow.turn.down.right")
                    }
                    .theoFont(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            if let existing, !existing.liveTasks.filter({ !$0.isDone }).isEmpty, !currentTraits.isEmpty {
                Button {
                    applyToExisting(existing)
                } label: {
                    SheetRowLabel("Apply to the \(existing.liveTasks.filter { !$0.isDone }.count) Open Tasks Here", action: "wand.and.stars")
                }
            }
        } header: {
            Text("Tasks Placed Here Get")
        } footer: {
            Text("New and moved tasks take these where they have nothing of their own. Where a task already has something else, it shows a suggestion instead and keeps its own. Subgroups inherit these unless they set their own.")
        }
    }

    private var projectSection: some View {
        Section {
            Toggle(isOn: $isProject.animation(Motion.resolved(Motion.list))) {
                SheetRowLabel("Project", symbol: "chart.bar.fill")
            }
            if isProject {
                Toggle(isOn: $hasDue.animation(Motion.resolved(Motion.list))) {
                    SheetRowLabel("Deadline", symbol: "calendar", color: Tint.deadline)
                }
                if hasDue {
                    DatePicker(selection: $due, displayedComponents: [.date]) {
                        SheetRowLabel("Date")
                    }
                }
            }
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(2...6)
        } footer: {
            Text("Projects show how far along they are, and an optional deadline.")
        }
    }

    @ViewBuilder private var deleteSection: some View {
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
