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
    /// Taps on the ready-made and saved views, for the light tick of a pick.
    @State private var picks = 0

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
            header(query: query, rows: result.rows, matched: result.matched)
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
            TextField("Name, e.g. Admin this week", text: $newName)
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

    /// The figures, the views to switch to, the controls, and what to do about a changed view
    /// or an empty list. The rows of chips and figures scroll from one edge of the screen to the
    /// other; their first item lines up with everything else.
    private func header(query: TaskQuery, rows: [ListRow], matched: [TaskItem]) -> some View {
        let changed: Bool = savedView != nil && draft != nil
        let isEmpty: Bool = rows.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            TaskStatsBar(stats: TaskStats(matched, today: app.dayStart))
                .contentMargins(.horizontal, edgeBleed, for: .scrollContent)
                .padding(.horizontal, -edgeBleed)
            if savedView == nil {
                quickSwitch(current: query)
            }
            controls(query)
            if changed {
                changedBanner
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
            if isEmpty {
                emptyState(filtered: query.filterCount > 0)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .animation(Motion.resolved(Motion.layout), value: changed)
        .animation(Motion.resolved(Motion.layout), value: isEmpty)
    }

    /// Ready-made views and saved ones, one tap to switch.
    private func quickSwitch(current: TaskQuery) -> some View {
        let saved = views.sorted { ($0.isFavorite ? 0 : 1, $0.sortOrder) < ($1.isFavorite ? 0 : 1, $1.sortOrder) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskQuery.presets) { preset in
                    ChipButton(title: preset.title, symbol: preset.symbol, isOn: current == preset.query) {
                        pick(preset.query)
                    }
                }
                ForEach(saved, id: \.uuid) { view in
                    ChipButton(title: view.displayName, symbol: view.isFavorite ? "star.fill" : view.symbol, color: view.color.color,
                               isOn: current == view.query) {
                        pick(view.query)
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, edgeBleed)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -edgeBleed)
        .sensoryFeedback(.selection, trigger: picks)
    }

    /// One of the views above: its chip lights up and the list settles on it in one movement.
    private func pick(_ new: TaskQuery) {
        picks += 1
        Motion.animate(Motion.tap) { setQuery(new) }
    }

    /// Filters, grouping and order as quiet chips. The filter chip turns the accent while
    /// filters are on; the two menus show their choice and a small up-and-down chevron.
    private func controls(_ query: TaskQuery) -> some View {
        let motion: Animation = Motion.resolved(Motion.list)
        let filtered: Bool = query.filterCount > 0
        return HStack(spacing: 8) {
            Button {
                showFilters = true
            } label: {
                controlChip(filtered ? "Filters · \(query.filterCount)" : "Filters", symbol: "line.3.horizontal.decrease", active: filtered)
            }
            .buttonStyle(.plain)
            Menu {
                Picker("Group By", selection: groupingBinding(query).animation(motion)) {
                    ForEach(TaskQuery.Grouping.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                controlChip(query.grouping.shortTitle, symbol: "rectangle.3.group", isMenu: true)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            Menu {
                Picker("Sort By", selection: sortBinding(query).animation(motion)) {
                    ForEach(TaskQuery.Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: {
                controlChip(query.sort.shortTitle, symbol: "arrow.up.arrow.down", isMenu: true)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private func groupingBinding(_ query: TaskQuery) -> Binding<TaskQuery.Grouping> {
        Binding(get: { query.grouping }, set: { value in
            var new = query
            new.grouping = value
            setQuery(new)
        })
    }

    private func sortBinding(_ query: TaskQuery) -> Binding<TaskQuery.Sort> {
        Binding(get: { query.sort }, set: { value in
            var new = query
            new.sort = value
            setQuery(new)
        })
    }

    /// A small capsule on a quiet fill, like a chip that's off.
    private func controlChip(_ title: String, symbol: String, active: Bool = false, isMenu: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(title)
                .lineLimit(1)
            if isMenu {
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            }
        }
        .theoFont(.caption, weight: .semibold)
        .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .contentShape(Capsule())
        .animation(Motion.resolved(Motion.tap), value: active)
    }

    /// A saved view with unsaved changes: keep them or go back.
    private var changedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text("Changed")
                .theoFont(.subheadline, weight: .medium)
            Spacer()
            Button {
                Motion.animate(Motion.list) { draft = nil }
            } label: {
                Text("Revert")
                    .theoFont(.subheadline)
            }
            .buttonStyle(.bordered)
            Button {
                updateView()
            } label: {
                Text("Update View")
                    .theoFont(.subheadline, weight: .semibold)
                    .modifier(OnAccentForeground())
            }
            .buttonStyle(.borderedProminent)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    private func updateView() {
        guard let savedView, let draft else { return }
        Motion.animate(Motion.layout) {
            app.store.updateView(savedView, query: draft)
            self.draft = nil
        }
    }

    /// Nothing to list: the same calm form as every empty page.
    @ViewBuilder
    private func emptyState(filtered: Bool) -> some View {
        if filtered {
            EmptyHint(symbol: "line.3.horizontal.decrease.circle", title: "No Matches", message: "Nothing matches these filters.")
        } else {
            EmptyHint(symbol: "checklist", title: "No Tasks Yet", message: "Add one below.")
        }
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
                    Motion.animate(Motion.list) { setQuery(.standard) }
                } label: {
                    Label("Reset to Standard", systemImage: "arrow.counterclockwise")
                }
            }
            #if os(iOS)
            // Pick matches to move, plan or tag several at once (the selection bar below).
            Button {
                app.isSelecting = true
            } label: {
                Label("Select Tasks", systemImage: "checklist")
            }
            #endif
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

    /// Groups that are off, or inside one that is (shown dimmed with a pause sign).
    private var offIDs: Set<UUID> { GroupTree.inactiveIDs(groups) }

    private var groupsFooter: String {
        if query.groupIDs.isEmpty && !query.quickEntryOnly {
            return "Nothing ticked: every group that's switched on. A group includes its subgroups."
        }
        return offIDs.isEmpty ? "A group includes its subgroups." : "A group includes its subgroups. Off subgroups stay hidden unless ticked."
    }

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
                Toggle("Only Quick Entry", isOn: $query.quickEntryOnly.animation(Motion.resolved(Motion.list)))
                if !query.quickEntryOnly {
                    let off = offIDs
                    ForEach(GroupTree.ordered(groups), id: \.group.uuid) { item in
                        groupRow(item.group, level: item.level, isOff: off.contains(item.group.uuid))
                    }
                }
            } header: {
                Text("Groups")
            } footer: {
                Text(groupsFooter)
            }

            if !tags.isEmpty {
                Section("Tags (any of)") {
                    ForEach(tags, id: \.self) { tag in
                        tagRow(tag)
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
        .theoBodyFont()
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

    /// A group to tick: its icon in its colour, its name in the text colour, indented under
    /// the group it sits in.
    private func groupRow(_ group: TaskGroup, level: Int, isOff: Bool) -> some View {
        let id = group.uuid
        let isOn = query.groupIDs.contains(id)
        return Button {
            Motion.animate(Motion.tap) { toggleGroup(id) }
        } label: {
            HStack {
                Label {
                    Text(group.displayName)
                        .foregroundStyle(Color.primary)
                } icon: {
                    Image(systemName: group.symbol)
                        .foregroundStyle(group.color.color)
                }
                .opacity(isOff ? 0.5 : 1)
                .padding(.leading, CGFloat(level) * 14)
                if isOff {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Off")
                }
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
    }

    private func tagRow(_ tag: String) -> some View {
        let isOn = query.tags.contains(tag)
        return Button {
            Motion.animate(Motion.tap) { toggleTag(tag) }
        } label: {
            HStack {
                Text("#" + tag)
                    .foregroundStyle(TheoColor.forTag(tag).color)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
    }

    private func toggleGroup(_ id: UUID) {
        if let index = query.groupIDs.firstIndex(of: id) {
            query.groupIDs.remove(at: index)
        } else {
            query.groupIDs.append(id)
        }
    }

    private func toggleTag(_ tag: String) {
        if let index = query.tags.firstIndex(of: tag) {
            query.tags.remove(at: index)
        } else {
            query.tags.append(tag)
        }
    }
}

/// How far a row of chips reaches past the list's side margin, so it scrolls from one edge of
/// the screen to the other (the Mac's list has narrower margins).
#if os(macOS)
private let edgeBleed: CGFloat = 8
#else
private let edgeBleed: CGFloat = 16
#endif
