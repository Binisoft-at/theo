import Foundation

/// Theo's side of the Binisoft exchange (format v1, `ExchangeFormat.swift`): what Theo tells Thalia.
///
/// - `task.done`: every finished task (subtasks and the logged copies of ongoing tasks too), on the
///   calendar day it was finished in the device's time zone.
/// - `ph`: the Power Hours of every finished task that has some, counted like the day review
///   (`PowerHours.total`): when a subtask finished the same day has its own estimate, the line above
///   it doesn't count again.
/// - Each fact names its group (`ref` "grp-<uuid>", `refTitle` "Work/Clients") and, when the group
///   (or, unless it chose "Keine", a group it sits in) is mapped to a Thalia category, carries `thalia`.
/// - Finished tasks of switched-off groups count too, as in the day review.
///
/// Built from plain values, so the rules run and are tested anywhere (also on Linux); the app turns
/// its synced store into these values. Never in demo or in-memory stores, never on the watch.
public enum TheoExchange {
    /// The folder in the App Group ("Theo") and, lower-cased, the source id ("theo").
    public static let appName = "Theo"
    public static let source = BinisoftExchange.sourceID(appName)
    /// Tasks without a group.
    public static let noGroupRef = "ohne-gruppe"
    public static let noGroupTitle = "Ohne Gruppe"
    /// Where a group keeps its Thalia category (its synced extras).
    public static let categoryKey = "thalia.category"
    public static let categoryTitleKey = "thalia.categoryTitle"
    /// A subgroup's explicit "Keine": no category, and none taken from the groups it sits in.
    public static let noCategory = "-"

    /// A group as the exchange needs it.
    public struct GroupRecord: Equatable, Sendable {
        /// The group's synced id (its UUID).
        public var id: String
        public var name: String
        public var parentID: String?
        /// The Thalia category chosen for this group ("3.2"); nil or empty: none of its own (a
        /// subgroup then takes its group's); `TheoExchange.noCategory`: none at all.
        public var category: String?
        public var categoryTitle: String?

        public init(id: String, name: String, parentID: String? = nil,
                    category: String? = nil, categoryTitle: String? = nil) {
            self.id = id
            self.name = name
            self.parentID = parentID
            self.category = category
            self.categoryTitle = categoryTitle
        }

        /// "Keine" chosen explicitly: no category, not even its group's.
        public var choseNone: Bool { category?.trimmingCharacters(in: .whitespaces) == noCategory }

        /// Its own Thalia category, if one is chosen.
        public var hint: ExchangeThaliaHint? {
            guard let key = category?.trimmingCharacters(in: .whitespaces), !key.isEmpty, key != noCategory else { return nil }
            let title = categoryTitle?.trimmingCharacters(in: .whitespaces)
            return ExchangeThaliaHint(category: key, categoryTitle: (title?.isEmpty ?? true) ? nil : title)
        }
    }

    /// A task as the exchange needs it (only finished ones matter).
    public struct TaskRecord: Equatable, Sendable, ChecklistItem, Estimated {
        /// The task's synced id (its UUID).
        public var id: String
        public var title: String
        /// nil: no group.
        public var groupID: String?
        public var isDone: Bool
        public var completedAt: Date?
        /// Power Hours.
        public var estimate: Double
        public var sortOrder: Double
        public var indent: Int

        public init(id: String, title: String, groupID: String?, isDone: Bool, completedAt: Date?,
                    estimate: Double = 0, sortOrder: Double = 0, indent: Int = 0) {
            self.id = id
            self.title = title
            self.groupID = groupID
            self.isDone = isDone
            self.completedAt = completedAt
            self.estimate = estimate
            self.sortOrder = sortOrder
            self.indent = indent
        }
    }

    public static func groupRef(_ id: String) -> String { "grp-" + id }

    /// "Arbeit/Kunden": the group's name after those of the groups it sits in.
    public static func path(of id: String, in groups: [String: GroupRecord]) -> String {
        guard let group = groups[id] else { return noGroupTitle }
        var names = [displayName(group)]
        var seen: Set<String> = [id]
        var current = group
        while let parent = current.parentID, !seen.contains(parent), let next = groups[parent] {
            names.insert(displayName(next), at: 0)
            seen.insert(parent)
            current = next
        }
        return names.joined(separator: "/")
    }

    /// The Thalia category a group's facts carry: its own, else that of the nearest group it sits
    /// in, unless "Keine" was chosen on the way.
    public static func hint(for id: String, in groups: [String: GroupRecord]) -> ExchangeThaliaHint? {
        var seen: Set<String> = []
        var current = groups[id]
        while let group = current, !seen.contains(group.id) {
            if group.choseNone { return nil }
            if let hint = group.hint { return hint }
            seen.insert(group.id)
            current = group.parentID.flatMap { groups[$0] }
        }
        return nil
    }

    /// The facts of the last `BinisoftExchange.keepDays` days up to `today` ("2026-11-22"), by day.
    /// Days without facts are missing from the result.
    public static func facts(tasks: [TaskRecord], groups: [GroupRecord], today: String,
                             timeZone: TimeZone = .current) -> [String: [ExchangeFact]] {
        guard let oldest = BinisoftExchange.day(today, adding: -BinisoftExchange.keepDays) else { return [:] }
        let byID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Finished tasks by day and by group ("" = no group, or a group that's gone).
        var finished: [String: [String: [TaskRecord]]] = [:]
        for task in tasks where task.isDone {
            guard let completed = task.completedAt else { continue }
            let day = ExchangeDate.day(completed, timeZone: timeZone)
            guard day >= oldest, day <= today else { continue }
            var key = ""
            if let groupID = task.groupID, byID[groupID] != nil {
                key = groupID
            }
            finished[day, default: [:]][key, default: []].append(task)
        }
        var result: [String: [ExchangeFact]] = [:]
        for (day, sections) in finished {
            var facts: [ExchangeFact] = []
            for (key, section) in sections {
                let ref = key.isEmpty ? noGroupRef : groupRef(key)
                let refTitle = key.isEmpty ? noGroupTitle : path(of: key, in: byID)
                let thalia = key.isEmpty ? nil : hint(for: key, in: byID)
                // The order lines have in their group, so nesting reads as in Theo.
                let lines = section.sorted { ($0.sortOrder, $0.id) < ($1.sortOrder, $1.id) }
                let counts = PowerHours.countsOwnEstimate(lines)
                for (index, task) in lines.enumerated() {
                    let at = task.completedAt.map { ExchangeDate.string($0, timeZone: timeZone) }
                    let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    facts.append(ExchangeFact(id: "task-" + task.id, kind: ExchangeKind.taskDone.rawValue, ref: ref,
                                              refTitle: refTitle, title: title.isEmpty ? nil : title, at: at,
                                              origin: .app, thalia: thalia))
                    if counts[index] {
                        facts.append(ExchangeFact(id: "ph-" + task.id, kind: ExchangeKind.powerHours.rawValue, ref: ref,
                                                  refTitle: refTitle, title: title.isEmpty ? nil : title,
                                                  value: task.estimate, unit: "PH", at: at, origin: .app, thalia: thalia))
                    }
                }
            }
            result[day] = ordered(facts)
        }
        return result
    }

    /// The fixed order of a day's facts, the same on every device: by `at`, then `id`.
    public static func ordered(_ facts: [ExchangeFact]) -> [ExchangeFact] {
        facts.sorted { ($0.at ?? "", $0.id) < ($1.at ?? "", $1.id) }
    }

    /// Every group Bini can pick in Thalia, plus "Ohne Gruppe", for `source.json`.
    public static func refs(groups: [GroupRecord]) -> [ExchangeRef] {
        let byID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let refs = groups.map { ExchangeRef(id: groupRef($0.id), title: path(of: $0.id, in: byID), kind: "group") }
            .sorted { ($0.title.lowercased(), $0.id) < ($1.title.lowercased(), $1.id) }
        return refs + [ExchangeRef(id: noGroupRef, title: noGroupTitle, kind: "group")]
    }

    private static func displayName(_ group: GroupRecord) -> String {
        let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}

// MARK: - Thalia's catalog in Theo

extension TheoExchange {
    /// One goal of Thalia's catalog with its categories, as the picker lists them.
    public struct CategoryChoices: Equatable, Sendable {
        public var goal: ExchangeCatalog.GoalEntry
        public var categories: [ExchangeCatalog.CategoryEntry]
    }

    /// The categories of the catalog (of its current segment) by goal, both in Thalia's numbering
    /// ("1.2" before "1.10"). A category whose goal isn't listed gets a goal of its own.
    public static func choices(_ catalog: ExchangeCatalog) -> [CategoryChoices] {
        let segment = catalog.segment?.id
        let categories = catalog.categories.filter { category in
            guard let segment, let own = category.segment else { return true }
            return own == segment
        }
        var goals = catalog.goals
        for category in categories where !goals.contains(where: { $0.key == category.goal }) {
            goals.append(ExchangeCatalog.GoalEntry(key: category.goal, title: ""))
        }
        return goals.sorted { keyOrder($0.key, $1.key) }.compactMap { goal in
            let own = categories.filter { $0.goal == goal.key }.sorted { keyOrder($0.key, $1.key) }
            return own.isEmpty ? nil : CategoryChoices(goal: goal, categories: own)
        }
    }

    /// "3.2 Kunden".
    public static func label(_ category: ExchangeCatalog.CategoryEntry) -> String {
        category.title.isEmpty ? category.key : category.key + " " + category.title
    }

    /// "3 Arbeit".
    public static func label(_ goal: ExchangeCatalog.GoalEntry) -> String {
        goal.title.isEmpty ? goal.key : goal.key + " " + goal.title
    }

    /// How a group's chosen category stands against the catalog on this device.
    public enum MappingState: Equatable, Sendable {
        /// Nothing chosen.
        case none
        /// Chosen and found under the same title.
        case ok
        /// Chosen, but there's no catalog on this device (Thalia wasn't opened here yet).
        case catalogMissing
        /// Chosen, but the catalog no longer has it or calls it something else.
        case check
    }

    public static func state(category: String?, categoryTitle: String?, catalog: ExchangeCatalog?) -> MappingState {
        guard let key = category?.trimmingCharacters(in: .whitespaces), !key.isEmpty, key != noCategory else { return .none }
        guard let catalog else { return .catalogMissing }
        guard let found = choices(catalog).flatMap(\.categories).first(where: { $0.key == key }) else { return .check }
        if let title = categoryTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty, title != found.title {
            return .check
        }
        return .ok
    }

    /// Thalia's numbering: "1.2" < "1.10" < "2"; anything else after, by text.
    static func keyOrder(_ a: String, _ b: String) -> Bool {
        let left = a.split(separator: ".").map { Int($0) }
        let right = b.split(separator: ".").map { Int($0) }
        for (x, y) in zip(left, right) {
            switch (x, y) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: continue
            }
        }
        if left.count != right.count { return left.count < right.count }
        return a < b
    }
}
