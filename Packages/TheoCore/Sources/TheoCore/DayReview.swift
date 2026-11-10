import Foundation

/// Numbers for looking back at a day: how much got done, compared with the days before.
public enum DayReview {
    /// One day's result.
    public struct Day: Equatable, Sendable {
        public var start: Date
        public var powerHours: Double
        public var done: Int

        public init(start: Date, powerHours: Double, done: Int) {
            self.start = start
            self.powerHours = powerHours
            self.done = done
        }
    }

    /// Average Power Hours per day. Every day counts, a day without anything done as 0.
    public static func average(_ days: [Day]) -> Double {
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + $1.powerHours } / Double(days.count)
    }

    /// The day against the average (1 = an average day); nil without anything to compare with.
    public static func ratio(_ value: Double, average: Double) -> Double? {
        average > 0.0001 ? value / average : nil
    }

    /// 1 for the best of these days, 2 for the second best …
    public static func rank(of value: Double, among days: [Day]) -> Int {
        days.filter { $0.powerHours > value + 1e-9 }.count + 1
    }

    /// Share of the day's tasks that got done, 0...1 (0 when there were none).
    public static func share(done: Int, open: Int) -> Double {
        let total = done + open
        return total > 0 ? Double(done) / Double(total) : 0
    }

    /// "+0,5 PH", "−1 PH", "±0 PH".
    public static func signed(_ delta: Double, locale: Locale = .current) -> String {
        if abs(delta) < 0.005 { return "±" + PowerHours.format(0, locale: locale) }
        return (delta > 0 ? "+" : "−") + PowerHours.format(abs(delta), locale: locale)
    }
}

/// Spreadsheet text. Fields are quoted when they need it (RFC 4180).
public enum CSV {
    /// Where the decimal mark is a comma (German, Austrian …), spreadsheets expect `;` between
    /// fields and a comma in numbers.
    public struct Format: Equatable, Sendable {
        public var separator: Character
        public var decimalComma: Bool

        public init(separator: Character, decimalComma: Bool) {
            self.separator = separator
            self.decimalComma = decimalComma
        }

        public static let standard = Format(separator: ",", decimalComma: false)
        public static let semicolon = Format(separator: ";", decimalComma: true)

        public static func `for`(_ locale: Locale) -> Format {
            locale.decimalSeparator == "," ? .semicolon : .standard
        }
    }

    public static func field(_ value: String, format: Format = .standard) -> String {
        let needsQuotes = value.contains(format.separator) || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func number(_ value: Double, format: Format = .standard) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return format.decimalComma ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    /// A header line and the rows, with CRLF line ends.
    public static func document(header: [String], rows: [[String]], format: Format = .standard) -> String {
        ([header] + rows)
            .map { $0.map { field($0, format: format) }.joined(separator: String(format.separator)) }
            .joined(separator: "\r\n") + "\r\n"
    }
}
