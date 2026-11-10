import Foundation

/// The urgency × importance grid every task gets ranked by. It isn't a separate view of the
/// tasks: where a task sits decides where it shows up in every list.
///
/// - Urgency comes from the deadline, in days: today (or overdue) is the most urgent, 14 days out
///   is the far edge, and no deadline (or a later one) means no urgency.
/// - Importance has 10 levels. The `!` / `!!` / `!!!` marks are a coarse view of it.
/// - The score weighs importance above urgency, so "important, not urgent" outranks "urgent,
///   not important", the Eisenhower order.
public enum Matrix {
    /// Days from today that still count as urgent (the grid's columns are 0...horizonDays).
    public static let horizonDays = 14
    public static let levels = 10
    /// New tasks: not important, an average amount of it (level 3 of 10).
    public static let defaultImportance = 0.3

    public static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    // MARK: - Importance levels

    /// 1...10.
    public static func level(forImportance importance: Double) -> Int {
        min(levels, max(1, Int((clamp(importance) * Double(levels)).rounded())))
    }

    public static func importance(forLevel level: Int) -> Double {
        Double(min(levels, max(1, level))) / Double(levels)
    }

    /// The marks shown for an importance: levels 9–10 `!!!`, 7–8 `!!`, 5–6 `!`.
    public static func priority(forImportance importance: Double) -> Priority {
        switch level(forImportance: importance) {
        case 9...: .high
        case 7...8: .medium
        case 5...6: .low
        default: .normal
        }
    }

    /// Importance after setting a priority mark. A level already inside that mark's band is kept.
    public static func importance(for priority: Priority, current: Double) -> Double {
        if self.priority(forImportance: current) == priority { return current }
        switch priority {
        case .normal: return defaultImportance
        case .low: return importance(forLevel: 6)
        case .medium: return importance(forLevel: 8)
        case .high: return importance(forLevel: 10)
        }
    }

    // MARK: - Urgency from the deadline

    /// Whole days from today to `due` (negative when overdue), nil without a deadline.
    public static func daysUntil(_ due: Date?, today: Date, calendar: Calendar = .current) -> Int? {
        due.map { DateText.dayDelta($0, today: today, calendar: calendar) }
    }

    /// 1 for today or overdue, falling to almost 0 at 14 days; 0 later or without a deadline.
    public static func urgency(daysUntilDue days: Int?) -> Double {
        guard let days else { return 0 }
        if days <= 0 { return 1 }
        if days > horizonDays { return 0 }
        return 1 - Double(days) / Double(horizonDays + 1)
    }

    /// The deadline (in days from today) an urgency stands for; nil means no urgency.
    public static func days(forUrgency urgency: Double) -> Int? {
        guard urgency > 0.0001 else { return nil }
        if urgency >= 1 { return 0 }
        let days = Int(((1 - urgency) * Double(horizonDays + 1)).rounded())
        return days > horizonDays ? nil : max(0, days)
    }

    // MARK: - Ranking

    public static func score(importance: Double, urgency: Double) -> Double {
        0.6 * clamp(importance) + 0.4 * clamp(urgency)
    }

    public static func score(importance: Double, due: Date?, today: Date, calendar: Calendar = .current) -> Double {
        score(importance: importance, urgency: urgency(daysUntilDue: daysUntil(due, today: today, calendar: calendar)))
    }

    /// The importance that gives a task with `urgency` the score `target`, for dropping it
    /// between two others. Kept within level 1...10.
    public static func importance(toReach target: Double, urgency: Double) -> Double {
        min(1, max(0.1, (target - 0.4 * clamp(urgency)) / 0.6))
    }

    /// A new task between two others gets the average of both (or the one neighbour's values).
    public static func between(_ above: (importance: Double, urgency: Double)?, _ below: (importance: Double, urgency: Double)?)
        -> (importance: Double, urgency: Double)? {
        switch (above, below) {
        case let (a?, b?): return ((a.importance + b.importance) / 2, (a.urgency + b.urgency) / 2)
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }

    /// A task's place in the ranking: importance, and whole days until its deadline (nil = none).
    public struct Rank: Equatable, Sendable {
        public var importance: Double
        public var days: Int?

        public init(importance: Double, days: Int?) {
            self.importance = importance
            self.days = days.map { max(0, $0) }
        }

        public var score: Double { Matrix.score(importance: importance, urgency: Matrix.urgency(daysUntilDue: days)) }
    }

    /// Importance and deadline for a new task dropped between two ranked tasks, so that it ranks
    /// right between them (just below the last one, or just above the first). It gets no
    /// deadline whenever importance alone can do that, so dropping a task never invents one.
    /// Otherwise it takes the lower neighbour's deadline, then the upper one's.
    public static func insertion(above: Rank?, below: Rank?) -> Rank? {
        let target: Double
        switch (above, below) {
        case let (a?, b?): target = (a.score + b.score) / 2
        case let (a?, nil): target = a.score - 0.02
        case let (nil, b?): target = b.score + 0.02
        case (nil, nil): return nil
        }
        var candidates: [Int?] = [nil]
        for days in [below?.days, above?.days] where days != nil && !candidates.contains(days) {
            candidates.append(days)
        }
        for days in candidates {
            let needed = (target - 0.4 * urgency(daysUntilDue: days)) / 0.6
            if needed >= 0.1 - 1e-9, needed <= 1 + 1e-9 {
                return Rank(importance: min(1, max(0.1, needed)), days: days)
            }
        }
        let days = above?.days ?? below?.days
        return Rank(importance: importance(toReach: target, urgency: urgency(daysUntilDue: days)), days: days)
    }

    // MARK: - Grid

    /// Columns: today ... +14 days, then one "no date" column.
    public static var columns: Int { horizonDays + 2 }

    /// The column for a deadline: 0 = today/overdue ... 14, and 15 for none or later.
    public static func column(forDays days: Int?) -> Int {
        guard let days, days <= horizonDays else { return horizonDays + 1 }
        return max(0, days)
    }

    /// Days for a column; nil for the "no date" column.
    public static func days(forColumn column: Int) -> Int? {
        column > horizonDays ? nil : max(0, column)
    }
}
