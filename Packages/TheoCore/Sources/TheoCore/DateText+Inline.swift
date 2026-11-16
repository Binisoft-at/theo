import Foundation

extension DateText {
    /// `due` for the middle of a sentence ("was due yesterday", "next tomorrow 09:00"):
    /// today, tomorrow and yesterday in lower case; weekdays and dates read as in `due`.
    public static func dueInline(_ date: Date, hasTime: Bool, today: Date) -> String {
        let label = due(date, hasTime: hasTime, today: today)
        switch dayDelta(date, today: today) {
        case -1, 0, 1:
            guard let first = label.first else { return label }
            return first.lowercased() + String(label.dropFirst())
        default:
            return label
        }
    }
}
