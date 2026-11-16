import Foundation
import CoreData
import SwiftData
import WidgetKit
import TheoCore

// MARK: - Building the snapshot from the store

extension WidgetSnapshot {
    /// Lines kept per page: the large widget lists 8, with some to spare.
    static let lineLimit = 10

    /// Today's and tomorrow's page, from the same rules as Today: tasks planned for the day in
    /// groups that are on, ranked like Today's default ("Ranked") layout, then what Today's
    /// carry-over strip offers. Pure: reads the tasks, changes nothing.
    @MainActor
    static func build(tasks: [TaskItem], groups: [TaskGroup], now: Date = Date(), boundary: DayBoundary = .current) -> WidgetSnapshot {
        let live = tasks.filter { $0.deletedAt == nil }
        let liveGroups = groups.filter { $0.deletedAt == nil }
        // Every live task by group, so each line nests under its real parent (as on Today).
        let sections = Dictionary(grouping: live, by: \.groupID)
        let active = live.activeOnly(liveGroups)
        // Subtasks folded away on Today stay out here too (this device's choice).
        let stored = UserDefaults.standard.stringArray(forKey: Prefs.collapsedTasks) ?? []
        let folded = Set(stored.compactMap(UUID.init(uuidString:)))
        let today = boundary.start(of: now)
        let tomorrow = boundary.end(ofDayStarting: today)
        let todayPage = page(day: today, end: tomorrow, active: active, sections: sections, folded: folded)
        let tomorrowPage = page(day: tomorrow, end: boundary.end(ofDayStarting: tomorrow), active: active, sections: sections, folded: folded)
        return WidgetSnapshot(generatedAt: now, today: todayPage, tomorrow: tomorrowPage)
    }

    @MainActor
    private static func page(day: Date, end: Date, active: [TaskItem], sections: [UUID?: [TaskItem]], folded: Set<UUID>) -> Page {
        // Today's page: planned for the day and open, or finished during it.
        let visible = active.filter { $0.isOnPage(of: day) }
        let openCount = visible.filter { !$0.isDone }.count
        let totals = powerHours(visible, sections: sections)
        let openActive = active.filter { !$0.isDone }
        let overdue = openActive.filter { task in
            guard let due = task.dueDate else { return false }
            return DateText.dayDelta(due, today: day) < 0
        }.count

        var lines: [Line] = []
        for item in rankedOpen(visible, sections: sections, day: day, folded: folded) where lines.count < lineLimit {
            lines.append(line(for: item.task, depth: item.depth, planned: true))
        }
        if lines.count < lineLimit {
            // Today's carry-over strip: left open on an earlier day's plan, or due without a plan.
            let carry = CarryOver.compute(open: openActive, dayStart: day, sections: sections)
            for task in carry.leftOver + carry.dueUnplanned where lines.count < lineLimit {
                lines.append(line(for: task, depth: 0, planned: false))
            }
        }
        return Page(
            dayStart: day,
            dayEnd: end,
            open: openCount,
            done: visible.count - openCount,
            powerHoursLeft: totals.open,
            powerHoursDone: totals.done,
            overdue: overdue,
            lines: lines
        )
    }

    @MainActor
    private static func line(for task: TaskItem, depth: Int, planned: Bool) -> Line {
        let group: TaskGroup? = task.groupID == nil ? nil : task.group
        let title = task.trimmedTitle
        return Line(
            id: task.uuid,
            title: title.isEmpty ? "New Task" : title,
            due: task.dueDate,
            dueHasTime: task.dueHasTime,
            priority: task.priority.rawValue,
            groupName: group?.displayName,
            groupColor: group?.colorName,
            groupSymbol: group?.symbol,
            powerHours: task.estimate,
            isOngoing: task.isOngoing,
            isPlanned: planned,
            depth: depth
        )
    }

    // MARK: Today's ranking (mirrors PageBuilder.rankedRows, which only the apps have)

    private struct RankedLine {
        let task: TaskItem
        let depth: Int
    }

    /// A top-level line with the lines nested under it.
    private struct RankedBlock {
        let score: Double
        let done: Bool
        let groupOrder: Double
        let order: Double
        var lines: [RankedLine]
    }

    /// The open lines in Today's order: each group nested and ranked on its own (subtasks stay
    /// with their parents), then the top-level blocks merged by score, open ones first; equal
    /// scores keep group order, then manual order.
    @MainActor
    private static func rankedOpen(_ visible: [TaskItem], sections: [UUID?: [TaskItem]], day: Date, folded: Set<UUID>) -> [RankedLine] {
        var blocks: [RankedBlock] = []
        for section in Dictionary(grouping: visible, by: \.groupID).values {
            let ordered = Checklist.displayOrder(displayLines(section, sections: sections), showCompleted: true, rank: { line in
                line.task.matrixScore(today: day)
            })
            let depths = ordered.map(\.depth)
            var current: RankedBlock?
            var index = 0
            while index < ordered.count {
                let task = ordered[index].item.task
                let depth = ordered[index].depth
                let end = Checklist.blockEnd(after: index, depths: depths)
                if depth == 0 {
                    if let current { blocks.append(current) }
                    current = RankedBlock(
                        score: task.matrixScore(today: day),
                        done: task.isDone,
                        groupOrder: groupOrder(of: task),
                        order: task.sortOrder,
                        lines: []
                    )
                }
                current?.lines.append(RankedLine(task: task, depth: depth))
                // A folded parent hides its subtasks (an ongoing task's old logs aren't subtasks).
                let hasSubtasks = ordered[(index + 1)..<end].contains { $0.item.task.loggedFor == nil }
                index = hasSubtasks && folded.contains(task.uuid) ? end : index + 1
            }
            if let current { blocks.append(current) }
        }
        blocks.sort { a, b in
            if a.done != b.done { return !a.done }
            if abs(a.score - b.score) > 1e-9 { return a.score > b.score }
            if a.groupOrder != b.groupOrder { return a.groupOrder < b.groupOrder }
            return a.order < b.order
        }
        let lines: [RankedLine] = blocks.flatMap { $0.lines }
        return lines.filter { !$0.task.isDone }
    }

    @MainActor
    private static func groupOrder(of task: TaskItem) -> Double {
        guard let group = task.group, group.deletedAt == nil else { return -.infinity }
        return group.sortOrder
    }

    /// Planned and finished Power Hours, totalled per group so nesting is read as on Today.
    @MainActor
    private static func powerHours(_ tasks: [TaskItem], sections: [UUID?: [TaskItem]]) -> (open: Double, done: Double) {
        var open = 0.0
        var done = 0.0
        for section in Dictionary(grouping: tasks, by: \.groupID).values {
            let lines = displayLines(section, sections: sections)
            open += PowerHours.total(lines, where: { !$0.isDone })
            done += PowerHours.total(lines, where: { $0.isDone })
        }
        return (open, done)
    }

    /// One group's lines with the depth Today gives them: a subtask whose parent isn't on the
    /// page stands at the top level instead of under the line before it.
    @MainActor
    private static func displayLines(_ tasks: [TaskItem], sections: [UUID?: [TaskItem]]) -> [SnapshotLine] {
        let stored = tasks.map { SnapshotLine(task: $0, indent: $0.indent) }
        guard let first = tasks.first, let full = sections[first.groupID] else { return stored }
        let sectionID = first.groupID
        guard tasks.allSatisfy({ $0.groupID == sectionID }) else { return stored }
        let ordered = full.sorted { $0.sortOrder < $1.sortOrder }
        let shown = Set(tasks.map(\.uuid))
        let depths = Checklist.visibleDepths(ordered: ordered) { shown.contains(ordered[$0].uuid) }
        var placed: [UUID: Int] = [:]
        for index in ordered.indices {
            if let depth = depths[index] { placed[ordered[index].uuid] = depth }
        }
        // A line missing from the full section: keep the stored nesting rather than guess.
        guard tasks.allSatisfy({ placed[$0.uuid] != nil }) else { return stored }
        return tasks.map { SnapshotLine(task: $0, indent: placed[$0.uuid] ?? $0.indent) }
    }
}

/// A task with the indent it has on the page.
private struct SnapshotLine: ChecklistItem, Estimated {
    let task: TaskItem
    let indent: Int

    var sortOrder: Double { task.sortOrder }
    var isDone: Bool { task.isDone }
    var completedAt: Date? { task.completedAt }
    var estimate: Double { task.estimate }
}

// MARK: - Writing it

/// Keeps the widgets' snapshot current: rebuilt shortly after every save (here or synced from
/// another device), when the day-start setting or the folded subtasks change, and when the next
/// logical day starts. It's written only when something the widgets show changed, and then the
/// widgets reload. The iPhone/iPad/Mac app starts it through `WidgetBridge`, the watch app in
/// `TheoWatchApp`; both also call it when they come to the front or leave.
@MainActor
final class WidgetSnapshotWriter {
    private let container: ModelContainer
    private var pending: Task<Void, Never>?
    private var dayChange: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    /// What the widgets have (read back from the file at launch), so nothing is written twice.
    private var written: WidgetSnapshot?
    /// The settings the last build used; a change rebuilds.
    private var appliedSettings: String

    init(container: ModelContainer) {
        self.container = container
        written = WidgetSnapshot.load()
        appliedSettings = WidgetSnapshotWriter.settingsSignature
        let center = NotificationCenter.default
        // Every save of Theo's store, from any part of the app: lists, the Mac's Quick Add
        // panel, Siri and Shortcuts, notification actions (which change nothing on screen, so
        // activation alone wouldn't catch them). Not the tour's practice store.
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let saved = note.object as? ModelContext, saved.container === container else { return }
                self?.scheduleSoon()
            }
        })
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSoon() }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.appliedSettings != WidgetSnapshotWriter.settingsSignature else { return }
                self.scheduleSoon()
            }
        })
        scheduleSoon()
    }

    /// "New day starts at" and the folded subtasks: both change what the widgets list.
    private static var settingsSignature: String {
        let folded = UserDefaults.standard.stringArray(forKey: Prefs.collapsedTasks) ?? []
        return String(DayBoundary.storedStartHour) + "|" + folded.sorted().joined(separator: ",")
    }

    /// Rebuilds once a burst of saves has settled.
    func scheduleSoon(after seconds: Double = 2) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    /// Rebuilds right away, e.g. as Theo goes to the background (it may be suspended next).
    func writeNow() {
        pending?.cancel()
        pending = nil
        appliedSettings = Self.settingsSignature
        let store = TaskStore(context: container.mainContext)
        let snapshot = WidgetSnapshot.build(tasks: store.liveTasks(), groups: store.liveGroups())
        refreshAtNextDay(snapshot.today.dayEnd)
        if let written, written.hasSameContent(as: snapshot) { return }
        do {
            try snapshot.write()
            written = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Theo: widget snapshot not written: \(error)")
        }
    }

    /// A Mac (or an iPhone that keeps Theo running) sees the new day without being touched.
    private func refreshAtNextDay(_ dayEnd: Date) {
        dayChange?.cancel()
        let seconds = max(60, dayEnd.timeIntervalSinceNow + 5)
        dayChange = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }
}
