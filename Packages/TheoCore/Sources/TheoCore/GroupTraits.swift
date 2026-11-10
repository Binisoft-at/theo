import Foundation

/// Defaults a group hands to the tasks placed in it: an importance, a Power Hours estimate,
/// tags and a deadline some days out. A subgroup inherits its parent's traits and can set its
/// own instead.
///
/// A task only takes a trait where it has nothing of its own. Where it already has a different
/// value, the trait becomes a proposal the task shows, and nothing is overwritten.
public struct GroupTraits: Equatable, Sendable {
    /// 0.1...1, nil = no trait.
    public var importance: Double?
    /// Power Hours, nil = no trait.
    public var estimate: Double?
    /// Always added (tags never conflict).
    public var tags: [String]
    /// A deadline this many days after the day the task arrives, nil = no trait.
    public var dueDays: Int?

    public init(importance: Double? = nil, estimate: Double? = nil, tags: [String] = [], dueDays: Int? = nil) {
        self.importance = importance
        self.estimate = estimate
        self.tags = tags
        self.dueDays = dueDays
    }

    public var isEmpty: Bool { importance == nil && estimate == nil && tags.isEmpty && dueDays == nil }

    /// These traits where set, the parent's for the rest; tags from both.
    public func inheriting(from parent: GroupTraits) -> GroupTraits {
        var tags = parent.tags
        for tag in self.tags where !tags.contains(tag) { tags.append(tag) }
        return GroupTraits(
            importance: importance ?? parent.importance,
            estimate: estimate ?? parent.estimate,
            tags: tags,
            dueDays: dueDays ?? parent.dueDays
        )
    }

    /// One line per trait, e.g. ["Importance 8", "1 PH", "#work", "Due in 3 days"].
    public var summary: [String] {
        var parts: [String] = []
        if let importance { parts.append("Importance \(Matrix.level(forImportance: importance))") }
        if let estimate { parts.append(estimate > 0 ? PowerHours.format(estimate) : "No estimate") }
        parts += tags.map { "#" + $0 }
        if let dueDays {
            let due: String = switch dueDays {
            case 0: "Due today"
            case 1: "Due tomorrow"
            default: "Due in \(dueDays) days"
            }
            parts.append(due)
        }
        return parts
    }

    /// What a task already has of its own. nil means "nothing set" (a default value counts as
    /// nothing): importance and estimate, and the deadline in days from today.
    public struct TaskValues: Equatable, Sendable {
        public var importance: Double?
        public var estimate: Double?
        public var tags: [String]
        public var hasDeadline: Bool
        public var dueDays: Int?

        public init(importance: Double?, estimate: Double?, tags: [String], hasDeadline: Bool, dueDays: Int?) {
            self.importance = importance
            self.estimate = estimate
            self.tags = tags
            self.hasDeadline = hasDeadline
            self.dueDays = dueDays
        }
    }

    /// `apply`: traits to take right away (the task has nothing there). `propose`: traits that
    /// differ from what the task already has, to offer instead of overwriting.
    public func plan(for task: TaskValues) -> (apply: GroupTraits, propose: GroupTraits) {
        var apply = GroupTraits()
        var propose = GroupTraits()
        if let importance {
            if let own = task.importance {
                if Matrix.level(forImportance: own) != Matrix.level(forImportance: importance) { propose.importance = importance }
            } else {
                apply.importance = importance
            }
        }
        if let estimate {
            if let own = task.estimate {
                if abs(own - estimate) > 0.001 { propose.estimate = estimate }
            } else {
                apply.estimate = estimate
            }
        }
        apply.tags = tags.filter { !task.tags.contains($0) }
        if let dueDays {
            if !task.hasDeadline {
                apply.dueDays = dueDays
            } else if task.dueDays != dueDays {
                propose.dueDays = dueDays
            }
        }
        return (apply, propose)
    }
}
