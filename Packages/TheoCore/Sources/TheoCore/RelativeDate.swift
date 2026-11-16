import Foundation

/// Dates and times the way people type them, in English and German: "morgen", "bis Freitag",
/// "next week", "in 3 Tagen", "am 15.12. um 14 Uhr", "tomorrow 5pm". Deterministic and measured
/// from the logical day, so "morgen" typed at 01:30 means the day after the day you're still in.
///
/// Whole words only: "Morgenroutine" or "Montagsmeeting" never match, and short weekdays
/// ("fr", "do", "mon") count only right after a connector ("bis Fr") or capitalised right
/// before a time ("Mi 15 Uhr"), so "Mail an Fr. Müller" or "do the laundry" stay text.
/// "Morgen" as a noun ("am Morgen", "guten Morgen") isn't a date, and "ab Montag" (starting
/// Monday) isn't a deadline. A part of the day goes with its day or time ("heute Abend",
/// "morgen früh", "um 8 abends" = 20:00).
public enum RelativeDate {
    public struct Match: Equatable, Sendable {
        /// Start of the day, or that day at the time when `hasTime`.
        public var date: Date
        public var hasTime: Bool
        /// False for a time alone ("um 9"): today at that time, or tomorrow once it has passed.
        public var hasDay: Bool
        /// The words that were taken, with the connectors right before them ("bis Freitag").
        public var range: Range<String.Index>

        public init(date: Date, hasTime: Bool, hasDay: Bool = true, range: Range<String.Index>) {
            self.date = date
            self.hasTime = hasTime
            self.hasDay = hasDay
            self.range = range
        }
    }

    /// The first date (with a time right before or after it), else the first time alone.
    /// - Parameters:
    ///   - today: the start of the logical day (only its calendar day counts).
    ///   - now: the current moment; a time alone that has already passed moves to tomorrow.
    ///     nil leaves it on today.
    public static func find(in text: String, today: Date, now: Date? = nil, calendar: Calendar = .current) -> Match? {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return nil }
        let base = calendar.startOfDay(for: today)
        let reader = WordReader(tokens: tokens, base: base, calendar: calendar)

        for index in tokens.indices {
            guard let day = reader.day(at: index) else { continue }
            var start = index
            var end = day.end
            // "heute Abend", "morgen früh", "Freitag Nachmittag": the part of the day goes too.
            var later = false
            if let isLater = reader.dayPart(at: end, after: tokens[end - 1].word) {
                later = isLater
                end += 1
            }
            var time: (hour: Int, minute: Int)?
            if let after = reader.time(at: end) {
                time = (hour: after.hour, minute: after.minute)
                end = after.end
                if let isLater = reader.dayPart(at: end) {
                    later = later || isLater
                    end += 1
                }
            } else if let before = reader.time(endingAt: index) {
                time = (hour: before.hour, minute: before.minute)
                start = before.start
            }
            if start > 0, blockers.contains(tokens[start - 1].word) { continue }
            start = reader.connectorStart(before: start)
            let date: Date
            if let time {
                let hour = later && (1...11).contains(time.hour) ? time.hour + 12 : time.hour
                guard let timed = calendar.date(bySettingHour: hour, minute: time.minute, second: 0, of: day.date) else { continue }
                date = timed
            } else {
                date = day.date
            }
            return Match(date: date, hasTime: time != nil, range: tokens[start].range.lowerBound ..< tokens[end - 1].range.upperBound)
        }

        for index in tokens.indices {
            guard let time = reader.time(at: index) else { continue }
            if index > 0, blockers.contains(tokens[index - 1].word) { continue }
            var end = time.end
            var hour = time.hour
            // "um 8 abends" is 20:00, "um 7 morgens" 07:00.
            if let isLater = reader.dayPart(at: end) {
                if isLater, (1...11).contains(hour) { hour += 12 }
                end += 1
            }
            guard var date = calendar.date(bySettingHour: hour, minute: time.minute, second: 0, of: base) else { continue }
            if let now, date <= now {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
            let start = reader.connectorStart(before: index)
            return Match(date: date, hasTime: true, hasDay: false, range: tokens[start].range.lowerBound ..< tokens[end - 1].range.upperBound)
        }
        return nil
    }

    // MARK: - Words

    /// Calendar weekdays (1 = Sunday … 7 = Saturday) by their full names.
    static let weekdayNames: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5, "freitag": 6, "samstag": 7, "sonnabend": 7,
    ]

    /// Short names; they only count after a connector, after "next", or capitalised before a time.
    static let shortWeekdays: [String: Int] = [
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7,
        "so": 1, "mo": 2, "di": 3, "mi": 4, "do": 5, "fr": 6, "sa": 7,
    ]

    /// Parts of the day that go with a day or a time ("heute Abend", "morgen früh", "um 8 abends").
    /// They set no time of their own.
    static let dayParts: Set<String> = [
        "früh", "morgens", "vormittag", "vormittags", "mittag", "mittags", "nachmittag", "nachmittags",
        "abend", "abends", "nacht", "nachts", "morning", "afternoon", "evening", "night",
    ]

    /// After these an hour from 1 to 11 is in the afternoon or evening: "heute Abend um 8" is 20:00.
    static let laterDayParts: Set<String> = ["nachmittag", "nachmittags", "abend", "abends", "afternoon", "evening"]

    /// Day words this reader knows. When it turned them down ("am Morgen", "Mail an Fr. Müller",
    /// "ab Montag"), the system's date detector mustn't take them either.
    static let knownWords: Set<String> = Set(weekdayNames.keys).union(shortWeekdays.keys)
        .union(["heute", "morgen", "übermorgen", "today", "tomorrow"])

    /// "in a week", "in drei Tagen", "alle zwei Wochen".
    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "ein": 1, "eine": 1, "einem": 1, "einen": 1, "einer": 1, "eins": 1, "zwei": 2, "zwo": 2, "drei": 3, "vier": 4,
        "fünf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9, "zehn": 10,
    ]

    /// Taken along with the date, at most two of them ("bis zum 15.12.").
    static let connectors: Set<String> = [
        "am", "bis", "um", "zum", "vor", "für", "spätestens",
        "on", "by", "at", "due", "until", "before", "for",
    ]

    /// After one of these a day.month date is a deadline even when it's far off or past.
    static let dateConnectors: Set<String> = [
        "am", "bis", "zum", "vor", "für", "spätestens", "on", "by", "due", "until", "before", "for",
    ]

    /// After one of these a short weekday ("bis Fr", "by fri") is a date, German names after
    /// German words and English after English, so "work on so many things" stays text.
    static let shortDayConnectors: Set<String> = ["am", "bis", "zum", "vor", "spätestens", "on", "by", "due", "until", "before"]
    static let englishDayConnectors: Set<String> = ["on", "by", "due", "until", "before"]
    static let englishShortWeekdays: Set<String> = ["sun", "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat"]

    /// A date right after these isn't a deadline: "ab Montag" means starting then, and
    /// "every Monday" / "jeden Montag" is a repeat.
    static let blockers: Set<String> = ["ab", "every", "jeden", "jede", "jeder", "alle"]

    static let nextWords: Set<String> = ["next", "nächsten", "nächste", "nächster", "nächstes", "kommenden", "kommende", "kommender"]
    static let thisWords: Set<String> = ["this", "diesen", "diese", "dieser", "dieses"]

    /// Words before "Morgen" that make it the noun (the morning), not tomorrow.
    static let morningArticles: Set<String> = [
        "am", "jeden", "jede", "jeder", "guten", "den", "der", "dem", "des", "diesen", "diesem", "dieser",
        "heute", "gestern", "ein", "einen", "eines", "schönen", "frühen", "zum", "vom", "every", "this",
    ]

    /// The next `weekday` (1 = Sunday … 7 = Saturday) from `base`, today included.
    static func nextWeekday(_ weekday: Int, from base: Date, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: base)
        let offset = (weekday - current + 7) % 7
        return calendar.date(byAdding: .day, value: offset, to: base) ?? base
    }

    /// "next Friday": the next such day after today, a week later when that day is still in this
    /// (Monday-based) week.
    static func weekdayNextWeek(_ weekday: Int, from base: Date, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: base)
        var offset = (weekday - current + 7) % 7
        if offset == 0 { offset = 7 }
        let daysSinceMonday = (current + 5) % 7
        if offset <= 6 - daysSinceMonday { offset += 7 }
        return calendar.date(byAdding: .day, value: offset, to: base) ?? base
    }

    // MARK: - Tokens

    struct Token {
        /// As typed, without surrounding brackets, quotes or commas.
        let raw: String
        /// Lower-cased, keeping dots ("15.12.", "fr.").
        let lower: String
        /// Lower-cased without a trailing dot or colon ("fr", "morgen").
        let word: String
        let range: Range<String.Index>
    }

    private static let edgeCharacters: Set<Character> = [
        "(", ")", "[", "]", "{", "}", ",", ";", "!", "?", "\"", "'", "„", "“", "”", "«", "»", "‚", "‘", "’",
    ]

    static func tokenize(_ text: String) -> [Token] {
        var result: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            guard index < text.endIndex else { break }
            var end = index
            while end < text.endIndex, !text[end].isWhitespace { end = text.index(after: end) }
            var lower = index
            var upper = end
            while lower < upper, edgeCharacters.contains(text[lower]) { lower = text.index(after: lower) }
            while upper > lower, edgeCharacters.contains(text[text.index(before: upper)]) { upper = text.index(before: upper) }
            if lower < upper {
                let raw = String(text[lower ..< upper])
                let lowered = raw.lowercased()
                var word = lowered
                while word.count > 1, let last = word.last, last == "." || last == ":" { word.removeLast() }
                result.append(Token(raw: raw, lower: lowered, word: word, range: lower ..< upper))
            }
            index = end
        }
        return result
    }

    // MARK: - Reading days and times

    private struct WordReader {
        let tokens: [Token]
        let base: Date
        let calendar: Calendar

        func word(_ index: Int) -> String? {
            index >= 0 && index < tokens.count ? tokens[index].word : nil
        }

        func days(_ value: Int) -> Date {
            calendar.date(byAdding: .day, value: value, to: base) ?? base
        }

        /// A part of the day at `index` ("Abend", "früh", "evening"); after "heute" also "Morgen"
        /// (this morning). nil when there's none; true when it moves an hour from 1 to 11 past
        /// noon ("Abend", "nachmittags").
        func dayPart(at index: Int, after previous: String? = nil) -> Bool? {
            guard let w = word(index) else { return nil }
            if w == "morgen", previous == "heute" || previous == "today" { return false }
            guard RelativeDate.dayParts.contains(w) else { return nil }
            return RelativeDate.laterDayParts.contains(w)
        }

        /// Steps back over up to two connectors right before `index`.
        func connectorStart(before index: Int) -> Int {
            var start = index
            while start > 0, index - start < 2, RelativeDate.connectors.contains(tokens[start - 1].word) {
                // "9 am Montag": an "am" right after a number belongs to the time, not the date.
                if tokens[start - 1].word == "am", start >= 2, Int(tokens[start - 2].word) != nil { break }
                start -= 1
            }
            return start
        }

        /// A day starting at `index`, with the index after its last word.
        func day(at index: Int) -> (date: Date, end: Int)? {
            guard let w = word(index) else { return nil }
            let previous = word(index - 1)

            switch w {
            case "heute", "today":
                return (days(0), index + 1)
            case "tomorrow":
                return (days(1), index + 1)
            case "morgen":
                guard isTomorrow(at: index) else { return nil }
                return (days(1), index + 1)
            case "übermorgen", "uebermorgen":
                return (days(2), index + 1)
            case "the":
                if word(index + 1) == "day", word(index + 2) == "after", word(index + 3) == "tomorrow" { return (days(2), index + 4) }
                if word(index + 1) == "weekend" { return (QuickDate.weekend.date(from: base, calendar: calendar), index + 2) }
                if word(index + 1) == "end", word(index + 2) == "of", let month = word(index + 3), month == "month" || month == "the" {
                    return endOfMonth(at: index + 1)
                }
                return nil
            case "day":
                if word(index + 1) == "after", word(index + 2) == "tomorrow" { return (days(2), index + 3) }
                return nil
            case "monatsende":
                return endOfMonth(at: index)
            case "end", "ende":
                return endOfMonth(at: index)
            case "in":
                return inSomeDays(at: index)
            case "weekend", "wochenende":
                // Only "am Wochenende", "bis Wochenende", "on weekend": alone it's just a word.
                guard let previous, RelativeDate.connectors.contains(previous) else { return nil }
                return (QuickDate.weekend.date(from: base, calendar: calendar), index + 1)
            default:
                break
            }

            if RelativeDate.nextWords.contains(w), let following = word(index + 1) {
                if following == "week" || following == "woche" {
                    return (QuickDate.nextWeek.date(from: base, calendar: calendar), index + 2)
                }
                if let weekday = RelativeDate.weekdayNames[following] ?? RelativeDate.shortWeekdays[following] {
                    return (RelativeDate.weekdayNextWeek(weekday, from: base, calendar: calendar), index + 2)
                }
                return nil
            }
            if RelativeDate.thisWords.contains(w), let following = word(index + 1) {
                if following == "weekend" || following == "wochenende" {
                    return (QuickDate.weekend.date(from: base, calendar: calendar), index + 2)
                }
                if let weekday = RelativeDate.weekdayNames[following] ?? RelativeDate.shortWeekdays[following] {
                    return (RelativeDate.nextWeekday(weekday, from: base, calendar: calendar), index + 2)
                }
                return nil
            }
            if let weekday = RelativeDate.weekdayNames[w] {
                return (RelativeDate.nextWeekday(weekday, from: base, calendar: calendar), index + 1)
            }
            if let weekday = RelativeDate.shortWeekdays[w] {
                // "bis Fr", or written like a calendar entry: "Mi 15 Uhr Zahnarzt". Never an
                // acronym ("on SAT prep").
                let raw = tokens[index].raw
                guard raw.count < 3 || raw != raw.uppercased() else { return nil }
                let isEnglish = RelativeDate.englishShortWeekdays.contains(w)
                let afterConnector = previous.map {
                    RelativeDate.shortDayConnectors.contains($0) && RelativeDate.englishDayConnectors.contains($0) == isEnglish
                } ?? false
                let beforeTime = raw.first?.isUppercase == true && time(at: index + 1) != nil
                guard afterConnector || beforeTime else { return nil }
                return (RelativeDate.nextWeekday(weekday, from: base, calendar: calendar), index + 1)
            }
            if let date = numericDate(at: index) {
                return (date, index + 1)
            }
            return nil
        }

        /// "morgen" is tomorrow unless it's the noun: after an article ("am Morgen", "guten
        /// Morgen") or capitalised in the middle of a sentence, unless "bis" or a time makes it a day.
        private func isTomorrow(at index: Int) -> Bool {
            let previous = word(index - 1)
            if let previous, RelativeDate.morningArticles.contains(previous) { return false }
            guard index > 0, tokens[index].raw.first?.isUppercase == true else { return true }
            return previous == "bis" || time(at: index + 1) != nil
        }

        /// "end of month", "end of the month", "Ende des Monats", "Ende Monat", "Monatsende".
        private func endOfMonth(at index: Int) -> (date: Date, end: Int)? {
            let w = word(index)
            var end: Int?
            if w == "monatsende" {
                end = index + 1
            } else if w == "end", word(index + 1) == "of" {
                if word(index + 2) == "month" { end = index + 3 }
                if word(index + 2) == "the", word(index + 3) == "month" { end = index + 4 }
            } else if w == "ende" {
                if word(index + 1) == "des", word(index + 2) == "monats" { end = index + 3 }
                if word(index + 1) == "monat" || word(index + 1) == "monats" { end = index + 2 }
            }
            guard let end, let month = calendar.dateInterval(of: .month, for: base),
                  let last = calendar.date(byAdding: .day, value: -1, to: month.end) else { return nil }
            return (calendar.startOfDay(for: last), end)
        }

        /// "in 3 days", "in einer Woche", "in zwei Monaten".
        private func inSomeDays(at index: Int) -> (date: Date, end: Int)? {
            guard let amountWord = word(index + 1), let unit = word(index + 2) else { return nil }
            guard let amount = Int(amountWord) ?? RelativeDate.numberWords[amountWord], amount > 0, amount <= 999 else { return nil }
            let component: Calendar.Component
            let value: Int
            switch unit {
            case "day", "days", "tag", "tage", "tagen":
                component = .day
                value = amount
            case "week", "weeks", "woche", "wochen":
                component = .day
                value = amount * 7
            case "month", "months", "monat", "monate", "monaten":
                component = .month
                value = amount
            default:
                return nil
            }
            guard let date = calendar.date(byAdding: component, value: value, to: base) else { return nil }
            return (date, index + 3)
        }

        /// "15.12.", "15.12", "15.12.2026", "15.12.26". After a connector it's a deadline, and
        /// without a year a past day rolls to next year. Without a connector it must look like a
        /// date ("15.12", not "1.5") and fall within the next six months (183 days): numbers
        /// in notes are often references to the past ("Anfrage 09.09 keine Antwort").
        private func numericDate(at index: Int) -> Date? {
            let text = tokens[index].lower
            guard let range = text.range(of: #"^\d{1,2}\.\d{1,2}(?:\.(?:\d{4}|\d{2})?)?$"#, options: .regularExpression),
                  range == text.startIndex ..< text.endIndex else { return nil }
            // "15.12 Uhr" is a time.
            if word(index + 1) == "uhr" { return nil }
            let parts = text.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2, let day = Int(parts[0]), let month = Int(parts[1]) else { return nil }
            var year: Int?
            if parts.count == 3, let typed = Int(parts[2]) {
                year = parts[2].count == 2 ? 2000 + typed : typed
            }
            let hasConnector = word(index - 1).map { RelativeDate.dateConnectors.contains($0) } ?? false
            if !hasConnector {
                let looksLikeADate = (parts[0].count == 2 && parts[1].count == 2) || text.hasSuffix(".") || year != nil
                guard looksLikeADate else { return nil }
            }
            let currentYear = calendar.component(.year, from: base)
            guard var date = validDate(day: day, month: month, year: year ?? currentYear) else { return nil }
            if year == nil, date < base, let next = validDate(day: day, month: month, year: currentYear + 1) {
                date = next
            }
            if !hasConnector {
                let delta = calendar.dateComponents([.day], from: base, to: date).day ?? -1
                guard delta >= 0, delta <= 183 else { return nil }
            }
            return date
        }

        private func validDate(day: Int, month: Int, year: Int) -> Date? {
            guard (1...31).contains(day), (1...12).contains(month) else { return nil }
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            let check = calendar.dateComponents([.year, .month, .day], from: date)
            guard check.day == day, check.month == month, check.year == year else { return nil }
            return calendar.startOfDay(for: date)
        }

        /// A time starting at `index`: "14:30", "14 Uhr", "14.30 Uhr", "um 9", "at 5", "5pm",
        /// "9:30 am".
        func time(at index: Int) -> (hour: Int, minute: Int, end: Int)? {
            guard let w = word(index) else { return nil }
            if w == "um" || w == "at" || w == "gegen" {
                return clock(at: index + 1, needsMarker: false, allowsDot: w != "at")
            }
            return clock(at: index, needsMarker: true, allowsDot: false)
        }

        /// A time that ends right before `index` (directly, or with "am"/"on" in between, as in
        /// "um 14 Uhr am Freitag").
        func time(endingAt index: Int) -> (hour: Int, minute: Int, start: Int)? {
            var ends = [index]
            if let previous = word(index - 1), previous == "am" || previous == "on" { ends.append(index - 1) }
            for end in ends {
                for start in max(0, end - 3) ..< end {
                    if let found = time(at: start), found.end == end { return (hour: found.hour, minute: found.minute, start: start) }
                }
            }
            return nil
        }

        /// The clock part: with `needsMarker`, only what is a time on its own (a colon, "Uhr",
        /// am/pm); after "um" or "at" a plain hour counts too.
        private func clock(at index: Int, needsMarker: Bool, allowsDot: Bool) -> (hour: Int, minute: Int, end: Int)? {
            guard index < tokens.count else { return nil }
            let text = tokens[index].lower
            let next = word(index + 1)

            // "5pm", "9:30am", "5p.m."
            if text.range(of: #"^\d{1,2}(?::\d{2})?(?:am|pm|a\.m\.?|p\.m\.?)$"#, options: .regularExpression) != nil {
                let digits = String(text.prefix(while: { $0.isNumber || $0 == ":" }))
                guard let parsed = hourMinute(digits), let twelve = twelveHour(parsed.hour, parsed.minute, isPM: text.contains("p")) else {
                    return nil
                }
                return (hour: twelve.hour, minute: twelve.minute, end: index + 1)
            }
            // "14uhr", "14:30uhr"
            if text.range(of: #"^\d{1,2}(?:[:.]\d{2})?uhr$"#, options: .regularExpression) != nil {
                guard let parsed = hourMinute(String(text.dropLast(3))) else { return nil }
                return (hour: parsed.hour, minute: parsed.minute, end: index + 1)
            }
            let isColon = text.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
            let isDotted = text.range(of: #"^\d{1,2}\.\d{2}$"#, options: .regularExpression) != nil
            let isHour = text.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil
            guard isColon || isDotted || isHour, let parsed = hourMinute(text) else { return nil }

            if next == "uhr" {
                return (hour: parsed.hour, minute: parsed.minute, end: index + 2)
            }
            // "9 am", "5 p.m." (an hour above 12 before "am" is German: "um 14 am Freitag").
            if let next, ["am", "pm", "a.m", "p.m"].contains(next), !isDotted,
               let twelve = twelveHour(parsed.hour, parsed.minute, isPM: next.hasPrefix("p")) {
                return (hour: twelve.hour, minute: twelve.minute, end: index + 2)
            }
            if isColon { return (hour: parsed.hour, minute: parsed.minute, end: index + 1) }
            guard !needsMarker else { return nil }
            if isDotted && !allowsDot { return nil }
            return (hour: parsed.hour, minute: parsed.minute, end: index + 1)
        }

        /// "9", "9:30", "14.30" as hour and minute, nil when it isn't a time of day.
        private func hourMinute(_ text: String) -> (hour: Int, minute: Int)? {
            let parts = text.split(whereSeparator: { $0 == ":" || $0 == "." }).map(String.init)
            guard parts.count == 1 || parts.count == 2, let hour = Int(parts[0]) else { return nil }
            let minute = parts.count == 2 ? Int(parts[1]) : 0
            guard let minute, (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return (hour: hour, minute: minute)
        }

        private func twelveHour(_ hour: Int, _ minute: Int, isPM: Bool) -> (hour: Int, minute: Int)? {
            guard (1...12).contains(hour) else { return nil }
            if isPM { return (hour: hour == 12 ? 12 : hour + 12, minute: minute) }
            return (hour: hour == 12 ? 0 : hour, minute: minute)
        }
    }
}
