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
                link(.upcoming, title: "Upcoming", symbol: "calendar", color: .red, count: upcomingCount)
                link(.priority, title: "Priority", symbol: "exclamationmark.3", color: .orange,
                     count: openTasks.filter { $0.priority != .normal }.count)
            }
            Section("Groups") {
                link(.group(nil), title: String(localized: "Quick Entry"), symbol: "tray.and.arrow.down.fill", color: .secondary,
                     count: openTasks.filter { $0.groupID == nil }.count)
                ForEach(groups) { group in
                    link(.group(group.uuid), title: group.displayName, symbol: group.symbol, color: group.color.color,
                         count: openTasks.filter { $0.groupID == group.uuid }.count)
                }
            }
        }
        .navigationTitle("Lists")
    }

    private var upcomingCount: Int {
        openTasks.filter { $0.dueDate != nil || ($0.plannedDay ?? .distantPast) > model.dayStart }.count
    }

    private func link(_ route: WatchRoute, title: String, symbol: String, color: Color, count: Int) -> some View {
        NavigationLink(value: route) {
            HStack {
                WatchSectionHeader(title: title, symbol: symbol, color: color)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The next seven days, by deadline or "Not Today" date.
struct WatchUpcomingView: View {
    @Environment(WatchModel.self) private var model
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && !$0.isDone }, sort: \TaskItem.sortOrder)
    private var openTasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        WatchSectionList(
            sections: Sections.upcoming(openTasks, groups: groups, today: model.dayStart).filter { !$0.tasks.isEmpty },
            emptyTitle: "Nothing Scheduled",
            emptySymbol: "calendar",
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
            sections: Sections.byPriority(openTasks, groups: groups, includeNone: false).filter { !$0.tasks.isEmpty },
            emptyTitle: "No Priorities",
            emptySymbol: "exclamationmark.3",
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
                ContentUnavailableView(emptyTitle, systemImage: emptySymbol, description: Text(emptyText))
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
