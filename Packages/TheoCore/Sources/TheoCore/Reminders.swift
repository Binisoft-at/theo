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
