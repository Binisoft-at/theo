import SwiftUI
import SwiftData
import Charts
import TheoCore

/// Everything at a glance, so a long list never feels like a wall: totals, today, the
/// deadlines ahead, each group's size and state, priorities, ongoing work and the biggest
/// open blocks. Every card leads to the list behind it.
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

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: tiles, spacing: 10) {
                    tile("\(stats.open)", "open tasks", symbol: "circle.dashed", color: .accentColor) { app.go(.allTasks) }
                    tile(PowerHours.format(stats.openHours), "still to do", symbol: "timer", color: .teal) { app.go(.allTasks) }
                    tile("\(stats.overdue)", "overdue", symbol: "exclamationmark.circle", color: stats.overdue > 0 ? .red : .secondary) { app.go(.upcoming) }
                    tile("\(stats.dueSoon)", "due in 7 days", symbol: "calendar", color: .orange) { app.go(.upcoming) }
                    tile("\(planned.count)", "planned today · \(PowerHours.format(PageBuilder.estimateTotals(planned).open))", symbol: "sun.max", color: .orange) { app.go(.today) }
                    tile("\(doneWeek.count)", "done this week · \(PowerHours.format(PageBuilder.estimateTotals(doneWeek).done))", symbol: "checkmark.seal", color: .green) { app.reviewDay = DayRef(start: today) }
                }

                card("Deadlines Ahead", symbol: "calendar") {
                    deadlineChart(open, today: today)
                }

                card("Groups", symbol: "square.grid.2x2") {
                    VStack(spacing: 10) {
                        ForEach(GroupTree.ordered(groups.activeOnly).filter { $0.level == 0 }, id: \.group.uuid) { item in
                            groupCard(item.group, open: open, today: today)
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

                let ongoing = open.filter(\.isOngoing)
                if !ongoing.isEmpty {
                    card("Ongoing", symbol: "infinity") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ongoing.prefix(8), id: \.uuid) { task in
                                HStack {
                                    Text(task.trimmedTitle)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(task.lastDoneAt.map { "last " + DateText.due($0, hasTime: false, today: today) } ?? "not done yet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }

                let blocks = biggestBlocks(open)
                if !blocks.isEmpty {
                    card("Biggest Open Blocks", symbol: "square.stack.3d.up") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(blocks, id: \.task.uuid) { block in
                                HStack(spacing: 8) {
                                    if let group = block.task.group {
                                        Image(systemName: group.symbol)
                                            .foregroundStyle(group.color.color)
                                            .frame(width: 20)
                                    }
                                    Text(block.task.trimmedTitle)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(block.count) open · \(PowerHours.format(block.hours))")
                                        .font(.caption.weight(.medium))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }

                let favorites = views.filter(\.isFavorite)
                if !favorites.isEmpty || !views.isEmpty {
                    card("Views", symbol: "line.3.horizontal.decrease.circle") {
                        FlowLinks(views: favorites.isEmpty ? views : favorites) { view in app.go(.view(view.uuid)) }
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

    private func tile(_ value: String, _ label: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
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
        return VStack(alignment: .leading, spacing: 6) {
            Chart(days, id: \.day) { item in
                BarMark(x: .value("Day", item.day, unit: .day), y: .value("Tasks", item.count))
                    .foregroundStyle(item.day == days.first?.day ? Color.orange : Color.accentColor.opacity(0.7))
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 120)
            Text("\(days.reduce(0) { $0 + $1.count }) due in the next two weeks · \(PowerHours.format(days.reduce(0) { $0 + $1.hours }))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onTapGesture { app.go(.upcoming) }
    }

    /// One top-level group: what's open and how big, what's pressing, and its subgroups.
    private func groupCard(_ group: TaskGroup, open: [TaskItem], today: Date) -> some View {
        let inside = Set([group.uuid] + GroupTree.descendants(of: group.uuid, in: groups).map(\.uuid))
        let mine = open.filter { $0.groupID.map { inside.contains($0) } ?? false }
        let stats = TaskStats(mine, today: today)
        let nextDue = mine.compactMap(\.dueDate).min()
        let subgroups = groups.filter { $0.parentUUID == group.uuid }
        return Button {
            app.go(.group(group.uuid))
        } label: {
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
                            let count = open.filter { $0.groupID == sub.uuid }.count
                            Text("\(sub.displayName) \(count)")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(sub.color.color.opacity(sub.isActive ? 0.15 : 0.05)))
                                .foregroundStyle(sub.isActive ? sub.color.color : Color.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(group.color.color.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "12 open · 3 PH · 2 overdue · next Fri".
    private static func groupLine(_ stats: TaskStats, nextDue: Date?, today: Date) -> String {
        var parts = ["\(stats.open) open", PowerHours.format(stats.openHours)]
        if stats.overdue > 0 { parts.append("\(stats.overdue) overdue") }
        if let nextDue { parts.append("next " + DateText.due(nextDue, hasTime: false, today: today)) }
        return parts.joined(separator: " · ")
    }

    private func quickEntryCard(_ quick: [TaskItem]) -> some View {
        Button {
            app.go(.quickEntry)
        } label: {
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
        .buttonStyle(.plain)
    }

    /// How the open tasks split over !!!, !!, ! and none.
    private func priorityBar(_ open: [TaskItem]) -> some View {
        let bands: [PriorityBand] = [Priority.high, .medium, .low, .normal].map { band in
            PriorityBand(priority: band, count: open.filter { $0.priority == band }.count)
        }
        let total = max(1, open.count)
        return VStack(alignment: .leading, spacing: 8) {
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
            }
        }
        .onTapGesture { app.go(.priority) }
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
    let open: (SavedView) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(views, id: \.uuid) { view in
                    Button {
                        open(view)
                    } label: {
                        Label(view.displayName, systemImage: view.isFavorite ? "star.fill" : view.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(view.color.color.opacity(0.14)))
                            .foregroundStyle(view.color.color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
