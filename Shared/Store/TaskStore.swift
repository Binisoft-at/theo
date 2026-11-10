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
        task.estimate = entry.estimate ?? PowerHours.defaultForNewTasks
        task.recurrence = entry.recurrence
        task.importance = Matrix.importance(for: entry.priority, current: Matrix.defaultImportance)
        applyTraits(to: task, values: Self.typedValues(entry, task), propose: false)
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
        new.importance = Matrix.defaultImportance
        new.estimate = PowerHours.defaultForNewTasks
        new.plannedDay = task.plannedDay
        applyTraits(to: new, propose: false)
        normalizeIfNeeded(groupID: task.groupID)
        save()
        return new
    }

    /// A new line after `task` and its subtasks, at the same level (inserting between lines).
    func insertSibling(after task: TaskItem, title: String = "") -> TaskItem {
        let layout = self.layout(for: task.groupID)
        guard let index = layout.index(of: task) else { return insertTask(after: task, title: title) }
        let end = layout.blockEnd(after: index)
        let upper = end < layout.items.count ? layout.items[end].sortOrder : nil
        let new = TaskItem(title: title, sortOrder: midpoint(layout.items[end - 1].sortOrder, upper), indent: layout.depths[index])
        context.insert(new)
        new.group = task.group?.deletedAt == nil ? task.group : nil
        new.importance = Matrix.defaultImportance
        new.estimate = PowerHours.defaultForNewTasks
        new.plannedDay = task.plannedDay
        applyTraits(to: new, propose: false)
        normalizeIfNeeded(groupID: task.groupID)
        save()
        return new
    }

    /// A new subtask of `parent`: the last one, right after its existing subtasks, or with
    /// `first` the first one, right under the parent. Adding work under a finished task reopens it.
    @discardableResult
    func addSubtask(_ entry: ParsedEntry, to parent: TaskItem, first: Bool = false) -> TaskItem {
        let layout = self.layout(for: parent.groupID)
        guard let index = layout.index(of: parent) else {
            return addTask(entry, defaultGroupID: parent.groupID, placement: .bottom)
        }
        let order: Double
        if first {
            let next = index + 1 < layout.items.count ? layout.items[index + 1].sortOrder : nil
            order = midpoint(parent.sortOrder, next)
        } else {
            let end = layout.blockEnd(after: index)
            let upper = end < layout.items.count ? layout.items[end].sortOrder : nil
            order = midpoint(layout.items[end - 1].sortOrder, upper)
        }
        let task = TaskItem(title: entry.title, sortOrder: order, indent: layout.depths[index] + 1)
        context.insert(task)
        task.group = parent.group?.deletedAt == nil ? parent.group : nil
        task.priority = entry.priority
        task.dueDate = entry.due
        task.dueHasTime = entry.dueHasTime
        task.tags = entry.tags
        task.estimate = entry.estimate ?? PowerHours.defaultForNewTasks
        task.recurrence = entry.recurrence
        task.importance = Matrix.importance(for: entry.priority, current: Matrix.defaultImportance)
        task.plannedDay = parent.plannedDay
        applyTraits(to: task, values: Self.typedValues(entry, task), propose: false)
        if parent.isDone {
            parent.isDone = false
            parent.completedAt = nil
            parent.touch()
        }
        normalizeIfNeeded(groupID: parent.groupID)
        save()
        return task
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
            let wasDone = task.isDone
            apply(task)
            if done {
                // Completing a parent completes its subtasks, like checking off a whole block.
                for child in layout(for: task.groupID).block(of: task).dropFirst() { apply(child) }
                if !wasDone { scheduleNextOccurrence(of: task, now: now) }
            }
        }
        save()
    }

    /// Completing a repeating task files its next occurrence right where it was, hidden until
    /// that day. The finished one stays in History without the repeat, so reopening it doesn't
    /// create a second copy.
    private func scheduleNextOccurrence(of task: TaskItem, now: Date) {
        guard let recurrence = task.recurrence, let due = task.dueDate else { return }
        var next = recurrence.next(after: due)
        let today = Calendar.current.startOfDay(for: now)
        var steps = 0
        while next < today && steps < 1000 {
            next = recurrence.next(after: next)
            steps += 1
        }
        let copy = insertTask(after: task, title: task.title)
        copy.notes = task.notes
        copy.priorityRaw = task.priorityRaw
        copy.tagsRaw = task.tagsRaw
        copy.estimate = task.estimate
        copy.urgency = task.urgency
        copy.importance = task.importance
        copy.recurrenceRaw = task.recurrenceRaw
        copy.remindersRaw = task.remindersRaw
        copy.dueDate = next
        copy.dueHasTime = task.dueHasTime
        // A repeat is planned for its day on its own.
        copy.plannedDay = Calendar.current.startOfDay(for: next)
        task.recurrenceRaw = ""
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

    /// The marks and importance move together: a mark sets a matching importance level.
    func setPriority(_ tasks: [TaskItem], _ priority: Priority) {
        for task in tasks {
            task.importance = Matrix.importance(for: priority, current: task.importance)
            task.priority = priority
            task.touch()
        }
        save()
    }

    /// Importance (0.1...1); the priority marks follow it.
    func setImportance(_ tasks: [TaskItem], _ importance: Double) {
        for task in tasks {
            task.importance = min(1, max(0.1, importance))
            task.priority = Matrix.priority(forImportance: task.importance)
            task.touch()
        }
        save()
    }

    /// Moves the deadline to `days` from today, keeping its time of day; nil clears it (a
    /// deadline beyond the matrix's two weeks stays).
    func setDueDay(_ task: TaskItem, days: Int?, today: Date) {
        let calendar = Calendar.current
        guard let days else {
            if let due = task.dueDate, (Matrix.daysUntil(due, today: today) ?? 0) <= Matrix.horizonDays {
                task.dueDate = nil
                task.dueHasTime = false
            }
            return
        }
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: today)) ?? today
        if task.dueHasTime, let due = task.dueDate {
            let time = calendar.dateComponents([.hour, .minute], from: due)
            task.dueDate = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day)
        } else {
            task.dueDate = day
            task.dueHasTime = false
        }
    }

    /// Where it was dropped on the matrix: deadline in days (nil = no date) and importance level.
    func placeOnMatrix(_ task: TaskItem, days: Int?, level: Int, today: Date) {
        setDueDay(task, days: days, today: today)
        task.importance = Matrix.importance(forLevel: level)
        task.priority = Matrix.priority(forImportance: task.importance)
        task.touch()
        save()
    }

    /// Takes over a ranking position (importance plus urgency, as from `Matrix.between`).
    func applyRank(_ task: TaskItem, importance: Double, urgency: Double, today: Date) {
        if task.dueDate == nil || urgency > 0 { setDueDay(task, days: Matrix.days(forUrgency: urgency), today: today) }
        task.importance = min(1, max(0.1, importance))
        task.priority = Matrix.priority(forImportance: task.importance)
        task.touch()
        save()
    }

    /// After dragging a task between two others: only its importance changes, just enough to
    /// rank between them. Its deadline stays.
    func rank(_ task: TaskItem, between above: TaskItem?, and below: TaskItem?, today: Date) {
        let scoreAbove = above?.matrixScore(today: today)
        let scoreBelow = below?.matrixScore(today: today)
        let target: Double
        switch (scoreAbove, scoreBelow) {
        case let (a?, b?): target = (a + b) / 2
        case let (a?, nil): target = a - 0.03
        case let (nil, b?): target = b + 0.03
        case (nil, nil): return
        }
        setImportance([task], Matrix.importance(toReach: target, urgency: task.matrixPosition(today: today).urgency))
    }

    /// Moves deadlines `days` after today (keeping the time), e.g. to push something overdue.
    func postpone(_ tasks: [TaskItem], days: Int, today: Date) {
        for task in tasks {
            setDueDay(task, days: days, today: today)
            task.touch()
        }
        save()
    }

    /// Plans tasks (with their subtasks) for a day; nil takes them off any plan.
    func plan(_ tasks: [TaskItem], for day: Date?) {
        let key = day.map { Calendar.current.startOfDay(for: $0) }
        var seen = Set<ObjectIdentifier>()
        for task in tasks {
            for item in layout(for: task.groupID).block(of: task) where !seen.contains(ObjectIdentifier(item)) {
                seen.insert(ObjectIdentifier(item))
                guard item.plannedDay != key else { continue }
                item.plannedDay = key
                item.touch()
            }
        }
        save()
    }

    /// One-time: open tasks from before the default Power Hours get it too (finished ones keep
    /// what they had, so past days don't change).
    func applyDefaultEstimateOnce() {
        let key = "defaultEstimateApplied"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let value = PowerHours.defaultForNewTasks
        if value > 0 {
            for task in liveTasks() where !task.isDone && task.estimate <= 0 {
                task.estimate = value
            }
            save()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// One-time: older tasks only had priority marks; give them a matching importance.
    func syncImportanceWithPriority() {
        let key = "importanceFromPriority"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for task in liveTasks() where task.priority != .normal && Matrix.priority(forImportance: task.importance) != task.priority {
            task.importance = Matrix.importance(for: task.priority, current: task.importance)
        }
        save()
        UserDefaults.standard.set(true, forKey: key)
    }

    func setEstimate(_ tasks: [TaskItem], _ powerHours: Double) {
        for task in tasks {
            task.estimate = max(0, powerHours)
            task.touch()
        }
        save()
    }

    func setRecurrence(_ tasks: [TaskItem], _ recurrence: Recurrence?) {
        for task in tasks {
            task.recurrence = recurrence
            task.touch()
        }
        save()
    }

    func setReminders(_ task: TaskItem, _ offsets: [Int]) {
        task.reminderOffsets = offsets
        task.touch()
        save()
    }

    func addFocusTime(_ task: TaskItem, seconds: Double) {
        guard seconds > 0 else { return }
        task.focusSeconds += seconds
        task.touch()
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

    // MARK: - Group traits

    /// A group's traits, with what it inherits from the groups it sits in.
    func traits(of group: TaskGroup?) -> GroupTraits {
        guard let group else { return GroupTraits() }
        var result = group.ownTraits
        var seen: Set<UUID> = [group.uuid]
        var current = group
        while let parentID = current.parentUUID, !seen.contains(parentID), let parent = self.group(id: parentID) {
            result = result.inheriting(from: parent.ownTraits)
            seen.insert(parentID)
            current = parent
        }
        return result
    }

    /// What a task has of its own (a default importance or estimate counts as nothing).
    func traitValues(of task: TaskItem, today: Date) -> GroupTraits.TaskValues {
        GroupTraits.TaskValues(
            importance: abs(task.importance - Matrix.defaultImportance) < 0.001 ? nil : task.importance,
            estimate: task.estimate <= 0 || abs(task.estimate - PowerHours.defaultForNewTasks) < 0.001 ? nil : task.estimate,
            tags: task.tags,
            hasDeadline: task.dueDate != nil,
            dueDays: Matrix.daysUntil(task.dueDate, today: today)
        )
    }

    /// What was typed for a new task (anything not typed is open for the group's traits).
    static func typedValues(_ entry: ParsedEntry, _ task: TaskItem) -> GroupTraits.TaskValues {
        GroupTraits.TaskValues(
            importance: entry.priority != .normal ? task.importance : nil,
            estimate: entry.estimate,
            tags: task.tags,
            hasDeadline: entry.due != nil,
            dueDays: nil
        )
    }

    /// Gives a task its group's traits where it has nothing of its own. With `propose`, traits
    /// that differ from its own values become a proposal it shows; nothing is overwritten.
    func applyTraits(to task: TaskItem, values: GroupTraits.TaskValues? = nil, propose: Bool) {
        let today = DayBoundary.current.start(of: Date())
        let traits = self.traits(of: task.group)
        guard !traits.isEmpty else {
            task.traitProposalGroupID = nil
            return
        }
        let plan = traits.plan(for: values ?? traitValues(of: task, today: today))
        apply(plan.apply, to: task, today: today)
        if propose {
            task.traitProposalGroupID = plan.propose.isEmpty ? nil : task.groupID
        }
    }

    private func apply(_ traits: GroupTraits, to task: TaskItem, today: Date) {
        if let importance = traits.importance {
            task.importance = min(1, max(0.1, importance))
            task.priority = Matrix.priority(forImportance: task.importance)
        }
        if let estimate = traits.estimate { task.estimate = max(0, estimate) }
        if !traits.tags.isEmpty {
            var tags = task.tags
            for tag in traits.tags where !tags.contains(tag) { tags.append(tag) }
            task.tags = tags
        }
        if let days = traits.dueDays { setDueDay(task, days: days, today: today) }
    }

    /// What a task still offers from the group it was moved to, recomputed each time so it
    /// disappears once the values match. nil = nothing to offer.
    func traitProposal(for task: TaskItem) -> (group: TaskGroup, traits: GroupTraits)? {
        guard let id = task.traitProposalGroupID, id == task.groupID, !task.isDone, let group = self.group(id: id) else { return nil }
        let today = DayBoundary.current.start(of: Date())
        let proposal = traits(of: group).plan(for: traitValues(of: task, today: today)).propose
        return proposal.isEmpty ? nil : (group, proposal)
    }

    /// Takes over some (or all) of a proposal.
    func acceptProposal(_ task: TaskItem, _ traits: GroupTraits) {
        apply(traits, to: task, today: DayBoundary.current.start(of: Date()))
        if traitProposal(for: task) == nil { task.traitProposalGroupID = nil }
        task.touch()
        save()
    }

    func dismissProposal(_ task: TaskItem) {
        task.traitProposalGroupID = nil
        task.touch()
        save()
    }

    /// Switches a group (with its subgroups) on or off.
    func setActive(_ group: TaskGroup, _ active: Bool) {
        group.isActive = active
        group.touch()
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
                let changed = item.groupID != target?.uuid
                item.group = target
                item.sortOrder = next
                if changed { applyTraits(to: item, propose: true) }
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

    /// Tucks a task (with its subtasks) under `parent`, the line shown above it, as its last
    /// subtask. Used by swipe right, which follows what's on screen rather than stored order.
    func makeSubtask(_ task: TaskItem, of parent: TaskItem) {
        guard task !== parent, task.groupID == parent.groupID else { return }
        let layout = self.layout(for: task.groupID)
        guard let taskIndex = layout.index(of: task), layout.index(of: parent) != nil else { return }
        let block = layout.block(of: task)
        guard !block.contains(where: { $0 === parent }) else { return }
        let blockIDs = Set(block.map(ObjectIdentifier.init))
        let remaining = SectionLayout(layout.items.filter { !blockIDs.contains(ObjectIdentifier($0)) })
        guard let parentIndex = remaining.index(of: parent) else { return }
        let parentDepth = remaining.depths[parentIndex]
        guard parentDepth < 4 else { return }
        let end = remaining.blockEnd(after: parentIndex)
        let lower = remaining.items[end - 1].sortOrder
        let upper = end < remaining.items.count ? remaining.items[end].sortOrder : nil
        let taskDepth = layout.depths[taskIndex]
        for item in block {
            item.indent = parentDepth + 1 + (layout.depth(of: item) - taskDepth)
        }
        assignOrders(block, lower: lower, upper: upper)
        if parent.isDone && !task.isDone {
            parent.isDone = false
            parent.completedAt = nil
        }
        normalizeIfNeeded(groupID: task.groupID)
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
    func addGroup(name: String, symbol: String = "list.bullet", color: TheoColor = .blue, isProject: Bool = false, parent: UUID? = nil) -> TaskGroup {
        let order = (liveGroups().map(\.sortOrder).max() ?? 0) + 1
        let group = TaskGroup(name: name, symbol: symbol, color: color, sortOrder: order)
        group.isProject = isProject
        group.parentUUID = parent
        context.insert(group)
        save()
        return group
    }

    /// Moves a group inside another one (a subproject), or to the top level with nil.
    func setParent(_ group: TaskGroup, _ parentID: UUID?) {
        guard parentID != group.uuid, group.parentUUID != parentID else { return }
        if let parentID, GroupTree.descendants(of: group.uuid, in: liveGroups()).contains(where: { $0.uuid == parentID }) { return }
        group.parentUUID = parentID
        group.touch()
        save()
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
        // Subprojects move up a level instead of disappearing with their parent.
        for child in liveGroups() where child.parentUUID == group.uuid {
            child.parentUUID = group.parentUUID
            child.touch()
        }
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
