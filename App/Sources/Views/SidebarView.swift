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
    private var openTasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @State private var groupPendingDelete: TaskGroup?

    var body: some View {
        @Bindable var app = app
        let today = app.dayStart
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

        sidebarList(selection: usesSelection ? $app.selection : nil) {
            Section {
                if showsDayPages {
                    NavigationLink(value: SidebarItem.today) {
                        SidebarRow(title: "Today", symbol: "sun.max.fill", color: .orange, count: todayCount, shortcut: "⌘1")
                    }
                    NavigationLink(value: SidebarItem.plan) {
                        SidebarRow(title: "Plan", symbol: "calendar.badge.plus", color: .indigo, count: tomorrowCount, shortcut: "⌘2")
                    }
                }
                NavigationLink(value: SidebarItem.upcoming) {
                    SidebarRow(title: "Upcoming", symbol: "calendar", color: .red, count: dueCount, countIsAlert: dueCount > 0, shortcut: "⌘3")
                }
                NavigationLink(value: SidebarItem.matrix) {
                    SidebarRow(title: "Matrix", symbol: "square.grid.3x3.fill", color: .purple, count: 0, shortcut: "⌘4")
                }
                NavigationLink(value: SidebarItem.quickEntry) {
                    SidebarRow(title: "Quick Entry", symbol: "tray.and.arrow.down.fill", color: .teal, count: quickCount, shortcut: "⌘5")
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
                            count: openTasks.filter { $0.groupID == group.uuid }.count
                        )
                        .padding(.leading, CGFloat(item.level) * 16)
                    }
                    .contextMenu {
                        Button {
                            app.groupEditor = .edit(group)
                        } label: {
                            Label("Edit Group…", systemImage: "pencil")
                        }
                        Button {
                            app.groupEditor = .subgroup(group)
                        } label: {
                            Label("New Subproject…", systemImage: "folder.badge.plus")
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
                    Label("New Group", systemImage: "plus.circle")
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
                                count: openTasks.filter { $0.tags.contains(tag) }.count
                            )
                        }
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
            VStack(alignment: .leading, spacing: 8) {
                ShortcutLegend()
                SyncFooter()
            }
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
            }
        }
        .confirmationDialog(
            "Delete Group",
            isPresented: Binding(get: { groupPendingDelete != nil }, set: { if !$0 { groupPendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: groupPendingDelete
        ) { group in
            Button("Delete Group and Its Tasks", role: .destructive) {
                if app.selection == .group(group.uuid) { app.go(.today) }
                app.store.deleteGroup(group, keepTasks: false)
            }
            Button("Delete Group, Keep Tasks") {
                if app.selection == .group(group.uuid) { app.go(.today) }
                app.store.deleteGroup(group, keepTasks: true)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

extension SidebarView {
    @ViewBuilder
    func sidebarList<Content: View>(selection: Binding<SidebarItem?>?, @ViewBuilder content: () -> Content) -> some View {
        if let selection {
            List(selection: selection, content: content)
        } else {
            List(content: content)
        }
    }
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    let color: Color
    let count: Int
    var countIsAlert = false
    /// Shown in grey on the Mac.
    var shortcut: String?

    var body: some View {
        HStack {
            Label {
                Text(title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.subheadline.weight(countIsAlert ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(countIsAlert ? Color.red : Color.secondary)
            }
            #if os(macOS)
            if let shortcut {
                Text(shortcut)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 22, alignment: .trailing)
            }
            #endif
        }
    }
}

#if os(macOS)
/// The shortcuts worth remembering, small and grey under the sidebar.
struct ShortcutLegend: View {
    private static let items: [(keys: String, action: String)] = [
        ("⌘N", "New task"), ("⌥⌘N", "Subtask"), ("Space", "Done"), ("⌘]  ⌘[", "In / out"),
        ("⌥⌘1–3", "Priority"), ("⌥⌘M", "Matrix"), ("⌥⌘D  ⌥⌘L", "Today / not"), ("⌥⌘F", "Focus"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
            ForEach(Self.items, id: \.keys) { item in
                GridRow {
                    Text(item.keys)
                        .monospaced()
                    Text(item.action)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard shortcuts")
    }
}
#endif

#if os(macOS)
struct SyncFooter: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: app.sync.lastError == nil ? "icloud" : "exclamationmark.icloud")
            Text(app.sync.statusText)
                .lineLimit(1)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
#endif
