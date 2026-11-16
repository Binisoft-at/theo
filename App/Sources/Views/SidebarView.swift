import SwiftUI
import SwiftData
import TheoCore

/// The list of pages — like the folder list in Notes.
struct SidebarView: View {
    /// Split view (iPad/Mac) drives the detail through selection; the iPhone stack pushes links.
    var usesSelection = true
    /// Today and Plan rows (the iPhone has them as tabs instead).
    var showsDayPages = true

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false })
    private var allOpen: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @Query(filter: #Predicate<SavedView> { $0.deletedAt == nil }, sort: \SavedView.sortOrder)
    private var views: [SavedView]
    @State private var groupPendingDelete: TaskGroup?
    @AppStorage("sidebar.showShortcuts") private var showShortcuts = false

    var body: some View {
        @Bindable var app = app
        let today = app.dayStart
        let openTasks = allOpen.activeOnly(groups)
        let todayCount = openTasks.filter { PageBuilder.isOnToday($0, dayStart: today) }.count
        let tomorrowCount = openTasks.filter { $0.isPlanned(for: DayBoundary.current.dayStart(byAdding: 1, to: today)) }.count
        let dueCount = openTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return DateText.dayDelta(due, today: today) <= 0
        }.count
        let priorityCount = openTasks.filter { $0.priority != .normal }.count
        let quickCount = openTasks.filter { $0.groupID == nil }.count
        let tags = Sections.tags(in: openTasks)
        let tree = GroupTree.ordered(groups)
        let off = GroupTree.inactiveIDs(groups)
        let viewCounts = openCounts(of: views, today: today)

        let favoriteGroups = tree.map(\.group).filter(\.isFavorite)
        let favoriteViews = views.filter(\.isFavorite)

        sidebarList(selection: usesSelection ? $app.selection : nil) {
            if !favoriteGroups.isEmpty || !favoriteViews.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteGroups, id: \.uuid) { group in
                        NavigationLink(value: SidebarItem.group(group.uuid)) {
                            SidebarRow(title: group.displayName, symbol: group.symbol, color: group.color.color,
                                       count: allOpen.filter { $0.groupID == group.uuid }.count, isOwn: true)
                                .modifier(taskDrop(on: .group(group.uuid)))
                        }
                        .contextMenu {
                            Button {
                                Motion.animate(Motion.list) { app.store.setFavorite(group, false) }
                            } label: {
                                Label("Remove from Favorites", systemImage: "star.slash")
                            }
                        }
                    }
                    ForEach(favoriteViews, id: \.uuid) { view in
                        NavigationLink(value: SidebarItem.view(view.uuid)) {
                            SidebarRow(title: view.displayName, symbol: view.symbol, color: view.color.color,
                                       count: viewCounts[view.uuid] ?? 0, isOwn: true)
                        }
                        .contextMenu { viewMenu(view) }
                    }
                }
            }
            // Theo's own pages: rounded-square tiles, each in its page's colour. What you made
            // (groups, views, tags) gets round ones below, like the lists in Reminders.
            Section {
                if showsDayPages {
                    NavigationLink(value: SidebarItem.today) {
                        SidebarRow(title: "Today", symbol: "sun.max.fill", color: Tint.today, count: todayCount, shortcut: "⌘1")
                            .modifier(taskDrop(on: .today))
                    }
                    NavigationLink(value: SidebarItem.plan) {
                        SidebarRow(title: "Plan", symbol: "calendar.badge.plus", color: Tint.planned, count: tomorrowCount, shortcut: "⌘2")
                            .modifier(taskDrop(on: .plan))
                    }
                    // The number is what's planned for tomorrow.
                    .help("Planned for tomorrow")
                }
                if showsDayPages {
                    NavigationLink(value: SidebarItem.overview) {
                        SidebarRow(title: "Overview", symbol: "chart.pie.fill", color: .mint, count: 0, shortcut: "⇧⌘O")
                    }
                }
                NavigationLink(value: SidebarItem.allTasks) {
                    SidebarRow(title: "All Tasks", symbol: "tray.full.fill", color: .blue, count: openTasks.count, shortcut: "⇧⌘A")
                }
                NavigationLink(value: SidebarItem.upcoming) {
                    SidebarRow(title: "Upcoming", symbol: "calendar", color: .red, count: dueCount, countIsAlert: dueCount > 0, shortcut: "⌘3")
                }
                NavigationLink(value: SidebarItem.matrix) {
                    SidebarRow(title: "Matrix", symbol: "square.grid.3x3.fill", color: .purple, count: 0, shortcut: "⌘4")
                }
                NavigationLink(value: SidebarItem.quickEntry) {
                    SidebarRow(title: "Quick Entry", symbol: "tray.and.arrow.down.fill", color: .teal, count: quickCount, shortcut: "⌘5")
                        .modifier(taskDrop(on: .quickEntry))
                }
                NavigationLink(value: SidebarItem.priority) {
                    SidebarRow(title: "Priority", symbol: "exclamationmark.3", color: .pink, count: priorityCount, shortcut: "⌘8")
                }
            }

            Section("Groups") {
                ForEach(tree, id: \.group.uuid) { item in
                    let group = item.group
                    NavigationLink(value: SidebarItem.group(group.uuid)) {
                        SidebarRow(
                            title: group.displayName,
                            symbol: group.symbol,
                            color: group.color.color,
                            count: allOpen.filter { $0.groupID == group.uuid }.count,
                            isOwn: true,
                            // Switched off: a pause mark before the count.
                            isPaused: !group.isActive
                        )
                        .padding(.leading, CGFloat(item.level) * 16)
                        // Switched off (or inside a group that is): dimmed.
                        .opacity(off.contains(group.uuid) ? 0.45 : 1)
                        .modifier(taskDrop(on: .group(group.uuid)))
                    }
                    #if os(iOS)
                    .swipeActions(edge: .leading) {
                        Button {
                            Motion.animate(Motion.list) { app.store.setActive(group, !group.isActive) }
                        } label: {
                            Label(group.isActive ? "Off" : "On", systemImage: group.isActive ? "pause.circle" : "play.circle")
                        }
                        .tint(group.isActive ? .gray : .green)
                    }
                    #endif
                    .contextMenu {
                        Button {
                            Motion.animate(Motion.list) { app.store.setActive(group, !group.isActive) }
                        } label: {
                            Label(group.isActive ? "Switch Off" : "Switch On", systemImage: group.isActive ? "pause.circle" : "play.circle")
                        }
                        Button {
                            Motion.animate(Motion.list) { app.store.setFavorite(group, !group.isFavorite) }
                        } label: {
                            Label(group.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: group.isFavorite ? "star.slash" : "star")
                        }
                        Button {
                            app.groupEditor = .edit(group)
                        } label: {
                            Label("Edit Group…", systemImage: "pencil")
                        }
                        Button {
                            app.groupEditor = .subgroup(group)
                        } label: {
                            Label("New Subgroup…", systemImage: "folder.badge.plus")
                        }
                        Button(role: .destructive) {
                            groupPendingDelete = group
                        } label: {
                            Label("Delete Group…", systemImage: "trash")
                        }
                    }
                }
                .onMove { source, destination in
                    var reordered = tree.map(\.group)
                    reordered.move(fromOffsets: source, toOffset: destination)
                    app.store.reorderGroups(reordered)
                }
                Button {
                    app.groupEditor = .new
                } label: {
                    // An action, not a place: the accent's + in the icons' column.
                    Label {
                        Text("New Group")
                            .theoFont(.body)
                    } icon: {
                        IconTile(symbol: "plus", kind: .bare)
                    }
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
            }

            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags, id: \.self) { tag in
                        NavigationLink(value: SidebarItem.tag(tag)) {
                            SidebarRow(
                                title: "#" + tag,
                                symbol: "number",
                                color: TheoColor.forTag(tag).color,
                                count: openTasks.filter { $0.tags.contains(tag) }.count,
                                isOwn: true
                            )
                        }
                    }
                }
            }

            if !views.isEmpty {
                Section("Views") {
                    ForEach(views, id: \.uuid) { view in
                        NavigationLink(value: SidebarItem.view(view.uuid)) {
                            SidebarRow(
                                title: view.displayName,
                                symbol: view.isFavorite ? "star.fill" : view.symbol,
                                color: view.color.color,
                                count: viewCounts[view.uuid] ?? 0,
                                isOwn: true
                            )
                        }
                        .contextMenu { viewMenu(view) }
                    }
                }
            }

            Section {
                NavigationLink(value: SidebarItem.history) {
                    SidebarRow(title: "History", symbol: "clock.arrow.circlepath", color: .indigo, count: 0, shortcut: "⌘6")
                }
                NavigationLink(value: SidebarItem.trash) {
                    SidebarRow(title: "Recently Deleted", symbol: "trash", color: .gray, count: 0, shortcut: "⌘7")
                }
            }
        }
        .navigationTitle("Theo")
        #if os(macOS)
        .safeAreaInset(edge: .bottom) {
            // On its own background, so the list never shows through it; the legend folds away
            // (each item already shows its shortcut) and opens smoothly, the list giving way.
            VStack(alignment: .leading, spacing: 6) {
                DisclosureGroup(isExpanded: $showShortcuts.animation(Motion.resolved(Motion.list))) {
                    ShortcutLegend()
                        .padding(.top, 4)
                } label: {
                    Text("Keyboard Shortcuts")
                        .theoFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                SyncFooter()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    app.showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.groupEditor = .new
                } label: {
                    Label("New Group", systemImage: "folder.badge.plus")
                }
                .help("New Group (⇧⌘N)")
            }
        }
        .confirmationDialog(
            "Delete Group",
            isPresented: Binding(get: { groupPendingDelete != nil }, set: { if !$0 { groupPendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: groupPendingDelete
        ) { group in
            Button("Delete Group and Its Tasks", role: .destructive) {
                deleteGroup(group, keepTasks: false)
            }
            Button("Delete Group, Keep Tasks") {
                deleteGroup(group, keepTasks: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: { group in
            Text("“\(group.displayName)” contains \(group.liveTasks.count) task\(group.liveTasks.count == 1 ? "" : "s").")
        }
    }

    /// Deletes a group with an Undo that brings back the group, its tasks and its subgroups.
    private func deleteGroup(_ group: TaskGroup, keepTasks: Bool) {
        if app.selection == .group(group.uuid) {
            if usesSelection {
                app.go(.today)
            } else {
                // iPhone: the Lists page stays; nothing should reopen the deleted group.
                app.selection = nil
            }
        }
        let model = app
        Motion.animate(Motion.list) { model.store.deleteGroup(group, keepTasks: keepTasks) }
        let message = keepTasks ? "Deleted “\(group.displayName)” · tasks moved to Quick Entry" : "Deleted “\(group.displayName)”"
        model.show(message, symbol: "trash.fill") {
            Motion.animate(Motion.list) { model.store.restoreGroup(group) }
        }
    }
}

extension SidebarView {
    /// What each saved view shows open, found the way its page finds it.
    private func openCounts(of views: [SavedView], today: Date) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for view in views where counts[view.uuid] == nil {
            counts[view.uuid] = QueryBuilder.build(tasks: allOpen, groups: groups, query: view.query, today: today, collapsed: []).matched.count
        }
        return counts
    }

    @ViewBuilder
    func viewMenu(_ view: SavedView) -> some View {
        Button {
            Motion.animate(Motion.list) { app.store.setFavorite(view, !view.isFavorite) }
        } label: {
            Label(view.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: view.isFavorite ? "star.slash" : "star")
        }
        Button(role: .destructive) {
            if app.selection == .view(view.uuid) { app.go(.allTasks) }
            Motion.animate(Motion.list) { app.store.deleteView(view) }
        } label: {
            Label("Delete View", systemImage: "trash")
        }
    }

    @ViewBuilder
    func sidebarList<Content: View>(selection: Binding<SidebarItem?>?, @ViewBuilder content: () -> Content) -> some View {
        if let selection {
            List(selection: selection, content: content)
        } else {
            List(content: content)
        }
    }

    /// A row that takes tasks dragged from the list beside it (Mac and iPad; see `TaskDrag`).
    /// The iPhone's Lists page has no list beside it, so its rows take none.
    func taskDrop(on item: SidebarItem) -> TaskDropTarget {
        let model = app
        return TaskDropTarget(isEnabled: usesSelection, onDrop: { texts in
            TaskDrag.drop(texts, on: item, app: model)
        })
    }
}

/// While tasks are dragged over a sidebar row, it lights up in the accent colour and fades when
/// they move on; dropped there, `onDrop` gets the dragged texts and says whether it took them.
/// A drop it took makes the row's icon bounce once, with a light tap where there's a finger.
struct TaskDropTarget: ViewModifier {
    let isEnabled: Bool
    let onDrop: ([String]) -> Bool

    @State private var isTargeted = false
    /// Drops the row took: each one bounces its icon.
    @State private var drops = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .contentShape(Rectangle())
                .background { highlight }
                .symbolEffect(.bounce, value: drops)
                .dropDestination(for: String.self, action: { texts, _ in
                    let took = onDrop(texts)
                    if took { drops += 1 }
                    return took
                }, isTargeted: { targeted in
                    // Lights up at once; fades out a little slower.
                    Motion.animate(targeted ? Motion.hover : Motion.list) { isTargeted = targeted }
                })
                .sensoryFeedback(.impact(weight: .light), trigger: drops)
        } else {
            content
        }
    }

    @ViewBuilder
    private var highlight: some View {
        if isTargeted {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.tint)
                    .opacity(0.16)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 1.5)
            }
            .padding(.horizontal, -6)
            .padding(.vertical, -3)
            .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
    }
}

/// A line in the sidebar: the page's icon on its tile, its name, and how many open tasks it
/// holds (the number rolls when it changes, and fades in and out at zero). On the Mac, its
/// shortcut in grey.
struct SidebarRow: View {
    let title: String
    let symbol: String
    let color: Color
    let count: Int
    /// Something is due today or late: the count in the overdue colour, a little bolder.
    var countIsAlert = false
    /// Shown in grey on the Mac.
    var shortcut: String?
    /// Something you made (a group, view or tag): a round tile. Theo's own pages keep the
    /// rounded square.
    var isOwn = false
    /// A switched-off group: a pause mark before the count.
    var isPaused = false

    var body: some View {
        HStack {
            Label {
                Text(title)
                    .theoFont(.body)
                    .lineLimit(1)
            } icon: {
                IconTile(symbol: symbol, color: color, kind: isOwn ? .circle : .square)
            }
            Spacer(minLength: 4)
            if isPaused {
                Image(systemName: "pause.circle")
                    .theoFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Off")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if count > 0 {
                Text("\(count)")
                    .theoFont(.body, weight: countIsAlert ? .semibold : .regular)
                    .rollingNumber(count)
                    .foregroundStyle(countIsAlert ? Tint.overdue : Color.secondary)
                    .transition(.opacity)
            }
            #if os(macOS)
            if let shortcut {
                Text(shortcut)
                    .theoFont(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 22, alignment: .trailing)
            }
            #endif
        }
        .animation(Motion.resolved(Motion.tap), value: count == 0)
        .animation(Motion.resolved(Motion.tap), value: isPaused)
    }
}

/// An icon on a small tile of its colour with the symbol in white, like the Settings app's: the
/// sidebar's pages and groups and the settings. Round for what you made, a rounded square for
/// Theo's own pages and settings; `bare` is the accent's symbol on its own, for an action in the
/// same column. It grows with the text (Theo's text size on the Mac, Dynamic Type elsewhere).
struct IconTile: View {
    enum Kind {
        case square, circle, bare
    }

    let symbol: String
    let color: Color
    let kind: Kind

    #if os(macOS)
    @Environment(\.textScale) private var scale
    #else
    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 29
    #endif

    init(symbol: String, color: Color = .accentColor, kind: Kind = .square) {
        self.symbol = symbol
        self.color = color
        self.kind = kind
    }

    /// The Settings app's 29 pt on iPhone and iPad; System Settings' 20 pt on the Mac, times
    /// Theo's text size.
    private var side: CGFloat {
        #if os(macOS)
        20 * scale
        #else
        scaledSide
        #endif
    }

    var body: some View {
        glyph
            .frame(width: side, height: side)
            .background { backdrop }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        if kind == .bare {
            Image(systemName: symbol)
                .font(.system(size: side * 0.62))
                .foregroundStyle(.tint)
        } else {
            Image(systemName: symbol)
                .symbolVariant(.fill)
                .font(.system(size: side * (kind == .circle ? 0.5 : 0.56), weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        switch kind {
        case .square:
            RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                .fill(color.gradient)
        case .circle:
            Circle()
                .fill(color.gradient)
        case .bare:
            EmptyView()
        }
    }
}

#if os(macOS)
/// The shortcuts worth remembering, small and grey under the sidebar (the pages' own numbers
/// sit next to each item): what it does on the left, the keys lined up on the right, the way a
/// menu shows them.
struct ShortcutLegend: View {
    @AppStorage(HotKeyChoice.preferenceKey) private var hotKeyRaw = HotKeyChoice.standard.rawValue

    private var items: [(keys: String, action: String)] {
        var list: [(keys: String, action: String)] = [
            ("⌘N", "New task"), ("⌥⌘N", "Subtask"), ("Return", "Edit line"), ("Esc", "Done editing"),
            ("Space", "Done"), ("⌫", "Delete"), ("⌘]  ⌘[", "In / out"), ("←  →", "Fold / unfold"),
            ("⌥⌘1–3", "Priority"), ("⌥⌘M", "Matrix"), ("⌥⌘D  ⌥⌘L", "Today / Tomorrow"), ("⌥⌘F", "Focus"),
            ("⌘F", "Search"),
        ]
        // The Quick Add shortcut, as chosen in Settings.
        let hotKey = HotKeyChoice(rawValue: hotKeyRaw) ?? .standard
        if hotKey != .off { list.append((keys: hotKey.title, action: "Add from any app")) }
        return list
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            ForEach(items, id: \.keys) { item in
                GridRow {
                    Text(item.action)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.keys)
                        .foregroundStyle(.tertiary)
                        .gridColumnAlignment(.trailing)
                }
            }
        }
        .theoFont(.caption2)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard shortcuts")
    }
}
#endif

#if os(macOS)
/// The sync state under the sidebar, lined up with the line above it. The cloud pulses while
/// Theo syncs and turns into the warning one when something went wrong.
struct SyncFooter: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let sync = app.sync
        HStack(spacing: 6) {
            Image(systemName: sync.lastError == nil ? "icloud" : "exclamationmark.icloud")
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: sync.activeEvents > 0)
            Text(sync.statusText)
                .lineLimit(1)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .theoFont(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
        .animation(Motion.resolved(Motion.tap), value: sync.statusText)
    }
}
#endif
