import SwiftUI
import SwiftData
import TheoCore

/// A single group (or Quick Entry) as its own page: every task in it, planned or not.
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
            PageEmptyState(title: "Group Not Found", symbol: "folder", color: Color.secondary,
                           message: "It may have been deleted on another device.")
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
        let rows = pageRows(mine, completed: completed)
        let open = mine.filter { !$0.isDone }.count
        // Ongoing tasks never finish (checking one off only logs it), so they stay out.
        let toComplete = mine.filter { !$0.isDone && !$0.isOngoing }
        let name = group?.displayName ?? "Quick Entry"

        TaskListView(rows: rows, allowsReorder: true, defaultGroupID: groupID) {
            GroupPageHeader(group: group, open: open, done: mine.count - open, today: app.dayStart, groups: groups,
                            stats: TaskStats(mine, today: app.dayStart))
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
                    Toggle(isOn: $showAllCompleted.animation(Motion.resolved(Motion.list))) {
                        Label("Show All Completed", systemImage: "clock.arrow.circlepath")
                    }
                    Button {
                        app.complete(toComplete)
                    } label: {
                        Label("Complete All Open", systemImage: "checkmark.circle")
                    }
                    .disabled(toComplete.isEmpty)
                    if let group {
                        Button {
                            app.groupEditor = .subgroup(group)
                        } label: {
                            Label("New Subgroup…", systemImage: "folder.badge.plus")
                        }
                        Button {
                            app.store.setFavorite(group, !group.isFavorite)
                        } label: {
                            Label(group.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: group.isFavorite ? "star.slash" : "star")
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

    /// The page's rows. Nesting comes from each group's whole stored list (every live task, open
    /// or done), so a subtask whose parent isn't shown here isn't drawn under another task.
    private func pageRows(_ mine: [TaskItem], completed: CompletedMode) -> [ListRow] {
        var options = PageBuilder.Options(completed: completed, style: RowStyle(showDeferred: true), collapsedTasks: app.collapsedTaskIDs, rankDay: app.dayStart)
        options.fullSections = Dictionary(grouping: tasks, by: \.groupID)
        return PageBuilder.groupPage(groupID: groupID, tasks: mine, groups: groups, options: options)
    }
}

/// The top of a group's page: its icon on a disc of its colour, its deadline and figures, then
/// what it hands to new tasks and its subgroups. Quick Entry has the figures and what it's for.
struct GroupPageHeader: View {
    let group: TaskGroup?
    let open: Int
    let done: Int
    let today: Date
    var groups: [TaskGroup] = []
    var stats: TaskStats?

    @Environment(AppModel.self) private var app

    /// Off by itself, or with a group it sits in.
    private var isOff: Bool {
        guard let group else { return false }
        return GroupTree.isOff(group, in: groups)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let group, isOff {
                OffBanner(group: group, groups: groups)
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
            if let group {
                groupSummary(group)
            } else {
                quickEntrySummary
            }
        }
        .padding(.vertical, 4)
        .animation(Motion.resolved(Motion.layout), value: isOff)
    }

    /// The counts live in the figures; next to the icon only what they don't say.
    @ViewBuilder
    private func groupSummary(_ group: TaskGroup) -> some View {
        HStack(spacing: 12) {
            iconTile(group)
            VStack(alignment: .leading, spacing: 6) {
                if let due = group.dueDate {
                    deadline(due)
                }
                if let stats {
                    figuresBesideIcon(stats)
                }
            }
        }
        if group.isProject, open + done > 0 {
            ProgressView(value: Double(done), total: Double(open + done))
                .tint(group.color.color)
                .animation(Motion.resolved(Motion.layout), value: done)
        }
        if !group.notes.isEmpty {
            Text(group.notes)
                .theoFont(.callout)
                .foregroundStyle(.secondary)
        }
        traitsButton(group)
        SubgroupSwitches(parent: group, groups: groups)
    }

    /// The group's icon on a disc of its colour, like a list in Reminders. The glyph is white,
    /// and dark on yellow, where white wouldn't read.
    private func iconTile(_ group: TaskGroup) -> some View {
        let glyph: Color = group.color == .yellow ? Color.black.opacity(0.75) : Color.white
        return Image(systemName: group.symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(glyph)
            .frame(width: 44, height: 44)
            .background(Circle().fill(group.color.color.gradient))
            .accessibilityHidden(true)
    }

    /// A project's deadline in the deadline's blue, calm orange once it's today or past.
    private func deadline(_ due: Date) -> some View {
        let reached = DateText.dayDelta(due, today: today) <= 0
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "calendar")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("Deadline \(DateText.due(due, hasTime: false, today: today))")
        }
        .theoFont(.caption, weight: .semibold)
        .foregroundStyle(reached ? Tint.overdue : Tint.deadline)
    }

    /// The figures beside the icon: clipped on the left so they don't scroll over it, and
    /// running on to the screen's edge on the right like any row of chips.
    private func figuresBesideIcon(_ stats: TaskStats) -> some View {
        TaskStatsBar(stats: stats)
            .contentMargins(.trailing, edgeBleed, for: .scrollContent)
            .clipped()
            .padding(.trailing, -edgeBleed)
    }

    /// What the group hands to tasks placed in it; tap to change it.
    @ViewBuilder
    private func traitsButton(_ group: TaskGroup) -> some View {
        let traits = app.store.traits(of: group)
        if !traits.isEmpty {
            Button {
                app.groupEditor = .edit(group)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .symbolRenderingMode(.hierarchical)
                    Text("New tasks get " + traits.summary.joined(separator: " · "))
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(.tertiary)
                }
                .theoFont(.caption, weight: .medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.1)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .help("New and moved tasks take these unless they have their own")
            .accessibilityHint("Opens the group's settings")
        }
    }

    private var quickEntrySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stats {
                TaskStatsBar(stats: stats)
                    .contentMargins(.horizontal, edgeBleed, for: .scrollContent)
                    .padding(.horizontal, -edgeBleed)
            }
            Text("Everything you threw in quickly. Drag tasks onto a group, or swipe left → Move.")
                .theoFont(.callout)
                .foregroundStyle(.secondary)
        }
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
        let rows = PageBuilder.labeled(sections, options: PageBuilder.Options(style: RowStyle(showGroup: true, showDeferred: true), rankDay: app.dayStart))
        Group {
            if rows.isEmpty {
                PageEmptyState(title: "Nothing Scheduled", symbol: "calendar", color: Tint.deadline,
                               message: "Tasks with a deadline appear here. Try typing “Pay rent friday” below.")
            } else {
                TaskListView(rows: rows, allowsReorder: false)
            }
        }
        .animation(Motion.resolved(Motion.layout), value: rows.isEmpty)
        .navigationTitle("Upcoming")
        .safeAreaInset(edge: .bottom) {
            QuickEntryBar(defaultGroupID: nil, placeholder: "Add with a date: fri 3pm")
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
        let rows = PageBuilder.labeled(sections, options: PageBuilder.Options(style: RowStyle(showGroup: true), rankDay: app.dayStart))
        Group {
            if rows.isEmpty {
                PageEmptyState(title: "No Priorities Set", symbol: "exclamationmark", color: Tint.priority,
                               message: "Add !, !! or !!! when typing a task, or long-press a task → Priority.")
            } else {
                TaskListView(rows: rows, allowsReorder: false)
            }
        }
        .animation(Motion.resolved(Motion.layout), value: rows.isEmpty)
        .navigationTitle("Priority")
        .safeAreaInset(edge: .bottom) {
            QuickEntryBar(defaultGroupID: nil, placeholder: "Add an important task !!")
        }
    }
}

/// Every open task carrying one tag (plus those finished today), grouped by their group and
/// ranked, the same set the sidebar counts.
struct TagView: View {
    let tag: String

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        let dayStart = app.dayStart
        let tagged = tasks.activeOnly(groups).filter { task in
            task.tags.contains(tag) && (!task.isDone || (task.completedAt ?? .distantPast) >= dayStart)
        }
        let rows = PageBuilder.labeled(Sections.byGroup(tagged, groups: groups),
                                       options: PageBuilder.Options(completed: .bottom, style: RowStyle(showDeferred: true), rankDay: dayStart))
        let toPlan = tagged.filter { !$0.isDone && !$0.isPlanned(for: dayStart) }
        Group {
            if rows.isEmpty {
                PageEmptyState(title: "No Tasks", symbol: "number", color: TheoColor.forTag(tag).color,
                               message: "No open tasks tagged #\(tag).")
            } else {
                TaskListView(rows: rows, allowsReorder: false)
            }
        }
        .animation(Motion.resolved(Motion.layout), value: rows.isEmpty)
        .navigationTitle("#" + tag)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Motion.animate(Motion.list) { app.plan(toPlan, for: dayStart) }
                    } label: {
                        Label("Plan All for Today", systemImage: "sun.max.fill")
                    }
                    .disabled(toPlan.isEmpty)
                    Button {
                        saveAsView()
                    } label: {
                        Label("Save as View", systemImage: "square.and.arrow.down")
                    }
                    #if os(iOS)
                    Button {
                        app.isSelecting = true
                    } label: {
                        Label("Select Tasks", systemImage: "checklist")
                    }
                    .disabled(rows.isEmpty)
                    #endif
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
    }

    /// A saved view of this tag's open tasks, opened right away (it stays in the sidebar).
    private func saveAsView() {
        var query = TaskQuery.standard
        query.tags = [tag]
        let view = app.store.addView(name: "#" + tag, query: query)
        app.go(.view(view.uuid))
        app.show("Saved “\(view.displayName)” · it's in the sidebar", symbol: "square.and.arrow.down.fill")
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
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill")
                .theoFont(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(switchedOff === group
                 ? "Off: these tasks stay out of Today, Plan and the other lists."
                 : "Off with “\(switchedOff?.displayName ?? "its group")”: these tasks stay out of the other lists.")
                .theoFont(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let switchedOff {
                Button {
                    Motion.animate(Motion.list) { app.store.setActive(switchedOff, true) }
                } label: {
                    Text("Turn On")
                        .theoFont(.footnote, weight: .semibold)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.secondary.opacity(0.1)))
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
                HStack(spacing: 8) {
                    ForEach(children, id: \.uuid) { child in
                        switchChip(child)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, edgeBleed)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -edgeBleed)
        }
    }

    /// On: a filled dot in the subgroup's colour and its name in the text colour. Off: a hollow
    /// dot in a dashed outline, everything quieter.
    private func switchChip(_ child: TaskGroup) -> some View {
        let isOn = child.isActive
        return Button {
            Motion.animate(Motion.list) { app.store.setActive(child, !child.isActive) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "circle.inset.filled" : "circle")
                    .imageScale(.small)
                    .foregroundStyle(isOn ? child.color.color : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                Text(child.displayName)
                    .lineLimit(1)
                    .foregroundStyle(isOn ? Color.primary : Color.secondary)
            }
            .theoFont(.caption, weight: .semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.secondary.opacity(isOn ? 0.12 : 0.05)))
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(isOn ? 0 : 0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in app.go(.group(child.uuid)) })
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(child.displayName)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint("Tap to switch it \(isOn ? "off" : "on"), touch and hold to open it")
    }
}

/// A page with nothing to show: a symbol in the colour of what the page is about, a title and
/// one calm line, at Theo's text size. It fades in and out as the page empties or fills.
struct PageEmptyState: View {
    let title: String
    let symbol: String
    /// The page's colour (deadlines blue, priority purple …); nil = the accent.
    var color: Color?
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
                    .theoFont(.title3, weight: .semibold)
            } icon: {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tint))
            }
        } description: {
            Text(message)
                .theoFont(.subheadline)
        }
        .transition(.opacity)
    }
}

/// How far a row of chips reaches past the list's side margin, so it scrolls from one edge of
/// the screen to the other (the Mac's list has narrower margins).
#if os(macOS)
private let edgeBleed: CGFloat = 8
#else
private let edgeBleed: CGFloat = 16
#endif
