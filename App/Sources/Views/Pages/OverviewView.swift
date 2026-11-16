import SwiftUI
import SwiftData
import Charts
import TheoCore
#if os(iOS)
import UIKit
#endif

/// Everything at a glance, so a long list never feels like a wall: totals, today, the
/// deadlines ahead, each group's size and state, priorities, ongoing work and the biggest
/// open blocks. Every card leads to the list behind it; on iPhone that list opens inside the
/// Overview tab, so Back comes back here.
struct OverviewView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @Query(filter: #Predicate<SavedView> { $0.deletedAt == nil }, sort: \SavedView.sortOrder)
    private var views: [SavedView]
    @AppStorage(Prefs.accent) private var accentRaw = AccentChoice.notes.rawValue

    private let tiles = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    #if os(iOS)
    /// The page and its cards in the system's grouped colours, like Settings: light grey and
    /// white by day, black and dark grey by night.
    private static let pageFill = Color(uiColor: .systemGroupedBackground)
    private static let cardFill = Color(uiColor: .secondarySystemGroupedBackground)
    #else
    /// Cards on the Mac: a soft fill on the window, so they stand out by day and by night.
    private static let cardFill = Color.secondary.opacity(0.1)
    #endif
    /// Lines inside a card (a group, Quick Entry).
    private static let rowFill = Color.secondary.opacity(0.08)
    private static let cardShape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    private static let rowShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        let today = app.dayStart
        let live = tasks.activeOnly(groups)
        let open = live.filter { !$0.isDone }
        let stats = TaskStats(live, today: today)
        let weekStart = DayBoundary.current.dayStart(byAdding: -6, to: today)
        let doneWeek = live.filter { task in
            guard task.isDone, let completed = task.completedAt else { return false }
            return completed >= weekStart
        }
        let planned = open.filter { $0.isPlanned(for: today) }
        // Every open task, switched-off groups included: a subgroup that's off still shows
        // how much it holds.
        let openAnywhere = tasks.filter { !$0.isDone }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statTiles(stats, planned: planned, doneWeek: doneWeek)

                card("Deadlines Ahead", symbol: "calendar", tint: Tint.deadline) {
                    deadlineChart(open, today: today)
                }

                card("Groups", symbol: "square.grid.2x2", tint: Color.secondary) {
                    groupList(open: open, openAnywhere: openAnywhere, today: today)
                }

                card("Priorities", symbol: "exclamationmark.3", tint: Tint.priority) {
                    priorityBar(open)
                }

                ongoingCard(open, today: today)
                blocksCard(open)
                viewsCard
            }
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        .background(Self.pageFill)
        #endif
        .navigationTitle("Overview")
    }

    // MARK: - Pieces

    /// Six numbers at a glance, each opening the list behind it. Each keeps the colour of what
    /// it counts, as in a group's figures: open tasks in the chosen accent, Power Hours teal,
    /// overdue orange (grey while there's none), deadlines blue, Today orange, done green.
    private func statTiles(_ stats: TaskStats, planned: [TaskItem], doneWeek: [TaskItem]) -> some View {
        let plannedHours: Double = PageBuilder.estimateTotals(planned).open
        let doneHours: Double = PageBuilder.estimateTotals(doneWeek).done
        let accent: Color = (AccentChoice(rawValue: accentRaw) ?? .notes).color
        let overdueTint: Color = stats.overdue > 0 ? Tint.overdue : Color.gray
        let plannedLabel: String = "planned today · \(PowerHours.number(plannedHours)) PH left"
        let doneLabel: String = "done in 7 days · \(PowerHours.format(doneHours))"
        return LazyVGrid(columns: tiles, spacing: 12) {
            tile("\(stats.open)", number: Double(stats.open), label: "open tasks", symbol: "tray.full.fill", color: accent, opens: .allTasks)
            tile(PowerHours.number(stats.openHours), number: stats.openHours, label: "PH left", symbol: "timer", color: Tint.powerHours, opens: .allTasks)
            tile("\(stats.overdue)", number: Double(stats.overdue), label: "overdue", symbol: "exclamationmark.circle", color: overdueTint, opens: .upcoming)
            tile("\(stats.dueSoon)", number: Double(stats.dueSoon), label: "due in 7 days", symbol: "calendar", color: Tint.deadline, opens: .upcoming)
            tile("\(planned.count)", number: Double(planned.count), label: plannedLabel, symbol: "sun.max.fill", color: Tint.today, opens: .today)
            tile("\(doneWeek.count)", number: Double(doneWeek.count), label: doneLabel, symbol: "checkmark", color: Tint.done, opens: .history)
        }
    }

    /// One number, Reminders style: its symbol on a small disc in its colour, the number in
    /// rounded figures that roll when it changes, and what it counts below.
    private func tile(_ value: String, number: Double, label: String, symbol: String, color: Color, opens page: SidebarItem) -> some View {
        DrillDown(page, hoverRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    IconDisc(symbol: symbol, color: color)
                    Spacer(minLength: 0)
                    Text(value)
                        .theoFont(.title2, weight: .bold, design: .rounded)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .rollingNumber(number)
                }
                Text(label)
                    .theoFont(.subheadline, weight: .medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Self.cardShape.fill(Self.cardFill)
            }
            .contentShape(Self.cardShape)
        }
    }

    /// A card with a title: its symbol in the colour of what it shows, the title in the text's.
    private func card<Content: View>(_ title: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
            .theoFont(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Self.cardShape.fill(Self.cardFill)
        }
    }

    /// Open tasks due on each of the next 14 days (overdue ones on today): today's bar in
    /// Today's orange, the others in the deadline blue. The bars grow and the total rolls as
    /// deadlines change.
    private func deadlineChart(_ open: [TaskItem], today: Date) -> some View {
        let days = (0...13).map { offset -> (day: Date, count: Int, hours: Double) in
            let day = DayBoundary.current.dayStart(byAdding: offset, to: today)
            let due = open.filter { task in
                guard let date = task.dueDate else { return false }
                let delta = DateText.dayDelta(date, today: today)
                return offset == 0 ? delta <= 0 : delta == offset
            }
            return (day, due.count, PageBuilder.estimateTotals(due).open)
        }
        let first: Date? = days.first?.day
        let counts: [Int] = days.map { $0.count }
        let total: Int = counts.reduce(0, +)
        let hours: Double = days.reduce(0) { $0 + $1.hours }
        let ahead: Color = Tint.deadline.opacity(0.8)
        // The whole chart opens Upcoming, which lists the same deadlines day by day.
        return DrillDown(.upcoming, pressScale: 0.98) {
            VStack(alignment: .leading, spacing: 8) {
                Chart(days, id: \.day) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value("Tasks", item.count))
                        .foregroundStyle(item.day == first ? Tint.today : ahead)
                        .cornerRadius(3)
                }
                .chartXAxis {
                    // A mark under every bar, labelled on every second day only, so the short
                    // weekday names have room.
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(centered: true) {
                            Text(value.as(Date.self).map { Self.axisLabel($0, today: today) } ?? "")
                        }
                    }
                }
                .frame(height: 120)
                .animation(Motion.resolved(Motion.layout), value: counts)
                Text("\(total) due in the next two weeks · \(PowerHours.format(hours))")
                    .theoFont(.caption)
                    .foregroundStyle(.secondary)
                    .rollingNumber(total)
            }
            .contentShape(Rectangle())
        }
    }

    /// The deadline chart's day labels: "Today" under the first bar, then the short weekday
    /// ("Tue", "Thu") of every second day, so Tuesday and Thursday can't be mixed up.
    private nonisolated static func axisLabel(_ date: Date, today: Date) -> String {
        let offset = DateText.dayDelta(date, today: today)
        if offset == 0 { return "Today" }
        guard offset > 0, offset < 14, offset % 2 == 0 else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// Every top-level group, then Quick Entry when something waits there.
    private func groupList(open: [TaskItem], openAnywhere: [TaskItem], today: Date) -> some View {
        let tops = GroupTree.ordered(groups.activeOnly).filter { $0.level == 0 }
        let quick: [TaskItem] = open.filter { $0.groupID == nil }
        // Each group's bar shows its share of all the open Power Hours.
        let total: Double = max(PageBuilder.estimateTotals(open).open, 0.01)
        return VStack(spacing: 8) {
            ForEach(tops, id: \.group.uuid) { item in
                groupCard(item.group, open: open, openAnywhere: openAnywhere, today: today, total: total)
            }
            if !quick.isEmpty {
                quickEntryCard(quick)
            }
        }
    }

    /// One top-level group: what's open and how big, what's pressing, and its subgroups.
    private func groupCard(_ group: TaskGroup, open: [TaskItem], openAnywhere: [TaskItem], today: Date, total: Double) -> some View {
        let inside = Set([group.uuid] + GroupTree.descendants(of: group.uuid, in: groups).map(\.uuid))
        let mine = open.filter { $0.groupID.map { inside.contains($0) } ?? false }
        let stats = TaskStats(mine, today: today)
        // The next deadline still ahead; the overdue ones are counted on their own.
        let nextDue = mine.compactMap(\.dueDate).filter { DateText.dayDelta($0, today: today) >= 0 }.min()
        let subgroups = groups.filter { $0.parentUUID == group.uuid }
        let share: Double = stats.openHours / total
        return DrillDown(.group(group.uuid), hoverRadius: 12) {
            VStack(alignment: .leading, spacing: 8) {
                groupHeader(group, stats: stats, nextDue: nextDue, today: today)
                ShareBar(fraction: share, tint: group.color.color)
                if !subgroups.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(subgroups, id: \.uuid) { sub in
                            // Counted from every open task: a subgroup that's off keeps its
                            // tasks, it only keeps them out of the lists. Shown dimmed.
                            subgroupChip(sub, count: openAnywhere.filter { $0.groupID == sub.uuid }.count)
                        }
                    }
                }
            }
            .padding(12)
            .background {
                Self.rowShape.fill(Self.rowFill)
            }
            .contentShape(Self.rowShape)
        }
    }

    /// The group's icon on a disc in its colour, its name, and "12 open · 3 PH · next Friday"
    /// (orange while something in it is overdue).
    private func groupHeader(_ group: TaskGroup, stats: TaskStats, nextDue: Date?, today: Date) -> some View {
        let lineColor: Color = stats.overdue > 0 ? Tint.overdue : Color.secondary
        return HStack(spacing: 12) {
            IconDisc(symbol: group.symbol, color: group.color.color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(group.displayName)
                        .theoFont(.subheadline, weight: .semibold)
                        .lineLimit(1)
                    if group.isFavorite {
                        Image(systemName: "star.fill")
                            .theoFont(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(Self.groupLine(stats, nextDue: nextDue, today: today))
                    .theoFont(.caption)
                    .foregroundStyle(lineColor)
                    .lineLimit(1)
                    .rollingNumber(stats.open)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .theoFont(.caption, weight: .semibold)
                .foregroundStyle(.tertiary)
        }
    }

    /// A subgroup and how much it holds: its icon in its colour, its name in the text's. One
    /// that's switched off shows a pause symbol and is dimmed.
    private func subgroupChip(_ sub: TaskGroup, count: Int) -> some View {
        HStack(spacing: 4) {
            if sub.isActive {
                Image(systemName: sub.symbol)
                    .foregroundStyle(sub.color.color)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "pause.circle")
                    .accessibilityLabel("Switched off")
            }
            Text(sub.displayName)
                .lineLimit(1)
            Text("\(count)")
                .foregroundStyle(.secondary)
                .rollingNumber(count)
        }
        .theoFont(.caption2, weight: .medium)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(Color.secondary.opacity(0.1))
        }
        .foregroundStyle(sub.isActive ? Color.primary : Color.secondary)
        .opacity(sub.isActive ? 1 : 0.75)
    }

    /// "12 open · 3 PH · 2 overdue · next tomorrow".
    private static func groupLine(_ stats: TaskStats, nextDue: Date?, today: Date) -> String {
        var parts = ["\(stats.open) open", PowerHours.format(stats.openHours)]
        if stats.overdue > 0 { parts.append("\(stats.overdue) overdue") }
        if let nextDue { parts.append("next " + DateText.dueInline(nextDue, hasTime: false, today: today)) }
        return parts.joined(separator: " · ")
    }

    /// Ongoing routines, the longest untouched first: never checked off, then the oldest
    /// check-off. Equal ones keep their manual order.
    private static func byStaleness(_ tasks: [TaskItem]) -> [(task: TaskItem, lastDone: Date?)] {
        tasks.map { (task: $0, lastDone: $0.lastDoneAt) }.sorted { a, b in
            let left = a.lastDone ?? .distantPast
            let right = b.lastDone ?? .distantPast
            if left != right { return left < right }
            return a.task.sortOrder < b.task.sortOrder
        }
    }

    @ViewBuilder
    private func ongoingCard(_ open: [TaskItem], today: Date) -> some View {
        let ongoing = Self.byStaleness(open.filter(\.isOngoing))
        if !ongoing.isEmpty {
            card("Ongoing", symbol: "infinity", tint: Tint.ongoing) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ongoing.prefix(8), id: \.task.uuid) { item in
                        ongoingRow(item.task, lastDone: item.lastDone, today: today)
                    }
                }
            }
        }
    }

    /// One routine and when it was last checked off; orange once that's over a week ago
    /// (or, never done, once it's been around for over a week). Opens the task.
    private func ongoingRow(_ task: TaskItem, lastDone: Date?, today: Date) -> some View {
        let stale = DateText.dayDelta(lastDone ?? task.createdAt, today: today) < -7
        return Button {
            app.reveal(task)
        } label: {
            HStack {
                Text(Self.title(of: task))
                    .lineLimit(1)
                Spacer()
                Text(lastDone.map { "last " + DateText.dueInline($0, hasTime: false, today: today) } ?? "not done yet")
                    .theoFont(.caption)
                    .foregroundStyle(stale ? Color.orange : Color.secondary)
            }
            .theoFont(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func blocksCard(_ open: [TaskItem]) -> some View {
        let blocks = biggestBlocks(open)
        if !blocks.isEmpty {
            card("Biggest Open Blocks", symbol: "square.stack.3d.up", tint: Tint.powerHours) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(blocks, id: \.task.uuid) { block in
                        blockRow(block.task, count: block.count, hours: block.hours)
                    }
                }
            }
        }
    }

    /// A big block: its group's icon (Quick Entry's tray when it has none) in a column of its
    /// own, its title, and what's left in it. Opens the task.
    private func blockRow(_ task: TaskItem, count: Int, hours: Double) -> some View {
        let symbol: String = task.group?.symbol ?? "tray.and.arrow.down.fill"
        let color: Color = task.group?.color.color ?? Color.teal
        return Button {
            app.reveal(task)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 20)
                Text(Self.title(of: task))
                    .lineLimit(1)
                Spacer()
                Text("\(count) open · \(PowerHours.format(hours))")
                    .theoFont(.caption, weight: .medium)
                    .foregroundStyle(.secondary)
                    .rollingNumber(hours)
            }
            .theoFont(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var viewsCard: some View {
        let favorites = views.filter(\.isFavorite)
        if !favorites.isEmpty || !views.isEmpty {
            card("Views", symbol: "line.3.horizontal.decrease.circle", tint: Color.secondary) {
                FlowLinks(views: favorites.isEmpty ? views : favorites)
            }
        }
    }

    private static func title(of task: TaskItem) -> String {
        task.trimmedTitle.isEmpty ? "New Task" : task.trimmedTitle
    }

    /// Quick Entry, like a group: its tray on a teal disc and what waits there to be sorted in.
    private func quickEntryCard(_ quick: [TaskItem]) -> some View {
        DrillDown(.quickEntry, hoverRadius: 12) {
            HStack(spacing: 12) {
                IconDisc(symbol: "tray.and.arrow.down.fill", color: Color.teal, size: 34)
                Text("Quick Entry")
                    .theoFont(.subheadline, weight: .semibold)
                Spacer(minLength: 0)
                Text("\(quick.count) to sort in")
                    .theoFont(.caption)
                    .foregroundStyle(.secondary)
                    .rollingNumber(quick.count)
                Image(systemName: "chevron.right")
                    .theoFont(.caption, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background {
                Self.rowShape.fill(Self.rowFill)
            }
            .contentShape(Self.rowShape)
        }
    }

    /// How the open tasks split over !!!, !!, ! and none. Opens the Priority page. The parts
    /// grow and shrink smoothly, and the counts roll.
    private func priorityBar(_ open: [TaskItem]) -> some View {
        let bands: [PriorityBand] = [Priority.high, .medium, .low, .normal].map { band in
            PriorityBand(priority: band, count: open.filter { $0.priority == band }.count)
        }
        let shown: [PriorityBand] = bands.filter { $0.count > 0 }
        let counts: [Int] = bands.map { $0.count }
        let total = max(1, open.count)
        // The 2-point gaps between the parts come off the width they share.
        let gaps: CGFloat = CGFloat(max(shown.count - 1, 0)) * 2
        return DrillDown(.priority, pressScale: 0.98) {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(shown) { band in
                            Rectangle()
                                .fill(band.color)
                                .frame(width: max(0, geo.size.width - gaps) * CGFloat(band.count) / CGFloat(total))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                .animation(Motion.resolved(Motion.layout), value: counts)
                HStack(spacing: 16) {
                    ForEach(bands) { band in
                        HStack(spacing: 4) {
                            bandMark(band)
                            Text("\(band.count)")
                                .theoFont(.caption, weight: .medium, design: .rounded)
                                .rollingNumber(band.count)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
    }

    /// A priority's marks in its colour ("none" in grey for tasks without one).
    @ViewBuilder
    private func bandMark(_ band: PriorityBand) -> some View {
        if band.priority == .normal {
            Text("none")
                .theoFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
        } else {
            Text(band.priority.marks)
                .theoFont(.caption, weight: .heavy)
                .foregroundStyle(band.color)
        }
    }

    /// Top-level tasks with subtasks, by open Power Hours.
    private func biggestBlocks(_ open: [TaskItem]) -> [(task: TaskItem, count: Int, hours: Double)] {
        var result: [(task: TaskItem, count: Int, hours: Double)] = []
        for section in Dictionary(grouping: open, by: \.groupID).values {
            let rows = PageBuilder.taskRows(section, options: PageBuilder.Options())
            for row in rows {
                guard case .task(let task, let depth, let style) = row, depth == 0, style.subtaskCount > 0 else { continue }
                result.append((task, style.subtaskCount - style.subtasksDone, style.blockEstimate))
            }
        }
        return Array(result.sorted { $0.hours > $1.hours }.prefix(5))
    }
}

private struct PriorityBand: Identifiable {
    let priority: Priority
    let count: Int

    var id: Int { priority.rawValue }
    var color: Color { priority == .normal ? Color.secondary.opacity(0.4) : priority.color }
}

/// A symbol on a small disc in its colour, like the tiles in Reminders and the icons in
/// Settings: the glyph in white, or near-black on a bright fill (Notes Yellow, a yellow group)
/// where white would be hard to see. It grows with Theo's text size on the Mac.
private struct IconDisc: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30

    @Environment(\.textScale) private var textScale
    @Environment(\.self) private var environment

    var body: some View {
        let side: CGFloat = size * max(1, textScale)
        let glyph: Color = color.onFillForeground(in: environment)
        Image(systemName: symbol)
            .font(.system(size: side * 0.47, weight: .semibold))
            .foregroundStyle(glyph)
            .frame(width: side, height: side)
            .background {
                Circle().fill(color.gradient)
            }
            .accessibilityHidden(true)
    }
}

/// A thin track with a coloured part for a share (a group's part of all the open Power Hours),
/// which grows or shrinks smoothly when it changes.
private struct ShareBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let filled: CGFloat = geo.size.width * CGFloat(min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: fraction > 0 ? max(filled, 4) : 0)
            }
        }
        .frame(height: 4)
        .animation(Motion.resolved(Motion.layout), value: fraction)
        .accessibilityHidden(true)
    }
}

/// Saved views as tappable chips: each view's symbol in its colour, its name in the text's.
private struct FlowLinks: View {
    let views: [SavedView]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(views, id: \.uuid) { view in
                    DrillDown(.view(view.uuid)) {
                        Label {
                            Text(view.displayName)
                        } icon: {
                            Image(systemName: view.isFavorite ? "star.fill" : view.symbol)
                                .foregroundStyle(view.color.color)
                        }
                        .theoFont(.caption, weight: .semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule().fill(Color.secondary.opacity(0.1))
                        }
                        .contentShape(Capsule())
                    }
                }
            }
        }
    }
}

/// Opens the page behind a card. On iPhone the page is pushed inside the Overview tab, so
/// Back comes back to the Overview (Today and Plan switch to their own tabs). On the Mac and
/// iPad the sidebar moves to the page. Cards give way a little under the finger; with a
/// `hoverRadius` they also light up faintly under the pointer.
private struct DrillDown<Content: View>: View {
    let page: SidebarItem
    let content: Content
    /// How far it gives way when pressed (large cards less than small tiles).
    var pressScale: CGFloat = 0.96
    /// The corner radius of its surface, for the pointer's highlight (nil = none).
    var hoverRadius: CGFloat?
    @Environment(AppModel.self) private var app
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var hovering = false

    init(_ page: SidebarItem, pressScale: CGFloat = 0.96, hoverRadius: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.page = page
        self.pressScale = pressScale
        self.hoverRadius = hoverRadius
        self.content = content()
    }

    var body: some View {
        if pushesInPlace {
            NavigationLink(value: page) {
                label
            }
            .buttonStyle(PressableStyle(scale: pressScale))
        } else {
            Button {
                app.go(page)
            } label: {
                label
            }
            .buttonStyle(PressableStyle(scale: pressScale))
        }
    }

    private var label: some View {
        content
            .foregroundStyle(.primary)
            .overlay {
                hoverFill
            }
            .onHover { inside in
                hover(inside)
            }
    }

    @ViewBuilder
    private var hoverFill: some View {
        if let hoverRadius, hovering {
            RoundedRectangle(cornerRadius: hoverRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func hover(_ inside: Bool) {
        guard hoverRadius != nil else { return }
        Motion.animate(Motion.hover) { hovering = inside }
    }

    /// iPhone (and a narrow iPad window, which shows the same tabs): the Overview tab's
    /// stack has a destination for every sidebar page.
    private var pushesInPlace: Bool {
        #if os(iOS)
        return sizeClass == .compact && page != .today && page != .plan
        #else
        return false
        #endif
    }
}
