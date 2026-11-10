import SwiftUI
import SwiftData
import TheoCore

/// Every task, filtered, grouped and sorted any way (All Tasks), or a saved combination of that
/// (a saved view). Starts as: open tasks, by group, by priority and then deadline. Ready-made and
/// saved views sit on top for switching in one tap.
struct AllTasksView: View {
    /// A saved view to show (and edit); nil = All Tasks.
    var viewID: UUID?

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @Query(filter: #Predicate<SavedView> { $0.deletedAt == nil }, sort: \SavedView.sortOrder)
    private var views: [SavedView]
    @AppStorage(Prefs.allTasksQuery) private var storedRaw = ""
    /// Unsaved changes to a saved view.
    @State private var draft: TaskQuery?
    @State private var showFilters = false
    @State private var naming = false
    @State private var newName = ""

    private var savedView: SavedView? { viewID.flatMap { id in views.first { $0.uuid == id } } }

    private var query: TaskQuery {
        if let savedView { return draft ?? savedView.query }
        return storedRaw.isEmpty ? .standard : TaskQuery(raw: storedRaw)
    }

    private func setQuery(_ new: TaskQuery) {
        if savedView != nil {
            draft = new == savedView?.query ? nil : new
        } else {
            storedRaw = new.raw
        }
    }

    var body: some View {
        let query = self.query
        let result = QueryBuilder.build(tasks: tasks, groups: groups, query: query, today: app.dayStart, collapsed: app.collapsedTaskIDs)

        TaskListView(rows: result.rows, allowsReorder: false, defaultGroupID: query.quickEntryOnly ? nil : query.groupIDs.first) {
            VStack(alignment: .leading, spacing: 12) {
                TaskStatsBar(stats: TaskStats(result.matched, today: app.dayStart))
                if savedView == nil {
                    quickSwitch(current: query)
                }
                controls(query)
                if savedView != nil, draft != nil {
                    changedBanner
                }
                if result.rows.isEmpty {
                    Text(query.filterCount > 0 ? "Nothing matches these filters." : "No tasks yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle(savedView?.displayName ?? "All Tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showFilters = true
                } label: {
                    Label("Filters", systemImage: query.filterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                moreMenu
            }
        }
        .sheet(isPresented: $showFilters) {
            NavigationStack {
                QueryEditor(query: Binding(get: { self.query }, set: { setQuery($0) }), groups: groups, tags: Sections.tags(in: tasks.filter { !$0.isDone }))
            }
            #if os(macOS)
            .frame(minWidth: 460, minHeight: 620)
            #endif
        }
        .alert("Save as View", isPresented: $naming) {
            TextField("Name, e.g. HAEB this week", text: $newName)
            Button("Save") { saveAsView() }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("It shows up in the sidebar and stays up to date as tasks change.")
        }
        .safeAreaInset(edge: .bottom) {
            if !app.isSelecting {
                QuickEntryBar(defaultGroupID: query.quickEntryOnly ? nil : query.groupIDs.first, placeholder: "Add a task")
            }
        }
        .onChange(of: viewID) { _, _ in draft = nil }
    }

    // MARK: - Header

    /// Ready-made views and saved ones, one tap to switch.
    private func quickSwitch(current: TaskQuery) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TaskQuery.presets) { preset in
                    ChipButton(title: preset.title, symbol: preset.symbol, isOn: current == preset.query) {
                        withAnimation(.snappy) { setQuery(preset.query) }
                    }
                }
                let saved = views.sorted { ($0.isFavorite ? 0 : 1, $0.sortOrder) < ($1.isFavorite ? 0 : 1, $1.sortOrder) }
                ForEach(saved, id: \.uuid) { view in
                    ChipButton(title: view.displayName, symbol: view.isFavorite ? "star.fill" : view.symbol, color: view.color.color,
                               isOn: current == view.query) {
                        withAnimation(.snappy) { setQuery(view.query) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func controls(_ query: TaskQuery) -> some View {
        HStack(spacing: 8) {
            Button {
                showFilters = true
            } label: {
                Label(query.filterCount > 0 ? "Filters · \(query.filterCount)" : "Filters", systemImage: "line.3.horizontal.decrease")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.glass)
            Menu {
                Picker("Group By", selection: Binding(get: { query.grouping }, set: { value in
                    var new = query
                    new.grouping = value
                    setQuery(new)
                })) {
                    ForEach(TaskQuery.Grouping.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                Label(query.grouping.shortTitle, systemImage: "rectangle.3.group")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            Menu {
                Picker("Sort By", selection: Binding(get: { query.sort }, set: { value in
                    var new = query
                    new.sort = value
                    setQuery(new)
                })) {
                    ForEach(TaskQuery.Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                Label(query.sort.shortTitle, systemImage: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            Spacer(minLength: 0)
        }
    }

    /// A saved view with unsaved changes: keep them or go back.
    private var changedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(.tint)
            Text("Changed")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Revert") { withAnimation(.snappy) { draft = nil } }
                .buttonStyle(.glass)
            Button("Update View") {
                if let savedView, let draft {
                    app.store.updateView(savedView, query: draft)
                    self.draft = nil
                }
            }
            .buttonStyle(.glassProminent)
        }
        .controlSize(.small)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                newName = ""
                naming = true
            } label: {
                Label(savedView == nil ? "Save as View…" : "Save as New View…", systemImage: "square.and.arrow.down")
            }
            if let savedView {
                Button {
                    app.store.setFavorite(savedView, !savedView.isFavorite)
                } label: {
                    Label(savedView.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: savedView.isFavorite ? "star.slash" : "star")
                }
                Button(role: .destructive) {
                    app.store.deleteView(savedView)
                    app.go(.allTasks)
                } label: {
                    Label("Delete View", systemImage: "trash")
                }
            } else {
                Button {
                    withAnimation(.snappy) { setQuery(.standard) }
                } label: {
                    Label("Reset to Standard", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    private func saveAsView() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        newName = ""
        guard !name.isEmpty else { return }
        let view = app.store.addView(name: name, query: query)
        draft = nil
        app.show("Saved “\(view.displayName)” · it's in the sidebar", symbol: "square.and.arrow.down.fill")
    }
}

/// Every filter, the grouping and the order, in one sheet.
struct QueryEditor: View {
    @Binding var query: TaskQuery
    let groups: [TaskGroup]
    let tags: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Picker("Show", selection: $query.status) {
                    ForEach(TaskQuery.Status.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Search titles and notes", text: $query.search)
            }

            Section("Group & Order") {
                Picker("Group By", selection: $query.grouping) {
                    ForEach(TaskQuery.Grouping.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Sort By", selection: $query.sort) {
                    ForEach(TaskQuery.Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section {
                Toggle("Only Quick Entry", isOn: $query.quickEntryOnly)
                if !query.quickEntryOnly {
                    ForEach(GroupTree.ordered(groups), id: \.group.uuid) { item in
                        let id = item.group.uuid
                        Button {
                            if let index = query.groupIDs.firstIndex(of: id) {
                                query.groupIDs.remove(at: index)
                            } else {
                                query.groupIDs.append(id)
                            }
                        } label: {
                            HStack {
                                Label(item.group.displayName, systemImage: item.group.symbol)
                                    .foregroundStyle(item.group.color.color)
                                    .padding(.leading, CGFloat(item.level) * 14)
                                Spacer()
                                if query.groupIDs.contains(id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Groups")
            } footer: {
                Text(query.groupIDs.isEmpty && !query.quickEntryOnly ? "Nothing ticked: every group that's switched on. A group includes its subgroups." : "A group includes its subgroups.")
            }

            if !tags.isEmpty {
                Section("Tags (any of)") {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            if let index = query.tags.firstIndex(of: tag) {
                                query.tags.remove(at: index)
                            } else {
                                query.tags.append(tag)
                            }
                        } label: {
                            HStack {
                                Text("#" + tag)
                                    .foregroundStyle(TheoColor.forTag(tag).color)
                                Spacer()
                                if query.tags.contains(tag) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Details") {
                Picker("Importance", selection: $query.minLevel) {
                    Text("Any").tag(0)
                    Text("! and up (5+)").tag(5)
                    Text("!! and up (7+)").tag(7)
                    Text("!!! only (9+)").tag(9)
                }
                Picker("Deadline", selection: $query.deadline) {
                    ForEach(TaskQuery.Deadline.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Planned", selection: $query.planned) {
                    ForEach(TaskQuery.Planned.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Size", selection: $query.maxEstimate) {
                    Text("Any").tag(Double?.none)
                    ForEach([0.25, 0.5, 1.0, 2.0], id: \.self) { value in
                        Text("Up to \(PowerHours.format(value))").tag(Double?.some(value))
                    }
                }
                Toggle("Only ongoing tasks", isOn: $query.ongoingOnly)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Filters")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Reset") { query = .standard }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
