import SwiftUI
import SwiftData
import TheoCore

/// A single group (or Quick Entry) as its own page, including tasks hidden with "Not Today".
struct GroupPageView: View {
    let groupID: UUID?

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @AppStorage(Prefs.completedMode) private var completedRaw = CompletedMode.bottom.rawValue
    @State private var showAllCompleted = false

    var body: some View {
        let group = groups.first { $0.uuid == groupID }
        if groupID != nil && group == nil {
            ContentUnavailableView("Group Not Found", systemImage: "folder", description: Text("It may have been deleted on another device."))
        } else {
            content(group: group)
        }
    }

    @ViewBuilder
    private func content(group: TaskGroup?) -> some View {
        let completed = showAllCompleted ? CompletedMode.bottom : (CompletedMode(rawValue: completedRaw) ?? .bottom)
        let mine = tasks.filter { task in
            guard task.groupID == groupID else { return false }
            if task.isDone { return showAllCompleted || (task.completedAt ?? .distantPast) >= app.dayStart }
            return true
        }
        let ordered = PageBuilder.ordered(mine, completed: completed)
        let rows = ordered.map { ListRow.task($0.task, depth: $0.depth, style: RowStyle(showDeferred: true)) }
        let open = mine.filter { !$0.isDone }.count
        let name = group?.displayName ?? "Quick Entry"

        TaskListView(rows: rows, allowsReorder: true, defaultGroupID: groupID) {
            GroupPageHeader(group: group, open: open, done: mine.count - open, today: app.dayStart)
        }
        .navigationTitle(name)
        .toolbar {
            if let group {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        app.groupEditor = .edit(group)
                    } label: {
                        Label("Edit Group", systemImage: "pencil")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle(isOn: $showAllCompleted) {
                        Label("Show All Completed", systemImage: "clock.arrow.circlepath")
                    }
                    Button {
                        withAnimation(.snappy) { app.store.completeAll(in: groupID) }
                    } label: {
                        Label("Complete All", systemImage: "checkmark.circle")
                    }
                    #if os(iOS)
                    Button {
                        app.isSelecting = true
                    } label: {
                        Label("Select Tasks", systemImage: "checklist")
                    }
                    #endif
                    ShareLink(item: TextExport.markdown(title: name, rows: rows)) {
                        Label("Share as Text", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !app.isSelecting {
                QuickEntryBar(defaultGroupID: groupID, placeholder: "Add to \(name)")
            }
        }
    }
}

struct GroupPageHeader: View {
    let group: TaskGroup?
    let open: Int
    let done: Int
    let today: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let group {
                HStack(spacing: 10) {
                    Image(systemName: group.symbol)
                        .font(.title2)
                        .foregroundStyle(group.color.color)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(group.color.color.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(open) open · \(done) done")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let due = group.dueDate {
                            Label("Deadline \(DateText.due(due, hasTime: false, today: today))", systemImage: "flag.checkered")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DateText.dayDelta(due, today: today) < 0 ? Color.red : Color.orange)
                        }
                    }
                }
                if group.isProject, open + done > 0 {
                    ProgressView(value: Double(done), total: Double(open + done))
                        .tint(group.color.color)
                }
                if !group.notes.isEmpty {
                    Text(group.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Everything you threw in quickly. Drag tasks onto a group, or swipe left → Move.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Everything with a deadline (or hidden until a later day), one section per day.
struct UpcomingView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        let sections = Sections.upcoming(tasks, groups: groups, today: app.dayStart)
        let rows = PageBuilder.labeled(sections, options: PageBuilder.Options(style: RowStyle(showGroup: true, showDeferred: true)))
        Group {
            if rows.isEmpty {
                ContentUnavailableView("Nothing Scheduled", systemImage: "calendar",
                                       description: Text("Tasks with a deadline appear here. Try typing “Pay rent friday” below."))
            } else {
                TaskListView(rows: rows, allowsReorder: false)
            }
        }
        .navigationTitle("Upcoming")
        .safeAreaInset(edge: .bottom) {
            QuickEntryBar(defaultGroupID: nil, placeholder: "Add with a date, e.g. “dentist fri 3pm”")
        }
    }
}

/// All open tasks with a priority, highest first.
struct PriorityView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        let sections = Sections.byPriority(tasks, groups: groups, includeNone: false)
        let rows = PageBuilder.labeled(sections, options: PageBuilder.Options(style: RowStyle(showGroup: true)))
        Group {
            if rows.isEmpty {
                ContentUnavailableView("No Priorities Set", systemImage: "exclamationmark.3",
                                       description: Text("Add !, !! or !!! when typing a task, or long-press a task → Priority."))
            } else {
                TaskListView(rows: rows, allowsReorder: false)
            }
        }
        .navigationTitle("Priority")
        .safeAreaInset(edge: .bottom) {
            QuickEntryBar(defaultGroupID: nil, placeholder: "Add an important task, e.g. “Call bank !!!”")
        }
    }
}

/// Tasks carrying one tag, grouped by their group.
struct TagView: View {
    let tag: String

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        let tagged = tasks.filter { $0.tags.contains(tag) && PageBuilder.isOnToday($0, dayStart: app.dayStart) }
        let rows = PageBuilder.labeled(Sections.byGroup(tagged, groups: groups), options: PageBuilder.Options())
        Group {
            if rows.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "number", description: Text("Nothing tagged #\(tag) right now."))
            } else {
                TaskListView(rows: rows, allowsReorder: false)
            }
        }
        .navigationTitle("#" + tag)
    }
}
