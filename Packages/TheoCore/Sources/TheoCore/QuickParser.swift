import Foundation

/// Result of parsing a quick-entry line such as
/// `Call mom tomorrow 5pm !! #family @home`.
public struct ParsedEntry: Equatable, Sendable {
    public var title: String
    public var priority: Priority
    public var due: Date?
    public var dueHasTime: Bool
    public var dueText: String?
    public var tags: [String]
    public var groupID: UUID?
    public var groupName: String?
    /// Power Hours ("(0,25PH)").
    public var estimate: Double?
    public var recurrence: Recurrence?
    /// An ongoing task ("∞", "laufend", "ongoing"): never finished, each check-off is logged.
    public var ongoing: Bool
    /// A description typed after " // " ("Call bank // ask about the fee").
    public var notes: String

    public init(
        title: String,
        priority: Priority = .normal,
        due: Date? = nil,
        dueHasTime: Bool = false,
        dueText: String? = nil,
        tags: [String] = [],
        groupID: UUID? = nil,
        groupName: String? = nil,
        estimate: Double? = nil,
        recurrence: Recurrence? = nil,
        ongoing: Bool = false,
        notes: String = ""
    ) {
        self.title = title
        self.priority = priority
        self.due = due
        self.dueHasTime = dueHasTime
        self.dueText = dueText
        self.tags = tags
        self.groupID = groupID
        self.groupName = groupName
        self.estimate = estimate
        self.recurrence = recurrence
        self.ongoing = ongoing
        self.notes = notes
    }

    public var hasExtras: Bool {
        priority != .normal || due != nil || !tags.isEmpty || groupID != nil || estimate != nil || recurrence != nil || ongoing
    }
}

/// Lightweight natural-language parser for fast entry.
///
/// - `!`, `!!`, `!!!` or `p3`/`p2`/`p1` set the priority
/// - `#tag` adds a tag
/// - `@group` files the task into a group (prefix match, spaces ignored)
/// - dates and times ("tomorrow 5pm", "morgen 9 Uhr", "bis Freitag", "am 15.12.", "oct 30")
///   become the deadline (see `RelativeDate`; Apple's date detector catches the rest)
/// - `📅 2026-11-04` or `due:2026-11-04` set an exact deadline (also understood by Import)
/// - `0,5PH` / `(1PH)` set the estimate in Power Hours
/// - `daily`, `weekly`, `every 3 days`, `täglich`, `jeden Montag`, `alle 2 Wochen` ... make it
///   repeat ("every Monday" also makes the next Monday the deadline)
/// - `∞`, `laufend`, `ongoing` or `andauernd` make it an ongoing task
/// - everything after ` // ` is the task's description
public enum QuickParser {
    public struct GroupRef: Sendable {
        public let id: UUID
        public let name: String

        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Options: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let dates = Options(rawValue: 1 << 0)
        public static let priority = Options(rawValue: 1 << 1)
        public static let tags = Options(rawValue: 1 << 2)
        public static let group = Options(rawValue: 1 << 3)
        public static let estimate = Options(rawValue: 1 << 4)
        public static let recurrence = Options(rawValue: 1 << 5)
        /// Only `📅 2026-11-04` / `due:2026-11-04`, never guessed dates (used by Import).
        public static let exactDates = Options(rawValue: 1 << 6)
        /// `∞`, `laufend`, `ongoing`, `andauernd`.
        public static let ongoing = Options(rawValue: 1 << 7)
        public static let all: Options = [.dates, .priority, .tags, .group, .estimate, .recurrence, .exactDates, .ongoing]

        /// Words (whole tokens) that make a task ongoing.
        public static let ongoingWords: Set<String> = ["∞", "laufend", "ongoing", "andauernd"]
    }

    private static let detector: NSDataDetector? = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// - Parameters:
    ///   - now: the logical day the words are measured from: "morgen" is the day after it.
    ///     Pass the start of the logical day (`app.dayStart`), so "tomorrow" typed at 01:30 is
    ///     still the day after the day you're in. Defaults to the moment of the call.
    ///   - clock: the current moment; a time alone ("um 9") that has passed is tomorrow's.
    public static func parse(
        _ fullText: String,
        groups: [GroupRef],
        options: Options = .all,
        now: Date = Date(),
        clock: Date = Date(),
        calendar: Calendar = .current
    ) -> ParsedEntry {
        let today = calendar.startOfDay(for: now)
        let split = splitNote(fullText)
        var entry = ParsedEntry(title: split.title.trimmingCharacters(in: .whitespacesAndNewlines))
        entry.notes = split.note
        var kept: [String] = []
        var source = split.title
        let text = split.title

        if options.contains(.exactDates) || options.contains(.dates), let found = exactDate(in: source, calendar: calendar) {
            entry.due = found.date
            entry.dueText = String(source[found.range])
            source.removeSubrange(found.range)
        }
        if options.contains(.estimate), let found = PowerHours.find(in: source) {
            entry.estimate = found.value
            source.replaceSubrange(found.range, with: " ")
        }
        // "every Monday": the first one is the deadline unless the text names another date.
        var repeatFirstDue: Date?
        if options.contains(.recurrence), let found = Recurrence.find(in: source, today: today, calendar: calendar) {
            entry.recurrence = found.recurrence
            repeatFirstDue = found.firstDue
            source.replaceSubrange(found.range, with: " ")
        }

        for token in source.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) {
            let lower = token.lowercased()
            if options.contains(.priority), let priority = priority(for: lower) {
                entry.priority = priority
                continue
            }
            if options.contains(.ongoing), Options.ongoingWords.contains(lower) {
                entry.ongoing = true
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

        if options.contains(.dates), entry.due == nil, !title.isEmpty {
            if let match = RelativeDate.find(in: title, today: today, now: clock, calendar: calendar) {
                // Our own reading wins; the detector would read "15.12" as a time.
                var remaining = title
                remaining.removeSubrange(match.range)
                remaining = cleanupAfterDateRemoval(remaining)
                if !remaining.isEmpty {
                    var due = match.date
                    // "Standup jeden Montag 9 Uhr": the time belongs to the first Monday.
                    if !match.hasDay, let first = repeatFirstDue {
                        let time = calendar.dateComponents([.hour, .minute], from: match.date)
                        due = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: first) ?? first
                    }
                    entry.due = match.hasTime ? due : calendar.startOfDay(for: due)
                    entry.dueHasTime = match.hasTime
                    entry.dueText = String(title[match.range])
                    title = remaining
                }
            } else if let detector {
                let range = NSRange(title.startIndex..., in: title)
                if let match = detector.matches(in: title, options: [], range: range).first,
                   let date = match.date,
                   let swiftRange = Range(match.range, in: title) {
                    let matched = String(title[swiftRange])
                    var remaining = title
                    remaining.removeSubrange(swiftRange)
                    remaining = cleanupAfterDateRemoval(remaining)
                    // Bare numbers ("09.09", "2026") are references more often than deadlines, and
                    // day words our own reading turned down ("am Morgen", "ab Montag") stay text.
                    let onlyDigits = matched.allSatisfy { $0.isNumber || $0 == "." || $0 == " " }
                    let declined = RelativeDate.tokenize(matched).contains { RelativeDate.knownWords.contains($0.word) }
                    let blocked = title[..<swiftRange.lowerBound].split(separator: " ").last
                        .map { RelativeDate.blockers.contains($0.lowercased()) } ?? false
                    if !remaining.isEmpty, !onlyDigits, !declined, !blocked {
                        let hasTime = containsTime(matched)
                        entry.due = hasTime ? date : calendar.startOfDay(for: date)
                        entry.dueHasTime = hasTime
                        entry.dueText = matched
                        title = remaining
                    }
                }
            }
        }
        if entry.due == nil, let repeatFirstDue {
            entry.due = repeatFirstDue
            entry.dueHasTime = false
        }

        entry.title = collapseSpaces(title)
        entry.tags = Tags.normalize(entry.tags)
        if entry.title.isEmpty {
            entry.title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return entry
    }

    /// "Call bank // ask about the fee" → ("Call bank", "ask about the fee"). Links like
    /// "https://…" aren't split: the separator needs a space on both sides.
    public static func splitNote(_ text: String) -> (title: String, note: String) {
        guard let range = text.range(of: " // ") else { return (text, "") }
        let note = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (String(text[..<range.lowerBound]), note)
    }

    /// `📅 2026-11-04` or `due:2026-11-04`.
    static func exactDate(in text: String, calendar: Calendar = .current) -> (date: Date, range: Range<String.Index>)? {
        guard let range = text.range(of: #"(?:📅|due:)\s*\d{4}-\d{2}-\d{2}"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let digits = text[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard digits.count == 3 else { return nil }
        var components = DateComponents()
        components.year = digits[0]
        components.month = digits[1]
        components.day = digits[2]
        guard let date = calendar.date(from: components) else { return nil }
        return (calendar.startOfDay(for: date), range)
    }

    public static func priority(for lower: String) -> Priority? {
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

    public static func matchGroup(_ query: String, in groups: [GroupRef]) -> GroupRef? {
        let q = squash(query)
        guard !q.isEmpty else { return nil }
        if let exact = groups.first(where: { squash($0.name) == q }) { return exact }
        if let prefix = groups.first(where: { squash($0.name).hasPrefix(q) }) { return prefix }
        return groups.first(where: { squash($0.name).contains(q) })
    }

    private static func squash(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Whether what the detector matched names a time: a colon time ("14:30"), am/pm, "Uhr" or a
    /// time word. A dotted "15.12" is a day and month, never a time.
    static func containsTime(_ s: String) -> Bool {
        let lower = s.lowercased()
        if lower.range(of: #"\b(?:noon|midnight|morning|evening|tonight|afternoon|night|o'clock|uhr)\b"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"\d\s*(?:am|pm|a\.m|p\.m)\b"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil { return true }
        if lower.range(of: #"\bat \d"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func cleanupAfterDateRemoval(_ s: String) -> String {
        var result = collapseSpaces(s)
        // "ab" stays: "ab Montag" (starting Monday) is never taken as a deadline.
        let danglers = [" at", " on", " by", " due", " until", " before", " for", " in", " from",
                        " bis", " am", " um", " zum", " für", " vor"]
        var changed = true
        while changed {
            changed = false
            for d in danglers where result.lowercased().hasSuffix(d) {
                result = String(result.dropLast(d.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        let leading = ["on ", "by ", "at ", "due ", "bis ", "am ", "um ", "zum "]
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
