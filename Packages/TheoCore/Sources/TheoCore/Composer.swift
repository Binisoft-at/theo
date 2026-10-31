import Foundation

/// Text rules of the quick-entry bar beyond the per-line shortcuts in `QuickParser`:
/// a leading "- " files the line as a subtask, and pasted lists keep their nesting.
public enum Composer {
    public struct Line: Equatable, Sendable {
        public var title: String
        public var level: Int

        public init(title: String, level: Int) {
            self.title = title
            self.level = level
        }
    }

    private static let subtaskMarkers = ["- ", "– ", "— ", "> ", "↳ ", "↳"]
    private static let listMarkers = ["- [ ] ", "* [ ] ", "- [x] ", "- [X] ", "[ ] ", "[x] ", "☐ ", "• ", "◦ ", "- ", "* ", "– "]

    /// The text after a leading subtask marker ("- book flights" → "book flights"), or nil when
    /// the line doesn't start with one. The result can be empty while the user is still typing.
    public static func subtaskBody(_ text: String) -> String? {
        let trimmed = text.drop(while: { $0 == " " })
        for marker in subtaskMarkers where trimmed.hasPrefix(marker) {
            return trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Pasted text as task lines. Leading tabs or pairs of spaces nest a line under the one
    /// above (at most one level deeper); list markers ("- ", "• ", "[ ] " ...) are dropped.
    public static func lines(_ text: String) -> [Line] {
        var result: [Line] = []
        for raw in text.components(separatedBy: .newlines) {
            var level = 0
            var spaces = 0
            var body = Substring(raw)
            while let first = body.first, first == " " || first == "\t" {
                if first == "\t" {
                    level += 1
                    spaces = 0
                } else {
                    spaces += 1
                    if spaces == 2 {
                        level += 1
                        spaces = 0
                    }
                }
                body = body.dropFirst()
            }
            var title = String(body)
            if let marker = listMarkers.first(where: { title.hasPrefix($0) }) {
                title = String(title.dropFirst(marker.count))
            }
            title = title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            let deepest = (result.last?.level ?? -1) + 1
            result.append(Line(title: title, level: min(level, deepest)))
        }
        return result
    }
}
