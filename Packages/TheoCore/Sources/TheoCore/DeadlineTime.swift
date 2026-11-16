import Foundation

/// The time a deadline gets when its time is switched on. A deadline picked as a day sits at
/// midnight, and midnight today has already passed, so no reminder could ever fire for it.
public enum DeadlineTime {
    /// Due on the logical day `today` at a time that has passed: the next full hour after
    /// `now`. Due at midnight on any other day: 9:00 that day. Anything else keeps its time.
    public static func suggested(for due: Date, today: Date, now: Date, calendar: Calendar = .current) -> Date {
        if calendar.isDate(due, inSameDayAs: today) {
            guard due <= now else { return due }
            return nextFullHour(after: now, calendar: calendar)
        }
        let midnight = calendar.startOfDay(for: due)
        guard due == midnight else { return due }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: midnight) ?? midnight
    }

    /// 10:20 → 11:00, 10:00 → 11:00.
    public static func nextFullHour(after now: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .hour, for: now)?.end ?? now.addingTimeInterval(3600)
    }
}

/// How long a task has been on the plan without being done: the days since its current run of
/// plans began (`plannedSince`, kept while it's carried over or moved to another day).
public enum PlanAge {
    /// Whole calendar days from the day the run began to the logical day starting at `today`
    /// (0 = planned today).
    public static func days(since: Date, today: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: since)
        let end = calendar.startOfDay(for: today)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// "Planned since Mon (3 days)"; a week or more names the date too. nil until it's been on
    /// the plan for a day.
    public static func describe(since: Date, today: Date, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        let count = days(since: since, today: today, calendar: calendar)
        guard count >= 1 else { return nil }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        if count >= 7 { style = style.day().month(.abbreviated) }
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        let length = count == 1 ? "1 day" : "\(count) days"
        return "Planned since \(since.formatted(style)) (\(length))"
    }
}
