import Foundation

/// How a task with a deadline repeats. Completing it creates the next occurrence.
public enum Recurrence: Hashable, Sendable {
    case daily
    case weekdays
    case weekly
    case monthly
    case yearly
    case everyDays(Int)

    public static let common: [Recurrence] = [.daily, .weekdays, .weekly, .monthly, .yearly]

    /// Stored form ("daily", "days:3").
    public var raw: String {
        switch self {
        case .daily: "daily"
        case .weekdays: "weekdays"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .yearly: "yearly"
        case .everyDays(let days): "days:\(days)"
        }
    }

    public init?(raw: String) {
        switch raw {
        case "daily": self = .daily
        case "weekdays": self = .weekdays
        case "weekly": self = .weekly
        case "monthly": self = .monthly
        case "yearly": self = .yearly
        default:
            guard raw.hasPrefix("days:"), let days = Int(raw.dropFirst(5)), days > 0 else { return nil }
            self = .everyDays(days)
        }
    }

    public var title: String {
        switch self {
        case .daily: "Every Day"
        case .weekdays: "Every Weekday"
        case .weekly: "Every Week"
        case .monthly: "Every Month"
        case .yearly: "Every Year"
        case .everyDays(let days): days == 1 ? "Every Day" : "Every \(days) Days"
        }
    }

    /// The next occurrence after `date`, keeping its time of day.
    public func next(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
            }
            return next
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        case .everyDays(let days):
            return calendar.date(byAdding: .day, value: max(1, days), to: date) ?? date
        }
    }

    private static let patterns: [(String, Recurrence?)] = [
        (#"\b(?:every|alle)\s+(\d+)\s+(?:days|tage)\b"#, nil),
        (#"\b(?:every\s+weekday|weekdays|werktags|jeden\s+werktag)\b"#, .weekdays),
        (#"\b(?:every\s+day|daily|täglich|jeden\s+tag)\b"#, .daily),
        (#"\b(?:every\s+week|weekly|wöchentlich|jede\s+woche)\b"#, .weekly),
        (#"\b(?:every\s+month|monthly|monatlich|jeden\s+monat)\b"#, .monthly),
        (#"\b(?:every\s+year|yearly|annually|jährlich|jedes\s+jahr)\b"#, .yearly),
    ]

    /// Finds "every day", "weekly", "täglich", "every 3 days" ... in text, with its range.
    public static func find(in text: String) -> (recurrence: Recurrence, range: Range<String.Index>)? {
        for (pattern, recurrence) in patterns {
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            if let recurrence { return (recurrence, range) }
            let match = text[range]
            if let numberRange = match.range(of: #"\d+"#, options: .regularExpression), let days = Int(match[numberRange]), days > 0 {
                return (days == 1 ? .daily : .everyDays(days), range)
            }
        }
        return nil
    }
}
