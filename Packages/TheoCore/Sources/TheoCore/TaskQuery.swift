import Foundation

/// What a task list shows: which tasks (filters), in which sections (grouping) and in which
/// order (sort). All Tasks edits one; a saved view stores one as JSON.
public struct TaskQuery: Codable, Equatable, Hashable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case open, done, all

        public var title: String {
            switch self {
            case .open: "Open"
            case .done: "Done"
            case .all: "All"
            }
        }
    }

    public enum Deadline: String, Codable, CaseIterable, Sendable {
        case any, overdue, today, week, twoWeeks, some, none

        public var title: String {
            switch self {
            case .any: "Any"
            case .overdue: "Overdue"
            case .today: "Due today (or overdue)"
            case .week: "Due within 7 days"
            case .twoWeeks: "Due within 14 days"
            case .some: "Has a deadline"
            case .none: "No deadline"
            }
        }
    }

    public enum Planned: String, Codable, CaseIterable, Sendable {
        case any, today, someDay, unplanned

        public var title: String {
            switch self {
            case .any: "Any"
            case .today: "Planned for today"
            case .someDay: "Planned for a day"
            case .unplanned: "Not planned"
            }
        }
    }

    public enum Grouping: String, Codable, CaseIterable, Sendable {
        case group, topGroup, priority, deadline, tag, size, planned, none

        public var title: String {
            switch self {
            case .group: "Group & Subgroup"
            case .topGroup: "Group"
            case .priority: "Priority"
            case .deadline: "Deadline"
            case .tag: "Tag"
            case .size: "Size (Power Hours)"
            case .planned: "Planned Day"
            case .none: "No Grouping"
            }
        }

        /// For a small button.
        public var shortTitle: String {
            switch self {
            case .group: "Subgroups"
            case .topGroup: "Groups"
            case .priority: "Priority"
            case .deadline: "Deadline"
            case .tag: "Tags"
            case .size: "Size"
            case .planned: "Planned"
            case .none: "Ungrouped"
            }
        }
    }

    public enum Sort: String, Codable, CaseIterable, Sendable {
        case priorityDeadline, rank, deadline, priority, estimate, created, title

        public var title: String {
            switch self {
            case .priorityDeadline: "Priority, then Deadline"
            case .rank: "Rank (Importance × Urgency)"
            case .deadline: "Deadline"
            case .priority: "Priority"
            case .estimate: "Power Hours"
            case .created: "Newest First"
            case .title: "Title"
            }
        }

        /// For a small button.
        public var shortTitle: String {
            switch self {
            case .priorityDeadline: "Priority · Due"
            case .rank: "Rank"
            case .deadline: "Due"
            case .priority: "Priority"
            case .estimate: "PH"
            case .created: "Newest"
            case .title: "A–Z"
            }
        }
    }

    public var status: Status = .open
    /// Groups to show (with their subgroups); empty = all.
    public var groupIDs: [UUID] = []
    /// Only Quick Entry (tasks without a group).
    public var quickEntryOnly = false
    /// Any of these tags; empty = no tag filter.
    public var tags: [String] = []
    /// Importance level at least this (1...10); 0 = any.
    public var minLevel = 0
    public var deadline: Deadline = .any
    public var planned: Planned = .any
    public var ongoingOnly = false
    /// Power Hours at most this; nil = any.
    public var maxEstimate: Double?
    public var search = ""
    public var grouping: Grouping = .group
    public var sort: Sort = .priorityDeadline

    public init() {}

    /// All Tasks' starting point: open tasks, by group, by priority and deadline.
    public static let standard = TaskQuery()

    /// How many filters narrow the list (for the "Filters · 2" badge).
    public var filterCount: Int {
        var count = 0
        if status != .open { count += 1 }
        if !groupIDs.isEmpty || quickEntryOnly { count += 1 }
        if !tags.isEmpty { count += 1 }
        if minLevel > 0 { count += 1 }
        if deadline != .any { count += 1 }
        if planned != .any { count += 1 }
        if ongoingOnly { count += 1 }
        if maxEstimate != nil { count += 1 }
        if !search.trimmingCharacters(in: .whitespaces).isEmpty { count += 1 }
        return count
    }

    // MARK: - Stored form

    /// JSON, for storing in a saved view or in the app's settings.
    public var raw: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads `raw`; anything unreadable or missing falls back to the standard values, so older
    /// and newer app versions understand each other's views.
    public init(raw: String) {
        guard let data = raw.data(using: .utf8), let query = try? JSONDecoder().decode(TaskQuery.self, from: data) else {
            self = .standard
            return
        }
        self = query
    }

    private enum CodingKeys: String, CodingKey {
        case status, groupIDs, quickEntryOnly, tags, minLevel, deadline, planned, ongoingOnly, maxEstimate, search, grouping, sort
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = (try? c.decodeIfPresent(Status.self, forKey: .status)) ?? .open
        groupIDs = (try? c.decodeIfPresent([UUID].self, forKey: .groupIDs)) ?? []
        quickEntryOnly = (try? c.decodeIfPresent(Bool.self, forKey: .quickEntryOnly)) ?? false
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        minLevel = (try? c.decodeIfPresent(Int.self, forKey: .minLevel)) ?? 0
        deadline = (try? c.decodeIfPresent(Deadline.self, forKey: .deadline)) ?? .any
        planned = (try? c.decodeIfPresent(Planned.self, forKey: .planned)) ?? .any
        ongoingOnly = (try? c.decodeIfPresent(Bool.self, forKey: .ongoingOnly)) ?? false
        maxEstimate = try? c.decodeIfPresent(Double.self, forKey: .maxEstimate)
        search = (try? c.decodeIfPresent(String.self, forKey: .search)) ?? ""
        grouping = (try? c.decodeIfPresent(Grouping.self, forKey: .grouping)) ?? .group
        sort = (try? c.decodeIfPresent(Sort.self, forKey: .sort)) ?? .priorityDeadline
    }

    // MARK: - Matching

    /// What a task is, as far as a query cares.
    public struct Facts: Sendable {
        public var title: String
        public var notes: String
        public var isDone: Bool
        /// The task's group and every group it sits in; empty for Quick Entry.
        public var groupPath: [UUID]
        public var tags: [String]
        public var level: Int
        /// Days until the deadline (negative = overdue), nil without one.
        public var daysUntilDue: Int?
        /// Days from today to the planned day (0 = today), nil when not planned.
        public var plannedIn: Int?
        public var isOngoing: Bool
        public var estimate: Double
        public var created: Date

        public init(title: String, notes: String = "", isDone: Bool, groupPath: [UUID], tags: [String], level: Int,
                    daysUntilDue: Int?, plannedIn: Int?, isOngoing: Bool, estimate: Double, created: Date = .distantPast) {
            self.title = title
            self.notes = notes
            self.isDone = isDone
            self.groupPath = groupPath
            self.tags = tags
            self.level = level
            self.daysUntilDue = daysUntilDue
            self.plannedIn = plannedIn
            self.isOngoing = isOngoing
            self.estimate = estimate
            self.created = created
        }
    }

    public func matches(_ task: Facts) -> Bool {
        switch status {
        case .open: if task.isDone { return false }
        case .done: if !task.isDone { return false }
        case .all: break
        }
        if quickEntryOnly {
            if !task.groupPath.isEmpty { return false }
        } else if !groupIDs.isEmpty {
            if !task.groupPath.contains(where: { groupIDs.contains($0) }) { return false }
        }
        if !tags.isEmpty, !task.tags.contains(where: { tags.contains($0) }) { return false }
        if minLevel > 0, task.level < minLevel { return false }
        switch deadline {
        case .any: break
        case .overdue: guard let days = task.daysUntilDue, days < 0 else { return false }
        case .today: guard let days = task.daysUntilDue, days <= 0 else { return false }
        case .week: guard let days = task.daysUntilDue, days <= 7 else { return false }
        case .twoWeeks: guard let days = task.daysUntilDue, days <= 14 else { return false }
        case .some: if task.daysUntilDue == nil { return false }
        case .none: if task.daysUntilDue != nil { return false }
        }
        switch planned {
        case .any: break
        case .today: if task.plannedIn != 0 { return false }
        case .someDay: if task.plannedIn == nil { return false }
        case .unplanned: if task.plannedIn != nil { return false }
        }
        if ongoingOnly, !task.isOngoing { return false }
        if let maxEstimate, task.estimate > maxEstimate + 0.0001 { return false }
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty, !task.title.lowercased().contains(needle), !task.notes.lowercased().contains(needle) { return false }
        return true
    }

    /// True when `a` comes before `b` in this query's order. Ties fall back to the deadline,
    /// then the title, so the order is always the same.
    public func precedes(_ a: Facts, _ b: Facts, scoreA: Double = 0, scoreB: Double = 0) -> Bool {
        func dueKey(_ facts: Facts) -> Int { facts.daysUntilDue ?? Int.max }
        func tieBreak() -> Bool {
            if dueKey(a) != dueKey(b) { return dueKey(a) < dueKey(b) }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        switch sort {
        case .priorityDeadline:
            if a.level != b.level { return a.level > b.level }
            return tieBreak()
        case .rank:
            if abs(scoreA - scoreB) > 1e-9 { return scoreA > scoreB }
            return tieBreak()
        case .deadline:
            if dueKey(a) != dueKey(b) { return dueKey(a) < dueKey(b) }
            if a.level != b.level { return a.level > b.level }
            return tieBreak()
        case .priority:
            if a.level != b.level { return a.level > b.level }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        case .estimate:
            if abs(a.estimate - b.estimate) > 0.0001 { return a.estimate > b.estimate }
            return tieBreak()
        case .created:
            if a.created != b.created { return a.created > b.created }
            return tieBreak()
        case .title:
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    // MARK: - Ready-made views

    public struct Preset: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let symbol: String
        public let query: TaskQuery
    }

    /// Quick switches on top of All Tasks.
    public static let presets: [Preset] = {
        var dueSoon = TaskQuery()
        dueSoon.deadline = .week
        dueSoon.grouping = .deadline
        dueSoon.sort = .deadline
        var important = TaskQuery()
        important.minLevel = 7
        var quickWins = TaskQuery()
        quickWins.maxEstimate = 0.25
        quickWins.sort = .rank
        var ongoing = TaskQuery()
        ongoing.ongoingOnly = true
        var unplanned = TaskQuery()
        unplanned.planned = .unplanned
        unplanned.sort = .rank
        var done = TaskQuery()
        done.status = .done
        done.grouping = .none
        done.sort = .created
        return [
            Preset(id: "all", title: "All Open", symbol: "tray.full", query: .standard),
            Preset(id: "due", title: "Due This Week", symbol: "calendar", query: dueSoon),
            Preset(id: "important", title: "Important", symbol: "exclamationmark.3", query: important),
            Preset(id: "quick", title: "Quick Wins", symbol: "hare", query: quickWins),
            Preset(id: "ongoing", title: "Ongoing", symbol: "infinity", query: ongoing),
            Preset(id: "unplanned", title: "Not Planned", symbol: "calendar.badge.exclamationmark", query: unplanned),
            Preset(id: "done", title: "Done", symbol: "checkmark.circle", query: done),
        ]
    }()
}
