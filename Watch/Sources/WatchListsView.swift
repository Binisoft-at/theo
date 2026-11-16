import SwiftUI
import SwiftData
import TheoCore

/// Every other page: Upcoming, Priority, Quick Entry and each group.
struct WatchListsView: View {
    @Environment(WatchModel.self) private var model
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && !$0.isDone })
    private var openTasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        List {
            Section {
                // The same colours as these pages have in the iPhone's and Mac's sidebar.
                link(.upcoming, title: "Upcoming", symbol: "calendar", color: .red, count: upcomingCount)
                link(.priority, title: "Priority", symbol: "exclamationmark.3", color: .pink,
                     count: openTasks.activeOnly(groups).filter { $0.priority != .normal }.count)
            }
            Section("Groups") {
                link(.group(nil), title: String(localized: "Quick Entry"), symbol: "tray.and.arrow.down.fill", color: .teal,
                     count: openTasks.filter { $0.groupID == nil }.count)
                ForEach(groups) { group in
                    link(.group(group.uuid), title: group.displayName, symbol: group.symbol, color: group.color.color,
                         count: openTasks.filter { $0.groupID == group.uuid }.count)
                }
            }
        }
        .navigationTitle("Lists")
    }

    /// The same tasks as the Upcoming page: switched-off groups don't count.
    private var upcomingCount: Int {
        openTasks.activeOnly(groups).filter { $0.dueDate != nil || ($0.plannedDay ?? .distantPast) > model.dayStart }.count
    }

    private func link(_ route: WatchRoute, title: String, symbol: String, color: Color, count: Int) -> some View {
        NavigationLink(value: route) {
            WatchListLabel(title: title, symbol: symbol, color: color, count: count)
        }
    }
}

/// A page in Lists: its icon white in a circle of its colour (like the watch's own Settings),
/// the name, and how many open tasks it holds.
struct WatchListLabel: View {
    let title: String
    let symbol: String
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .symbolVariant(.fill)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The next seven days, by deadline or planned day.
struct WatchUpcomingView: View {
    @Environment(WatchModel.self) private var model
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && !$0.isDone }, sort: \TaskItem.sortOrder)
    private var openTasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        WatchSectionList(
            sections: Sections.upcoming(openTasks.activeOnly(groups), groups: groups, today: model.dayStart).filter { !$0.tasks.isEmpty },
            emptyTitle: "Nothing Scheduled",
            emptySymbol: "calendar",
            emptyColor: .red,
            emptyText: "Tasks with a deadline show up here."
        )
        .navigationTitle("Upcoming")
    }
}

/// Open tasks with a priority, highest first.
struct WatchPriorityView: View {
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && !$0.isDone }, sort: \TaskItem.sortOrder)
    private var openTasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        WatchSectionList(
            sections: Sections.byPriority(openTasks.activeOnly(groups), groups: groups, includeNone: false).filter { !$0.tasks.isEmpty },
            emptyTitle: "No Priorities",
            emptySymbol: "exclamationmark.3",
            emptyColor: .pink,
            emptyText: "Say \"!!\" when adding a task, or set a priority in its details."
        )
        .navigationTitle("Priority")
    }
}

/// A list of labeled sections (Upcoming, Priority).
struct WatchSectionList: View {
    let sections: [LabeledSection]
    let emptyTitle: LocalizedStringKey
    let emptySymbol: String
    /// The page's colour, for the empty state's symbol (the same as its icon in Lists).
    var emptyColor: Color = .secondary
    let emptyText: LocalizedStringKey

    var body: some View {
        List {
            ForEach(sections, id: \.key) { section in
                Section {
                    ForEach(section.tasks, id: \.uuid) { task in
                        WatchTaskRow(task: task, showGroup: true)
                    }
                } header: {
                    WatchSectionHeader(title: section.title, symbol: section.symbol, color: section.color)
                }
            }
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(emptyTitle)
                    } icon: {
                        Image(systemName: emptySymbol)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(emptyColor)
                    }
                } description: {
                    Text(emptyText)
                }
                .transition(.opacity)
            }
        }
    }
}

/// One group (or Quick Entry), in its manual order. Projects show their progress.
struct WatchGroupView: View {
    let groupID: UUID?

    @Environment(WatchModel.self) private var model
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        let group = groups.first { $0.uuid == groupID }
        let rows = WatchPage.groupRows(tasks, groupID: groupID, dayStart: model.dayStart)
        List {
            if let group, group.isProject {
                Section {
                    projectProgress(group)
                }
            }
            Section {
                WatchAddTaskRow(groupID: groupID)
                ForEach(rows) { row in
                    WatchTaskRow(task: row.task, depth: row.depth)
                }
            }
        }
        .navigationTitle(group?.displayName ?? String(localized: "Quick Entry"))
    }

    private func projectProgress(_ group: TaskGroup) -> some View {
        let all = group.liveTasks
        let caption = group.dueDate.map { DateText.due($0, hasTime: false, today: model.dayStart) } ?? String(localized: "Project")
        return WatchProgressRow(caption: caption, done: all.filter(\.isDone).count, total: all.count)
    }
}
