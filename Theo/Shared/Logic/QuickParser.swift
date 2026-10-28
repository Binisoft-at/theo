import Foundation

/// Result of parsing a quick-entry line such as
/// `Call mom tomorrow 5pm !! #family @home`.
struct ParsedEntry: Equatable {
    var title: String
    var priority: Priority = .normal
    var due: Date?
    var dueHasTime = false
    var dueText: String?
    var tags: [String] = []
    var groupID: UUID?
    var groupName: String?

    var hasExtras: Bool {
        priority != .normal || due != nil || !tags.isEmpty || groupID != nil
    }
}

/// Lightweight natural-language parser for fast entry.
///
/// - `!`, `!!`, `!!!` or `p3`/`p2`/`p1` set the priority
/// - `#tag` adds a tag
/// - `@group` files the task into a group (prefix match, spaces ignored)
/// - dates and times ("tomorrow 5pm", "next friday", "oct 30") become the deadline
enum QuickParser {
    struct GroupRef {
        let id: UUID
        let name: String
    }

    struct Options: OptionSet {
        let rawValue: Int
        static let dates = Options(rawValue: 1 << 0)
        static let priority = Options(rawValue: 1 << 1)
        static let tags = Options(rawValue: 1 << 2)
        static let group = Options(rawValue: 1 << 3)
        static let all: Options = [.dates, .priority, .tags, .group]
    }

    private static let detector: NSDataDetector? = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func parse(_ text: String, groups: [GroupRef], options: Options = .all, now: Date = Date()) -> ParsedEntry {
        var entry = ParsedEntry(title: text.trimmingCharacters(in: .whitespacesAndNewlines))
        var kept: [String] = []

        for token in text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) {
            let lower = token.lowercased()
            if options.contains(.priority), let priority = priority(for: lower) {
                entry.priority = priority
                continue
            }
            if options.contains(.tags), token.count > 1, token.hasPrefix("#") {
                let tag = Tags.clean(token)
                if !tag.isEmpty, tag.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
                    entry.tags.append(tag)
                    continue
                }
            }
            if options.contains(.group), token.count > 1, token.hasPrefix("@"), let match = matchGroup(String(lower.dropFirst()), in: groups) {
                entry.groupID = match.id
                entry.groupName = match.name
                continue
            }
            kept.append(token)
        }

        var title = kept.joined(separator: " ")

        if options.contains(.dates), let detector, !title.isEmpty {
            let range = NSRange(title.startIndex..., in: title)
            if let match = detector.matches(in: title, options: [], range: range).first,
               let date = match.date,
               let swiftRange = Range(match.range, in: title) {
                let matched = String(title[swiftRange])
                var remaining = title
                remaining.removeSubrange(swiftRange)
                remaining = cleanupAfterDateRemoval(remaining)
                if !remaining.isEmpty {
                    let hasTime = containsTime(matched)
                    entry.due = hasTime ? date : Calendar.current.startOfDay(for: date)
                    entry.dueHasTime = hasTime
                    entry.dueText = matched
                    title = remaining
                }
            }
        }

        entry.title = collapseSpaces(title)
        entry.tags = Tags.normalize(entry.tags)
        if entry.title.isEmpty {
            entry.title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return entry
    }

    static func priority(for lower: String) -> Priority? {
        switch lower {
        case "!": .low
        case "!!": .medium
        case "!!!": .high
        case "p3": .low
        case "p2": .medium
        case "p1": .high
        default: nil
        }
    }

    static func matchGroup(_ query: String, in groups: [GroupRef]) -> GroupRef? {
        let q = squash(query)
        guard !q.isEmpty else { return nil }
        if let exact = groups.first(where: { squash($0.name) == q }) { return exact }
        if let prefix = groups.first(where: { squash($0.name).hasPrefix(q) }) { return prefix }
        return groups.first(where: { squash($0.name).contains(q) })
    }

    private static func squash(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func containsTime(_ s: String) -> Bool {
        let lower = s.lowercased()
        let words = ["am", "pm", "a.m", "p.m", "noon", "midnight", "morning", "evening", "tonight", "afternoon", "night", "o'clock", "uhr"]
        for word in words where lower.contains(word) { return true }
        if lower.range(of: #"\d{1,2}[:.]\d{2}"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"\bat \d"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func cleanupAfterDateRemoval(_ s: String) -> String {
        var result = collapseSpaces(s)
        let danglers = [" at", " on", " by", " due", " until", " before", " for", " in", " from"]
        var changed = true
        while changed {
            changed = false
            for d in danglers where result.lowercased().hasSuffix(d) {
                result = String(result.dropLast(d.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        let leading = ["on ", "by ", "at ", "due "]
        for d in leading where result.lowercased().hasPrefix(d) {
            result = String(result.dropFirst(d.count))
        }
        return result.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",-–")))
    }

    private static func collapseSpaces(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
