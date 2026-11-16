import Foundation

/// What a quick entry understood, for the confirmation after adding:
/// "Work · due Friday · !! · 0,5 PH · ↻ Every Week · ∞". Defaults are left out (no priority,
/// the estimate every new task gets anyway), so a plain task reads just "Work".
public enum CaptureSummary {
    public static func describe(
        groupName: String?,
        due: Date?,
        dueHasTime: Bool,
        today: Date,
        priority: Priority,
        estimate: Double?,
        defaultEstimate: Double,
        recurrence: Recurrence?,
        ongoing: Bool,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var parts: [String] = []
        if let groupName, !groupName.isEmpty { parts.append(groupName) }
        if let due {
            parts.append("due " + dueLabel(due, hasTime: dueHasTime, today: today, calendar: calendar, locale: locale))
        }
        if priority != .normal { parts.append(priority.marks) }
        if let estimate, estimate > 0, abs(estimate - defaultEstimate) > 0.0001 {
            parts.append(PowerHours.format(estimate, locale: locale))
        }
        if let recurrence {
            parts.append("↻ " + recurrence.title(firstDue: due, calendar: calendar, locale: locale))
        }
        if ongoing { parts.append("∞") }
        return parts.joined(separator: " · ")
    }

    /// "today", "tomorrow", "Friday", "15 Dec" (plus the time), to follow "due" in a sentence.
    static func dueLabel(_ date: Date, hasTime: Bool, today: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle.dateTime
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        let delta = DateText.dayDelta(date, today: today, calendar: calendar)
        var label: String
        switch delta {
        case 0: label = "today"
        case 1: label = "tomorrow"
        case -1: label = "yesterday"
        case 2...6: label = date.formatted(style.weekday(.wide))
        default:
            let sameYear = calendar.isDate(date, equalTo: today, toGranularity: .year)
            label = sameYear
                ? date.formatted(style.day().month(.abbreviated))
                : date.formatted(style.day().month(.abbreviated).year())
        }
        if hasTime {
            label += " " + date.formatted(style.hour().minute())
        }
        return label
    }
}
