import Foundation
import SwiftData
import TheoCore

/// A single line in a Theo page. Mirrors a checklist item in an Apple Notes daily note,
/// with extra structure (priority, deadline, tags, nesting, deferral).
///
/// CloudKit rules apply: every attribute has a default value, relationships are optional,
/// and nothing is marked unique. Keep `cloudkit/schema.ckdb` in sync when adding fields.
@Model
final class TaskItem {
    var uuid: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var isDone: Bool = false
    var completedAt: Date?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    /// Manual position inside its group. Lower = higher up = more important.
    var sortOrder: Double = 0
    /// Visual nesting level, like indented checklist lines in Notes.
    var indent: Int = 0
    var priorityRaw: Int = 0
    var dueDate: Date?
    var dueHasTime: Bool = false
    /// Hidden from Today until this logical day starts ("Not Today").
    var deferredUntil: Date?
    /// Comma separated, lowercase tags without the leading '#'.
    var tagsRaw: String = ""
    /// Soft delete ("Recently Deleted").
    var deletedAt: Date?
    var group: TaskGroup?
    /// Estimated effort in Power Hours (50 focused minutes each); 0 = none.
    var estimate: Double = 0
    /// Focus-timer time spent on this task.
    var focusSeconds: Double = 0
    /// Position on the Eisenhower matrix, 0...1 each.
    var urgency: Double = 0.25
    var importance: Double = 0.25
    /// How the deadline repeats (`Recurrence.raw`); empty = once.
    var recurrenceRaw: String = ""
    /// Notification offsets for timed deadlines (`Reminders` format); empty = at the time.
    var remindersRaw: String = ""

    init(title: String = "", group: TaskGroup? = nil, sortOrder: Double = 0, indent: Int = 0) {
        let now = Date()
        self.uuid = UUID()
        self.title = title
        self.group = group
        self.sortOrder = sortOrder
        self.indent = indent
        self.createdAt = now
        self.modifiedAt = now
    }
}

extension TaskItem {
    var rowID: String { "t-" + uuid.uuidString }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var tags: [String] {
        get { tagsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set { tagsRaw = Tags.normalize(newValue).joined(separator: ",") }
    }

    var groupID: UUID? {
        guard let group, group.deletedAt == nil else { return nil }
        return group.uuid
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var notesPreview: String? {
        let line = notes.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let line, !line.isEmpty else { return nil }
        return line
    }

    func touch() { modifiedAt = Date() }

    var recurrence: Recurrence? {
        get { Recurrence(raw: recurrenceRaw) }
        set { recurrenceRaw = newValue?.raw ?? "" }
    }

    var reminderOffsets: [Int] {
        get { Reminders.offsets(from: remindersRaw) }
        set { remindersRaw = Reminders.raw(for: newValue) }
    }

    /// Importance and urgency as the matrix ranks them: priority adds importance, a close
    /// deadline adds urgency.
    func matrixPosition(today: Date) -> (urgency: Double, importance: Double) {
        (Matrix.effectiveUrgency(urgency, due: isDone ? nil : dueDate, today: today), Matrix.effectiveImportance(importance, priority: priority))
    }

    func matrixScore(today: Date) -> Double {
        let position = matrixPosition(today: today)
        return Matrix.score(urgency: position.urgency, importance: position.importance)
    }

    /// Whether the task belongs on the daily page starting at `dayStart`: still open (and not
    /// hidden with "Not Today" past that day), or completed during that day.
    func isOnPage(of dayStart: Date) -> Bool {
        guard deletedAt == nil else { return false }
        if isDone {
            guard let completedAt else { return false }
            return completedAt >= dayStart
        }
        if let deferredUntil, deferredUntil > dayStart { return false }
        return true
    }
}

extension TaskItem: ChecklistItem, Estimated {}
