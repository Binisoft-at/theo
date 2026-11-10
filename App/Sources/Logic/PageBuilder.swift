import SwiftUI
import TheoCore

/// What a section header represents.
enum SectionKind {
    case quickEntry
    case group(TaskGroup)
    case label(key: String, title: String, symbol: String, color: Color)

    /// Group the section files new tasks into (nil = Quick Entry).
    var groupID: UUID? {
        if case .group(let group) = self { return group.uuid }
        return nil
    }

    var acceptsTasks: Bool {
        switch self {
        case .quickEntry, .group: true
        case .label: false
        }
    }
}

struct SectionHeaderInfo: Identifiable {
    let id: String
    let kind: SectionKind
    let openCount: Int
    let doneCount: Int
    let isCollapsed: Bool
    let collapsible: Bool
    /// Power Hours still open in the section.
    var openEstimate: Double = 0
    /// Subproject depth (0 = top-level group).
    var level: Int = 0
}

/// Per-row presentation flags.
struct RowStyle {
    var showGroup = false
    var showDeferred = false
    /// Subtasks below this line (all levels), and how many of them are done.
    var subtaskCount = 0
    var subtasksDone = 0
    /// The subtasks are folded away.
    var subtasksFolded = false
}

/// The flat row model behind every task list. Headers are rows too, exactly like headings
/// inside a note, which makes drag-and-drop across groups natural.
enum ListRow: Identifiable {
    case header(SectionHeaderInfo)
    case task(TaskItem, depth: Int, style: RowStyle)
    case placeholder(id: String, text: String)

    var id: String {
        switch self {
        case .header(let info): "h-" + info.id
        case .task(let task, _, _): task.rowID
        case .placeholder(let id, _): "p-" + id
        }
    }

    var task: TaskItem? {
        if case .task(let task, _, _) = self { return task }
        return nil
    }
}

enum PageBuilder {
    struct Options {
        var completed: CompletedMode = .bottom
        var style = RowStyle()
        var showEmptyPlaceholders = true
        /// Parents whose subtasks are folded away.
        var collapsedTasks: Set<UUID> = []
        /// Ranks open lines by importance and urgency as of this day (nil = manual order).
        var rankDay: Date?
    }

    /// One section's task rows: nested, completed lines at the bottom of their level, parents
    /// carrying their subtask counts, and the subtasks of folded parents left out.
    static func taskRows(_ tasks: [TaskItem], options: Options) -> [ListRow] {
        let rank: ((TaskItem) -> Double)? = options.rankDay.map { day in { $0.matrixScore(today: day) } }
        let all = Checklist.displayOrder(tasks, showCompleted: true, rank: rank)
        let depths = all.map(\.depth)
        var rows: [ListRow] = []
        var index = 0
        while index < all.count {
            let task = all[index].item
            let end = Checklist.blockEnd(after: index, depths: depths)
            if task.isDone && options.completed == .hide {
                index = end
                continue
            }
            let children = all[(index + 1)..<end].map(\.item)
            var style = options.style
            style.subtaskCount = children.count
            style.subtasksDone = children.filter(\.isDone).count
            style.subtasksFolded = !children.isEmpty && options.collapsedTasks.contains(task.uuid)
            rows.append(.task(task, depth: all[index].depth, style: style))
            index = style.subtasksFolded ? end : index + 1
        }
        return rows
    }

    /// One ranked list across groups (Today's default): each group is ordered on its own so
    /// subtasks stay with their parents, then the top-level blocks are merged by score, open
    /// ones first.
    static func rankedRows(_ tasks: [TaskItem], options: Options) -> [ListRow] {
        let day = options.rankDay ?? Date()
        // Equal scores keep a fixed order (group order, then manual order), so the list never
        // reshuffles when something is added.
        var blocks: [(score: Double, done: Bool, groupOrder: Double, order: Double, rows: [ListRow])] = []
        func append(_ head: TaskItem, _ rows: [ListRow]) {
            let groupOrder = head.group.map { $0.deletedAt == nil ? $0.sortOrder : -.infinity } ?? -.infinity
            blocks.append((head.matrixScore(today: day), head.isDone, groupOrder, head.sortOrder, rows))
        }
        for section in Dictionary(grouping: tasks, by: \.groupID).values {
            var current: [ListRow] = []
            var head: TaskItem?
            for row in taskRows(section, options: options) {
                guard case .task(let task, let depth, _) = row else { continue }
                if depth == 0 {
                    if let head { append(head, current) }
                    head = task
                    current = []
                }
                current.append(row)
            }
            if let head { append(head, current) }
        }
        blocks.sort { a, b in
            if a.done != b.done { return !a.done }
            if abs(a.score - b.score) > 1e-9 { return a.score > b.score }
            if a.groupOrder != b.groupOrder { return a.groupOrder < b.groupOrder }
            return a.order < b.order
        }
        return blocks.flatMap(\.rows)
    }

    /// A Notes-style page: Quick Entry on top, then every group heading with its tasks.
    static func page(
        tasks: [TaskItem],
        groups: [TaskGroup],
        includeQuickEntry: Bool = true,
        quickEntryCollapsed: Bool,
        options: Options
    ) -> [ListRow] {
        var byGroup: [UUID: [TaskItem]] = [:]
        var quick: [TaskItem] = []
        let liveGroupIDs = Set(groups.map(\.uuid))
        for task in tasks {
            if let id = task.groupID, liveGroupIDs.contains(id) {
                byGroup[id, default: []].append(task)
            } else {
                quick.append(task)
            }
        }

        var rows: [ListRow] = []
        if includeQuickEntry {
            appendSection(
                into: &rows,
                id: "quick",
                kind: .quickEntry,
                tasks: quick,
                collapsed: quickEntryCollapsed,
                options: options,
                placeholder: "Dump anything here. Sort it later."
            )
        }
        // Subprojects follow their parent and fold away with it.
        var foldedBelow: Int?
        for (group, level) in GroupTree.ordered(groups) {
            if let foldedBelow, level > foldedBelow { continue }
            foldedBelow = group.isCollapsed ? level : nil
            appendSection(
                into: &rows,
                id: group.uuid.uuidString,
                kind: .group(group),
                tasks: byGroup[group.uuid] ?? [],
                collapsed: group.isCollapsed,
                options: options,
                placeholder: nil,
                level: level
            )
        }
        return rows
    }

    /// Sections that are computed (priority, deadline, tag ...). Not collapsible, not reorderable.
    static func labeled(_ sections: [(key: String, title: String, symbol: String, color: Color, tasks: [TaskItem])], options: Options) -> [ListRow] {
        var rows: [ListRow] = []
        for section in sections where !section.tasks.isEmpty {
            let open = section.tasks.filter { !$0.isDone }.count
            rows.append(.header(SectionHeaderInfo(
                id: section.key,
                kind: .label(key: section.key, title: section.title, symbol: section.symbol, color: section.color),
                openCount: open,
                doneCount: section.tasks.count - open,
                isCollapsed: false,
                collapsible: false
            )))
            var open1 = section.tasks.filter { !$0.isDone }
            if let day = options.rankDay {
                open1 = open1.enumerated()
                    .sorted { ($0.element.matrixScore(today: day), -$0.offset) > ($1.element.matrixScore(today: day), -$1.offset) }
                    .map(\.element)
            }
            let done1 = section.tasks.filter(\.isDone)
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            for task in open1 { rows.append(.task(task, depth: 0, style: options.style)) }
            if options.completed == .bottom {
                for task in done1 { rows.append(.task(task, depth: 0, style: options.style)) }
            }
        }
        return rows
    }

    /// Sections whose tasks keep their subtasks, each ranked on its own (Today by top group).
    static func rankedSections(_ sections: [(key: String, title: String, symbol: String, color: Color, tasks: [TaskItem])], options: Options) -> [ListRow] {
        var rows: [ListRow] = []
        for section in sections where !section.tasks.isEmpty {
            let open = section.tasks.filter { !$0.isDone }.count
            rows.append(.header(SectionHeaderInfo(
                id: section.key,
                kind: .label(key: section.key, title: section.title, symbol: section.symbol, color: section.color),
                openCount: open,
                doneCount: section.tasks.count - open,
                isCollapsed: false,
                collapsible: false,
                openEstimate: PowerHours.total(section.tasks, where: { !$0.isDone })
            )))
            rows += rankedRows(section.tasks, options: options)
        }
        return rows
    }

    private static func appendSection(
        into rows: inout [ListRow],
        id: String,
        kind: SectionKind,
        tasks: [TaskItem],
        collapsed: Bool,
        options: Options,
        placeholder: String?,
        level: Int = 0
    ) {
        let open = tasks.filter { !$0.isDone }.count
        rows.append(.header(SectionHeaderInfo(
            id: id,
            kind: kind,
            openCount: open,
            doneCount: tasks.count - open,
            isCollapsed: collapsed,
            collapsible: true,
            openEstimate: PowerHours.total(tasks, where: { !$0.isDone }),
            level: level
        )))
        guard !collapsed else { return }
        let lines = taskRows(tasks, options: options)
        if lines.isEmpty, options.showEmptyPlaceholders, let placeholder {
            rows.append(.placeholder(id: id, text: placeholder))
        }
        rows += lines
    }

    /// A group's own page: its tasks, then each subproject under its own heading.
    static func groupPage(groupID: UUID?, tasks: [TaskItem], groups: [TaskGroup], options: Options) -> [ListRow] {
        var rows = taskRows(tasks.filter { $0.groupID == groupID }, options: options)
        guard let groupID else { return rows }
        let inside = Set(GroupTree.descendants(of: groupID, in: groups).map(\.uuid))
        let ordered = GroupTree.ordered(groups).filter { inside.contains($0.group.uuid) }
        let base = ordered.map(\.level).min() ?? 0
        var foldedBelow: Int?
        for (group, level) in ordered {
            if let foldedBelow, level > foldedBelow { continue }
            foldedBelow = group.isCollapsed ? level : nil
            appendSection(
                into: &rows,
                id: group.uuid.uuidString,
                kind: .group(group),
                tasks: tasks.filter { $0.groupID == group.uuid },
                collapsed: group.isCollapsed,
                options: options,
                placeholder: nil,
                level: level - base
            )
        }
        return rows
    }

    /// Planned and finished Power Hours of a set of tasks, totalled per group so nesting is
    /// read correctly.
    static func estimateTotals(_ tasks: [TaskItem]) -> (open: Double, done: Double) {
        var open = 0.0
        var done = 0.0
        for section in Dictionary(grouping: tasks, by: \.groupID).values {
            open += PowerHours.total(section, where: { !$0.isDone })
            done += PowerHours.total(section, where: \.isDone)
        }
        return (open, done)
    }

    // MARK: - Filters

    /// A task belongs on the logical day page starting at `dayStart` if it is still open
    /// (and not deferred past that day) or if it was completed during that day.
    static func isOnToday(_ task: TaskItem, dayStart: Date) -> Bool {
        task.isOnPage(of: dayStart)
    }

    static func matches(_ task: TaskItem, search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        if query.hasPrefix("#") {
            let tag = Tags.clean(query)
            return task.tags.contains { $0.hasPrefix(tag) }
        }
        return task.title.lowercased().contains(query)
            || task.notes.lowercased().contains(query)
            || task.tagsRaw.contains(query)
            || (task.group?.name.lowercased().contains(query) ?? false)
    }
}
