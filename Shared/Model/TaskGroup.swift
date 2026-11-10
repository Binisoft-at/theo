import Foundation
import SwiftData
import TheoCore

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
    /// The group this one sits inside (a subproject); nil = top level.
    var parentUUID: UUID?
    /// Off: its tasks (and its subgroups') stay out of Today, Plan, Upcoming and the other
    /// lists until it's switched back on. They still show on its own page.
    var isActive: Bool = true
    /// Traits its tasks inherit (see `GroupTraits`); nil / empty = none.
    var traitImportance: Double?
    var traitEstimate: Double?
    var traitTagsRaw: String = ""
    var traitDueDays: Int?
    /// Small synced values without a CloudKit field of their own (see `Extras`).
    var extrasRaw: String = ""

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

    var extras: [String: String] {
        get { Extras.decode(extrasRaw) }
        set { extrasRaw = Extras.encode(newValue) }
    }

    /// The traits set on this group itself (a subgroup also inherits its parent's).
    var ownTraits: GroupTraits {
        get {
            GroupTraits(
                importance: traitImportance,
                estimate: traitEstimate,
                tags: traitTagsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty },
                dueDays: traitDueDays
            )
        }
        set {
            traitImportance = newValue.importance
            traitEstimate = newValue.estimate
            traitTagsRaw = newValue.tags.joined(separator: ",")
            traitDueDays = newValue.dueDays
        }
    }
}
