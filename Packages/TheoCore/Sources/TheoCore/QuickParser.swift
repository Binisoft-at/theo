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
/// - `@group` files the task into a group (prefix match, spaces ignored), `@Work/Admin` into the
///   subgroup Admin inside Work
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
        /// The group it sits in (it's a subgroup); nil = top level. Lets "@Work/Admin" find the
        /// subgroup Admin inside Work.
        public let parentID: UUID?

        public init(id: UUID, name: String, parentID: UUID? = nil) {
            self.id = id
            self.name = name
            self.parentID = parentID
        }

        /// Each group's names from the outermost group in, its own name last (["Work", "Admin"]).
        /// A parent that isn't in the list, or a loop, ends the path.
        public static func paths(_ groups: [GroupRef]) -> [UUID: [String]] {
            var byID: [UUID: GroupRef] = [:]
            for group in groups where byID[group.id] == nil {
                byID[group.id] = group
            }
            var result: [UUID: [String]] = [:]
            for group in groups {
                var names = [group.name]
                var seen: Set<UUID> = [group.id]
                var current = group
                while let parentID = current.parentID, !seen.contains(parentID), let parent = byID[parentID] {
                    names.insert(parent.name, at: 0)
                    seen.insert(parentID)
                    current = parent
                }
                result[group.id] = names
            }
            return result
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

    #if canImport(Darwin)
    private static let detector: NSDataDetector? = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    #endif

    /// The first date Apple's date detector finds in `text`. Linux's Foundation has no detector:
    /// there only Theo's own reading (`RelativeDate`) understands dates.
    private static func detectedDate(in text: String) -> (date: Date, range: Range<String.Index>)? {
        #if canImport(Darwin)
        guard let detector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.matches(in: text, options: [], range: range).first, let date = match.date,
              let found = Range(match.range, in: text) else { return nil }
        return (date, found)
        #else
        return nil
        #endif
    }

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
                remaining = cleanupAfterDateRemoval(remaining, leading: false)
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
            } else if let detected = detectedDate(in: title) {
                let date = detected.date
                let swiftRange = detected.range
                do {
                    let matched = String(title[swiftRange])
                    var remaining = title
                    remaining.removeSubrange(swiftRange)
                    remaining = cleanupAfterDateRemoval(remaining)
                    // Bare numbers ("09.09", "2026") are references more often than deadlines, and
                    // day words our own reading turned down ("am Morgen", "ab Montag") stay text,
                    // like a part of the day alone ("Joggen morgens" is a habit, not a deadline).
                    let onlyDigits = matched.allSatisfy { $0.isNumber || $0 == "." || $0 == " " }
                    let words = RelativeDate.tokenize(matched)
                    let declined = words.contains { RelativeDate.knownWords.contains($0.word) }
                        || words.allSatisfy { RelativeDate.dayParts.contains($0.word) }
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

    /// `query` is what follows the `@`: a name ("admin", exact first, then the start of a name,
    /// then a part of one) or a path to a subgroup ("work/admin"). Case, accents and spaces
    /// don't matter. Two groups of the same name: the one less deep wins, so "@Work" is the
    /// top-level Work.
    public static func matchGroup(_ query: String, in groups: [GroupRef]) -> GroupRef? {
        let parts = query.split(separator: "/").map { squash(String($0)) }.filter { !$0.isEmpty }
        if parts.count > 1, let match = matchPath(parts, in: groups) { return match }
        // A name read whole, also a slash in a name ("Q3/Q4") and "work/" (Work itself).
        let q = squash(query)
        guard !q.isEmpty else { return nil }
        let exact = groups.filter { squash($0.name) == q }
        if exact.count > 1 {
            let paths = GroupRef.paths(groups)
            var best = exact[0]
            var bestDepth = paths[best.id]?.count ?? 1
            for group in exact.dropFirst() {
                let depth = paths[group.id]?.count ?? 1
                if depth < bestDepth {
                    best = group
                    bestDepth = depth
                }
            }
            return best
        }
        if let only = exact.first { return only }
        if let prefix = groups.first(where: { squash($0.name).hasPrefix(q) }) { return prefix }
        return groups.first(where: { squash($0.name).contains(q) })
    }

    /// "work/admin": the group whose path ends in those names (Admin inside Work). Every name
    /// equal first, then each the start of its name ("wo/adm"), then the last one only a part
    /// of its name; less deep first, then in list order.
    private static func matchPath(_ parts: [String], in groups: [GroupRef]) -> GroupRef? {
        let paths = GroupRef.paths(groups)
        var best: (group: GroupRef, rank: Int, depth: Int)?
        for group in groups {
            let names = (paths[group.id] ?? [group.name]).map { squash($0) }
            guard names.count >= parts.count else { continue }
            let tail = Array(names.suffix(parts.count))
            let pairs = Array(zip(tail, parts))
            let rank: Int
            if tail == parts {
                rank = 0
            } else if pairs.allSatisfy({ pair in pair.0.hasPrefix(pair.1) }) {
                rank = 1
            } else if pairs.dropLast().allSatisfy({ pair in pair.0.hasPrefix(pair.1) }),
                      let last = pairs.last, last.0.contains(last.1) {
                rank = 2
            } else {
                continue
            }
            if let current = best, (current.rank, current.depth) <= (rank, names.count) { continue }
            best = (group, rank, names.count)
        }
        return best?.group
    }

    /// Lower case, no accents, letters and digits only: "Büro 2" → "buro2".
    private static func squash(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
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

    /// - Parameter leading: also drop a connector left at the start ("by oct 30 send it"). Off
    ///   for our own reading, whose match already took its connectors, so "Zum Arzt gehen morgen"
    ///   keeps "Zum".
    private static func cleanupAfterDateRemoval(_ s: String, leading: Bool = true) -> String {
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
        if leading {
            for d in ["on ", "by ", "at ", "due ", "bis ", "am ", "um ", "zum "] where result.lowercased().hasPrefix(d) {
                result = String(result.dropFirst(d.count))
            }
        }
        return result.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",-–")))
    }

    private static func collapseSpaces(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
