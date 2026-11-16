import SwiftUI
import SwiftData
import Charts
import TheoCore

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

    private let tiles = [GridItem(.adaptive(minimum: 150), spacing: 10)]

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
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: tiles, spacing: 10) {
                    tile("\(stats.open)", "open tasks", symbol: "circle.dashed", color: .accentColor, opens: .allTasks)
                    tile(PowerHours.number(stats.openHours), "PH left", symbol: "timer", color: .teal, opens: .allTasks)
                    tile("\(stats.overdue)", "overdue", symbol: "exclamationmark.circle", color: stats.overdue > 0 ? .red : .secondary, opens: .upcoming)
                    tile("\(stats.dueSoon)", "due in 7 days", symbol: "calendar", color: .orange, opens: .upcoming)
                    tile("\(planned.count)", "planned today · \(PowerHours.number(PageBuilder.estimateTotals(planned).open)) PH left", symbol: "sun.max", color: .orange, opens: .today)
                    tile("\(doneWeek.count)", "done in 7 days · \(PowerHours.format(PageBuilder.estimateTotals(doneWeek).done))", symbol: "checkmark.seal", color: .green, opens: .history)
                }

                card("Deadlines Ahead", symbol: "calendar") {
                    deadlineChart(open, today: today)
                }

                card("Groups", symbol: "square.grid.2x2") {
                    VStack(spacing: 10) {
                        ForEach(GroupTree.ordered(groups.activeOnly).filter { $0.level == 0 }, id: \.group.uuid) { item in
                            groupCard(item.group, open: open, openAnywhere: openAnywhere, today: today)
                        }
                        let quick = open.filter { $0.groupID == nil }
                        if !quick.isEmpty {
                            quickEntryCard(quick)
                        }
                    }
                }

                card("Priorities", symbol: "exclamationmark.3") {
                    priorityBar(open)
                }

                let ongoing = Self.byStaleness(open.filter(\.isOngoing))
                if !ongoing.isEmpty {
                    card("Ongoing", symbol: "infinity") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ongoing.prefix(8), id: \.task.uuid) { item in
                                ongoingRow(item.task, lastDone: item.lastDone, today: today)
                            }
                        }
                    }
                }

                let blocks = biggestBlocks(open)
                if !blocks.isEmpty {
                    card("Biggest Open Blocks", symbol: "square.stack.3d.up") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(blocks, id: \.task.uuid) { block in
                                Button {
                                    app.reveal(block.task)
                                } label: {
                                    HStack(spacing: 8) {
                                        if let group = block.task.group {
                                            Image(systemName: group.symbol)
                                                .foregroundStyle(group.color.color)
                                                .frame(width: 20)
                                        }
                                        Text(Self.title(of: block.task))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(block.count) open · \(PowerHours.format(block.hours))")
                                            .font(.caption.weight(.medium))
                                            .monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let favorites = views.filter(\.isFavorite)
                if !favorites.isEmpty || !views.isEmpty {
                    card("Views", symbol: "line.3.horizontal.decrease.circle") {
                        FlowLinks(views: favorites.isEmpty ? views : favorites)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Color.secondary.opacity(0.05))
        .navigationTitle("Overview")
    }

    // MARK: - Pieces

    private func tile(_ value: String, _ label: String, symbol: String, color: Color, opens page: SidebarItem) -> some View {
        DrillDown(page) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color.opacity(0.1)))
            .contentShape(Rectangle())
        }
    }

    private func card<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.secondary.opacity(0.12)))
    }

    /// Open tasks due on each of the next 14 days (overdue ones on today).
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
        // The whole chart opens Upcoming, which lists the same deadlines day by day.
        return DrillDown(.upcoming) {
            VStack(alignment: .leading, spacing: 6) {
                Chart(days, id: \.day) { item in
                    BarMark(x: .value("Day", item.day, unit: .day), y: .value("Tasks", item.count))
                        .foregroundStyle(item.day == days.first?.day ? Color.orange : Color.accentColor.opacity(0.7))
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
                Text("\(days.reduce(0) { $0 + $1.count }) due in the next two weeks · \(PowerHours.format(days.reduce(0) { $0 + $1.hours }))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    /// One top-level group: what's open and how big, what's pressing, and its subgroups.
    private func groupCard(_ group: TaskGroup, open: [TaskItem], openAnywhere: [TaskItem], today: Date) -> some View {
        let inside = Set([group.uuid] + GroupTree.descendants(of: group.uuid, in: groups).map(\.uuid))
        let mine = open.filter { $0.groupID.map { inside.contains($0) } ?? false }
        let stats = TaskStats(mine, today: today)
        // The next deadline still ahead; the overdue ones are counted on their own.
        let nextDue = mine.compactMap(\.dueDate).filter { DateText.dayDelta($0, today: today) >= 0 }.min()
        let subgroups = groups.filter { $0.parentUUID == group.uuid }
        return DrillDown(.group(group.uuid)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: group.symbol)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(group.color.color.gradient))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(group.displayName)
                                .font(.subheadline.weight(.semibold))
                            if group.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        Text(Self.groupLine(stats, nextDue: nextDue, today: today))
                            .font(.caption)
                            .foregroundStyle(stats.overdue > 0 ? Color.red : Color.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                // Each group's share of all the open Power Hours.
                let total = max(PageBuilder.estimateTotals(open).open, 0.01)
                GeometryReader { geo in
                    Capsule()
                        .fill(group.color.color.opacity(0.7))
                        .frame(width: max(4, geo.size.width * stats.openHours / total))
                }
                .frame(height: 4)
                if !subgroups.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(subgroups, id: \.uuid) { sub in
                            // Counted from every open task: a subgroup that's off keeps its
                            // tasks, it only keeps them out of the lists. Shown dimmed.
                            let count = openAnywhere.filter { $0.groupID == sub.uuid }.count
                            HStack(spacing: 3) {
                                if !sub.isActive {
                                    Image(systemName: "pause.circle")
                                        .accessibilityLabel("Switched off")
                                }
                                Text("\(sub.displayName) \(count)")
                            }
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(sub.color.color.opacity(sub.isActive ? 0.15 : 0.05)))
                            .foregroundStyle(sub.isActive ? sub.color.color : Color.secondary)
                            .opacity(sub.isActive ? 1 : 0.75)
                        }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(group.color.color.opacity(0.06)))
            .contentShape(Rectangle())
        }
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
                    .font(.caption)
                    .foregroundStyle(stale ? Color.orange : Color.secondary)
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func title(of task: TaskItem) -> String {
        task.trimmedTitle.isEmpty ? "New Task" : task.trimmedTitle
    }

    private func quickEntryCard(_ quick: [TaskItem]) -> some View {
        DrillDown(.quickEntry) {
            HStack {
                Label("Quick Entry", systemImage: "tray.and.arrow.down.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.teal)
                Spacer()
                Text("\(quick.count) to sort in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.teal.opacity(0.06)))
            .contentShape(Rectangle())
        }
    }

    /// How the open tasks split over !!!, !!, ! and none. Opens the Priority page.
    private func priorityBar(_ open: [TaskItem]) -> some View {
        let bands: [PriorityBand] = [Priority.high, .medium, .low, .normal].map { band in
            PriorityBand(priority: band, count: open.filter { $0.priority == band }.count)
        }
        let total = max(1, open.count)
        return DrillDown(.priority) {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(bands.filter { $0.count > 0 }) { band in
                            Rectangle()
                                .fill(band.color)
                                .frame(width: geo.size.width * CGFloat(band.count) / CGFloat(total))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                HStack(spacing: 14) {
                    ForEach(bands) { band in
                        HStack(spacing: 4) {
                            Text(band.priority == .normal ? "none" : band.priority.marks)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(band.color)
                            Text("\(band.count)")
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
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

/// Saved views as tappable chips.
private struct FlowLinks: View {
    let views: [SavedView]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(views, id: \.uuid) { view in
                    DrillDown(.view(view.uuid)) {
                        Label(view.displayName, systemImage: view.isFavorite ? "star.fill" : view.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(view.color.color.opacity(0.14)))
                            .foregroundStyle(view.color.color)
                    }
                }
            }
        }
    }
}

/// Opens the page behind a card. On iPhone the page is pushed inside the Overview tab, so
/// Back comes back to the Overview (Today and Plan switch to their own tabs). On the Mac and
/// iPad the sidebar moves to the page.
private struct DrillDown<Content: View>: View {
    let page: SidebarItem
    let content: Content
    @Environment(AppModel.self) private var app
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(_ page: SidebarItem, @ViewBuilder content: () -> Content) {
        self.page = page
        self.content = content()
    }

    var body: some View {
        if pushesInPlace {
            NavigationLink(value: page) {
                content
            }
            .buttonStyle(.plain)
        } else {
            Button {
                app.go(page)
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
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
