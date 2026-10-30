import Foundation
import SwiftData
import TheoCore

/// Stored order of one section, with nesting depth derived from `indent` the same way the
/// page renders it. A task's "block" is the task plus every deeper line right below it.
struct SectionLayout {
    let items: [TaskItem]
    let depths: [Int]

    init(_ tasks: [TaskItem]) {
        items = tasks.sorted { $0.sortOrder < $1.sortOrder }
        depths = Checklist.depths(of: items)
    }

    func index(of task: TaskItem) -> Int? {
        items.firstIndex { $0 === task }
    }

    func depth(of task: TaskItem) -> Int {
        index(of: task).map { depths[$0] } ?? 0
    }

    func blockEnd(after index: Int) -> Int {
        Checklist.blockEnd(after: index, depths: depths)
    }

    func block(of task: TaskItem) -> [TaskItem] {
        guard let index = index(of: task) else { return [task] }
        return Array(items[index..<blockEnd(after: index)])
    }
}

/// All mutations go through here so ordering, nesting, timestamps and saving stay consistent.
@MainActor
struct TaskStore {
    let context: ModelContext

    // MARK: - Fetching

    func liveTasks() -> [TaskItem] {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\TaskItem.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func liveGroups() -> [TaskGroup] {
        let descriptor = FetchDescriptor<TaskGroup>(
            predicate: #Predicate<TaskGroup> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\TaskGroup.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func group(id: UUID?) -> TaskGroup? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<TaskGroup>(predicate: #Predicate<TaskGroup> { $0.uuid == id })
        guard let group = (try? context.fetch(descriptor))?.first, group.deletedAt == nil else { return nil }
        return group
    }

    func task(id: UUID) -> TaskItem? {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.uuid == id })
        return (try? context.fetch(descriptor))?.first
    }

    func sectionTasks(_ groupID: UUID?) -> [TaskItem] {
        liveTasks().filter { $0.groupID == groupID }
    }

    func layout(for groupID: UUID?) -> SectionLayout {
        SectionLayout(sectionTasks(groupID))
    }

    // MARK: - Creating

    @discardableResult
    func addTask(_ entry: ParsedEntry, defaultGroupID: UUID?, placement: NewTaskPlacement) -> TaskItem {
        let group = self.group(id: entry.groupID ?? defaultGroupID)
        let siblings = sectionTasks(group?.uuid)
        let order: Double
        switch placement {
        case .bottom: order = (siblings.map(\.sortOrder).max() ?? 0) + 1
        case .top: order = (siblings.map(\.sortOrder).min() ?? 0) - 1
        }
        let task = TaskItem(title: entry.title, sortOrder: order)
        context.insert(task)
        task.group = group
        task.priority = entry.priority
        task.dueDate = entry.due
        task.dueHasTime = entry.dueHasTime
        task.tags = entry.tags
        save()
        return task
    }

    /// An empty line at the top or bottom of a section, ready for inline editing.
    func newBlankTask(in groupID: UUID?, placement: NewTaskPlacement) -> TaskItem {
        addTask(ParsedEntry(title: ""), defaultGroupID: groupID, placement: placement)
    }

    /// Return key inside a task: a new line directly below, at the same level.
    func insertTask(after task: TaskItem, title: String = "") -> TaskItem {
        let siblings = sectionTasks(task.groupID)
        let next = siblings.first { $0.sortOrder > task.sortOrder }
        let order = next.map { (task.sortOrder + $0.sortOrder) / 2 } ?? task.sortOrder + 1
        let new = TaskItem(title: title, sortOrder: order, indent: task.indent)
        context.insert(new)
        new.group = task.group?.deletedAt == nil ? task.group : nil
        normalizeIfNeeded(groupID: task.groupID)
        save()
        return new
    }

    func duplicate(_ task: TaskItem) {
        let copy = insertTask(after: task, title: task.title)
        copy.notes = task.notes
        copy.priorityRaw = task.priorityRaw
        copy.dueDate = task.dueDate
        copy.dueHasTime = task.dueHasTime
        copy.tagsRaw = task.tagsRaw
        save()
    }

    // MARK: - Completing

    func toggle(_ task: TaskItem) {
        setDone([task], !task.isDone)
    }

    func setDone(_ tasks: [TaskItem], _ done: Bool) {
        let now = Date()
        var touched = Set<ObjectIdentifier>()
        func apply(_ task: TaskItem) {
            guard !touched.contains(ObjectIdentifier(task)) else { return }
            touched.insert(ObjectIdentifier(task))
            guard task.isDone != done else { return }
            task.isDone = done
            task.completedAt = done ? now : nil
            if done { task.deferredUntil = nil }
            task.touch()
        }
        for task in tasks {
            apply(task)
            if done {
                // Completing a parent completes its subtasks, like checking off a whole block.
                for child in layout(for: task.groupID).block(of: task).dropFirst() { apply(child) }
            }
        }
        save()
    }

    // MARK: - Deleting

    /// Soft delete (with subtasks). Returns everything that was deleted, for Undo.
    @discardableResult
    func delete(_ tasks: [TaskItem]) -> [TaskItem] {
        let now = Date()
        var deleted: [TaskItem] = []
        var seen = Set<ObjectIdentifier>()
        for task in tasks {
            for item in layout(for: task.groupID).block(of: task) where !seen.contains(ObjectIdentifier(item)) {
                seen.insert(ObjectIdentifier(item))
                item.deletedAt = now
                item.touch()
                deleted.append(item)
            }
        }
        save()
        return deleted
    }

    func restore(_ tasks: [TaskItem]) {
        for task in tasks {
            task.deletedAt = nil
            if let group = task.group, group.deletedAt != nil {
                task.group = nil
            }
            task.touch()
        }
        save()
    }

    func purge(_ tasks: [TaskItem]) {
        for task in tasks { context.delete(task) }
        save()
    }

    func purge(_ groups: [TaskGroup]) {
        for group in groups {
            for task in group.tasks ?? [] where task.deletedAt != nil { context.delete(task) }
            context.delete(group)
        }
        save()
    }

    /// Lines that were created inline but never got any text disappear silently. They are
    /// soft-deleted (safe while a list still references them) and purged on next launch.
    func discardIfEmpty(_ task: TaskItem) {
        guard task.trimmedTitle.isEmpty, task.notes.isEmpty, task.deletedAt == nil else { return }
        task.deletedAt = Date()
        task.touch()
        save()
    }

    /// Hard-deletes items that have been in Recently Deleted for more than 30 days.
    func purgeExpired(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.deletedAt != nil }))) ?? []
        let groups = (try? context.fetch(FetchDescriptor<TaskGroup>(predicate: #Predicate<TaskGroup> { $0.deletedAt != nil }))) ?? []
        var changed = false
        for task in tasks where (task.deletedAt ?? now) < cutoff || task.trimmedTitle.isEmpty {
            context.delete(task)
            changed = true
        }
        for group in groups where (group.deletedAt ?? now) < cutoff {
            context.delete(group)
            changed = true
        }
        if changed { save() }
    }

    // MARK: - Attributes

    func setPriority(_ tasks: [TaskItem], _ priority: Priority) {
        for task in tasks {
            task.priority = priority
            task.touch()
        }
        save()
    }

    func cyclePriority(_ task: TaskItem) {
        let next = Priority(rawValue: (task.priority.rawValue + 1) % 4) ?? .normal
        setPriority([task], next)
    }

    func setDue(_ tasks: [TaskItem], _ date: Date?, hasTime: Bool = false) {
        for task in tasks {
            task.dueDate = date.map { hasTime ? $0 : Calendar.current.startOfDay(for: $0) }
            task.dueHasTime = date == nil ? false : hasTime
            task.touch()
        }
        save()
    }

    /// "Not Today": hide until the next logical day starts.
    func deferTasks(_ tasks: [TaskItem], until dayStart: Date?) {
        for task in tasks {
            task.deferredUntil = dayStart
            task.touch()
        }
        save()
    }

    func setTags(_ task: TaskItem, _ tags: [String]) {
        task.tags = tags
        task.touch()
        save()
    }

    func addTag(_ tasks: [TaskItem], _ tag: String) {
        for task in tasks {
            task.tags = task.tags + [tag]
            task.touch()
        }
        save()
    }

    // MARK: - Moving between groups

    /// Files tasks (with their subtasks) at the bottom of another group.
    func move(_ tasks: [TaskItem], toGroup groupID: UUID?) {
        let target = group(id: groupID)
        var next = (sectionTasks(target?.uuid).map(\.sortOrder).max() ?? 0) + 1
        var seen = Set<ObjectIdentifier>()
        for task in tasks.sorted(by: { $0.sortOrder < $1.sortOrder }) where !seen.contains(ObjectIdentifier(task)) {
            let source = layout(for: task.groupID)
            let rootDepth = source.depth(of: task)
            for item in source.block(of: task) where !seen.contains(ObjectIdentifier(item)) {
                seen.insert(ObjectIdentifier(item))
                item.indent = max(0, source.depth(of: item) - rootDepth)
                item.group = target
                item.sortOrder = next
                item.touch()
                next += 1
            }
        }
        save()
    }

    // MARK: - Reordering (priority by position)

    enum Direction { case up, down }

    /// Swaps a task (with its subtasks) with the neighbouring open sibling.
    func move(_ task: TaskItem, _ direction: Direction) {
        let layout = self.layout(for: task.groupID)
        guard let index = layout.index(of: task) else { return }
        let depth = layout.depths[index]
        let block = Array(layout.items[index..<layout.blockEnd(after: index)])
        let blockIDs = Set(block.map(ObjectIdentifier.init))

        // Sibling candidates: same depth, same parent, not completed.
        func parentIndex(of i: Int) -> Int? {
            var j = i - 1
            while j >= 0 {
                if layout.depths[j] < layout.depths[i] { return j }
                j -= 1
            }
            return nil
        }
        let parent = parentIndex(of: index)
        let siblings = layout.items.indices.filter { i in
            layout.depths[i] == depth && parentIndex(of: i) == parent && !layout.items[i].isDone && !blockIDs.contains(ObjectIdentifier(layout.items[i]))
        }
        let remaining = layout.items.filter { !blockIDs.contains(ObjectIdentifier($0)) }

        switch direction {
        case .up:
            guard let siblingIndex = siblings.last(where: { $0 < index }) else { return }
            let sibling = layout.items[siblingIndex]
            let lower = remaining.last(where: { $0.sortOrder < sibling.sortOrder })?.sortOrder
            assignOrders(block, lower: lower, upper: sibling.sortOrder)
        case .down:
            guard let siblingIndex = siblings.first(where: { $0 > index }) else { return }
            let siblingBlockLast = layout.items[layout.blockEnd(after: siblingIndex) - 1]
            let upper = remaining.first(where: { $0.sortOrder > siblingBlockLast.sortOrder })?.sortOrder
            assignOrders(block, lower: siblingBlockLast.sortOrder, upper: upper)
        }
        normalizeIfNeeded(groupID: task.groupID)
        save()
    }

    func moveToEdge(_ task: TaskItem, top: Bool) {
        let layout = self.layout(for: task.groupID)
        let rootDepth = layout.depth(of: task)
        let block = layout.block(of: task)
        let blockIDs = Set(block.map(ObjectIdentifier.init))
        let remaining = layout.items.filter { !blockIDs.contains(ObjectIdentifier($0)) }
        for item in block {
            item.indent = max(0, layout.depth(of: item) - rootDepth)
        }
        if top {
            assignOrders(block, lower: nil, upper: remaining.first?.sortOrder)
        } else {
            assignOrders(block, lower: remaining.last?.sortOrder, upper: nil)
        }
        save()
    }

    /// Indent (+1) or outdent (-1) a task together with its subtasks.
    func indent(_ task: TaskItem, by delta: Int) {
        let layout = self.layout(for: task.groupID)
        guard let index = layout.index(of: task) else { return }
        let depth = layout.depths[index]
        let block = Array(layout.items[index..<layout.blockEnd(after: index)])
        let blockIDs = Set(block.map(ObjectIdentifier.init))

        if delta > 0 {
            // New parent: the closest earlier open line at the same depth.
            var j = index - 1
            var parent: TaskItem?
            while j >= 0 {
                if layout.depths[j] < depth { break }
                if layout.depths[j] == depth, !layout.items[j].isDone || task.isDone {
                    parent = layout.items[j]
                    break
                }
                j -= 1
            }
            guard let parent, depth < 4 else { return }
            // Re-attach directly below the parent's existing subtasks, so completed lines
            // sitting in between can't capture it.
            let remaining = layout.items.filter { !blockIDs.contains(ObjectIdentifier($0)) }
            let remainingLayout = SectionLayout(remaining)
            let parentBlock = remainingLayout.block(of: parent)
            let anchor = parentBlock.last ?? parent
            let upper = remaining.first(where: { $0.sortOrder > anchor.sortOrder })?.sortOrder
            for item in block {
                item.indent = layout.depth(of: item) + 1
            }
            assignOrders(block, lower: anchor.sortOrder, upper: upper)
        } else {
            guard depth > 0 else { return }
            for item in block {
                item.indent = max(0, layout.depth(of: item) - 1)
                item.touch()
            }
        }
        normalizeIfNeeded(groupID: task.groupID)
        save()
    }

    // MARK: - Groups

    @discardableResult
    func addGroup(name: String, symbol: String = "list.bullet", color: TheoColor = .blue, isProject: Bool = false) -> TaskGroup {
        let order = (liveGroups().map(\.sortOrder).max() ?? 0) + 1
        let group = TaskGroup(name: name, symbol: symbol, color: color, sortOrder: order)
        group.isProject = isProject
        context.insert(group)
        save()
        return group
    }

    func reorderGroups(_ groups: [TaskGroup]) {
        for (index, group) in groups.enumerated() where group.sortOrder != Double(index) {
            group.sortOrder = Double(index)
            group.touch()
        }
        save()
    }

    func deleteGroup(_ group: TaskGroup, keepTasks: Bool) {
        let now = Date()
        if keepTasks {
            move(group.liveTasks, toGroup: nil)
        } else {
            for task in group.liveTasks {
                task.deletedAt = now
                task.touch()
            }
        }
        group.deletedAt = now
        group.touch()
        save()
    }

    func restoreGroup(_ group: TaskGroup) {
        if let deletedAt = group.deletedAt {
            for task in group.tasks ?? [] {
                if let taskDeleted = task.deletedAt, abs(taskDeleted.timeIntervalSince(deletedAt)) < 2 {
                    task.deletedAt = nil
                    task.touch()
                }
            }
        }
        group.deletedAt = nil
        group.touch()
        save()
    }

    func completeAll(in groupID: UUID?) {
        setDone(sectionTasks(groupID).filter { !$0.isDone }, true)
    }

    func setCollapsed(_ group: TaskGroup, _ collapsed: Bool) {
        group.isCollapsed = collapsed
        group.touch()
        save()
    }

    // MARK: - Helpers

    func midpoint(_ lower: Double?, _ upper: Double?) -> Double {
        switch (lower, upper) {
        case let (l?, u?): (l + u) / 2
        case let (l?, nil): l + 1
        case let (nil, u?): u - 1
        case (nil, nil): 0
        }
    }

    /// Spreads a contiguous block evenly between two neighbours.
    func assignOrders(_ block: [TaskItem], lower: Double?, upper: Double?) {
        let n = Double(block.count)
        let lo: Double
        let hi: Double
        switch (lower, upper) {
        case let (l?, u?):
            lo = l
            hi = u
        case let (l?, nil):
            lo = l
            hi = l + n + 1
        case let (nil, u?):
            lo = u - n - 1
            hi = u
        case (nil, nil):
            lo = 0
            hi = n + 1
        }
        for (offset, item) in block.enumerated() {
            item.sortOrder = lo + (hi - lo) * Double(offset + 1) / (n + 1)
            item.touch()
        }
    }

    /// Renumbers a section when repeated midpoint inserts make gaps too small.
    func normalizeIfNeeded(groupID: UUID?) {
        let items = sectionTasks(groupID)
        guard items.count > 1 else { return }
        var needs = false
        for index in 1..<items.count where items[index].sortOrder - items[index - 1].sortOrder < 0.000_001 {
            needs = true
            break
        }
        guard needs else { return }
        for (index, item) in items.enumerated() {
            item.sortOrder = Double(index)
        }
    }

    func save() {
        do {
            try context.save()
        } catch {
            print("Theo: save failed: \(error)")
        }
    }
}
