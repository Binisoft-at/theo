import Foundation

/// When to be notified about a task with a time: offsets in minutes before the time. Negative
/// offsets are follow-up nudges after the time.
public enum Reminders {
    /// Quick picks: at the time, 5/15/30 minutes, 1/2 hours and 1/2 days before.
    public static let presets: [Int] = [0, 5, 15, 30, 60, 120, 1440, 2880]

    /// Stored form: "" is the default (a notification at the time), "off" is none, otherwise
    /// comma-separated minutes.
    public static func offsets(from raw: String) -> [Int] {
        switch raw {
        case "": return [0]
        case "off": return []
        default:
            let values = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return Array(Set(values)).sorted(by: >)
        }
    }

    public static func raw(for offsets: [Int]) -> String {
        let unique = Array(Set(offsets)).sorted(by: >)
        if unique.isEmpty { return "off" }
        if unique == [0] { return "" }
        return unique.map(String.init).joined(separator: ",")
    }

    /// Follow-up nudges after the time: `count` notifications, `every` minutes apart.
    public static func nudges(count: Int, every minutes: Int) -> [Int] {
        guard count > 0, minutes > 0 else { return [] }
        return (1...count).map { -$0 * minutes }
    }

    /// "At time", "15 min before", "1 h 30 min before", "1 day before", "10 min after".
    public static func describe(_ minutes: Int) -> String {
        if minutes == 0 { return "At time" }
        let amount = abs(minutes)
        let text: String
        if amount % 1440 == 0 {
            let days = amount / 1440
            text = days == 1 ? "1 day" : "\(days) days"
        } else if amount >= 60 {
            text = amount % 60 == 0 ? "\(amount / 60) h" : "\(amount / 60) h \(amount % 60) min"
        } else {
            text = "\(amount) min"
        }
        return text + (minutes > 0 ? " before" : " after")
    }

    /// The moments to notify that are still ahead, in order.
    public static func fireDates(due: Date, offsets: [Int], after now: Date) -> [Date] {
        offsets.map { due.addingTimeInterval(-Double($0) * 60) }.filter { $0 > now }.sorted()
    }
}

// MARK: - Notification hygiene

extension Reminders {
    /// Every Theo reminder request starts with this, followed by its task's UUID:
    /// "theo.task.<uuid>.<offset>" for the reminders, "theo.task.<uuid>.snooze" for a snooze.
    public static let idPrefix = "theo.task."
    /// Snoozes made by earlier versions: "theo.snooze.<uuid>".
    public static let legacySnoozePrefix = "theo.snooze."
    static let snoozeSuffix = ".snooze"

    /// The request for one reminder of a task.
    public static func identifier(task: UUID, offset: Int) -> String {
        idPrefix + task.uuidString + "." + String(offset)
    }

    /// One snooze per task, so a second snooze replaces the first.
    public static func snoozeIdentifier(task: UUID) -> String {
        idPrefix + task.uuidString + snoozeSuffix
    }

    public static func isSnooze(_ identifier: String) -> Bool {
        identifier.hasPrefix(legacySnoozePrefix)
            || (identifier.hasPrefix(idPrefix) && identifier.hasSuffix(snoozeSuffix))
    }

    /// The task a Theo reminder belongs to; nil for anything else (the focus timer, say).
    public static func taskID(in identifier: String) -> UUID? {
        let rest: Substring
        if identifier.hasPrefix(idPrefix) {
            rest = identifier.dropFirst(idPrefix.count)
        } else if identifier.hasPrefix(legacySnoozePrefix) {
            rest = identifier.dropFirst(legacySnoozePrefix.count)
        } else {
            return nil
        }
        // A UUID string is 36 characters; what follows is the offset or ".snooze".
        return UUID(uuidString: String(rest.prefix(36)))
    }

    /// Notifications to take away: those of tasks that no longer want reminders (done,
    /// deleted, without a time, reminders off, in a switched-off group). Anything that
    /// belongs to no task stays.
    public static func staleIdentifiers(_ items: [(id: String, taskID: UUID?)], keep: Set<UUID>) -> [String] {
        items.compactMap { item -> String? in
            guard let task = item.taskID, !keep.contains(task) else { return nil }
            return item.id
        }
    }

    /// Pending requests to remove before the reminders are rebuilt: every regular Theo
    /// reminder (they are added again from the tasks), plus the snoozes, old-style ones
    /// included, of tasks that no longer want reminders. A snooze of a task that still
    /// does stays until it fires.
    public static func pendingToRemove(_ identifiers: [String], keep: Set<UUID>) -> [String] {
        var regular: [String] = []
        var snoozes: [(id: String, taskID: UUID?)] = []
        for id in identifiers {
            if isSnooze(id) {
                snoozes.append((id: id, taskID: Reminders.taskID(in: id)))
            } else if id.hasPrefix(idPrefix) {
                regular.append(id)
            }
        }
        return regular + staleIdentifiers(snoozes, keep: keep)
    }

    /// "Tomorrow" or "Next Week" from a banner moves the deadline to that day only when it is
    /// earlier, so a reminder sent days ahead never pulls a deadline closer.
    public static func pushesDeadline(_ due: Date?, by days: Int, today: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return false }
        return DateText.dayDelta(due, today: today, calendar: calendar) < days
    }

    /// An ongoing task never finishes: once it was checked off from its earliest reminder for
    /// the current deadline on, the remaining reminders for that deadline are moot.
    public static func isSettled(lastDone: Date?, due: Date, offsets: [Int]) -> Bool {
        guard let lastDone, let earliest = offsets.max() else { return false }
        return lastDone >= due.addingTimeInterval(-Double(earliest) * 60)
    }
}
