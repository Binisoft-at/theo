import SwiftUI
import TheoCore

typealias LabeledSection = (key: String, title: String, symbol: String, color: Color, tasks: [TaskItem])

enum TaskFilter: Hashable {
    case all
    case priority
    case due
    case tag(String)

    func matches(_ task: TaskItem, today: Date) -> Bool {
        switch self {
        case .all:
            return true
        case .priority:
            return task.priority != .normal
        case .due:
            guard let due = task.dueDate else { return false }
            return DateText.dayDelta(due, today: today) <= 0
        case .tag(let tag):
            return task.tags.contains(tag)
        }
    }
}

/// Computed groupings used by Today (re-grouped), Upcoming, Priority, Tags and Search.
enum Sections {
    /// Page position of a task: Quick Entry first, then groups in order, then manual order.
    static func pageOrder(_ groups: [TaskGroup]) -> (TaskItem, TaskItem) -> Bool {
        var groupRank: [UUID: Int] = [:]
        for (index, item) in GroupTree.ordered(groups).enumerated() { groupRank[item.group.uuid] = index }
        return { a, b in
            let ra = a.groupID.flatMap { groupRank[$0] } ?? -1
            let rb = b.groupID.flatMap { groupRank[$0] } ?? -1
            if ra != rb { return ra < rb }
            return a.sortOrder < b.sortOrder
        }
    }

    static func byPriority(_ tasks: [TaskItem], groups: [TaskGroup], includeNone: Bool) -> [LabeledSection] {
        let order = pageOrder(groups)
        var result: [LabeledSection] = []
        for priority in Priority.allCases.reversed() where includeNone || priority != .normal {
            let items = tasks.filter { $0.priority == priority }.sorted(by: order)
            let title = priority == .normal ? "No Priority" : "\(priority.title) Priority"
            result.append((key: "p\(priority.rawValue)", title: title, symbol: priority == .normal ? "circle.dashed" : priority.symbol,
                           color: priority == .normal ? .secondary : priority.color, tasks: items))
        }
        return result
    }

    static func byDeadline(_ tasks: [TaskItem], groups: [TaskGroup], today: Date, includeNone: Bool) -> [LabeledSection] {
        let order = pageOrder(groups)
        var overdue: [TaskItem] = []
        var todayItems: [TaskItem] = []
        var tomorrow: [TaskItem] = []
        var week: [TaskItem] = []
        var later: [TaskItem] = []
        var none: [TaskItem] = []
        for task in tasks {
            guard let due = task.dueDate else {
                none.append(task)
                continue
            }
            let delta = DateText.dayDelta(due, today: today)
            switch delta {
            case ..<0: overdue.append(task)
            case 0: todayItems.append(task)
            case 1: tomorrow.append(task)
            case 2...6: week.append(task)
            default: later.append(task)
            }
        }
        let byDate: (TaskItem, TaskItem) -> Bool = { a, b in
            let da = a.dueDate ?? .distantFuture
            let db = b.dueDate ?? .distantFuture
            if da != db { return da < db }
            return order(a, b)
        }
        var result: [LabeledSection] = [
            (key: "overdue", title: "Overdue", symbol: "exclamationmark.circle", color: .red, tasks: overdue.sorted(by: byDate)),
            (key: "today", title: "Today", symbol: "sun.max", color: .orange, tasks: todayItems.sorted(by: byDate)),
            (key: "tomorrow", title: "Tomorrow", symbol: "sunrise", color: .yellow, tasks: tomorrow.sorted(by: byDate)),
            (key: "week", title: "This Week", symbol: "calendar", color: .blue, tasks: week.sorted(by: byDate)),
            (key: "later", title: "Later", symbol: "calendar.badge.clock", color: .indigo, tasks: later.sorted(by: byDate))
        ]
        if includeNone {
            result.append((key: "none", title: "No Deadline", symbol: "circle.dashed", color: .secondary, tasks: none.sorted(by: order)))
        }
        return result
    }

    /// Upcoming: one section per day for the next week, keyed by deadline or planned day.
    static func upcoming(_ tasks: [TaskItem], groups: [TaskGroup], today: Date) -> [LabeledSection] {
        let cal = Calendar.current
        let order = pageOrder(groups)
        func keyDate(_ task: TaskItem) -> Date? {
            if let due = task.dueDate { return due }
            if let planned = task.plannedDay, planned > today { return planned }
            return nil
        }
        let dated = tasks.compactMap { task in keyDate(task).map { (task, $0) } }
        let sorter: ((TaskItem, Date), (TaskItem, Date)) -> Bool = { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if a.0.priority != b.0.priority { return a.0.priority > b.0.priority }
            return order(a.0, b.0)
        }

        var result: [LabeledSection] = []
        let overdue = dated.filter { DateText.dayDelta($0.1, today: today) < 0 }.sorted(by: sorter).map { $0.0 }
        result.append((key: "overdue", title: "Overdue", symbol: "exclamationmark.circle", color: .red, tasks: overdue))
        for offset in 0...6 {
            let items = dated.filter { DateText.dayDelta($0.1, today: today) == offset }.sorted(by: sorter).map { $0.0 }
            let date = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: today)) ?? today
            let title: String
            switch offset {
            case 0: title = "Today"
            case 1: title = "Tomorrow"
            default: title = date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
            }
            result.append((key: "d\(offset)", title: title, symbol: offset == 0 ? "sun.max" : "calendar",
                           color: offset == 0 ? .orange : .blue, tasks: items))
        }
        let later = dated.filter { DateText.dayDelta($0.1, today: today) > 6 }.sorted(by: sorter).map { $0.0 }
        result.append((key: "later", title: "Later", symbol: "calendar.badge.clock", color: .indigo, tasks: later))
        return result
    }

    static func byGroup(_ tasks: [TaskItem], groups: [TaskGroup]) -> [LabeledSection] {
        var result: [LabeledSection] = []
        let quick = tasks.filter { $0.groupID == nil }.sorted { $0.sortOrder < $1.sortOrder }
        result.append((key: "quick", title: "Quick Entry", symbol: "tray.and.arrow.down.fill", color: .secondary, tasks: quick))
        for (group, _) in GroupTree.ordered(groups) {
            let items = tasks.filter { $0.groupID == group.uuid }.sorted { $0.sortOrder < $1.sortOrder }
            result.append((key: group.uuid.uuidString, title: GroupTree.path(of: group, in: groups), symbol: group.symbol, color: group.color.color, tasks: items))
        }
        return result
    }

    /// One section per top-level group, holding its subgroups' tasks too (Quick Entry first).
    static func byTopGroup(_ tasks: [TaskItem], groups: [TaskGroup]) -> [LabeledSection] {
        var result: [LabeledSection] = [
            (key: "quick", title: "Quick Entry", symbol: "tray.and.arrow.down.fill", color: .secondary, tasks: tasks.filter { $0.groupID == nil })
        ]
        for item in GroupTree.ordered(groups) where item.level == 0 {
            let inside = Set([item.group.uuid] + GroupTree.descendants(of: item.group.uuid, in: groups).map(\.uuid))
            let items = tasks.filter { task in task.groupID.map { inside.contains($0) } ?? false }
            result.append((key: item.group.uuid.uuidString, title: item.group.displayName, symbol: item.group.symbol,
                           color: item.group.color.color, tasks: items))
        }
        return result
    }

    /// One section per tag, most used first; a task with several tags sits under its first.
    static func byTag(_ tasks: [TaskItem]) -> [LabeledSection] {
        var result: [LabeledSection] = []
        var placed = Set<ObjectIdentifier>()
        for tag in Self.tags(in: tasks) {
            let items = tasks.filter { !placed.contains(ObjectIdentifier($0)) && $0.tags.first == tag }
            items.forEach { placed.insert(ObjectIdentifier($0)) }
            result.append((key: "tag-" + tag, title: "#" + tag, symbol: "number", color: TheoColor.forTag(tag).color, tasks: items))
        }
        let untagged = tasks.filter { !placed.contains(ObjectIdentifier($0)) }
        result.append((key: "tag-none", title: "No Tag", symbol: "circle.dashed", color: .secondary, tasks: untagged))
        return result
    }

    /// By estimate: quick wins, short tasks, deep work, and the ones without one.
    static func bySize(_ tasks: [TaskItem]) -> [LabeledSection] {
        [
            (key: "size-quick", title: "Quick Wins · up to \(PowerHours.format(0.25))", symbol: "hare", color: .green,
             tasks: tasks.filter { $0.estimate > 0 && $0.estimate <= 0.25 }),
            (key: "size-short", title: "Short · up to \(PowerHours.format(1))", symbol: "timer", color: .teal,
             tasks: tasks.filter { $0.estimate > 0.25 && $0.estimate <= 1 }),
            (key: "size-deep", title: "Deep Work · more than \(PowerHours.format(1))", symbol: "brain.head.profile", color: .indigo,
             tasks: tasks.filter { $0.estimate > 1 }),
            (key: "size-none", title: "No Estimate", symbol: "circle.dashed", color: .secondary,
             tasks: tasks.filter { $0.estimate <= 0 }),
        ]
    }

    static func tags(in tasks: [TaskItem]) -> [String] {
        var counts: [String: Int] = [:]
        for task in tasks {
            for tag in task.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
    }
}
