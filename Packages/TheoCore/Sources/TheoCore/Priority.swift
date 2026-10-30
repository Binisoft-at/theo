import Foundation

/// Explicit priority on top of the implicit one (position on the page).
public enum Priority: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case normal = 0
    case low = 1
    case medium = 2
    case high = 3

    public var id: Int { rawValue }

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Reminders-style marks: "!", "!!", "!!!".
    public var marks: String { String(repeating: "!", count: rawValue) }

    public var title: String {
        switch self {
        case .normal: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public var symbol: String {
        switch self {
        case .normal: "minus"
        case .low: "exclamationmark"
        case .medium: "exclamationmark.2"
        case .high: "exclamationmark.3"
        }
    }
}

public enum Tags {
    /// Cleans, lowercases and de-duplicates tags, keeping their order.
    public static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in tags {
            let tag = clean(raw)
            guard !tag.isEmpty, !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)
        }
        return result
    }

    public static func clean(_ raw: String) -> String {
        var tag = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while tag.hasPrefix("#") { tag.removeFirst() }
        tag = tag.replacingOccurrences(of: ",", with: "")
        tag = tag.replacingOccurrences(of: " ", with: "-")
        return tag
    }
}
