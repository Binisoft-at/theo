import SwiftUI
import SwiftData
import TheoCore

/// The daily page: only what was planned for today, ranked by importance and urgency, with
/// finished tasks sinking to the bottom. Nothing lands here by itself; Plan picks the tasks, and
/// a strip under the header offers what earlier days left open and what's due without a plan.
struct TodayView: View {
    let dayStart: Date

    @Environment(AppModel.self) private var app
    /// Every live task. The page, the carry-over strip, the last week (for "usually") and the
    /// full sections that nest each line under its real parent all come from this one fetch.
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    @AppStorage(Prefs.completedMode) private var completedRaw = CompletedMode.bottom.rawValue
    @AppStorage(Prefs.quickEntryCollapsed) private var quickCollapsed = false
    @AppStorage(Prefs.todayGrouping) private var groupingRaw = TodayGrouping.ranked.rawValue
    @State private var filter: TaskFilter = .all

    init(dayStart: Date) {
        self.dayStart = dayStart
    }

    private var completed: CompletedMode { CompletedMode(rawValue: completedRaw) ?? .bottom }
    private var grouping: TodayGrouping { TodayGrouping(rawValue: groupingRaw) ?? .ranked }

    /// `sections`: every live task by group, so a subtask planned without its parent stands on
    /// its own instead of under whatever line comes before it.
    private func rows(for visible: [TaskItem], sections: [UUID?: [TaskItem]]) -> [ListRow] {
        let filtered = visible.filter { filter.matches($0, today: dayStart) }
        var options = PageBuilder.Options(completed: completed, style: RowStyle(showGroup: true), collapsedTasks: app.collapsedTaskIDs, rankDay: dayStart)
        options.fullSections = sections
        switch grouping {
        case .ranked:
            return PageBuilder.rankedRows(filtered, options: options)
        case .groups:
            options.style = RowStyle()
            if filter != .all {
                options.showEmptyPlaceholders = false
                let rows = PageBuilder.page(tasks: filtered, groups: groups.activeOnly, quickEntryCollapsed: false, options: options)
                return Self.droppingEmptySections(rows)
            }
            return PageBuilder.page(tasks: filtered, groups: groups.activeOnly, quickEntryCollapsed: quickCollapsed, options: options)
        case .topGroups:
            return PageBuilder.rankedSections(Sections.byTopGroup(filtered, groups: groups.activeOnly), options: options)
        case .deadline:
            return PageBuilder.labeled(Sections.byDeadline(filtered, groups: groups, today: dayStart, includeNone: true), options: options)
        case .priority:
            return PageBuilder.labeled(Sections.byPriority(filtered, groups: groups, includeNone: true), options: options)
        case .tags:
            return PageBuilder.labeled(Sections.byTag(filtered), options: options)
        case .size:
            return PageBuilder.labeled(Sections.bySize(filtered), options: options)
        }
    }

    /// Finished in the seven days before today, by the (logical) day they were finished.
    private func finishedLastWeek() -> [Date: [TaskItem]] {
        let boundary = DayBoundary.current
        let weekStart = boundary.dayStart(byAdding: -7, to: dayStart)
        var result: [Date: [TaskItem]] = [:]
        for task in tasks where task.isDone {
            guard let finishedAt = task.completedAt, finishedAt >= weekStart, finishedAt < dayStart else { continue }
            result[boundary.start(of: finishedAt), default: []].append(task)
        }
        return result
    }

    var body: some View {
        let active = tasks.activeOnly(groups)
        // Planned for today, leaving out groups that are switched off.
        let visible = active.filter { PageBuilder.isOnToday($0, dayStart: dayStart) }
        let sections = Dictionary(grouping: tasks, by: \.groupID)
        let rows = self.rows(for: visible, sections: sections)
        let open = visible.filter { !$0.isDone }.count
        let done = visible.count - open
        let estimates = PageBuilder.estimateTotals(visible, fullSections: sections)
        let carry = CarryOver.compute(open: active.filter { !$0.isDone }, dayStart: dayStart, sections: sections)
        let lastWeek = finishedLastWeek()
        // What a usual day gets done, the way the Day Review counts a day.
        let usual = DayReview.activeAverage(lastWeek.map {
            DayReview.Day(start: $0.key, powerHours: PageBuilder.estimateTotals($0.value).done, done: $0.value.count)
        })

        TaskListView(rows: rows, allowsReorder: grouping.allowsReorder && filter == .all, plansFor: dayStart, rankOnly: grouping == .ranked) {
            TodayHeader(
                date: dayStart,
                open: open,
                done: done,
                openEstimate: estimates.open,
                doneEstimate: estimates.done,
                usual: usual,
                carry: carry,
                offersCarryOver: !visible.isEmpty,
                filter: $filter,
                tags: Sections.tags(in: visible.filter { !$0.isDone })
            )
            if visible.isEmpty {
                PlanPrompt(
                    dayStart: dayStart,
                    carry: carry,
                    doneYesterday: lastWeek[DayBoundary.current.dayStart(byAdding: -1, to: dayStart)] ?? []
                )
            }
        }
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                focusButton
            }
            if !app.isSelecting {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        app.isSelecting = true
                    } label: {
                        Label("Select", systemImage: "checklist")
                    }
                }
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                focusButton
                    .help("Focus Timer (⇧⌘F)")
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                pageMenu(rows: rows, visible: visible)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !app.isSelecting {
                QuickEntryBar(defaultGroupID: nil, placeholder: "Add a task for today", plansFor: dayStart)
            }
        }
    }

    /// Opens the focus timer (the running one, if there is one).
    private var focusButton: some View {
        Button {
            app.showFocus = true
        } label: {
            Label("Focus", systemImage: "scope")
        }
    }

    private func pageMenu(rows: [ListRow], visible: [TaskItem]) -> some View {
        let parents = Self.parents(in: rows)
        return Menu {
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
            // Only where there's something to fold: group headings, or parents with subtasks.
            if grouping == .groups || !parents.isEmpty {
                Button {
                    setAllCollapsed(false, parents: parents, visible: visible)
                } label: {
                    Label("Expand All", systemImage: "chevron.down.2")
                }
                Button {
                    setAllCollapsed(true, parents: parents, visible: visible)
                } label: {
                    Label("Collapse All", systemImage: "chevron.up.2")
                }
            }
            Button {
                app.reviewDay = DayRef(start: dayStart)
            } label: {
                Label("Day Review", systemImage: "chart.bar.xaxis")
            }
            Button {
                app.groupEditor = .new
            } label: {
                Label("New Group…", systemImage: "folder.badge.plus")
            }
            Divider()
            if !app.isSandbox {
                #if os(iOS)
                Button {
                    app.showSettings = true
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                #endif
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

    /// Lines on the page that have subtasks, folded or not.
    private static func parents(in rows: [ListRow]) -> [TaskItem] {
        rows.compactMap { row -> TaskItem? in
            guard case .task(let task, _, let style) = row, style.subtaskCount > 0 else { return nil }
            return task
        }
    }

    /// Groups & Subgroups folds its group headings (synced, as on the group pages). The other
    /// layouts have no headings that fold, so there it folds the parents' subtasks, on this
    /// device only.
    private func setAllCollapsed(_ collapsed: Bool, parents: [TaskItem], visible: [TaskItem]) {
        withAnimation(.snappy) {
            if grouping == .groups {
                quickCollapsed = collapsed
                for group in groups where group.isCollapsed != collapsed {
                    app.store.setCollapsed(group, collapsed)
                }
            } else if collapsed {
                for task in parents where !app.collapsedTaskIDs.contains(task.uuid) {
                    app.toggleSubtasks(task)
                }
            } else {
                // Also parents folded inside a folded parent, which aren't rows yet.
                for task in visible where app.collapsedTaskIDs.contains(task.uuid) {
                    app.toggleSubtasks(task)
                }
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
    var openEstimate: Double = 0
    var doneEstimate: Double = 0
    /// Power Hours a usual day gets done (0 until there's enough history to tell).
    var usual: Double = 0
    var carry = CarryOver.Result()
    /// Shows the carry-over strip (an empty page has the plan prompt's buttons instead).
    var offersCarryOver = false
    @Binding var filter: TaskFilter
    let tags: [String]

    @Environment(AppModel.self) private var app
    /// The start of the day the carry-over strip was hidden on (seconds since 1970), per device.
    @AppStorage("today.carryDismissedDay") private var carryDismissedDay: Double = 0
    /// The tour's practice page hides it without touching the real setting.
    @State private var carryHiddenHere = false

    private var total: Int { open + done }

    private var summary: String {
        if total == 0 { return "Nothing planned yet." }
        if open == 0 {
            // Never "all done" while earlier days left something open or something is due.
            if !carry.leftOver.isEmpty { return "All planned done · \(carry.leftOver.count) left from earlier" }
            if !carry.dueUnplanned.isEmpty { return "All planned done · \(carry.dueUnplanned.count) due by today" }
            return "All done — enjoy your day ✨"
        }
        return "\(open) to do · \(done) done"
    }

    private var isOverplanned: Bool {
        DayReview.isOverplanned(planned: openEstimate + doneEstimate, average: usual)
    }

    /// "3,5 PH left · 0,75 done · usually ~3 PH".
    private var estimateText: String {
        var text = "\(PowerHours.number(openEstimate)) PH left · \(PowerHours.number(doneEstimate)) done"
        if usual > 0 {
            // A usual day to the nearest quarter (a very small one as it is).
            let quarter = (usual * 4).rounded() / 4
            text += " · usually ~" + PowerHours.format(quarter > 0 ? quarter : usual)
        }
        if isOverplanned { text += " · more than a usual day" }
        return text
    }

    private var showsCarryOver: Bool {
        guard offersCarryOver, !carry.isEmpty else { return false }
        if app.isSandbox { return !carryHiddenHere }
        return carryDismissedDay != date.timeIntervalSince1970
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    app.reviewDay = DayRef(start: date)
                } label: {
                    ZStack {
                        ProgressRing(progress: total == 0 ? 0 : Double(done) / Double(total))
                        Text("\(done)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Day review")
                .accessibilityHint("Shows what got done today")
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateText.pageTitle(date))
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if openEstimate > 0 || doneEstimate > 0 {
                        estimateLine
                    }
                }
                Spacer(minLength: 0)
                if let session = app.focus {
                    FocusPill(session: session)
                }
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
            if showsCarryOver {
                CarryOverStrip(date: date, carry: carry) {
                    hideCarryOver()
                }
                .transition(.opacity)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    /// Power Hours still open and done today, against a usual day. A plan clearly bigger than
    /// that turns orange and opens Plan.
    @ViewBuilder
    private var estimateLine: some View {
        let line = Label(estimateText, systemImage: "timer")
            .labelStyle(CompactLabelStyle())
            .font(.caption.weight(.medium))
            .multilineTextAlignment(.leading)
        if isOverplanned {
            Button {
                app.go(.plan)
            } label: {
                line.foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Plan")
        } else {
            line.foregroundStyle(.secondary)
        }
    }

    private func toggle(_ value: TaskFilter) {
        filter = filter == value ? .all : value
    }

    private func hideCarryOver() {
        withAnimation(.snappy) {
            if app.isSandbox {
                carryHiddenHere = true
            } else {
                carryDismissedDay = date.timeIntervalSince1970
            }
        }
    }
}

/// Under Today's chips: what earlier days left open and what's due without a plan, each one tap
/// away from today's plan (with Undo). The words open Plan to pick by hand; × hides the strip
/// until tomorrow.
struct CarryOverStrip: View {
    let date: Date
    let carry: CarryOver.Result
    let onHide: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                if !carry.leftOver.isEmpty {
                    CarryOverCapsule(
                        text: "\(carry.leftOver.count) unfinished from earlier",
                        symbol: "arrow.uturn.forward",
                        color: .orange,
                        buttonTitle: "Bring Over"
                    ) {
                        app.plan(carry.leftOver, for: date)
                    }
                }
                if !carry.dueUnplanned.isEmpty {
                    CarryOverCapsule(
                        text: "\(carry.dueUnplanned.count) due by today, not planned",
                        symbol: "calendar.badge.exclamationmark",
                        color: .red,
                        buttonTitle: "Add"
                    ) {
                        app.plan(carry.dueUnplanned, for: date)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: onHide) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide until tomorrow")
            .help("Hide until tomorrow")
        }
    }
}

/// One line of the carry-over strip: what it is (tap: open Plan) and its one-tap action.
private struct CarryOverCapsule: View {
    let text: String
    let symbol: String
    let color: Color
    let buttonTitle: String
    let perform: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.self) private var environment

    var body: some View {
        HStack(spacing: 8) {
            Button {
                app.go(.plan)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: symbol)
                        .imageScale(.small)
                        .foregroundStyle(color)
                    Text(text)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.subheadline.weight(.medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Plan")
            Button {
                withAnimation(.snappy) { perform() }
            } label: {
                Text(buttonTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color.onFillForeground(in: environment))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(color))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

/// Today with nothing planned: start planning, or bring over what's left from earlier days.
struct PlanPrompt: View {
    let dayStart: Date
    /// What earlier days left open and what's due without a plan (see `CarryOver`).
    var carry = CarryOver.Result()
    /// Finished yesterday, for the link to its review.
    var doneYesterday: [TaskItem] = []

    @Environment(AppModel.self) private var app

    var body: some View {
        let leftOver = carry.leftOver
        let due = carry.dueUnplanned
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Pick what today is for")
                .font(.headline)
            Text("Today only shows the tasks you plan for it. Choose them in Plan, or add one below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                app.go(.plan)
            } label: {
                Label("Plan Today", systemImage: "calendar.badge.plus")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.glassProminent)
            if !leftOver.isEmpty {
                Button {
                    withAnimation(.snappy) { app.plan(leftOver, for: dayStart) }
                } label: {
                    Label(leftOver.count == 1 ? "Bring Over 1 Unfinished Task" : "Bring Over \(leftOver.count) Unfinished Tasks",
                          systemImage: "arrow.uturn.forward")
                }
                .buttonStyle(.glass)
            }
            if !due.isEmpty {
                Button {
                    withAnimation(.snappy) { app.plan(due, for: dayStart) }
                } label: {
                    Label(due.count == 1 ? "Add 1 Task Due Today" : "Add \(due.count) Tasks Due by Today", systemImage: "calendar")
                }
                .buttonStyle(.glass)
            }
            if !doneYesterday.isEmpty {
                let powerHours = PageBuilder.estimateTotals(doneYesterday).done
                Button {
                    app.reviewDay = DayRef(start: DayBoundary.current.dayStart(byAdding: -1, to: dayStart))
                } label: {
                    Label("Yesterday: \(doneYesterday.count) done" + (powerHours > 0 ? " · " + PowerHours.format(powerHours) : "") + " · Review",
                          systemImage: "chart.bar.xaxis")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .listRowSeparator(.hidden)
    }
}

/// Search across everything, including finished tasks: open matches first, ranked within their
/// group, then the finished ones, folded away until asked for (shown right away when nothing
/// open matches). An ongoing task's logs stay out; the task itself is the match.
struct SearchResultsView: View {
    let query: String

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @State private var showsFinished = false

    var body: some View {
        // The cheap text match first: reading `loggedFor` decodes the task's extras.
        let matches = tasks.filter { PageBuilder.matches($0, search: query) && $0.loggedFor == nil }
        let open = matches.filter { !$0.isDone }
        let finished = matches.filter(\.isDone)
        if matches.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            TaskListView(rows: rows(open: open, finished: finished), allowsReorder: false) {
                summary(open: open.count, finished: finished.count)
            }
        }
    }

    private func rows(open: [TaskItem], finished: [TaskItem]) -> [ListRow] {
        var sections = Sections.byGroup(open, groups: groups)
        if showsFinished || open.isEmpty {
            sections.append((key: "finished", title: "Finished", symbol: "checkmark.circle", color: .green, tasks: finished))
        }
        return PageBuilder.labeled(sections, options: PageBuilder.Options(completed: .bottom, rankDay: app.dayStart))
    }

    /// "3 open" and the switch for the finished matches.
    private func summary(open: Int, finished: Int) -> some View {
        let openText: String = open == 0 ? "Nothing open matches" : (open == 1 ? "1 open" : "\(open) open")
        let toggleText: String = showsFinished ? "Hide Finished" : "Show \(finished) Finished"
        let finishedText: String = finished == 1 ? "1 finished" : "\(finished) finished"
        return HStack(spacing: 8) {
            Text(openText)
            Spacer(minLength: 8)
            if finished > 0 && open > 0 {
                Button(toggleText) {
                    withAnimation(.snappy) { showsFinished.toggle() }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
            } else if finished > 0 {
                Text(finishedText)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
