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
        // Pages without headings drop into the page's own group, or (a list across groups)
        // keep the task in its own group: never into Quick Entry by accident.
        let targetGroupID: UUID?
        if let targetKind {
            targetGroupID = targetKind.groupID
        } else {
            targetGroupID = defaultGroupID ?? task.groupID
        }

        let source = layout(for: task.groupID)
        let block = source.block(of: task)
        let blockIDs = Set(block.map(ObjectIdentifier.init))
        let rootDepth = source.depth(of: task)

        // Neighbours from another group (a list across groups) say nothing about the stored
        // order or nesting in the target group, so they're skipped.
        var previous: (task: TaskItem, depth: Int)?
        var j = newIndex - 1
        while j >= 0 {
            if case .header = rows[j] { break }
            if case .task(let t, let d, _) = rows[j], !blockIDs.contains(ObjectIdentifier(t)), !t.isDone, t.groupID == targetGroupID {
                previous = (t, d)
                break
            }
            j -= 1
        }
        var next: (task: TaskItem, depth: Int)?
        var k = newIndex + 1
        while k < rows.count {
            if case .header = rows[k] { break }
            if case .task(let t, let d, _) = rows[k], !blockIDs.contains(ObjectIdentifier(t)), !t.isDone, t.groupID == targetGroupID {
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

    /// "!!", "#tag", "0,5PH", "∞" (or "laufend", "ongoing", "andauernd") and " // description"
    /// typed into a line take effect once you leave the line, like in the composer. The marks
    /// set a matching importance, so the line ranks the way it looks. Dates and repeats stay as
    /// typed: an inline line has no preview of what would be understood.
    func applyInlineShortcuts(_ task: TaskItem) {
        guard task.deletedAt == nil, Self.mayHaveInlineShortcuts(task.title) else { return }
        let parsed = QuickParser.parse(task.title, groups: [], options: [.priority, .tags, .estimate, .ongoing])
        let found = parsed.priority != .normal || !parsed.tags.isEmpty || parsed.estimate != nil || parsed.ongoing || !parsed.notes.isEmpty
        guard !parsed.title.isEmpty, found else { return }
        task.title = parsed.title
        if parsed.priority != .normal {
            task.importance = Matrix.importance(for: parsed.priority, current: task.importance)
            task.priority = parsed.priority
        }
        if !parsed.tags.isEmpty { task.tags = task.tags + parsed.tags }
        if let estimate = parsed.estimate { task.estimate = estimate }
        if parsed.ongoing { task.isOngoing = true }
        if !parsed.notes.isEmpty { task.notes = task.notes.isEmpty ? parsed.notes : task.notes + "\n" + parsed.notes }
        task.touch()
        save()
    }

    /// A cheap check before parsing: does the title hold anything `applyInlineShortcuts` reads?
    private static func mayHaveInlineShortcuts(_ title: String) -> Bool {
        if title.contains("!") || title.contains("#") || title.contains(" // ") || title.contains("∞") { return true }
        if title.range(of: #"\d\s*ph\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return title.range(of: #"\b(?:laufend|ongoing|andauernd)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
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
        var lastTask: TaskItem?
        // Indents of the lines above that carry their own estimate: their subtasks without one
        // get none, so the parent's total counts (instead of 0,25 PH defaults on each line).
        var estimatedAbove: [Int] = []
        for line in lines {
            if line.isNote {
                if let lastTask {
                    lastTask.notes = lastTask.notes.isEmpty ? line.title : lastTask.notes + "\n" + line.title
                } else if let currentGroup {
                    currentGroup.notes = currentGroup.notes.isEmpty ? line.title : currentGroup.notes + "\n" + line.title
                }
                continue
            }
            if line.isHeading {
                lastTask = nil
                estimatedAbove = []
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
            let parsed = QuickParser.parse(line.title, groups: [], options: [.priority, .tags, .estimate, .exactDates, .ongoing])
            let task = TaskItem(title: parsed.title, sortOrder: nextOrder(currentGroup?.uuid), indent: line.indent)
            context.insert(task)
            task.group = currentGroup
            task.priority = parsed.priority
            task.tags = parsed.tags
            estimatedAbove.removeAll { $0 >= line.indent }
            let underEstimate = !estimatedAbove.isEmpty
            task.estimate = parsed.estimate ?? (line.done || underEstimate ? 0 : PowerHours.defaultForNewTasks)
            if parsed.estimate != nil { estimatedAbove.append(line.indent) }
            if parsed.ongoing { task.isOngoing = true }
            if !parsed.notes.isEmpty { task.notes = parsed.notes }
            lastTask = task
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
