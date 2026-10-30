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
    }

    /// Orders one section like a checklist: manual order, nested by indent, with completed
    /// items sinking to the bottom of their level (most recently completed first).
    static func ordered(_ tasks: [TaskItem], completed: CompletedMode) -> [(task: TaskItem, depth: Int)] {
        Checklist.displayOrder(tasks, showCompleted: completed == .bottom).map { (task: $0.item, depth: $0.depth) }
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
        let ordered = ordered(tasks, completed: options.completed)
        if ordered.isEmpty, options.showEmptyPlaceholders, let placeholder {
            rows.append(.placeholder(id: id, text: placeholder))
        }
        for item in ordered {
            rows.append(.task(item.task, depth: item.depth, style: options.style))
        }
    }

    // MARK: - Filters

    /// A task belongs on the logical day page starting at `dayStart` if it is still open
    /// (and not deferred past that day) or if it was completed during that day.
    static func isOnToday(_ task: TaskItem, dayStart: Date) -> Bool {
        guard task.deletedAt == nil else { return false }
        if task.isDone {
            guard let completed = task.completedAt else { return false }
            return completed >= dayStart
        }
        if let deferred = task.deferredUntil, deferred > dayStart { return false }
        return true
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
