import SwiftUI
import SwiftData
import TheoCore

/// The daily page — the heart of Theo. Like a daily note in Apple Notes: Quick Entry on top,
/// group headings below, checked items sink to the bottom. Unfinished tasks roll over to the
/// next day automatically; finished ones move to History.
struct TodayView: View {
    let dayStart: Date

    @Environment(AppModel.self) private var app
    @Query private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    @AppStorage(Prefs.completedMode) private var completedRaw = CompletedMode.bottom.rawValue
    @AppStorage(Prefs.quickEntryCollapsed) private var quickCollapsed = false
    @AppStorage(Prefs.todayGrouping) private var groupingRaw = TodayGrouping.groups.rawValue
    @State private var filter: TaskFilter = .all
    @State private var search = ""

    init(dayStart: Date) {
        self.dayStart = dayStart
        let start = dayStart
        let past = Date.distantPast
        _tasks = Query(
            filter: #Predicate<TaskItem> { task in
                task.deletedAt == nil && (task.isDone == false || (task.completedAt ?? past) >= start)
            },
            sort: \TaskItem.sortOrder
        )
    }

    private var completed: CompletedMode { CompletedMode(rawValue: completedRaw) ?? .bottom }
    private var grouping: TodayGrouping { TodayGrouping(rawValue: groupingRaw) ?? .groups }

    private var visible: [TaskItem] {
        tasks.filter { PageBuilder.isOnToday($0, dayStart: dayStart) }
    }

    private func rows(for visible: [TaskItem]) -> [ListRow] {
        let filtered = visible.filter { filter.matches($0, today: dayStart) }
        switch grouping {
        case .groups:
            var options = PageBuilder.Options(completed: completed, collapsedTasks: app.collapsedTaskIDs)
            if filter != .all {
                options.showEmptyPlaceholders = false
                let rows = PageBuilder.page(tasks: filtered, groups: groups, quickEntryCollapsed: false, options: options)
                return Self.droppingEmptySections(rows)
            }
            return PageBuilder.page(tasks: filtered, groups: groups, quickEntryCollapsed: quickCollapsed, options: options)
        case .priority:
            let options = PageBuilder.Options(completed: completed, style: RowStyle(showGroup: true))
            return PageBuilder.labeled(Sections.byPriority(filtered, groups: groups, includeNone: true), options: options)
        case .deadline:
            let options = PageBuilder.Options(completed: completed, style: RowStyle(showGroup: true))
            return PageBuilder.labeled(Sections.byDeadline(filtered, groups: groups, today: dayStart, includeNone: true), options: options)
        }
    }

    var body: some View {
        let visible = self.visible
        let rows = self.rows(for: visible)
        let open = visible.filter { !$0.isDone }.count
        let done = visible.count - open

        Group {
            if search.isEmpty {
                TaskListView(rows: rows, allowsReorder: grouping == .groups && filter == .all) {
                    TodayHeader(
                        date: dayStart,
                        open: open,
                        done: done,
                        filter: $filter,
                        tags: Sections.tags(in: visible.filter { !$0.isDone })
                    )
                }
            } else {
                SearchResultsView(query: search)
            }
        }
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search all tasks")
        #else
        .searchable(text: $search, prompt: "Search all tasks")
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.groupEditor = .new
                } label: {
                    Label("New Group", systemImage: "folder.badge.plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                pageMenu(rows: rows)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !app.isSelecting && search.isEmpty {
                QuickEntryBar(defaultGroupID: nil)
            }
        }
    }

    private func pageMenu(rows: [ListRow]) -> some View {
        Menu {
            Picker(selection: $groupingRaw) {
                ForEach(TodayGrouping.allCases) { grouping in
                    Label(grouping.title, systemImage: grouping.symbol).tag(grouping.rawValue)
                }
            } label: {
                Label("Group By", systemImage: "rectangle.3.group")
            }
            .pickerStyle(.menu)

            Picker(selection: $completedRaw) {
                ForEach(CompletedMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            } label: {
                Label("Completed Tasks", systemImage: "checkmark.circle")
            }
            .pickerStyle(.menu)

            Divider()
            Button {
                setAllCollapsed(false)
            } label: {
                Label("Expand All", systemImage: "chevron.down.2")
            }
            Button {
                setAllCollapsed(true)
            } label: {
                Label("Collapse All", systemImage: "chevron.up.2")
            }
            #if os(iOS)
            Button {
                app.isSelecting = true
            } label: {
                Label("Select Tasks", systemImage: "checklist")
            }
            #endif
            Divider()
            if !app.isSandbox {
                Button {
                    app.startTour()
                } label: {
                    Label("Take the Tour", systemImage: "graduationcap")
                }
            }
            ShareLink(item: TextExport.markdown(title: DateText.pageTitle(dayStart), rows: rows)) {
                Label("Share as Text", systemImage: "square.and.arrow.up")
            }
            Button {
                app.showImport = true
            } label: {
                Label("Import from Notes…", systemImage: "square.and.arrow.down")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    private func setAllCollapsed(_ collapsed: Bool) {
        withAnimation(.snappy) {
            quickCollapsed = collapsed
            for group in groups where group.isCollapsed != collapsed {
                app.store.setCollapsed(group, collapsed)
            }
        }
    }

    /// When a filter is active, headings without matching tasks are hidden.
    static func droppingEmptySections(_ rows: [ListRow]) -> [ListRow] {
        var result: [ListRow] = []
        var pendingHeader: ListRow?
        for row in rows {
            switch row {
            case .header:
                pendingHeader = row
            case .task:
                if let header = pendingHeader {
                    result.append(header)
                    pendingHeader = nil
                }
                result.append(row)
            case .placeholder:
                break
            }
        }
        return result
    }
}

struct TodayHeader: View {
    let date: Date
    let open: Int
    let done: Int
    @Binding var filter: TaskFilter
    let tags: [String]

    private var total: Int { open + done }

    private var summary: String {
        if total == 0 { return "A fresh page. Type below to start." }
        if open == 0 { return "All done — enjoy your day ✨" }
        return "\(open) to do · \(done) done"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(progress: total == 0 ? 0 : Double(done) / Double(total))
                    Text("\(done)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateText.pageTitle(date))
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChipButton(title: "All", isOn: filter == .all) { filter = .all }
                    ChipButton(title: "Priority", symbol: "exclamationmark.3", color: .red, isOn: filter == .priority) {
                        toggle(.priority)
                    }
                    ChipButton(title: "Due", symbol: "calendar", color: .orange, isOn: filter == .due) {
                        toggle(.due)
                    }
                    ForEach(tags, id: \.self) { tag in
                        ChipButton(title: "#" + tag, color: TheoColor.forTag(tag).color, isOn: filter == .tag(tag)) {
                            toggle(.tag(tag))
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private func toggle(_ value: TaskFilter) {
        filter = filter == value ? .all : value
    }
}

/// Search across everything, including completed history.
struct SearchResultsView: View {
    let query: String

    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        let matches = tasks.filter { PageBuilder.matches($0, search: query) }
        if matches.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            TaskListView(
                rows: PageBuilder.labeled(Sections.byGroup(matches, groups: groups), options: PageBuilder.Options(completed: .bottom)),
                allowsReorder: false
            )
        }
    }
}
