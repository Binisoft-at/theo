import Foundation

/// Plain-text interchange with Apple Notes and Markdown checklists.
enum TextExport {
    static func markdown(title: String, rows: [ListRow]) -> String {
        var lines: [String] = ["# \(title)", ""]
        for row in rows {
            switch row {
            case .header(let info):
                if lines.last != "" { lines.append("") }
                switch info.kind {
                case .quickEntry: lines.append("## Quick Entry")
                case .group(let group): lines.append("## \(group.displayName)")
                case .label(_, let title, _, _): lines.append("## \(title)")
                }
            case .task(let task, let depth, _):
                let indent = String(repeating: "  ", count: depth)
                let box = task.isDone ? "[x]" : "[ ]"
                var line = "\(indent)- \(box) \(task.trimmedTitle)"
                if task.priority != .normal { line += " \(task.priority.marks)" }
                for tag in task.tags { line += " #\(tag)" }
                if let due = task.dueDate {
                    line += " (due \(DateText.due(due, hasTime: task.dueHasTime, today: Date())))"
                }
                lines.append(line)
            case .placeholder:
                break
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}

enum NotesImport {
    struct Line: Identifiable {
        let id = UUID()
        var title: String
        var done: Bool
        var indent: Int
        var isHeading: Bool
    }

    private static let openMarkers = ["- [ ] ", "* [ ] ", "[ ] ", "☐ ", "○ ", "◯ ", "◦ ", "• ", "- ", "* ", "– "]
    private static let doneMarkers = ["- [x] ", "- [X] ", "* [x] ", "[x] ", "[X] ", "☑ ", "☒ ", "✓ ", "✔ ", "✅ ", "● "]

    /// Parses pasted text. Headings are lines starting with `#` or ending with `:`; optionally any
    /// line without a checkbox marker is treated as a heading too.
    static func parse(_ text: String, plainLinesAreHeadings: Bool) -> [Line] {
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
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { result.append(Line(title: title, done: false, indent: 0, isHeading: true)) }
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
