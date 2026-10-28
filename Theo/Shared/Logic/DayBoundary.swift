import Foundation

/// Theo thinks in "logical days" like a daily note: a day starts at a configurable hour
/// (default 4:00) so late-night work still belongs to the day it started.
struct DayBoundary {
    var startHour: Int
    var calendar: Calendar = .current

    init(startHour: Int = DayBoundary.storedStartHour) {
        self.startHour = min(max(startHour, 0), 12)
    }

    static var storedStartHour: Int {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Prefs.dayStartHour) == nil { return 4 }
        return defaults.integer(forKey: Prefs.dayStartHour)
    }

    /// Start of the logical day containing `date`.
    func start(of date: Date) -> Date {
        let shifted = date.addingTimeInterval(TimeInterval(-startHour * 3600))
        let midnight = calendar.startOfDay(for: shifted)
        return calendar.date(byAdding: .hour, value: startHour, to: midnight) ?? midnight
    }

    func end(ofDayStarting start: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    func dayStart(byAdding days: Int, to start: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    /// Whole logical days between two dates (0 = same day).
    func days(from: Date, to: Date) -> Int {
        let a = calendar.startOfDay(for: start(of: from))
        let b = calendar.startOfDay(for: start(of: to))
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

enum DateText {
    static func pageTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Calendar-day difference between a due date and the logical "today".
    static func dayDelta(_ date: Date, today: Date) -> Int {
        let cal = Calendar.current
        let a = cal.startOfDay(for: today)
        let b = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    static func due(_ date: Date, hasTime: Bool, today: Date) -> String {
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

    static func relativeSection(_ date: Date, today: Date) -> String {
        let delta = dayDelta(date, today: today)
        switch delta {
        case 0: return "Today"
        case -1: return "Yesterday"
        default: return pageTitle(date)
        }
    }
}

/// Quick picks used by menus and the date sheet.
enum QuickDate: String, CaseIterable, Identifiable {
    case today, tomorrow, weekend, nextWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .weekend: "This Weekend"
        case .nextWeek: "Next Week"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .tomorrow: "sunrise"
        case .weekend: "sofa"
        case .nextWeek: "calendar.badge.clock"
        }
    }

    func date(from today: Date) -> Date {
        let cal = Calendar.current
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
