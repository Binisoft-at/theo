import Foundation
import SwiftData
import TheoCore

/// iPhone / iPad / Mac only: drag-and-drop on the flat page list and importing from Notes.
extension TaskStore {
    /// Applies a drag-and-drop from the flat page list. `rows` is the list *after* the move.
    func drop(task: TaskItem, at newIndex: Int, in rows: [ListRow], defaultGroupID: UUID? = nil) {
        var targetKind: SectionKind?
        var i = newIndex - 1
        while i >= 0 {
            if case .header(let info) = rows[i] {
                targetKind = info.kind
                break
            }
            i -= 1
        }
        if let targetKind, !targetKind.acceptsTasks { return }
        // Pages without headings (a single group page) drop into the page's own group.
        let targetGroupID = targetKind.map { $0.groupID } ?? defaultGroupID

        let source = layout(for: task.groupID)
        let block = source.block(of: task)
        let blockIDs = Set(block.map(ObjectIdentifier.init))
        let rootDepth = source.depth(of: task)

        var previous: (task: TaskItem, depth: Int)?
        var j = newIndex - 1
        while j >= 0 {
            if case .header = rows[j] { break }
            if case .task(let t, let d, _) = rows[j], !blockIDs.contains(ObjectIdentifier(t)), !t.isDone {
                previous = (t, d)
                break
            }
            j -= 1
        }
        var next: (task: TaskItem, depth: Int)?
        var k = newIndex + 1
        while k < rows.count {
            if case .header = rows[k] { break }
            if case .task(let t, let d, _) = rows[k], !blockIDs.contains(ObjectIdentifier(t)), !t.isDone {
                next = (t, d)
                break
            }
            k += 1
        }

        let targetTasks = sectionTasks(targetGroupID).filter { !blockIDs.contains(ObjectIdentifier($0)) }
        var lower: Double?
        var upper: Double?
        if let previous {
            lower = previous.task.sortOrder
            upper = targetTasks.first(where: { $0.sortOrder > previous.task.sortOrder })?.sortOrder
        } else if let next {
            upper = next.task.sortOrder
            lower = targetTasks.last(where: { $0.sortOrder < next.task.sortOrder })?.sortOrder
        } else {
            lower = targetTasks.last?.sortOrder
        }

        // Adopt the indentation of the line below (bounded by the line above).
        var newRootDepth = 0
        if let next {
            newRootDepth = min(next.depth, (previous?.depth ?? -1) + 1)
        }
        _ = rootDepth
        let target = group(id: targetGroupID)
        for item in block {
            item.indent = max(0, source.depth(of: item) - rootDepth + newRootDepth)
            let changed = item.groupID != target?.uuid
            item.group = target
            if changed { applyTraits(to: item, propose: true) }
        }
        assignOrders(block, lower: lower, upper: upper)
        normalizeIfNeeded(groupID: targetGroupID)
        save()
    }

    /// Applies a heading drag from the flat page list. `rows` is the list *after* the move.
    func drop(group: TaskGroup, at newIndex: Int, in rows: [ListRow]) {
        var previous: TaskGroup?
        var i = newIndex - 1
        while i >= 0 {
            if case .header(let info) = rows[i] {
                if case .group(let g) = info.kind, g !== group { previous = g }
                break
            }
            i -= 1
        }
        var next: TaskGroup?
        var k = newIndex + 1
        while k < rows.count {
            if case .header(let info) = rows[k], case .group(let g) = info.kind, g !== group {
                next = g
                break
            }
            k += 1
        }
        let others = liveGroups().filter { $0 !== group }
        let lower = previous?.sortOrder
        let upper = next?.sortOrder ?? (previous == nil ? others.first?.sortOrder : nil)
        group.sortOrder = midpoint(lower, upper)
        group.touch()
        save()
    }

    // MARK: - Inline shortcuts

    /// "!!" and "#tag" typed into a line become its priority and tags once you leave the line.
    func applyInlineShortcuts(_ task: TaskItem) {
        guard task.deletedAt == nil, task.title.contains("!") || task.title.contains("#") else { return }
        let parsed = QuickParser.parse(task.title, groups: [], options: [.priority, .tags])
        guard !parsed.title.isEmpty, parsed.priority != .normal || !parsed.tags.isEmpty else { return }
        task.title = parsed.title
        if parsed.priority != .normal { task.priority = parsed.priority }
        if !parsed.tags.isEmpty { task.tags = task.tags + parsed.tags }
        task.touch()
        save()
    }

    // MARK: - Import

    /// Creates groups and tasks from pasted Apple Notes / Markdown checklist text. `#` headings
    /// are groups, `##` headings subprojects inside the group above, and so on. Estimates
    /// ("(0,25PH)"), exact deadlines ("📅 2026-11-04"), priorities and tags are picked up.
    @discardableResult
    func importLines(_ lines: [NotesImport.Line], skipDone: Bool) -> Int {
        func lookupKey(_ parent: UUID?, _ name: String) -> String {
            (parent?.uuidString ?? "-") + "/" + name.lowercased()
        }
        var groupsByKey: [String: TaskGroup] = [:]
        for group in liveGroups() { groupsByKey[lookupKey(group.parentUUID, group.displayName)] = group }
        var headings: [TaskGroup] = []
        var skippedBelow: Int?
        var currentGroup: TaskGroup?
        var orders: [UUID?: Double] = [:]
        func nextOrder(_ id: UUID?) -> Double {
            if let value = orders[id] {
                orders[id] = value + 1
                return value + 1
            }
            let start = (sectionTasks(id).map(\.sortOrder).max() ?? 0) + 1
            orders[id] = start
            return start
        }
        var created = 0
        for line in lines {
            if line.isHeading {
                skippedBelow = nil
                let name = line.title.lowercased()
                if line.level <= 1 && (name == "quick entry" || name == "quick" || name == "inbox") {
                    currentGroup = nil
                    headings = []
                    continue
                }
                let level = max(1, min(line.level, headings.count + 1))
                let parent = level > 1 ? headings[level - 2] : nil
                let group: TaskGroup
                if let existing = groupsByKey[lookupKey(parent?.uuid, line.title)] {
                    group = existing
                } else {
                    group = addGroup(name: line.title, symbol: "list.bullet", color: TheoColor.forTag(name), parent: parent?.uuid)
                    groupsByKey[lookupKey(parent?.uuid, line.title)] = group
                }
                headings = Array(headings.prefix(level - 1)) + [group]
                currentGroup = group
                continue
            }
            // A finished line takes its subtasks with it.
            if let skippedBelow, line.indent > skippedBelow { continue }
            skippedBelow = nil
            if skipDone && line.done {
                skippedBelow = line.indent
                continue
            }
            let parsed = QuickParser.parse(line.title, groups: [], options: [.priority, .tags, .estimate, .exactDates])
            let task = TaskItem(title: parsed.title, sortOrder: nextOrder(currentGroup?.uuid), indent: line.indent)
            context.insert(task)
            task.group = currentGroup
            task.priority = parsed.priority
            task.tags = parsed.tags
            task.estimate = parsed.estimate ?? (line.done ? 0 : PowerHours.defaultForNewTasks)
            task.importance = Matrix.importance(for: parsed.priority, current: Matrix.defaultImportance)
            task.dueDate = parsed.due
            if !line.done { applyTraits(to: task, values: Self.typedValues(parsed, task), propose: false) }
            if line.done {
                task.isDone = true
                task.completedAt = Date()
            }
            created += 1
        }
        save()
        return created
    }
}
