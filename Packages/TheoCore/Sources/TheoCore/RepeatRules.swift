import Foundation

extension ParsedEntry {
    /// Something that repeats needs a first date: without one it gets `today` (no time), so
    /// checking it off files the next occurrence. Applied wherever a task is created, so the
    /// composer, pasted lists, the menu bar and the Watch all behave the same.
    public func withFirstOccurrence(today: Date, calendar: Calendar = .current) -> ParsedEntry {
        guard recurrence != nil, due == nil else { return self }
        var entry = self
        entry.due = calendar.startOfDay(for: today)
        entry.dueHasTime = false
        return entry
    }
}

extension Recurrence {
    /// Monthly and yearly repeats keep the day they started on (the 31st, 29 February)
    /// instead of drifting to the shortest month's last day for good.
    public var keepsDayOfMonth: Bool {
        switch self {
        case .monthly, .yearly: true
        default: false
        }
    }

    /// The next occurrence after `date`, keeping its time of day. Monthly and yearly repeats
    /// land on `anchorDay` (nil = `date`'s own day), or on the month's last day when the month
    /// is shorter: 31 Jan → 28 Feb → 31 Mar → 30 Apr.
    public func next(after date: Date, anchorDay: Int?, calendar: Calendar = .current) -> Date {
        guard keepsDayOfMonth else { return next(after: date, calendar: calendar) }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var monthStart = DateComponents()
        monthStart.year = parts.year
        monthStart.month = parts.month
        monthStart.day = 1
        monthStart.hour = 12
        let step: Calendar.Component = self == .monthly ? .month : .year
        guard let first = calendar.date(from: monthStart),
              let target = calendar.date(byAdding: step, value: 1, to: first),
              let days = calendar.range(of: .day, in: .month, for: target) else {
            return next(after: date, calendar: calendar)
        }
        var result = calendar.dateComponents([.year, .month], from: target)
        result.day = min(max(1, anchorDay ?? parts.day ?? 1), days.count)
        result.hour = parts.hour
        result.minute = parts.minute
        result.second = parts.second
        return calendar.date(from: result) ?? next(after: date, calendar: calendar)
    }

    /// The first occurrence after `due` that isn't before `notBefore`, so an overdue repeat
    /// catches up instead of filing occurrences that are already past.
    public func nextOccurrence(after due: Date, notBefore: Date, anchorDay: Int?, calendar: Calendar = .current) -> Date {
        var result = next(after: due, anchorDay: anchorDay, calendar: calendar)
        var steps = 0
        while result < notBefore && steps < 1000 {
            result = next(after: result, anchorDay: anchorDay, calendar: calendar)
            steps += 1
        }
        return result
    }
}
