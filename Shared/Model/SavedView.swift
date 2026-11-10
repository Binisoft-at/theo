import Foundation
import SwiftData
import TheoCore

/// A saved filter / grouping / sort combination ("Due this week by group"), shown in the
/// sidebar like a group. It holds no tasks of its own; it shows whatever matches.
@Model
final class SavedView {
    var uuid: UUID = UUID()
    var name: String = ""
    var symbol: String = "line.3.horizontal.decrease.circle"
    var colorName: String = "indigo"
    var sortOrder: Double = 0
    var isFavorite: Bool = false
    /// `TaskQuery.raw`.
    var queryRaw: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    init(name: String, query: TaskQuery, sortOrder: Double = 0) {
        let now = Date()
        self.uuid = UUID()
        self.name = name
        self.queryRaw = query.raw
        self.sortOrder = sortOrder
        self.createdAt = now
        self.modifiedAt = now
    }
}

extension SavedView {
    var query: TaskQuery {
        get { TaskQuery(raw: queryRaw) }
        set { queryRaw = newValue.raw }
    }

    var color: TheoColor {
        get { TheoColor(rawValue: colorName) ?? .indigo }
        set { colorName = newValue.rawValue }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled View" : trimmed
    }

    func touch() { modifiedAt = Date() }
}

extension TaskGroup {
    /// Shown under Favorites at the top of the sidebar.
    var isFavorite: Bool {
        get { extras["favorite"] == "1" }
        set { extras["favorite"] = newValue ? "1" : nil }
    }
}
