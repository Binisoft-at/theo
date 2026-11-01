import Foundation

/// Turns a pasted Apple Notes daily note (or a Markdown checklist) into lines to import.
public enum NotesImport {
    public struct Line: Identifiable, Sendable {
        public let id = UUID()
        public var title: String
        public var done: Bool
        public var indent: Int
        public var isHeading: Bool
        /// Heading level: 1 for `#` (a group), 2 for `##` (a subproject inside it) ...
        public var level: Int

        public init(title: String, done: Bool, indent: Int, isHeading: Bool, level: Int = 1) {
            self.title = title
            self.done = done
            self.indent = indent
            self.isHeading = isHeading
            self.level = level
        }
    }

    private static let openMarkers = ["- [ ] ", "* [ ] ", "[ ] ", "☐ ", "○ ", "◯ ", "◦ ", "• ", "- ", "* ", "– "]
    private static let doneMarkers = ["- [x] ", "- [X] ", "* [x] ", "[x] ", "[X] ", "☑ ", "☒ ", "✓ ", "✔ ", "✅ ", "● "]

    /// Parses pasted text. Headings are lines starting with `#` or ending with `:`; optionally any
    /// line without a checkbox marker is treated as a heading too.
    public static func parse(_ text: String, plainLinesAreHeadings: Bool) -> [Line] {
        var result: [Line] = []
        for rawLine in text.components(separatedBy: .newlines) {
            guard !rawLine.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            var indent = 0
            var body = Substring(rawLine)
            var spaces = 0
            while let first = body.first, first == " " || first == "\t" {
                if first == "\t" {
                    indent += 1
                    spaces = 0
                } else {
                    spaces += 1
                    if spaces == 2 {
                        indent += 1
                        spaces = 0
                    }
                }
                body = body.dropFirst()
            }
            var line = String(body).trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { result.append(Line(title: title, done: false, indent: 0, isHeading: true, level: level)) }
                continue
            }

            var marker: Bool?
            if let m = doneMarkers.first(where: { line.hasPrefix($0) }) {
                line = String(line.dropFirst(m.count))
                marker = true
            } else if let m = openMarkers.first(where: { line.hasPrefix($0) }) {
                line = String(line.dropFirst(m.count))
                marker = false
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if marker == nil, line.hasSuffix(":") || plainLinesAreHeadings {
                let title = line.hasSuffix(":") ? String(line.dropLast()) : line
                result.append(Line(title: title.trimmingCharacters(in: .whitespaces), done: false, indent: 0, isHeading: true))
                continue
            }
            result.append(Line(title: line, done: marker ?? false, indent: min(indent, 4), isHeading: false))
        }
        return result
    }
}
