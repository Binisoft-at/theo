import Foundation
import TheoCore

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
