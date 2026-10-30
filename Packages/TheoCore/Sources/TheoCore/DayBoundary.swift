import Foundation

/// Theo thinks in "logical days" like a daily note: a day starts at a configurable hour
/// (default 4:00) so late-night work still belongs to the day it started.
public struct DayBoundary: Sendable {
    public var startHour: Int
    public var calendar: Calendar

    public init(startHour: Int = 4, calendar: Calendar = .current) {
        self.startHour = min(max(startHour, 0), 12)
        self.calendar = calendar
    }

    /// Start of the logical day containing `date`.
    public func start(of date: Date) -> Date {
        let shifted = date.addingTimeInterval(TimeInterval(-startHour * 3600))
        let midnight = calendar.startOfDay(for: shifted)
        return calendar.date(byAdding: .hour, value: startHour, to: midnight) ?? midnight
    }

    public func end(ofDayStarting start: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    public func dayStart(byAdding days: Int, to start: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    /// Whole logical days between two dates (0 = same day).
    public func days(from: Date, to: Date) -> Int {
        let a = calendar.startOfDay(for: start(of: from))
        let b = calendar.startOfDay(for: start(of: to))
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

public enum DateText {
    public static func pageTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    public static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Calendar-day difference between a due date and the logical "today".
    public static func dayDelta(_ date: Date, today: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: today)
        let b = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    public static func due(_ date: Date, hasTime: Bool, today: Date) -> String {
        let delta = dayDelta(date, today: today)
        var label: String
        switch delta {
        case 0: label = "Today"
        case 1: label = "Tomorrow"
        case -1: label = "Yesterday"
        case 2...6: label = date.formatted(.dateTime.weekday(.wide))
        default:
            let sameYear = Calendar.current.isDate(date, equalTo: today, toGranularity: .year)
            label = sameYear
                ? date.formatted(.dateTime.day().month(.abbreviated))
                : date.formatted(.dateTime.day().month(.abbreviated).year())
        }
        if hasTime {
            label += " " + date.formatted(date: .omitted, time: .shortened)
        }
        return label
    }

    public static func relativeSection(_ date: Date, today: Date) -> String {
        switch dayDelta(date, today: today) {
        case 0: return "Today"
        case -1: return "Yesterday"
        default: return pageTitle(date)
        }
    }
}

/// Quick picks used by menus and the date sheet.
public enum QuickDate: String, CaseIterable, Identifiable, Sendable {
    case today, tomorrow, weekend, nextWeek

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .weekend: "This Weekend"
        case .nextWeek: "Next Week"
        }
    }

    public var symbol: String {
        switch self {
        case .today: "sun.max"
        case .tomorrow: "sunrise"
        case .weekend: "sofa"
        case .nextWeek: "calendar.badge.clock"
        }
    }

    public func date(from today: Date, calendar cal: Calendar = .current) -> Date {
        let base = cal.startOfDay(for: today)
        switch self {
        case .today:
            return base
        case .tomorrow:
            return cal.date(byAdding: .day, value: 1, to: base) ?? base
        case .weekend:
            // Next Saturday (or today if it already is Saturday).
            let weekday = cal.component(.weekday, from: base) // 1 = Sunday ... 7 = Saturday
            let offset = (7 - weekday + 7) % 7
            return cal.date(byAdding: .day, value: offset, to: base) ?? base
        case .nextWeek:
            // Next Monday.
            let weekday = cal.component(.weekday, from: base)
            var offset = (2 - weekday + 7) % 7
            if offset == 0 { offset = 7 }
            return cal.date(byAdding: .day, value: offset, to: base) ?? base
        }
    }
}
