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
    /// Unused since urgency comes from the deadline; kept so older records still sync.
    var urgency: Double = 0.25
    /// 0.1...1, shown as levels 1–10 (`Matrix`). The priority marks follow it.
    var importance: Double = 0.25
    /// The day it's planned for (midnight of that calendar day); nil = not planned.
    var plannedDay: Date?
    /// How the deadline repeats (`Recurrence.raw`); empty = once.
    var recurrenceRaw: String = ""
    /// Notification offsets for timed deadlines (`Reminders` format); empty = at the time.
    var remindersRaw: String = ""
    /// A group whose traits differ from this task's own values (set when it was moved there):
    /// the task offers them instead of being overwritten. nil = nothing to offer.
    var traitProposalGroupID: UUID?
    /// Small synced values without a CloudKit field of their own (see `Extras`).
    var extrasRaw: String = ""

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

    /// Importance and urgency as the matrix ranks them; urgency comes from the deadline.
    func matrixPosition(today: Date) -> (urgency: Double, importance: Double) {
        let days = isDone ? nil : Matrix.daysUntil(dueDate, today: today)
        return (Matrix.urgency(daysUntilDue: days), importance)
    }

    func matrixScore(today: Date) -> Double {
        let position = matrixPosition(today: today)
        return Matrix.score(importance: position.importance, urgency: position.urgency)
    }

    var importanceLevel: Int { Matrix.level(forImportance: importance) }

    /// Planned for the logical day starting at `dayStart`.
    func isPlanned(for dayStart: Date) -> Bool {
        guard let plannedDay else { return false }
        return Calendar.current.isDate(plannedDay, inSameDayAs: dayStart)
    }

    /// Whether the task is on the daily page starting at `dayStart`: planned for that day, or
    /// finished during it. Nothing lands on a day by itself.
    func isOnPage(of dayStart: Date) -> Bool {
        guard deletedAt == nil else { return false }
        if isDone {
            guard let completedAt else { return false }
            return completedAt >= dayStart && completedAt < dayStart.addingTimeInterval(86_400)
        }
        return isPlanned(for: dayStart)
    }

    /// Planned for a day before `dayStart` and still open: a candidate to carry over.
    func isLeftOver(before dayStart: Date) -> Bool {
        guard deletedAt == nil, !isDone, let plannedDay else { return false }
        return plannedDay < Calendar.current.startOfDay(for: dayStart)
    }
}

extension TaskItem: ChecklistItem, Estimated {}
