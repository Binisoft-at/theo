import Foundation

/// How a task with a deadline repeats. Completing it creates the next occurrence.
public enum Recurrence: Hashable, Sendable {
    case daily
    case weekdays
    case weekly
    case monthly
    case yearly
    case everyDays(Int)

    /// The choices every Repeat menu offers.
    public static let common: [Recurrence] = [.daily, .weekdays, .weekly, .everyDays(14), .monthly, .yearly]

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
        case .daily: return "Every Day"
        case .weekdays: return "Every Weekday"
        case .weekly: return "Every Week"
        case .monthly: return "Every Month"
        case .yearly: return "Every Year"
        case .everyDays(let days):
            if days == 1 { return "Every Day" }
            if days % 7 == 0 { return days == 7 ? "Every Week" : "Every \(days / 7) Weeks" }
            return "Every \(days) Days"
        }
    }

    /// Like `title`, but a weekly repeat names its day: "Every Monday" (from the first due date).
    public func title(firstDue: Date?, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard self == .weekly, let firstDue else { return title }
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return "Every " + firstDue.formatted(style)
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

    private static let weekdayPattern = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend|sonntag"
    private static let numberPattern = #"\d+|one|two|three|four|five|six|seven|eight|nine|ten|zwei|zwo|drei|vier|fünf|sechs|sieben|acht|neun|zehn"#
    private static let everyWeekdayPattern: String = #"\b(?:every|jeden|jede|jeder)\s+(?:"# + weekdayPattern + #")\b"#
    private static let everyWeeksPattern: String = #"\b(?:every|alle)\s+(?:"# + numberPattern + #")\s+(?:weeks?|wochen?)\b"#
    private static let everyDaysPattern: String = #"\b(?:every|alle)\s+(?:"# + numberPattern + #")\s+(?:days|tage)\b"#

    private enum Kind {
        case fixed(Recurrence)
        /// "every Monday", "jeden Montag": weekly from the next such day.
        case weekday
        /// "every 2 weeks", "alle drei Wochen".
        case weeks
        /// "every 3 days", "alle 3 Tage".
        case days
    }

    /// Tried in order; the first match wins.
    private static let patterns: [(String, Kind)] = [
        (everyWeekdayPattern, .weekday),
        (#"\b(?:every\s+(?:morning|evening)|jeden\s+(?:morgen|abend))\b"#, .fixed(.daily)),
        (#"\b(?:every\s+other\s+week|every\s+second\s+week|bi-?weekly|fortnightly|zweiwöchentlich|jede\s+zweite\s+woche)\b"#, .fixed(.everyDays(14))),
        (everyWeeksPattern, .weeks),
        (everyDaysPattern, .days),
        (#"\b(?:every\s+weekday|weekdays|werktags|jeden\s+werktag)\b"#, .fixed(.weekdays)),
        (#"\b(?:every\s+day|daily|täglich|jeden\s+tag)\b"#, .fixed(.daily)),
        (#"\b(?:every\s+week|weekly|wöchentlich|jede\s+woche)\b"#, .fixed(.weekly)),
        (#"\b(?:every\s+month|monthly|monatlich|jeden\s+monat)\b"#, .fixed(.monthly)),
        (#"\b(?:every\s+year|yearly|annually|jährlich|jedes\s+jahr)\b"#, .fixed(.yearly)),
    ]

    /// Finds "every day", "weekly", "täglich", "every 3 days" ... in text, with its range.
    public static func find(in text: String) -> (recurrence: Recurrence, range: Range<String.Index>)? {
        guard let found = find(in: text, today: Date()) else { return nil }
        return (recurrence: found.recurrence, range: found.range)
    }

    /// Also "every Monday" / "jeden Montag" (weekly, `firstDue` = the next Monday from `today`,
    /// today included), "every other week" / "alle zwei Wochen" (every 14 days) and "every 3
    /// weeks". `firstDue` is nil when the repeat doesn't name a day.
    public static func find(in text: String, today: Date, calendar: Calendar = .current)
        -> (recurrence: Recurrence, range: Range<String.Index>, firstDue: Date?)? {
        for (pattern, kind) in patterns {
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            let words = text[range].lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
            switch kind {
            case .fixed(let recurrence):
                return (recurrence: recurrence, range: range, firstDue: nil)
            case .weekday:
                guard let name = words.last, let weekday = RelativeDate.weekdayNames[name] else { continue }
                let first = RelativeDate.nextWeekday(weekday, from: calendar.startOfDay(for: today), calendar: calendar)
                return (recurrence: .weekly, range: range, firstDue: first)
            case .weeks:
                guard let amount = number(in: words) else { continue }
                return (recurrence: amount == 1 ? Recurrence.weekly : Recurrence.everyDays(amount * 7), range: range, firstDue: nil)
            case .days:
                guard let amount = number(in: words) else { continue }
                return (recurrence: amount == 1 ? Recurrence.daily : Recurrence.everyDays(amount), range: range, firstDue: nil)
            }
        }
        return nil
    }

    /// The number in "every 3 weeks" / "alle drei Wochen".
    private static func number(in words: [String]) -> Int? {
        guard words.count >= 3, let value = Int(words[1]) ?? RelativeDate.numberWords[words[1]], value > 0, value <= 999 else { return nil }
        return value
    }
}
