import SwiftUI
import TheoCore

/// Turns a `TaskQuery` into list rows (All Tasks and saved views): the matching tasks, in
/// sections by the query's grouping, sorted by its order. A matching task keeps its matching
/// subtasks under it, so parents still read as small groups.
enum QueryBuilder {
    struct Result {
        var rows: [ListRow]
        var matched: [TaskItem]
    }

    static func build(tasks: [TaskItem], groups: [TaskGroup], query: TaskQuery, today: Date, collapsed: Set<UUID>) -> Result {
        // Nesting per group, the way every page derives it.
        var parent: [ObjectIdentifier: TaskItem] = [:]
        var children: [ObjectIdentifier: [TaskItem]] = [:]
        for section in Dictionary(grouping: tasks, by: \.groupID).values {
            let ordered = section.sorted { $0.sortOrder < $1.sortOrder }
            let depths = Checklist.depths(of: ordered)
            var stack: [TaskItem] = []
            for (index, task) in ordered.enumerated() {
                let depth = depths[index]
                stack = Array(stack.prefix(depth))
                if let up = stack.last {
                    parent[ObjectIdentifier(task)] = up
                    children[ObjectIdentifier(up), default: []].append(task)
                }
                stack.append(task)
            }
        }

        // Groups switched off stay out unless the query asks for them by name.
        let off = query.groupIDs.isEmpty && !query.quickEntryOnly ? GroupTree.inactiveIDs(groups) : []
        let byID = Dictionary(groups.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        func path(_ id: UUID?) -> [UUID] {
            var result: [UUID] = []
            var current = id
            while let value = current, !result.contains(value), let group = byID[value] {
                result.append(value)
                current = group.parentUUID
            }
            return result
        }
        var facts: [ObjectIdentifier: TaskQuery.Facts] = [:]
        var scores: [ObjectIdentifier: Double] = [:]
        var matched: [TaskItem] = []
        for task in tasks {
            if let id = task.groupID, off.contains(id) { continue }
            let fact = TaskQuery.Facts(
                title: task.trimmedTitle,
                notes: task.notes,
                isDone: task.isDone,
                groupPath: path(task.groupID),
                tags: task.tags,
                level: task.importanceLevel,
                daysUntilDue: task.isDone ? nil : Matrix.daysUntil(task.dueDate, today: today),
                plannedIn: task.plannedDay.map { DateText.dayDelta($0, today: today) },
                isOngoing: task.isOngoing,
                estimate: task.estimate,
                created: task.createdAt
            )
            let key = ObjectIdentifier(task)
            facts[key] = fact
            scores[key] = task.matrixScore(today: today)
            if query.matches(fact) { matched.append(task) }
        }
        let matchedIDs = Set(matched.map(ObjectIdentifier.init))
        let roots = matched.filter { task in
            guard let up = parent[ObjectIdentifier(task)] else { return true }
            return !matchedIDs.contains(ObjectIdentifier(up))
        }

        func precedes(_ a: TaskItem, _ b: TaskItem) -> Bool {
            let ka = ObjectIdentifier(a), kb = ObjectIdentifier(b)
            guard let fa = facts[ka], let fb = facts[kb] else { return false }
            return query.precedes(fa, fb, scoreA: scores[ka] ?? 0, scoreB: scores[kb] ?? 0)
        }

        func block(_ task: TaskItem, depth: Int, into rows: inout [ListRow]) {
            let all = descendants(task, children: children)
            var style = RowStyle(showGroup: query.grouping != .group && query.grouping != .topGroup)
            style.subtaskCount = all.count
            style.subtasksDone = all.filter(\.isDone).count
            style.subtasksFolded = !all.isEmpty && collapsed.contains(task.uuid)
            style.blockEstimate = all.isEmpty ? 0 : PowerHours.total([task] + all, where: { !$0.isDone })
            rows.append(.task(task, depth: depth, style: style))
            guard !style.subtasksFolded else { return }
            for child in children[ObjectIdentifier(task)] ?? [] where matchedIDs.contains(ObjectIdentifier(child)) {
                block(child, depth: depth + 1, into: &rows)
            }
        }

        var rows: [ListRow] = []
        for section in sections(roots, groups: groups, query: query, today: today) where !section.tasks.isEmpty {
            let inSection = section.tasks.flatMap { [$0] + descendants($0, children: children) }.filter { matchedIDs.contains(ObjectIdentifier($0)) }
            let open = inSection.filter { !$0.isDone }
            if query.grouping != .none {
                rows.append(.header(SectionHeaderInfo(
                    id: "q-" + section.key,
                    kind: .label(key: section.key, title: section.title, symbol: section.symbol, color: section.color),
                    openCount: open.count,
                    doneCount: inSection.count - open.count,
                    isCollapsed: false,
                    collapsible: false,
                    openEstimate: PageBuilder.estimateTotals(open).open
                )))
            }
            for root in section.tasks.sorted(by: precedes) {
                block(root, depth: 0, into: &rows)
            }
        }
        return Result(rows: rows, matched: matched)
    }

    private static func descendants(_ task: TaskItem, children: [ObjectIdentifier: [TaskItem]]) -> [TaskItem] {
        var result: [TaskItem] = []
        var stack = children[ObjectIdentifier(task)] ?? []
        while !stack.isEmpty {
            let next = stack.removeFirst()
            result.append(next)
            stack.insert(contentsOf: children[ObjectIdentifier(next)] ?? [], at: 0)
        }
        return result
    }

    /// The query's sections, in their natural order.
    private static func sections(_ roots: [TaskItem], groups: [TaskGroup], query: TaskQuery, today: Date) -> [LabeledSection] {
        switch query.grouping {
        case .none:
            return [(key: "all", title: "All", symbol: "tray.full", color: .secondary, tasks: roots)]
        case .group:
            return Sections.byGroup(roots, groups: groups)
        case .topGroup:
            return Sections.byTopGroup(roots, groups: groups)
        case .priority:
            return Sections.byPriority(roots, groups: groups, includeNone: true)
        case .deadline:
            return Sections.byDeadline(roots, groups: groups, today: today, includeNone: true)
        case .tag:
            return Sections.byTag(roots)
        case .size:
            return Sections.bySize(roots)
        case .planned:
            let tomorrow = DayBoundary.current.dayStart(byAdding: 1, to: today)
            func delta(_ task: TaskItem) -> Int? { task.plannedDay.map { DateText.dayDelta($0, today: today) } }
            return [
                (key: "plan-today", title: "Today", symbol: "sun.max", color: .orange, tasks: roots.filter { delta($0) == 0 }),
                (key: "plan-tomorrow", title: DateText.pageTitle(tomorrow), symbol: "sunrise", color: .indigo, tasks: roots.filter { delta($0) == 1 }),
                (key: "plan-later", title: "Later", symbol: "calendar", color: .blue, tasks: roots.filter { (delta($0) ?? 0) > 1 }),
                (key: "plan-past", title: "Planned Earlier", symbol: "arrow.uturn.backward", color: .orange, tasks: roots.filter { (delta($0) ?? 0) < 0 }),
                (key: "plan-none", title: "Not Planned", symbol: "circle.dashed", color: .secondary, tasks: roots.filter { $0.plannedDay == nil }),
            ]
        }
    }
}

/// Numbers on top of a list: what's left, how big it is, and what's pressing.
struct TaskStats {
    var open = 0
    var openHours = 0.0
    var overdue = 0
    var dueSoon = 0
    var doneToday = 0
    var doneTodayHours = 0.0
    var total = 0

    init(_ tasks: [TaskItem], today: Date) {
        let end = DayBoundary.current.end(ofDayStarting: today)
        let openTasks = tasks.filter { !$0.isDone }
        open = openTasks.count
        total = tasks.count
        openHours = PageBuilder.estimateTotals(openTasks).open
        for task in openTasks {
            guard let due = task.dueDate else { continue }
            let days = DateText.dayDelta(due, today: today)
            if days < 0 { overdue += 1 } else if days <= 7 { dueSoon += 1 }
        }
        let doneNow = tasks.filter { task in
            guard task.isDone, let completed = task.completedAt else { return false }
            return completed >= today && completed < end
        }
        doneToday = doneNow.count
        doneTodayHours = PageBuilder.estimateTotals(doneNow).done
    }
}

/// A row of small figures for a group or a list: open, Power Hours, overdue, due soon, done today.
struct TaskStatsBar: View {
    let stats: TaskStats

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                figure("\(stats.open)", "open", symbol: "circle", color: .accentColor)
                figure(PowerHours.number(stats.openHours), "PH left", symbol: "timer", color: .teal)
                if stats.overdue > 0 {
                    figure("\(stats.overdue)", "overdue", symbol: "exclamationmark.circle", color: .red)
                }
                if stats.dueSoon > 0 {
                    figure("\(stats.dueSoon)", "due in 7 days", symbol: "calendar", color: .orange)
                }
                figure("\(stats.doneToday)", stats.doneTodayHours > 0 ? "done today · \(PowerHours.format(stats.doneTodayHours))" : "done today",
                       symbol: "checkmark.circle", color: .green)
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func figure(_ value: String, _ label: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }
}
