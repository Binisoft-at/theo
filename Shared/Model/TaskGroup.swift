import Foundation
import SwiftData

/// A heading inside the daily page ("Work", "Project X", ...). Groups can optionally be
/// treated as projects, which adds a progress bar and a deadline.
@Model
final class TaskGroup {
    var uuid: UUID = UUID()
    var name: String = ""
    var symbol: String = "list.bullet"
    var colorName: String = "blue"
    /// Position of the heading on the page. Lower = higher up.
    var sortOrder: Double = 0
    var isCollapsed: Bool = false
    var isProject: Bool = false
    var notes: String = ""
    var dueDate: Date?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \TaskItem.group)
    var tasks: [TaskItem]? = []

    init(name: String, symbol: String = "list.bullet", color: TheoColor = .blue, sortOrder: Double = 0) {
        let now = Date()
        self.uuid = UUID()
        self.name = name
        self.symbol = symbol
        self.colorName = color.rawValue
        self.sortOrder = sortOrder
        self.createdAt = now
        self.modifiedAt = now
    }
}

extension TaskGroup {
    var color: TheoColor {
        get { TheoColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }

    var liveTasks: [TaskItem] {
        (tasks ?? []).filter { $0.deletedAt == nil }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    func touch() { modifiedAt = Date() }
}
