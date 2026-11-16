import SwiftUI
import TheoCore

extension AppModel {
    /// Completes the open tasks among `tasks` (ongoing ones never finish, so they're left out)
    /// with an Undo toast. The one way to complete several at once: Undo reopens them, the
    /// subtasks they closed, takes back the next occurrences their repeats filed and the logs
    /// of ongoing subtasks they checked off.
    func complete(_ tasks: [TaskItem]) {
        var seen = Set<ObjectIdentifier>()
        let targets = tasks.filter { task in
            guard task.deletedAt == nil, !task.isDone, !task.isOngoing, !seen.contains(ObjectIdentifier(task)) else { return false }
            seen.insert(ObjectIdentifier(task))
            return true
        }
        guard !targets.isEmpty else { return }
        let plans = planStarts(of: targets)
        let logged = ongoingLines(checkedOffWith: targets)
        let earlierLogs = Set(logs(of: logged).map(ObjectIdentifier.init))
        withAnimation(.snappy) { store.setDone(targets, true) }
        let title = targets[0].trimmedTitle
        let message = targets.count == 1 && !title.isEmpty ? "“\(title)” done" : "\(targets.count) done"
        show(message) { [weak self] in
            guard let self else { return }
            let newLogs = self.logs(of: logged).filter { !earlierLogs.contains(ObjectIdentifier($0)) }
            withAnimation(.snappy) {
                self.store.setDone(targets, false)
                if !newLogs.isEmpty { self.store.setDone(newLogs, false) }
            }
            self.restorePlanStarts(plans)
        }
    }

    /// The checkbox of one row: checks it off or reopens it. When checking off does more than
    /// tick this line (it closes open subtasks, files the next repeat, logs an ongoing task, or
    /// the row goes away because finished tasks are hidden), an Undo toast says what happened.
    /// Reopening stays quiet: it already undoes what the check did.
    func check(_ task: TaskItem) {
        guard task.deletedAt == nil else { return }
        guard !task.isDone else {
            store.setDone([task], false)
            return
        }
        let openSubtasks = store.layout(for: task.groupID).block(of: task).dropFirst()
            .filter { !$0.isDone && !$0.isOngoing }.count
        let repeats = task.recurrence != nil
        let ongoing = task.isOngoing
        let hidesDone = UserDefaults.standard.string(forKey: Prefs.completedMode) == CompletedMode.hide.rawValue
        // The ongoing task itself, or the ongoing subtasks a parent's check logs.
        let logged = ongoingLines(checkedOffWith: [task])
        let earlierLogs = Set(logs(of: logged).map(ObjectIdentifier.init))
        let dueBefore = task.dueDate
        let plans = planStarts(of: [task])
        store.setDone([task], true)
        guard openSubtasks > 0 || repeats || !logged.isEmpty || hidesDone else { return }

        let title = task.trimmedTitle
        let message: String
        if ongoing {
            if let due = task.dueDate, due != dueBefore {
                // Its repeat moved the deadline on: it comes back on its own then.
                message = "Logged · next \(DateText.dueInline(due, hasTime: task.dueHasTime, today: dayStart))"
            } else {
                message = title.isEmpty ? "Logged" : "Logged “\(title)”"
            }
        } else if repeats, let copy = task.nextCopyID.flatMap({ store.task(id: $0) }), let due = copy.dueDate {
            message = "Done · next \(DateText.dueInline(due, hasTime: copy.dueHasTime, today: dayStart))"
        } else if openSubtasks > 0 {
            message = openSubtasks == 1 ? "Done with 1 subtask" : "Done with \(openSubtasks) subtasks"
        } else {
            message = title.isEmpty ? "Done" : "“\(title)” done"
        }
        show(message) { [weak self] in
            guard let self else { return }
            // Take back the logs this check made (an ongoing task itself never closed).
            let newLogs = self.logs(of: logged).filter { !earlierLogs.contains(ObjectIdentifier($0)) }
            withAnimation(.snappy) {
                if !ongoing { self.store.setDone([task], false) }
                if !newLogs.isEmpty { self.store.setDone(newLogs, false) }
            }
            self.restorePlanStarts(plans)
        }
    }

    /// The open ongoing lines a check-off of `tasks` logs: an ongoing task itself, or the
    /// ongoing subtasks in a checked-off parent's block.
    private func ongoingLines(checkedOffWith tasks: [TaskItem]) -> [TaskItem] {
        var seen = Set<ObjectIdentifier>()
        var result: [TaskItem] = []
        for task in tasks {
            let lines = task.isOngoing ? [task] : store.layout(for: task.groupID).block(of: task)
            for line in lines where line.isOngoing && !line.isDone && !seen.contains(ObjectIdentifier(line)) {
                seen.insert(ObjectIdentifier(line))
                result.append(line)
            }
        }
        return result
    }

    /// The finished logs of these ongoing tasks that are still there.
    private func logs(of tasks: [TaskItem]) -> [TaskItem] {
        let ids = Set(tasks.map(\.uuid))
        guard !ids.isEmpty else { return [] }
        return store.liveTasks().filter { log in
            guard log.isDone, let id = log.loggedFor else { return false }
            return ids.contains(id)
        }
    }

    /// When each line's run of plans began, for the tasks and their subtasks: checking off
    /// clears it, so Undo puts it back and the "carried over" count doesn't restart.
    private func planStarts(of tasks: [TaskItem]) -> [(task: TaskItem, since: Date)] {
        var layouts: [UUID?: SectionLayout] = [:]
        var result: [(task: TaskItem, since: Date)] = []
        var seen = Set<ObjectIdentifier>()
        for task in tasks {
            let layout = layouts[task.groupID] ?? store.layout(for: task.groupID)
            layouts[task.groupID] = layout
            for item in layout.block(of: task) where !seen.contains(ObjectIdentifier(item)) {
                seen.insert(ObjectIdentifier(item))
                if !item.isDone, let since = item.plannedSince { result.append((task: item, since: since)) }
            }
        }
        return result
    }

    private func restorePlanStarts(_ starts: [(task: TaskItem, since: Date)]) {
        var changed = false
        for start in starts where !start.task.isDone && start.task.plannedDay != nil && start.task.plannedSince != start.since {
            start.task.plannedSince = start.since
            changed = true
        }
        if changed { store.save() }
    }
}
