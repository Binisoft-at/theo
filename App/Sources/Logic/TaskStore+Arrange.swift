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
            item.group = target
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

    /// Creates groups and tasks from pasted Apple Notes / Markdown checklist text.
    @discardableResult
    func importLines(_ lines: [NotesImport.Line], skipDone: Bool) -> Int {
        var groupsByName: [String: TaskGroup] = [:]
        for group in liveGroups() { groupsByName[group.displayName.lowercased()] = group }
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
                let key = line.title.lowercased()
                if key == "quick entry" || key == "quick" || key == "inbox" {
                    currentGroup = nil
                } else if let existing = groupsByName[key] {
                    currentGroup = existing
                } else {
                    let group = addGroup(name: line.title, symbol: "list.bullet", color: TheoColor.forTag(key))
                    groupsByName[key] = group
                    currentGroup = group
                }
                continue
            }
            if skipDone && line.done { continue }
            let parsed = QuickParser.parse(line.title, groups: [], options: [.priority, .tags])
            let task = TaskItem(title: parsed.title, sortOrder: nextOrder(currentGroup?.uuid), indent: line.indent)
            context.insert(task)
            task.group = currentGroup
            task.priority = parsed.priority
            task.tags = parsed.tags
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
