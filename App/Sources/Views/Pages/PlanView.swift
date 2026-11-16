import SwiftUI
import SwiftData
import TheoCore

/// Pick what each day is for: choose a day, then plan tasks for it. Unfinished tasks from
/// earlier days, tasks due by then and the most important ones come first; everything else
/// follows by group. A planned parent shows once, with its subtasks counted. Planning ahead
/// keeps the plans of the days in between apart (folded, without "Add All").
struct PlanView: View {
    @Environment(AppModel.self) private var app
    /// Every live line, finished ones too, so subtasks nest under their parents exactly as the
    /// group page shows them.
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var allLive: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @State private var selected: Date?
    /// How "Browse All Tasks" is sorted into sections, which are open, and what's searched.
    @AppStorage("plan.browse") private var browseRaw = PlanBrowse.group.rawValue
    @State private var expanded: Set<String> = []
    @State private var browseSearch = ""
    /// The task whose colourful quick-action panel is open (Quick Edit in a line's menu).
    @State private var actionTaskID: UUID?

    /// Logical start of the selected day (defaults to today).
    private var day: Date { selected ?? app.dayStart }

    /// The folded "Already planned earlier" section's key in `expanded`.
    private static let earlierKey = "plan.earlier"

    #if os(macOS)
    private static let emptyHint = "Nothing planned yet. Click a task's circle below to add it."
    private static let browseHint = "Click a section to open it, then a task's circle to plan it (its subtasks come along). Click a task to see its details."
    #else
    private static let emptyHint = "Nothing planned yet. Tap a task below to add it."
    private static let browseHint = "Tap a section to open it, then tap a task to plan it (its subtasks come along)."
    #endif

    var body: some View {
        let day = self.day
        let live = allLive
        // Groups that are switched off stay out of planning.
        let openTasks = live.filter { !$0.isDone }.activeOnly(groups)
        let delta = DateText.dayDelta(day, today: app.dayStart)
        let todayKey = app.todayKey
        let dayKey = Calendar.current.startOfDay(for: day)
        let planned = rankedTop(openTasks.filter { $0.isPlanned(for: day) }, day: day)
        let rest = openTasks.filter { !$0.isPlanned(for: day) }
        // Plans of past days that weren't finished.
        let missed = rankedTop(rest.filter { $0.isLeftOver(before: app.dayStart) }, day: day)
        // Planning ahead: what's already on today's plan or a later day's before the selected one.
        let ahead = aheadOrder(rest.filter { task in
            guard let plannedDay = task.plannedDay, plannedDay >= todayKey, plannedDay < dayKey else { return false }
            return !isDoneForToday(task)
        }, day: day)
        let earlierIDs = Set(missed.map(\.uuid)).union(ahead.map(\.uuid))
        let due = rankedTop(rest.filter { task in
            guard !earlierIDs.contains(task.uuid), let date = task.dueDate else { return false }
            return DateText.dayDelta(date, today: day) <= 0
        }, day: day)
        let suggested = earlierIDs.union(due.map(\.uuid))
        // Ongoing work, to pick for the day (it never finishes, so it's always on offer).
        let ongoing = rankedTop(rest.filter { $0.isOngoing && !suggested.contains($0.uuid) }, day: day)
        let important = Array(rankedTop(rest.filter { !suggested.contains($0.uuid) && $0.plannedDay == nil && !$0.isOngoing }, day: day).prefix(5))
        let shownAbove = suggested.union(important.map(\.uuid)).union(ongoing.map(\.uuid))
        let layouts = PlanBlocks.layouts(for: [planned, missed, ahead, due, ongoing, important].flatMap { $0 }, live: live)
        // A planned parent counts its subtasks planned for the day, finished ones too.
        let plannedBlocks = PlanBlocks.make(planned, layouts: layouts) { $0.isPlanned(for: day) }
        let missedBlocks = PlanBlocks.make(missed, layouts: layouts)
        let aheadBlocks = PlanBlocks.make(ahead, layouts: layouts)
        let dueBlocks = PlanBlocks.make(due, layouts: layouts)
        let ongoingBlocks = PlanBlocks.make(ongoing, layouts: layouts)
        let importantBlocks = PlanBlocks.make(important, layouts: layouts)

        VStack(spacing: 0) {
            DayStrip(selected: day, tasks: openTasks) { selected = $0 }
            List {
                Section {
                    summary(planned: planned, lines: plannedBlocks.count, day: day)
                }
                Section {
                    if plannedBlocks.isEmpty {
                        Text(Self.emptyHint)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(plannedBlocks) { block in
                        row(block, isPlanned: true, day: day)
                    }
                } header: {
                    Text(dayTitle(day))
                }
                if !missedBlocks.isEmpty {
                    section("Unfinished from earlier", blocks: missedBlocks, day: day)
                }
                if delta == 1 && !aheadBlocks.isEmpty {
                    // The evening carry-over: what's left of today, one tap onto tomorrow.
                    section("Still open today", blocks: aheadBlocks, day: day)
                }
                if delta > 1 && !aheadBlocks.isEmpty {
                    earlierSection(aheadBlocks, day: day)
                }
                if !dueBlocks.isEmpty {
                    section("Due by then", blocks: dueBlocks, day: day)
                }
                if !ongoingBlocks.isEmpty {
                    section("Ongoing", blocks: ongoingBlocks, day: day)
                }
                if !importantBlocks.isEmpty {
                    section("Most important", blocks: importantBlocks, day: day)
                }
                browseSections(rest.filter { !shownAbove.contains($0.uuid) }, open: openTasks, day: day)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
            #endif
        }
        .navigationTitle("Plan")
        .safeAreaInset(edge: .bottom) {
            QuickEntryBar(defaultGroupID: nil, placeholder: "Add a task for \(shortDay(day))", plansFor: day)
        }
    }

    /// "3 planned (8 with subtasks) · 5 PH": the lines shown, and every task they stand for.
    private func summary(planned: [TaskItem], lines: Int, day: Date) -> some View {
        let estimate = PageBuilder.estimateTotals(planned).open
        let count = lines < planned.count ? "\(lines) planned (\(planned.count) with subtasks)" : "\(planned.count) planned"
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateText.pageTitle(day))
                    .font(.headline)
                Text(planned.isEmpty ? "Nothing planned" : count + (estimate > 0 ? " · " + PowerHours.format(estimate) : ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !Calendar.current.isDate(day, inSameDayAs: app.dayStart) {
                Button("Today") { selected = nil }
                    .buttonStyle(.glass)
            }
        }
    }

    private func row(_ block: PlanBlock, isPlanned: Bool, day: Date) -> PlanRow {
        PlanRow(task: block.task, isPlanned: isPlanned, day: day, style: block.style, parentTitle: block.parentTitle, actionTaskID: $actionTaskID)
    }

    private func section(_ title: String, blocks: [PlanBlock], day: Date) -> some View {
        Section {
            ForEach(blocks) { block in
                row(block, isPlanned: false, day: day)
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button("Add All") {
                    withAnimation(.snappy) { app.plan(blocks.map(\.task), for: day) }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
    }

    /// Planning a later day: what's already on the plan of today or a day in between, folded
    /// away and without "Add All", so those plans aren't moved by accident. Each line shows its
    /// day; tapping one still moves it to the selected day.
    private func earlierSection(_ blocks: [PlanBlock], day: Date) -> some View {
        let isOpen = expanded.contains(Self.earlierKey)
        return Section {
            if isOpen {
                ForEach(blocks) { block in
                    row(block, isPlanned: false, day: day)
                }
            }
        } header: {
            Button {
                withAnimation(.snappy) {
                    if isOpen { expanded.remove(Self.earlierKey) } else { expanded.insert(Self.earlierKey) }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Already planned earlier · \(blocks.count)")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Folds them away" : "Shows them")
        }
    }

    /// Ongoing work already checked off today counts as done for today (it stays open forever).
    private func isDoneForToday(_ task: TaskItem) -> Bool {
        guard task.isOngoing, let last = task.lastDoneAt else { return false }
        return last >= app.dayStart
    }

    /// Earliest planned day first, then highest score.
    private func aheadOrder(_ tasks: [TaskItem], day: Date) -> [TaskItem] {
        tasks.sorted { a, b in
            let dayA = a.plannedDay ?? .distantPast
            let dayB = b.plannedDay ?? .distantPast
            if dayA != dayB { return dayA < dayB }
            return a.matrixScore(today: day) > b.matrixScore(today: day)
        }
    }

    // MARK: - Browse All Tasks

    /// Top-level lines among `tasks` (matching the search), with their block's numbers.
    private func browseData(_ tasks: [TaskItem], open: [TaskItem], needle: String) -> (shown: [TaskItem], styles: [UUID: RowStyle]) {
        var styles: [UUID: RowStyle] = [:]
        var roots: [TaskItem] = []
        for section in Dictionary(grouping: open, by: \.groupID).values {
            for row in PageBuilder.taskRows(section, options: PageBuilder.Options()) {
                guard case .task(let task, let depth, let style) = row, depth == 0 else { continue }
                styles[task.uuid] = style
                roots.append(task)
            }
        }
        let wanted = Set(tasks.map(\.uuid))
        let shown = roots.filter { wanted.contains($0.uuid) && (needle.isEmpty || $0.trimmedTitle.lowercased().contains(needle)) }
        return (shown, styles)
    }

    /// A line's Power Hours: its subtasks' total when it has them, else its own.
    private static func hours(_ task: TaskItem, _ styles: [UUID: RowStyle]) -> Double {
        if let style = styles[task.uuid], style.subtaskCount > 0, style.blockEstimate > 0 { return style.blockEstimate }
        return task.estimate
    }

    /// Every other open task, a section per group (or priority, deadline, size). Only top-level
    /// lines are listed, with their subtasks counted and their Power Hours added up; planning
    /// one plans its subtasks too. Sections open on tap; a search opens them all.
    @ViewBuilder
    private func browseSections(_ tasks: [TaskItem], open: [TaskItem], day: Date) -> some View {
        let browse = PlanBrowse(rawValue: browseRaw) ?? .group
        let needle = browseSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let data = browseData(tasks, open: open, needle: needle)
        let sections = browse.sections(data.shown, groups: groups.activeOnly, today: day).filter { !$0.tasks.isEmpty }

        Section {
            Picker("Browse by", selection: $browseRaw) {
                ForEach(PlanBrowse.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            TextField("Search all tasks", text: $browseSearch)
        } header: {
            Text("Browse All Tasks · \(data.shown.count)")
        } footer: {
            Text(Self.browseHint)
        }
        ForEach(sections, id: \.key) { section in
            let isOpen = !needle.isEmpty || expanded.contains(section.key)
            let hours = section.tasks.reduce(0) { $0 + Self.hours($1, data.styles) }
            Section {
                if isOpen {
                    ForEach(rankedTop(section.tasks, day: day), id: \.uuid) { task in
                        PlanRow(task: task, isPlanned: false, day: day, style: data.styles[task.uuid], actionTaskID: $actionTaskID)
                    }
                }
            } header: {
                Button {
                    withAnimation(.snappy) {
                        if expanded.contains(section.key) { expanded.remove(section.key) } else { expanded.insert(section.key) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.symbol)
                            .foregroundStyle(section.color)
                        Text(section.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(hours > 0 ? "\(section.tasks.count) · \(PowerHours.format(hours))" : "\(section.tasks.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Highest score first.
    private func rankedTop(_ tasks: [TaskItem], day: Date) -> [TaskItem] {
        tasks.sorted { $0.matrixScore(today: day) > $1.matrixScore(today: day) }
    }

    private func dayTitle(_ day: Date) -> String {
        switch DateText.dayDelta(day, today: app.dayStart) {
        case 0: "Planned for today"
        case 1: "Planned for tomorrow"
        default: "Planned for " + day.formatted(.dateTime.weekday(.wide))
        }
    }

    private func shortDay(_ day: Date) -> String {
        switch DateText.dayDelta(day, today: app.dayStart) {
        case 0: "today"
        case 1: "tomorrow"
        default: day.formatted(.dateTime.weekday(.wide))
        }
    }
}

/// One line in Plan's lists: a task together with the subtasks that come along with it.
struct PlanBlock: Identifiable {
    let task: TaskItem
    /// Subtask count and Power Hours of the subtasks in the same list (nil = none).
    var style: RowStyle?
    /// The parent line, for a subtask listed without it.
    var parentTitle: String?

    var id: UUID { task.uuid }
}

/// Plan's lists show each block once: a line whose parent (or grandparent …) is in the same
/// list is left out and counted by it instead ("2 of 3 subtasks open", Σ PH). A subtask listed
/// without its parent names it. Planning or unplanning the line takes its subtasks along
/// (`TaskStore.plan` plans whole blocks).
enum PlanBlocks {
    /// Stored order and nesting of each group that `tasks` belong to, from every live line
    /// (finished ones included), the way the group page nests them.
    static func layouts(for tasks: [TaskItem], live: [TaskItem]) -> [UUID?: SectionLayout] {
        let needed = Set(tasks.map(\.groupID))
        var result: [UUID?: SectionLayout] = [:]
        guard !needed.isEmpty else { return result }
        for (groupID, section) in Dictionary(grouping: live.filter({ needed.contains($0.groupID) }), by: \.groupID) {
            result[groupID] = SectionLayout(section)
        }
        return result
    }

    /// `members`, in their order, one line per block.
    /// - Parameter counts: whether a line inside a shown block counts as one of its subtasks
    ///   even though it isn't a member (Planned: finished subtasks planned for the day).
    static func make(_ members: [TaskItem], layouts: [UUID?: SectionLayout], counts: (TaskItem) -> Bool = { _ in false }) -> [PlanBlock] {
        let memberIDs = Set(members.map(\.uuid))
        var blocks: [PlanBlock] = []
        for task in members {
            guard let layout = layouts[task.groupID], let index = layout.index(of: task) else {
                blocks.append(PlanBlock(task: task))
                continue
            }
            // Up through the parent lines: the nearest is named, a member carries the line.
            var parent: TaskItem?
            var carried = false
            var level = layout.depths[index]
            var cursor = index - 1
            while level > 0 && cursor >= 0 {
                if layout.depths[cursor] < level {
                    let ancestor = layout.items[cursor]
                    if parent == nil { parent = ancestor }
                    if memberIDs.contains(ancestor.uuid) {
                        carried = true
                        break
                    }
                    level = layout.depths[cursor]
                }
                cursor -= 1
            }
            if carried { continue }
            let below = layout.items[(index + 1)..<layout.blockEnd(after: index)].filter { line in
                line.loggedFor == nil && (memberIDs.contains(line.uuid) || counts(line))
            }
            var style: RowStyle?
            if !below.isEmpty {
                var value = RowStyle()
                value.subtaskCount = below.count
                value.subtasksDone = below.filter(\.isDone).count
                value.blockEstimate = PowerHours.total([task] + below, where: { !$0.isDone })
                style = value
            }
            let parentTitle = parent.map { $0.trimmedTitle.isEmpty ? "New Task" : $0.trimmedTitle }
            blocks.append(PlanBlock(task: task, style: style, parentTitle: parentTitle))
        }
        return blocks
    }
}

/// The next two weeks: each day shows its planned Power Hours, and a red dot when something
/// open is due that day.
struct DayStrip: View {
    let selected: Date
    let tasks: [TaskItem]
    let onSelect: (Date) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.self) private var environment
    @AppStorage(Prefs.accent) private var accentRaw = AccentChoice.notes.rawValue

    var body: some View {
        let byDay = Self.index(tasks)
        // The chosen accent fills the selected day, with text that stays readable on it
        // (dark on Notes Yellow).
        let accentFill = (AccentChoice(rawValue: accentRaw) ?? .notes).color
        let onFill = accentFill.onFillForeground(in: environment)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<15, id: \.self) { offset in
                    let day = DayBoundary.current.dayStart(byAdding: offset, to: app.dayStart)
                    let key = Calendar.current.startOfDay(for: day)
                    let planned = byDay.planned[key] ?? []
                    let estimate = PageBuilder.estimateTotals(planned).open
                    let dueCount = byDay.due[key] ?? 0
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
                    Button {
                        withAnimation(.snappy) { onSelect(day) }
                    } label: {
                        VStack(spacing: 2) {
                            Text(offset == 0 ? "Today" : day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption.weight(.semibold))
                            Text(day.formatted(.dateTime.day()))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                            Text(planned.isEmpty ? " " : (estimate > 0 ? PowerHours.format(estimate) : "\(planned.count)"))
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(isSelected ? onFill.opacity(0.9) : Color.secondary)
                        }
                        .frame(width: 54, height: 64)
                        .foregroundStyle(isSelected ? onFill : Color.primary)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? AnyShapeStyle(accentFill) : AnyShapeStyle(Color.secondary.opacity(0.1)))
                        }
                        .overlay(alignment: .topTrailing) {
                            // Something open is due that day.
                            if dueCount > 0 {
                                Circle()
                                    .fill(isSelected ? onFill : Color.red)
                                    .frame(width: 5, height: 5)
                                    .padding(6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(Self.spokenSummary(planned: planned.count, estimate: estimate, due: dueCount))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    /// Open tasks by the calendar day they're planned for, and how many fall due on each day.
    private static func index(_ tasks: [TaskItem]) -> (planned: [Date: [TaskItem]], due: [Date: Int]) {
        let calendar = Calendar.current
        var planned: [Date: [TaskItem]] = [:]
        var due: [Date: Int] = [:]
        for task in tasks {
            if let day = task.plannedDay {
                planned[calendar.startOfDay(for: day), default: []].append(task)
            }
            if let date = task.dueDate {
                due[calendar.startOfDay(for: date), default: 0] += 1
            }
        }
        return (planned, due)
    }

    /// "12 planned, 5 PH, 1 due".
    private static func spokenSummary(planned: Int, estimate: Double, due: Int) -> String {
        var parts = [planned == 0 ? "Nothing planned" : "\(planned) planned"]
        if estimate > 0 { parts.append(PowerHours.format(estimate)) }
        if due > 0 { parts.append("\(due) due") }
        return parts.joined(separator: ", ")
    }
}

/// A task in the planner. Its circle puts it on the selected day or takes it off (with Undo);
/// on iPhone and iPad the whole line does. Long-press (right-click on the Mac) for everything
/// else, and Quick Edit there for the colourful panel. On the Mac a click on the line shows it
/// in the details column and a double-click plans it.
struct PlanRow: View {
    let task: TaskItem
    let isPlanned: Bool
    let day: Date
    /// Subtask count and Power Hours total for a line with subtasks.
    var style: RowStyle?
    /// The parent line, for a subtask listed without it.
    var parentTitle: String?
    /// The task whose quick-action panel is open (one at a time on the page).
    @Binding var actionTaskID: UUID?

    @Environment(AppModel.self) private var app
    @State private var hovering = false

    private var rowStyle: RowStyle {
        var value = style ?? RowStyle()
        value.showGroup = true
        return value
    }

    /// Planned: the sun for today, the calendar check for another day, in indigo (the planned
    /// colour; a filled check would look finished). Pointing at a planned line shows that a
    /// click takes it off.
    private var symbol: String {
        guard isPlanned else { return "plus.circle" }
        if hovering { return "minus.circle" }
        return DateText.dayDelta(day, today: app.dayStart) == 0 ? "sun.max.fill" : "calendar.badge.checkmark"
    }

    var body: some View {
        line
            .contextMenu {
                TaskMenuItems(tasks: [task], onQuickEdit: { actionTaskID = task.uuid })
            }
            .popover(isPresented: Binding(get: { actionTaskID == task.uuid }, set: { if !$0 { actionTaskID = nil } }), arrowEdge: .top) {
                TaskActionPanel(tasks: [task]) { actionTaskID = nil }
                    .presentationCompactAdaptation(.popover)
            }
            .sensoryFeedback(.selection, trigger: isPlanned)
    }

    @ViewBuilder
    private var line: some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 10) {
            Button(action: togglePlan) {
                icon
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(isPlanned ? "Take it off this day" : "Plan it for this day")
            .accessibilityLabel(isPlanned ? "Take off this day" : "Plan for this day")
            content
                .contentShape(Rectangle())
                .onTapGesture { app.selectedRowIDs = [task.rowID] }
                .simultaneousGesture(TapGesture(count: 2).onEnded { togglePlan() })
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows it in the details")
        }
        .background {
            if app.selectedRowIDs.contains(task.rowID) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            }
        }
        #else
        Button(action: togglePlan) {
            HStack(alignment: .top, spacing: 10) {
                icon
                content
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityHint(isPlanned ? "Takes it off this day" : "Plans it for this day")
        #endif
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(isPlanned && !hovering ? Color.indigo : Color.secondary)
            .frame(width: 26)
            .contentTransition(.symbolEffect(.replace))
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if task.priority != .normal {
                        Text(task.priority.marks)
                            .font(.body.weight(.heavy))
                            .foregroundStyle(task.priority.color)
                    }
                    Text(task.trimmedTitle.isEmpty ? "New Task" : task.trimmedTitle)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                if let parentTitle {
                    Text("in: " + parentTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TaskMetaLine(task: task, style: rowStyle, today: app.dayStart, showAge: false)
                if let style, style.subtaskCount > 0 {
                    Text("\(style.subtaskCount - style.subtasksDone) of \(style.subtaskCount) subtasks open")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let plannedDay = task.plannedDay, !isPlanned {
                // The day it's planned for now: indigo while that's still ahead.
                Text(DateText.due(plannedDay, hasTime: false, today: app.dayStart))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(plannedDay >= app.todayKey ? Color.indigo : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
        }
    }

    private func togglePlan() {
        withAnimation(.snappy) { app.plan([task], for: isPlanned ? nil : day) }
    }
}

/// How Plan's "Browse All Tasks" is split into sections.
enum PlanBrowse: String, CaseIterable, Identifiable {
    case group, priority, deadline, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .group: "Group"
        case .priority: "Priority"
        case .deadline: "Deadline"
        case .size: "Size"
        }
    }

    func sections(_ tasks: [TaskItem], groups: [TaskGroup], today: Date) -> [LabeledSection] {
        switch self {
        case .group:
            // Every group and subgroup on its own, in sidebar order, named with its path.
            var result: [LabeledSection] = [
                (key: "quick", title: "Quick Entry", symbol: "tray.and.arrow.down.fill", color: .teal, tasks: tasks.filter { $0.groupID == nil })
            ]
            for item in GroupTree.ordered(groups) {
                result.append((key: item.group.uuid.uuidString, title: GroupTree.path(of: item.group, in: groups), symbol: item.group.symbol,
                               color: item.group.color.color, tasks: tasks.filter { $0.groupID == item.group.uuid }))
            }
            return result
        case .priority:
            return Sections.byPriority(tasks, groups: groups, includeNone: true)
        case .deadline:
            return Sections.byDeadline(tasks, groups: groups, today: today, includeNone: true)
        case .size:
            return Sections.bySize(tasks)
        }
    }
}
