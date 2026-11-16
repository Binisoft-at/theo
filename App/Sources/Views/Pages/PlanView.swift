import SwiftUI
import SwiftData
import TheoCore
#if os(macOS)
import AppKit
#endif

/// Pick what each day is for: choose a day, then plan tasks for it. Unfinished tasks from
/// earlier days, tasks due by then and the most important ones come first; everything else
/// follows by group. A planned parent shows once, with its subtasks counted. Planning ahead
/// keeps the plans of the days in between apart (folded, without "Add All").
/// A wide page (Mac, iPad) splits in two: what to plan on the left, the chosen day's plan on
/// the right, with tasks dragged across to plan them and back to take them off.
struct PlanView: View {
    @Environment(AppModel.self) private var app
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
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
    /// Two panes: the pane a task is dragged over, for its highlight.
    @State private var dropTarget: PlanPane?
    /// Two panes: where the current drag started.
    @State private var dragOrigin = DragOrigin()
    /// A light tick for every task planned or taken off with a tap, a click or "Add All".
    @State private var planTicks = 0
    /// A soft knock for every drop that planned tasks or took them off.
    @State private var dropTicks = 0

    /// The pane a drag started in. A plain box: setting it as a drag starts redraws nothing.
    final class DragOrigin {
        var pane: PlanPane?
    }

    /// Everything the page lists for the selected day.
    private struct PageLists {
        let day: Date
        let delta: Int
        let openTasks: [TaskItem]
        let planned: [TaskItem]
        let plannedBlocks: [PlanBlock]
        let missedBlocks: [PlanBlock]
        let aheadBlocks: [PlanBlock]
        let dueBlocks: [PlanBlock]
        let ongoingBlocks: [PlanBlock]
        let importantBlocks: [PlanBlock]
        /// Every other open task, for Browse All Tasks.
        let others: [TaskItem]
    }

    /// Logical start of the selected day (defaults to today).
    private var day: Date { selected ?? app.dayStart }

    /// The folded "Already planned earlier" section's key in `expanded`.
    private static let earlierKey = "plan.earlier"

    /// From this width on, the page shows two panes (Mac, and iPad at regular width).
    private static let twoPaneWidth: CGFloat = 880

    /// Something small that comes and goes in place (the Today button).
    private static let popIn: AnyTransition = .scale(scale: 0.92).combined(with: .opacity)
    /// A note that slides in from the edge it's pinned to ("More than a usual day").
    private static let fromTrailing: AnyTransition = .scale(scale: 0.92, anchor: .trailing).combined(with: .opacity)

    #if os(macOS)
    private static let emptyHint = "Nothing planned yet. Click a task's circle below to add it."
    private static let browseHint = "Click a section to open it, then a task's circle to plan it (its subtasks come along). Click a task to see its details."
    private static let browseHintWide = "Click a section to open it, then drag a task onto the plan on the right, or double-click it (its subtasks come along). Click a task to see its details."
    private static let dropHintDetail = "Or double-click one on the left. Drag a planned task back to the left to take it off."
    #else
    private static let emptyHint = "Nothing planned yet. Tap a task below to add it."
    private static let browseHint = "Tap a section to open it, then tap a task to plan it (its subtasks come along)."
    private static let browseHintWide = "Tap a section to open it, then drag a task onto the plan on the right, or tap it (its subtasks come along)."
    private static let dropHintDetail = "Or tap one on the left. Drag a planned task back to the left to take it off."
    #endif
    private static let dragBackHint = "Drag a task back to the left to take it off this day."

    var body: some View {
        let lists = pageLists(for: day)
        page(lists)
            .navigationTitle("Plan")
            .safeAreaInset(edge: .bottom) {
                QuickEntryBar(defaultGroupID: nil, placeholder: "Add a task for \(shortDay(lists.day))", plansFor: lists.day)
            }
            .sensoryFeedback(.selection, trigger: planTicks)
            .sensoryFeedback(.impact(weight: .light), trigger: dropTicks)
    }

    /// Two panes are offered on the Mac and on an iPad at regular width, never on an iPhone.
    private var allowsTwoPanes: Bool {
        #if os(iOS)
        return sizeClass == .regular
        #else
        return true
        #endif
    }

    /// Two panes once the page is wide enough, otherwise the one list.
    @ViewBuilder
    private func page(_ lists: PageLists) -> some View {
        if allowsTwoPanes {
            GeometryReader { proxy in
                if proxy.size.width >= Self.twoPaneWidth {
                    twoPanes(lists, width: proxy.size.width)
                } else {
                    singleList(lists)
                }
            }
        } else {
            singleList(lists)
        }
    }

    private func pageLists(for day: Date) -> PageLists {
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
        let others = rest.filter { !shownAbove.contains($0.uuid) }
        return PageLists(
            day: day,
            delta: delta,
            openTasks: openTasks,
            planned: planned,
            plannedBlocks: plannedBlocks,
            missedBlocks: missedBlocks,
            aheadBlocks: aheadBlocks,
            dueBlocks: dueBlocks,
            ongoingBlocks: ongoingBlocks,
            importantBlocks: importantBlocks,
            others: others
        )
    }

    // MARK: - One list

    /// The day strip, the day's plan, then everything to plan (iPhone, and any narrow page).
    private func singleList(_ lists: PageLists) -> some View {
        VStack(spacing: 0) {
            DayStrip(selected: lists.day, tasks: lists.openTasks) { selected = $0 }
            List {
                Section {
                    summary(planned: lists.planned, lines: lists.plannedBlocks.count, day: lists.day)
                }
                Section {
                    if lists.plannedBlocks.isEmpty {
                        Text(Self.emptyHint)
                            .theoFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lists.plannedBlocks) { block in
                        row(block, isPlanned: true, day: lists.day, pane: nil)
                    }
                } header: {
                    Text(dayTitle(lists.day))
                }
                suggestions(lists, pane: nil)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
            #endif
        }
    }

    /// Everything but the day's plan: what's suggested for it, then Browse All Tasks.
    /// `pane`: with two panes, the lines can be dragged across (nil = one list, no dragging).
    @ViewBuilder
    private func suggestions(_ lists: PageLists, pane: PlanPane?) -> some View {
        if !lists.missedBlocks.isEmpty {
            section("Unfinished from earlier", blocks: lists.missedBlocks, day: lists.day, pane: pane)
        }
        if lists.delta == 1 && !lists.aheadBlocks.isEmpty {
            // The evening carry-over: what's left of today, one tap onto tomorrow.
            section("Still open today", blocks: lists.aheadBlocks, day: lists.day, pane: pane)
        }
        if lists.delta > 1 && !lists.aheadBlocks.isEmpty {
            earlierSection(lists.aheadBlocks, day: lists.day, pane: pane)
        }
        if !lists.dueBlocks.isEmpty {
            section("Due by then", blocks: lists.dueBlocks, day: lists.day, pane: pane)
        }
        if !lists.ongoingBlocks.isEmpty {
            section("Ongoing", blocks: lists.ongoingBlocks, day: lists.day, pane: pane)
        }
        if !lists.importantBlocks.isEmpty {
            section("Most important", blocks: lists.importantBlocks, day: lists.day, pane: pane)
        }
        browseSections(lists.others, open: lists.openTasks, day: lists.day, pane: pane)
    }

    // MARK: - Two panes

    /// What to plan on the left, the day's plan on the right. A task dragged across is planned
    /// for the day; a planned one dragged back is taken off.
    private func twoPanes(_ lists: PageLists, width: CGFloat) -> some View {
        let planWidth: CGFloat = min(520, max(360, (width * 0.42).rounded()))
        return HStack(spacing: 0) {
            suggestionsPane(lists)
                #if os(macOS)
                .frame(maxWidth: 920)
                #endif
                .frame(maxWidth: .infinity)
            Divider()
            plannedPane(lists)
                .frame(width: planWidth)
        }
    }

    /// The left pane: suggestions and Browse. A planned task dropped here comes off the day.
    private func suggestionsPane(_ lists: PageLists) -> some View {
        let origin = dragOrigin
        let shown = dropTarget == .suggestions && origin.pane == .planned
        return List {
            suggestions(lists, pane: .suggestions)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .overlay {
            dropHighlight(shown, text: "Off Plan", symbol: "calendar.badge.minus", tint: Tint.offPlan)
        }
        .dropDestination(for: String.self) { items, _ in
            dropOffPlan(items, day: lists.day)
        } isTargeted: { over in
            setTarget(.suggestions, over)
        }
    }

    /// The right pane: the day strip (a task dropped on a day is planned for it) over the
    /// chosen day's plan.
    private func plannedPane(_ lists: PageLists) -> some View {
        VStack(spacing: 0) {
            DayStrip(selected: lists.day, tasks: lists.openTasks, onSelect: { selected = $0 }, onDrop: { day, items in
                dropOnPlan(items, day: day)
            })
            plannedList(lists)
        }
    }

    private func plannedList(_ lists: PageLists) -> some View {
        let origin = dragOrigin
        let shown = dropTarget == .planned && origin.pane != .planned
        let usual = usualDay()
        // Power Hours on the day: what's planned, and (today) what's already done.
        let hours = PageBuilder.estimateTotals(lists.planned).open + doneHours(on: lists.day)
        return List {
            Section {
                summary(planned: lists.planned, lines: lists.plannedBlocks.count, day: lists.day)
                if usual > 0 {
                    usualMeter(hours: hours, usual: usual)
                }
            }
            plannedSectionWide(lists)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .overlay {
            dropHighlight(shown, text: "Plan for " + shortDay(lists.day), symbol: planSymbol(lists.day), tint: dayTint(lists.day))
        }
        .dropDestination(for: String.self) { items, _ in
            dropOnPlan(items, day: lists.day)
        } isTargeted: { over in
            setTarget(.planned, over)
        }
    }

    /// The day's plan, as a column that takes dropped tasks.
    private func plannedSectionWide(_ lists: PageLists) -> some View {
        Section {
            if lists.plannedBlocks.isEmpty {
                dropHint(day: lists.day)
            }
            ForEach(lists.plannedBlocks) { block in
                row(block, isPlanned: true, day: lists.day, pane: .planned)
            }
        } header: {
            Text(dayTitle(lists.day))
        } footer: {
            if !lists.plannedBlocks.isEmpty {
                Text(Self.dragBackHint)
            }
        }
    }

    /// Nothing planned yet: where to drop, in the colour of planning for that day.
    private func dropHint(day: Date) -> some View {
        let tint = dayTint(day)
        return VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .theoFont(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
            Text("Drag tasks here to plan them for \(shortDay(day)).")
                .theoFont(.headline)
            Text(Self.dropHintDetail)
                .theoFont(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .padding(.vertical, 4)
    }

    /// The day's Power Hours (planned, plus what's already done today) against a usual day, the
    /// way Today's header compares them: orange when it's clearly more. The bar grows and the
    /// note slides in as tasks come and go.
    private func usualMeter(hours: Double, usual: Double) -> some View {
        let quarter = (usual * 4).rounded() / 4
        let typical: Double = quarter > 0 ? quarter : usual
        let over: Bool = DayReview.isOverplanned(planned: hours, average: usual)
        let fraction: Double = typical > 0 ? hours / typical : 0
        let barTint: Color = over ? Color.orange : Tint.powerHours
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("A usual day: ~" + PowerHours.format(typical))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: typical))
                Spacer(minLength: 0)
                if over {
                    Text("More than a usual day")
                        .foregroundStyle(Color.orange)
                        .transition(Self.fromTrailing)
                }
            }
            .theoFont(.caption, weight: .medium)
            .foregroundStyle(.secondary)
            UsualDayBar(fraction: fraction, tint: barTint)
        }
        .animation(Motion.resolved(Motion.layout), value: hours)
        .accessibilityElement(children: .combine)
        .accessibilityValue(PowerHours.format(hours) + " on the day")
    }

    /// A pane a task is dragged over: washed in the colour of what letting go does (the day's
    /// orange or indigo to plan, grey to take off), with a floating label that says it.
    @ViewBuilder
    private func dropHighlight(_ shown: Bool, text: String, symbol: String, tint: Color) -> some View {
        if shown {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.08))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(0.6), lineWidth: 2)
                dropLabel(text, symbol: symbol, tint: tint)
                    .padding(.top, 12)
            }
            .padding(6)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func dropLabel(_ text: String, symbol: String, tint: Color) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
        .theoFont(.subheadline, weight: .semibold)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }

    /// The drop highlight follows the pointer from pane to pane with a quick fade.
    private func setTarget(_ pane: PlanPane, _ over: Bool) {
        Motion.animate(Motion.hover) {
            updateTarget(pane, over)
        }
    }

    private func updateTarget(_ pane: PlanPane, _ over: Bool) {
        if over {
            dropTarget = pane
        } else if dropTarget == pane {
            dropTarget = nil
        }
    }

    /// The open tasks a drop names (text from anywhere else names none).
    private func droppedTasks(_ items: [String]) -> [TaskItem] {
        var seen = Set<UUID>()
        var result: [TaskItem] = []
        for item in items {
            for id in PlanDragPayload.taskIDs(from: item) where !seen.contains(id) {
                seen.insert(id)
                if let task = allLive.first(where: { $0.uuid == id }), !task.isDone {
                    result.append(task)
                }
            }
        }
        return result
    }

    /// Dropped on the plan or on a day in the strip: planned for that day (with Undo).
    private func dropOnPlan(_ items: [String], day: Date) -> Bool {
        dragOrigin.pane = nil
        let tasks = droppedTasks(items).filter { !$0.isPlanned(for: day) }
        guard !tasks.isEmpty else { return false }
        Motion.animate(Motion.list) { app.plan(tasks, for: day) }
        dropTicks += 1
        return true
    }

    /// A planned task dropped on the left: off the day's plan (with Undo).
    private func dropOffPlan(_ items: [String], day: Date) -> Bool {
        dragOrigin.pane = nil
        let tasks = droppedTasks(items).filter { $0.isPlanned(for: day) }
        guard !tasks.isEmpty else { return false }
        Motion.animate(Motion.list) { app.plan(tasks, for: nil) }
        dropTicks += 1
        return true
    }

    /// Power Hours a usual day gets done: the last seven days before today, counted the way
    /// Today and the Day Review count them (0 until two of those days had something done).
    private func usualDay() -> Double {
        let boundary = DayBoundary.current
        let today = app.dayStart
        let weekStart = boundary.dayStart(byAdding: -7, to: today)
        var byDay: [Date: [TaskItem]] = [:]
        for task in allLive where task.isDone {
            guard let finishedAt = task.completedAt, finishedAt >= weekStart, finishedAt < today else { continue }
            byDay[boundary.start(of: finishedAt), default: []].append(task)
        }
        let days: [DayReview.Day] = byDay.map { entry in
            DayReview.Day(start: entry.key, powerHours: PageBuilder.estimateTotals(entry.value).done, done: entry.value.count)
        }
        return DayReview.activeAverage(days)
    }

    /// Power Hours already finished on `day` (only today has any).
    private func doneHours(on day: Date) -> Double {
        let finished = allLive.filter { $0.isDone && $0.isOnPage(of: day) }.activeOnly(groups)
        return PageBuilder.estimateTotals(finished).done
    }

    /// Today's sun, tomorrow's moon, a calendar for later days: what dropping a task does.
    private func planSymbol(_ day: Date) -> String {
        switch DateText.dayDelta(day, today: app.dayStart) {
        case 0: "sun.max.fill"
        case 1: "moon.zzz.fill"
        default: "calendar.badge.plus"
        }
    }

    /// The day itself: Today's sun, Tomorrow's moon, a calendar with a check for a later day.
    private func daySymbol(_ day: Date) -> String {
        switch DateText.dayDelta(day, today: app.dayStart) {
        case 0: "sun.max.fill"
        case 1: "moon.zzz.fill"
        default: "calendar.badge.checkmark"
        }
    }

    /// The colour of planning for a day: Today's orange, the planned indigo for any later day.
    private func dayTint(_ day: Date) -> Color {
        DateText.dayDelta(day, today: app.dayStart) == 0 ? Tint.today : Tint.planned
    }

    // MARK: - Pieces

    /// The chosen day at the top of its plan: its symbol on a tile in the day's colour, the
    /// date, and "3 planned (8 with subtasks) · 5 PH". The date and the numbers roll when the
    /// day or its plan changes.
    private func summary(planned: [TaskItem], lines: Int, day: Date) -> some View {
        let estimate: Double = PageBuilder.estimateTotals(planned).open
        let count: String = lines < planned.count ? "\(lines) planned (\(planned.count) with subtasks)" : "\(planned.count) planned"
        let detail: String = planned.isEmpty ? "Nothing planned" : count + (estimate > 0 ? " · " + PowerHours.format(estimate) : "")
        let isToday: Bool = Calendar.current.isDate(day, inSameDayAs: app.dayStart)
        return HStack(spacing: 12) {
            dayBadge(day)
            VStack(alignment: .leading, spacing: 2) {
                Text(DateText.pageTitle(day))
                    .theoFont(.headline)
                    .contentTransition(.numericText(value: day.timeIntervalSinceReferenceDate))
                Text(detail)
                    .monospacedDigit()
                    .theoFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: estimate))
            }
            .animation(Motion.resolved(Motion.tap), value: detail)
            Spacer(minLength: 8)
            if !isToday {
                todayButton
                    .transition(Self.popIn)
            }
        }
    }

    /// The day's symbol on a small tile in its colour: Today's sun in orange, Tomorrow's moon
    /// and a later day's calendar in the planned indigo. The symbol morphs as the day changes.
    private func dayBadge(_ day: Date) -> some View {
        Image(systemName: daySymbol(day))
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(dayTint(day).gradient)
            }
            .accessibilityHidden(true)
    }

    /// Back to today's plan from a later day.
    private var todayButton: some View {
        Button("Today") {
            Motion.animate(Motion.tap) { selected = nil }
        }
        .theoFont(.subheadline, weight: .semibold)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(Tint.today)
        .help("Show today's plan")
    }

    /// `pane`: with two panes, the pane the line sits in (it can be dragged to the other).
    private func row(_ block: PlanBlock, isPlanned: Bool, day: Date, pane: PlanPane?) -> PlanRow {
        let origin = dragOrigin
        return PlanRow(
            task: block.task, isPlanned: isPlanned, day: day, style: block.style, parentTitle: block.parentTitle,
            actionTaskID: $actionTaskID, pane: pane, onDragStart: { origin.pane = $0 }, onToggle: { planTicks += 1 }
        )
    }

    private func section(_ title: String, blocks: [PlanBlock], day: Date, pane: PlanPane?) -> some View {
        Section {
            ForEach(blocks) { block in
                row(block, isPlanned: false, day: day, pane: pane)
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button("Add All") {
                    Motion.animate(Motion.list) { app.plan(blocks.map(\.task), for: day) }
                    planTicks += 1
                }
                .theoFont(.caption, weight: .semibold)
                .buttonStyle(.borderless)
            }
        }
    }

    /// Planning a later day: what's already on the plan of today or a day in between, folded
    /// away and without "Add All", so those plans aren't moved by accident. Each line shows its
    /// day; tapping one still moves it to the selected day.
    private func earlierSection(_ blocks: [PlanBlock], day: Date, pane: PlanPane?) -> some View {
        let isOpen = expanded.contains(Self.earlierKey)
        return Section {
            if isOpen {
                ForEach(blocks) { block in
                    row(block, isPlanned: false, day: day, pane: pane)
                }
            }
        } header: {
            Button {
                Motion.animate(Motion.list) { toggleExpanded(Self.earlierKey) }
            } label: {
                HStack(spacing: 8) {
                    Text("Already planned earlier · \(blocks.count)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                    chevron(isOpen)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Folds them away" : "Shows them")
        }
    }

    /// A section's fold chevron: right while folded, down while open, turning as it opens.
    private func chevron(_ isOpen: Bool) -> some View {
        Image(systemName: "chevron.right")
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isOpen ? 90 : 0))
    }

    /// Opens a folded section, or folds an open one.
    private func toggleExpanded(_ key: String) {
        if expanded.contains(key) {
            expanded.remove(key)
        } else {
            expanded.insert(key)
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

    private func browseRow(_ task: TaskItem, style: RowStyle?, day: Date, pane: PlanPane?) -> PlanRow {
        row(PlanBlock(task: task, style: style), isPlanned: false, day: day, pane: pane)
    }

    /// Every other open task, a section per group (or priority, deadline, size). Only top-level
    /// lines are listed, with their subtasks counted and their Power Hours added up; planning
    /// one plans its subtasks too. Sections open on tap; a search opens them all.
    @ViewBuilder
    private func browseSections(_ tasks: [TaskItem], open: [TaskItem], day: Date, pane: PlanPane?) -> some View {
        let browse = PlanBrowse(rawValue: browseRaw) ?? .group
        let needle = browseSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let data = browseData(tasks, open: open, needle: needle)
        let sections = browse.sections(data.shown, groups: groups.activeOnly, today: day).filter { !$0.tasks.isEmpty }
        let hint = pane == nil ? Self.browseHint : Self.browseHintWide

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
                .monospacedDigit()
                .contentTransition(.numericText())
        } footer: {
            Text(hint)
        }
        ForEach(sections, id: \.key) { section in
            browseSection(section, needle: needle, styles: data.styles, day: day, pane: pane)
        }
    }

    /// One section of Browse All Tasks: a header that opens it, then its lines.
    private func browseSection(_ section: LabeledSection, needle: String, styles: [UUID: RowStyle], day: Date, pane: PlanPane?) -> some View {
        let isOpen: Bool = !needle.isEmpty || expanded.contains(section.key)
        let hours: Double = section.tasks.reduce(0) { $0 + Self.hours($1, styles) }
        return Section {
            if isOpen {
                ForEach(rankedTop(section.tasks, day: day), id: \.uuid) { task in
                    browseRow(task, style: styles[task.uuid], day: day, pane: pane)
                }
            }
        } header: {
            browseHeader(section, isOpen: isOpen, hours: hours)
        }
    }

    /// The group's (or priority's, deadline's, size's) icon in its colour in a column of its
    /// own, its name, and "3 · 1,5 PH", rolling as tasks are planned from it.
    private func browseHeader(_ section: LabeledSection, isOpen: Bool, hours: Double) -> some View {
        let count: Int = section.tasks.count
        let figure: String = hours > 0 ? "\(count) · \(PowerHours.format(hours))" : "\(count)"
        return Button {
            Motion.animate(Motion.list) { toggleExpanded(section.key) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.symbol)
                    .foregroundStyle(section.color)
                    .frame(width: 22)
                Text(section.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(figure)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(count)))
                chevron(isOpen)
            }
            .theoFont(.subheadline, weight: .semibold)
            .textCase(nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isOpen ? "Folds them away" : "Shows them")
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

/// The usual-day meter's bar: a soft track, and the day's Power Hours in teal (orange once it's
/// clearly more than a usual day) that grows smoothly as tasks come and go.
private struct UsualDayBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let filled: CGFloat = proxy.size.width * CGFloat(min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: fraction > 0 ? max(filled, proxy.size.height) : 0)
            }
        }
        .frame(height: 6)
        .animation(Motion.resolved(Motion.layout), value: fraction)
        .accessibilityHidden(true)
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

/// The next two weeks: each day shows its planned Power Hours, and a dot in the deadline blue
/// when something open is due that day. The selected day's fill glides from day to day instead
/// of jumping. With two panes, a task dropped on a day is planned for it; the day rises a
/// little to meet the task dragged over it.
struct DayStrip: View {
    let selected: Date
    let tasks: [TaskItem]
    let onSelect: (Date) -> Void
    /// Two panes: plans the dropped tasks for that day (nil = the days take no drops).
    var onDrop: ((Date, [String]) -> Bool)?

    @Environment(AppModel.self) private var app
    @Environment(\.self) private var environment
    @AppStorage(Prefs.accent) private var accentRaw = AccentChoice.notes.rawValue
    /// Theo's text size on the Mac (1 elsewhere): the day chips grow with their text.
    @Environment(\.textScale) private var textScale
    /// The day a task is dragged over.
    @State private var dropDay: Date?
    /// The day under the pointer (Mac, iPad with a pointer), for its deeper fill.
    @State private var hoveredDay: Date?
    /// Where the selected day's fill glides between the days.
    @Namespace private var selection

    /// Today and the fourteen days after it.
    private static let length = 15

    /// Open tasks by the calendar day they're planned for, and how many fall due on each day.
    private typealias DayIndex = (planned: [Date: [TaskItem]], due: [Date: Int])

    var body: some View {
        let byDay = Self.index(tasks)
        // The chosen accent fills the selected day, with text that stays readable on it
        // (dark on Notes Yellow).
        let accentFill = (AccentChoice(rawValue: accentRaw) ?? .notes).color
        let onFill = accentFill.onFillForeground(in: environment)
        let chosen = offsetOfSelection()
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<Self.length, id: \.self) { offset in
                    let day = date(at: offset)
                    droppable(chip(offset: offset, day: day, byDay: byDay, onFill: onFill), day: day)
                        .matchedGeometryEffect(id: offset, in: selection)
                }
            }
            .background {
                selectionFill(chosen, fill: accentFill)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    /// The selected day's fill, drawn once behind all the days so it can glide from one to the
    /// next (over the days in between, never across their text).
    @ViewBuilder
    private func selectionFill(_ offset: Int?, fill: Color) -> some View {
        if let offset {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(fill)
                .matchedGeometryEffect(id: offset, in: selection, isSource: false)
        }
    }

    private func date(at offset: Int) -> Date {
        DayBoundary.current.dayStart(byAdding: offset, to: app.dayStart)
    }

    /// Which of the days is selected (nil when it's none of them).
    private func offsetOfSelection() -> Int? {
        (0..<Self.length).first { Calendar.current.isDate(date(at: $0), inSameDayAs: selected) }
    }

    private func chip(offset: Int, day: Date, byDay: DayIndex, onFill: Color) -> some View {
        let key = Calendar.current.startOfDay(for: day)
        let planned: [TaskItem] = byDay.planned[key] ?? []
        let estimate: Double = PageBuilder.estimateTotals(planned).open
        let dueCount: Int = byDay.due[key] ?? 0
        let isSelected: Bool = Calendar.current.isDate(day, inSameDayAs: selected)
        // Unselected days sit on a soft fill, a little deeper under the pointer; the selected
        // one shows the accent fill behind it.
        let wash: Double = isSelected ? 0 : (hoveredDay == day ? 0.16 : 0.1)
        let grow: CGFloat = max(1, textScale)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            Motion.animate(Motion.tap) { onSelect(day) }
        } label: {
            chipLabel(offset: offset, day: day, planned: planned.count, estimate: estimate, isSelected: isSelected, onFill: onFill)
                .frame(width: 54 * grow, height: 64 * grow)
                .background {
                    shape.fill(Color.secondary.opacity(wash))
                }
                .overlay(alignment: .topTrailing) {
                    // Something open is due that day.
                    if dueCount > 0 {
                        Circle()
                            .fill(isSelected ? onFill : Tint.deadline)
                            .frame(width: 5, height: 5)
                            .padding(6)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .onHover { inside in
            hover(day, inside)
        }
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(Self.spokenSummary(planned: planned.count, estimate: estimate, due: dueCount))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "Today" (in Today's orange until it's selected), the date in rounded figures, and the
    /// day's planned Power Hours, which roll as tasks are planned.
    private func chipLabel(offset: Int, day: Date, planned: Int, estimate: Double, isSelected: Bool, onFill: Color) -> some View {
        let weekday: String = offset == 0 ? "Today" : day.formatted(.dateTime.weekday(.abbreviated))
        let figure: String = planned == 0 ? " " : (estimate > 0 ? PowerHours.format(estimate) : "\(planned)")
        let weekdayColor: Color = isSelected ? onFill : (offset == 0 ? Tint.today : Color.primary)
        let dateColor: Color = isSelected ? onFill : Color.primary
        let figureColor: Color = isSelected ? onFill.opacity(0.9) : Color.secondary
        return VStack(spacing: 2) {
            Text(weekday)
                .theoFont(.caption, weight: .semibold)
                .foregroundStyle(weekdayColor)
            Text(day.formatted(.dateTime.day()))
                .monospacedDigit()
                .theoFont(.title3, weight: .bold, design: .rounded)
                .foregroundStyle(dateColor)
            Text(figure)
                .monospacedDigit()
                .theoFont(.caption2, weight: .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(figureColor)
                .contentTransition(.numericText(value: estimate))
                .animation(Motion.resolved(Motion.tap), value: figure)
        }
    }

    /// Two panes: the day takes a dragged task and plans it for that day. While a task is over
    /// it, it rises a little and outlines itself in the colour of planning for it.
    @ViewBuilder
    private func droppable<Content: View>(_ chip: Content, day: Date) -> some View {
        if let onDrop {
            let isTarget: Bool = dropDay == day
            chip
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(dropTint(day), lineWidth: 2)
                        .opacity(isTarget ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .scaleEffect(isTarget ? 1.06 : 1)
                .dropDestination(for: String.self) { items, _ in
                    onDrop(day, items)
                } isTargeted: { over in
                    target(day, over)
                }
        } else {
            chip
        }
    }

    /// Today's orange, the planned indigo for any later day.
    private func dropTint(_ day: Date) -> Color {
        DateText.dayDelta(day, today: app.dayStart) == 0 ? Tint.today : Tint.planned
    }

    private func hover(_ day: Date, _ inside: Bool) {
        Motion.animate(Motion.hover) {
            if inside {
                hoveredDay = day
            } else if hoveredDay == day {
                hoveredDay = nil
            }
        }
    }

    private func target(_ day: Date, _ over: Bool) {
        Motion.animate(Motion.hover) {
            if over {
                dropDay = day
            } else if dropDay == day {
                dropDay = nil
            }
        }
    }

    /// Open tasks by the calendar day they're planned for, and how many fall due on each day.
    private static func index(_ tasks: [TaskItem]) -> DayIndex {
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
/// in the details column and a double-click plans it. With two panes the line (not its circle)
/// can be dragged to the other pane; it lifts off the page as a small card.
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
    /// Two panes: the pane the line sits in (nil = it can't be dragged).
    var pane: PlanPane?
    /// Called as a drag of the line starts, with the pane it starts in.
    var onDragStart: (PlanPane) -> Void = { _ in }
    /// Called once a tap, a click on the circle or a double-click planned the line or took it
    /// off (the page gives a light tick for it).
    var onToggle: () -> Void = {}

    @Environment(AppModel.self) private var app
    @State private var hovering = false

    private var rowStyle: RowStyle {
        var value = style ?? RowStyle()
        value.showGroup = true
        return value
    }

    private var title: String {
        task.trimmedTitle.isEmpty ? "New Task" : task.trimmedTitle
    }

    private var isToday: Bool {
        DateText.dayDelta(day, today: app.dayStart) == 0
    }

    /// The colour of planning for this day: Today's orange, the planned indigo for a later day.
    private var dayTint: Color {
        isToday ? Tint.today : Tint.planned
    }

    /// Planned: Today's sun in orange, or the calendar check in the planned indigo for a later
    /// day (a filled check would look finished). Pointing at the circle shows what a click does:
    /// a grey minus takes the line off the day, a plus in the day's colour plans it.
    private var symbol: String {
        if isPlanned {
            if hovering { return "minus.circle.fill" }
            return isToday ? "sun.max.fill" : "calendar.badge.checkmark"
        }
        return hovering ? "plus.circle.fill" : "plus.circle"
    }

    private var iconColor: Color {
        if isPlanned { return hovering ? Tint.offPlan : dayTint }
        return hovering ? dayTint : Color.secondary
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
    }

    @ViewBuilder
    private var line: some View {
        #if os(macOS)
        HStack(alignment: .top, spacing: 10) {
            Button(action: togglePlan) {
                icon
            }
            .buttonStyle(.plain)
            .onHover { inside in
                hover(inside)
            }
            .help(isPlanned ? "Take it off this day" : "Plan it for this day")
            .accessibilityLabel(isPlanned ? "Take off this day" : "Plan for this day")
            dragSource(clickableContent)
        }
        .background {
            if app.selectedRowIDs.contains(task.rowID) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TintShapeStyle.tint.opacity(0.15))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            }
        }
        #else
        dragSource(tappableLine)
        #endif
    }

    #if os(macOS)
    /// A click shows the task in the details column, a double-click plans it.
    private var clickableContent: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { app.selectedRowIDs = [task.rowID] }
            .simultaneousGesture(TapGesture(count: 2).onEnded { togglePlan() })
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows it in the details")
    }
    #else
    /// A tap plans the task or takes it off.
    private var tappableLine: some View {
        Button(action: togglePlan) {
            HStack(alignment: .top, spacing: 10) {
                icon
                content
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hover(inside)
        }
        .accessibilityHint(isPlanned ? "Takes it off this day" : "Plans it for this day")
    }
    #endif

    /// Two panes: the line can be dragged to the other pane, carrying its task's ID. On the Mac
    /// it lifts off as a small card with a soft shadow; on the iPad the system lifts the line
    /// itself, on rounded corners.
    @ViewBuilder
    private func dragSource<Content: View>(_ view: Content) -> some View {
        if let pane {
            let text = PlanDragPayload.text(for: task)
            let notify = onDragStart
            #if os(macOS)
            view.draggable(Self.payload(text, from: pane, notify: notify), preview: { dragPreview })
            #else
            view
                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
                .draggable(Self.payload(text, from: pane, notify: notify))
            #endif
        } else {
            view
        }
    }

    /// Read as a drag starts: tells the page where it started.
    private nonisolated static func payload(_ text: String, from pane: PlanPane, notify: (PlanPane) -> Void) -> String {
        notify(pane)
        return text
    }

    #if os(macOS)
    /// What follows the pointer while the line is dragged: the task lifted off the page as a
    /// small card, with room around it for its soft shadow.
    private var dragPreview: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            if task.priority != .normal {
                Text(task.priority.marks)
                    .theoFont(.body, weight: .heavy)
                    .foregroundStyle(task.priority.color)
            }
            Text(title)
                .theoFont(.body, weight: .medium)
                .lineLimit(2)
        }
        .frame(width: 260, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        .padding(16)
    }
    #endif

    private var icon: some View {
        Image(systemName: symbol)
            .theoFont(.title3)
            .foregroundStyle(iconColor)
            .frame(width: 26)
            .contentTransition(.symbolEffect(.replace))
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if task.priority != .normal {
                        Text(task.priority.marks)
                            .theoFont(.body, weight: .heavy)
                            .foregroundStyle(task.priority.color)
                            .accessibilityLabel("\(task.priority.title) priority")
                    }
                    Text(title)
                        .theoBodyFont()
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                if let parentTitle {
                    parentLine(parentTitle)
                }
                TaskMetaLine(task: task, style: rowStyle, today: app.dayStart, showAge: false)
                if let style, style.subtaskCount > 0 {
                    subtaskLine(style)
                }
            }
            Spacer(minLength: 0)
            if let plannedDay = task.plannedDay, !isPlanned {
                plannedDayTag(plannedDay)
            }
        }
    }

    /// A subtask listed without its parent: which line it belongs to.
    private func parentLine(_ parentTitle: String) -> some View {
        Label(parentTitle, systemImage: "arrow.turn.down.right")
            .labelStyle(CompactLabelStyle())
            .theoFont(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel("Subtask of \(parentTitle)")
    }

    /// "2 of 3 subtasks open", beside the small ring that fills as they get done.
    private func subtaskLine(_ style: RowStyle) -> some View {
        let total: Int = style.subtaskCount
        let done: Int = style.subtasksDone
        let fraction: Double = total > 0 ? Double(done) / Double(total) : 0
        return HStack(spacing: 4) {
            MiniRing(fraction: fraction, lineWidth: 1.5)
                .frame(width: 10, height: 10)
            Text("\(total - done) of \(total) subtasks open")
                .monospacedDigit()
        }
        .theoFont(.caption2)
        .foregroundStyle(.secondary)
    }

    /// The day it's planned for now: Today's orange or the planned indigo while that's still
    /// ahead, grey once it has passed.
    private func plannedDayTag(_ plannedDay: Date) -> some View {
        let delta = DateText.dayDelta(plannedDay, today: app.dayStart)
        let color: Color = delta == 0 ? Tint.today : (delta > 0 ? Tint.planned : Color.secondary)
        return Text(DateText.due(plannedDay, hasTime: false, today: app.dayStart))
            .theoFont(.caption2, weight: .semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    private func hover(_ inside: Bool) {
        Motion.animate(Motion.hover) { hovering = inside }
    }

    private func togglePlan() {
        Motion.animate(Motion.list) { app.plan([task], for: isPlanned ? nil : day) }
        onToggle()
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

/// Which of Plan's two panes a line sits in.
enum PlanPane {
    /// The left pane: suggestions and Browse All Tasks.
    case suggestions
    /// The right pane: the selected day's plan.
    case planned
}

/// What a Plan line carries when it's dragged: "theo-task:" and its task's ID, the same text
/// a list's lines carry when dragged onto the sidebar, so text dropped from anywhere else is
/// ignored.
enum PlanDragPayload {
    static let prefix = "theo-task:"

    static func text(for task: TaskItem) -> String {
        prefix + task.uuid.uuidString
    }

    /// The task IDs a dropped text names (a list's drag can name several, comma-separated);
    /// none for text that isn't a Theo task drag.
    static func taskIDs(from text: String) -> [UUID] {
        guard text.hasPrefix(prefix) else { return [] }
        return text.dropFirst(prefix.count).split(separator: ",").compactMap { part in
            UUID(uuidString: part.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
