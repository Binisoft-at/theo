import SwiftUI
import SwiftData

/// Create or edit a group: name, icon, color, project settings.
struct GroupEditorView: View {
    let target: GroupEditorTarget

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = "list.bullet"
    @State private var color: TheoColor = .blue
    @State private var isProject = false
    @State private var hasDue = false
    @State private var due = Date()
    @State private var notes = ""
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private var existing: TaskGroup? {
        if case .edit(let group) = target { return group }
        return nil
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
            .navigationTitle(existing == nil ? "New Group" : "Edit Group")
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

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            name = existing.name
            symbol = existing.symbol
            color = existing.color
            isProject = existing.isProject
            notes = existing.notes
            if let date = existing.dueDate {
                hasDue = true
                due = date
            }
        } else {
            color = TheoColor.allCases.randomElement() ?? .blue
            nameFocused = true
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let group = existing ?? app.store.addGroup(name: trimmed, symbol: symbol, color: color)
        group.name = trimmed
        group.symbol = symbol
        group.color = color
        group.isProject = isProject
        group.dueDate = isProject && hasDue ? Calendar.current.startOfDay(for: due) : nil
        group.notes = notes
        group.touch()
        app.store.save()
        dismiss()
    }
}
