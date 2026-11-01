import Foundation

/// Something that carries a time estimate in Power Hours.
public protocol Estimated {
    var estimate: Double { get }
}

/// Time estimates in Power Hours (PH): one PH is 50 minutes of focused work.
public enum PowerHours {
    public static let minutesPerPH = 50.0
    /// Quick picks wherever an estimate is set.
    public static let presets: [Double] = [0.25, 0.5, 0.75, 1, 2]

    /// "0,25" (in the user's locale) without the unit.
    public static func number(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// "0,25 PH".
    public static func format(_ value: Double, locale: Locale = .current) -> String {
        number(value, locale: locale) + " PH"
    }

    /// Finds an estimate like "(0,25PH)", "0.5ph" or "2 PH" in text, with its range for removal.
    public static func find(in text: String) -> (value: Double, range: Range<String.Index>)? {
        guard let range = text.range(of: #"\(?\s*\d+(?:[.,]\d+)?\s*ph\b\s*\)?"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let match = text[range]
        guard let numberRange = match.range(of: #"\d+(?:[.,]\d+)?"#, options: .regularExpression),
              let value = Double(match[numberRange].replacingOccurrences(of: ",", with: ".")),
              value > 0 else { return nil }
        return (value, range)
    }

    /// Parses what someone typed as a custom estimate ("1,5", "1.5", "1,5 PH").
    public static func parse(_ text: String) -> Double? {
        let cleaned = text.lowercased().replacingOccurrences(of: "ph", with: "").replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0, value < 1000 else { return nil }
        return value
    }

    /// Total estimate of one section's lines. A line's own estimate counts only when none of its
    /// subtasks has one; otherwise the subtasks are the plan, so totals written on parent lines
    /// aren't counted twice.
    public static func total<Item: ChecklistItem & Estimated>(_ items: [Item], where include: (Item) -> Bool = { _ in true }) -> Double {
        let sorted = items.sorted { $0.sortOrder < $1.sortOrder }
        let depths = Checklist.depths(of: sorted)
        var sum = 0.0
        for index in sorted.indices where sorted[index].estimate > 0 && include(sorted[index]) {
            let end = Checklist.blockEnd(after: index, depths: depths)
            let subtaskHasEstimate = (index + 1 ..< end).contains { sorted[$0].estimate > 0 }
            if !subtaskHasEstimate { sum += sorted[index].estimate }
        }
        return sum
    }
}
