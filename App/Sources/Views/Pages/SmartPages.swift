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
        // The group's own tasks plus those of its subgroups, leaving out subgroups switched off
        // (the page's own group always shows, on or off).
        let offBelow = GroupTree.inactiveIDs(groups.filter { $0.uuid != groupID })
        let inside: Set<UUID> = groupID.map { id in
            Set([id] + GroupTree.descendants(of: id, in: groups).map(\.uuid).filter { !offBelow.contains($0) })
        } ?? []
        let mine = tasks.filter { task in
            if let groupID = task.groupID {
                guard inside.contains(groupID) else { return false }
            } else if groupID != nil {
                return false
            }
            if task.isDone { return showAllCompleted || (task.completedAt ?? .distantPast) >= app.dayStart }
            return true
        }
        let rows = PageBuilder.groupPage(
            groupID: groupID,
            tasks: mine,
            groups: groups,
            options: PageBuilder.Options(completed: completed, style: RowStyle(showDeferred: true), collapsedTasks: app.collapsedTaskIDs, rankDay: app.dayStart)
        )
        let open = mine.filter { !$0.isDone }.count
        let name = group?.displayName ?? "Quick Entry"

        TaskListView(rows: rows, allowsReorder: true, defaultGroupID: groupID) {
            GroupPageHeader(group: group, open: open, done: mine.count - open, today: app.dayStart, groups: groups)
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
                    if let group {
                        Button {
                            app.groupEditor = .subgroup(group)
                        } label: {
                            Label("New Subproject…", systemImage: "folder.badge.plus")
                        }
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
    var groups: [TaskGroup] = []

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let group, GroupTree.isOff(group, in: groups) {
                OffBanner(group: group, groups: groups)
            }
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
                let traits = app.store.traits(of: group)
                if !traits.isEmpty {
                    Label(traits.summary.joined(separator: " · "), systemImage: "wand.and.stars")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .help("New and moved tasks take these unless they have their own")
                }
                SubgroupSwitches(parent: group, groups: groups)
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
        let sections = Sections.upcoming(tasks.activeOnly(groups), groups: groups, today: app.dayStart)
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
        let sections = Sections.byPriority(tasks.activeOnly(groups), groups: groups, includeNone: false)
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
        let tagged = tasks.activeOnly(groups).filter { $0.tags.contains(tag) && PageBuilder.isOnToday($0, dayStart: app.dayStart) }
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

/// On the page of a group that's off: say so, and switch it back on in one tap.
struct OffBanner: View {
    let group: TaskGroup
    let groups: [TaskGroup]

    @Environment(AppModel.self) private var app

    /// The group above this one that's switched off.
    private var offAncestor: TaskGroup? {
        groups.first(where: { candidate in
            !candidate.isActive && GroupTree.descendants(of: candidate.uuid, in: groups).contains(where: { $0.uuid == group.uuid })
        })
    }

    var body: some View {
        // Off because of the group itself, or a group it sits in.
        let switchedOff: TaskGroup? = group.isActive ? offAncestor : group
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(switchedOff === group
                 ? "Off: these tasks stay out of Today, Plan and the other lists."
                 : "Off with “\(switchedOff?.displayName ?? "its group")”: these tasks stay out of the other lists.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let switchedOff {
                Button("Turn On") {
                    withAnimation(.snappy) { app.store.setActive(switchedOff, true) }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.1)))
    }
}

/// A group's subgroups as switches: tap one to turn it off (its tasks leave this page and every
/// list) or back on; touch and hold to open it.
struct SubgroupSwitches: View {
    let parent: TaskGroup
    let groups: [TaskGroup]

    @Environment(AppModel.self) private var app

    var body: some View {
        let children = groups.filter { $0.parentUUID == parent.uuid }.sorted { $0.sortOrder < $1.sortOrder }
        if !children.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(children, id: \.uuid) { child in
                        Button {
                            withAnimation(.snappy) { app.store.setActive(child, !child.isActive) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: child.isActive ? "circle.inset.filled" : "circle")
                                    .imageScale(.small)
                                Text(child.displayName)
                                    .lineLimit(1)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(child.isActive ? child.color.color : Color.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(child.isActive ? child.color.color.opacity(0.14) : Color.secondary.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(Color.secondary.opacity(child.isActive ? 0 : 0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in app.go(.group(child.uuid)) })
                        .accessibilityLabel(child.displayName)
                        .accessibilityValue(child.isActive ? "On" : "Off")
                        .accessibilityHint("Tap to switch it \(child.isActive ? "off" : "on"), touch and hold to open it")
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}
