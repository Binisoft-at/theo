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
    }

    /// One section's task rows: nested, completed lines at the bottom of their level, parents
    /// carrying their subtask counts, and the subtasks of folded parents left out.
    static func taskRows(_ tasks: [TaskItem], options: Options) -> [ListRow] {
        let all = Checklist.displayOrder(tasks, showCompleted: true)
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
        for group in groups {
            appendSection(
                into: &rows,
                id: group.uuid.uuidString,
                kind: .group(group),
                tasks: byGroup[group.uuid] ?? [],
                collapsed: group.isCollapsed,
                options: options,
                placeholder: nil
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
            let open1 = section.tasks.filter { !$0.isDone }
            let done1 = section.tasks.filter(\.isDone)
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            for task in open1 { rows.append(.task(task, depth: 0, style: options.style)) }
            if options.completed == .bottom {
                for task in done1 { rows.append(.task(task, depth: 0, style: options.style)) }
            }
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
        placeholder: String?
    ) {
        let open = tasks.filter { !$0.isDone }.count
        rows.append(.header(SectionHeaderInfo(
            id: id,
            kind: kind,
            openCount: open,
            doneCount: tasks.count - open,
            isCollapsed: collapsed,
            collapsible: true
        )))
        guard !collapsed else { return }
        let lines = taskRows(tasks, options: options)
        if lines.isEmpty, options.showEmptyPlaceholders, let placeholder {
            rows.append(.placeholder(id: id, text: placeholder))
        }
        rows += lines
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
