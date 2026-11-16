import Foundation
import TheoCore

/// What Today offers to take on in the morning: tasks planned for an earlier day and left open,
/// and tasks due by today that aren't planned for any day. Counted in whole blocks (a parent
/// with its subtasks is one), because planning a task plans its subtasks with it.
enum CarryOver {
    struct Result {
        /// Planned for an earlier day and still open, most important first.
        var leftOver: [TaskItem] = []
        /// Due today or overdue and not planned at all, most important first.
        var dueUnplanned: [TaskItem] = []

        var isEmpty: Bool { leftOver.isEmpty && dueUnplanned.isEmpty }
    }

    /// `open`: the open, live tasks of groups that are switched on. `sections`: every live task
    /// of each group (keyed by `groupID`), so subtasks are matched with their real parents even
    /// when a parent is finished; without it, the open tasks alone decide the nesting.
    static func compute(open: [TaskItem], dayStart: Date, sections: [UUID?: [TaskItem]]? = nil) -> Result {
        let leftOver = open.filter { $0.isLeftOver(before: dayStart) }
        let due = open.filter { task in
            guard task.plannedDay == nil, let date = task.dueDate else { return false }
            return DateText.dayDelta(date, today: dayStart) <= 0
        }
        guard !leftOver.isEmpty || !due.isEmpty else { return Result() }

        let leftIDs = Set(leftOver.map(ObjectIdentifier.init))
        let dueIDs = Set(due.map(ObjectIdentifier.init))
        // Lines that sit inside the block of a line in either set: planning that line plans them.
        var insideLeft = Set<ObjectIdentifier>()
        var insideDue = Set<ObjectIdentifier>()
        let openByGroup = Dictionary(grouping: open, by: \.groupID)
        for groupID in Set((leftOver + due).map(\.groupID)) {
            let layout = SectionLayout(sections?[groupID] ?? openByGroup[groupID] ?? [])
            // Ancestors of the current line, each with whether it (or one above it) is in a set.
            var stack: [(depth: Int, left: Bool, due: Bool)] = []
            for (index, item) in layout.items.enumerated() {
                let depth = layout.depths[index]
                while let last = stack.last, last.depth >= depth { stack.removeLast() }
                let id = ObjectIdentifier(item)
                let underLeft = stack.last?.left ?? false
                let underDue = stack.last?.due ?? false
                if underLeft { insideLeft.insert(id) }
                if underDue { insideDue.insert(id) }
                stack.append((depth: depth, left: underLeft || leftIDs.contains(id), due: underDue || dueIDs.contains(id)))
            }
        }

        var result = Result()
        result.leftOver = ranked(leftOver.filter { !insideLeft.contains(ObjectIdentifier($0)) }, dayStart: dayStart)
        result.dueUnplanned = ranked(due.filter { task in
            let id = ObjectIdentifier(task)
            return !insideDue.contains(id) && !insideLeft.contains(id)
        }, dayStart: dayStart)
        return result
    }

    /// Highest score first; equal scores keep their order.
    private static func ranked(_ tasks: [TaskItem], dayStart: Date) -> [TaskItem] {
        tasks.enumerated()
            .map { (task: $0.element, score: $0.element.matrixScore(today: dayStart), order: $0.offset) }
            .sorted { a, b in
                if abs(a.score - b.score) > 1e-9 { return a.score > b.score }
                return a.order < b.order
            }
            .map(\.task)
    }
}
