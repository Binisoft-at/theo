import Foundation
import Testing
@testable import TheoCore

@Suite("Task queries")
struct TaskQueryTests {
    private let work = UUID()
    private let sub = UUID()

    private func facts(_ title: String, done: Bool = false, path: [UUID] = [], tags: [String] = [], level: Int = 3,
                       due: Int? = nil, planned: Int? = nil, ongoing: Bool = false, estimate: Double = 0.25) -> TaskQuery.Facts {
        TaskQuery.Facts(title: title, isDone: done, groupPath: path, tags: tags, level: level, daysUntilDue: due,
                        plannedIn: planned, isOngoing: ongoing, estimate: estimate)
    }

    @Test func standardShowsOpenTasks() {
        let query = TaskQuery.standard
        #expect(query.matches(facts("a")))
        #expect(!query.matches(facts("b", done: true)))
        #expect(query.filterCount == 0)
        #expect(query.grouping == .group && query.sort == .priorityDeadline)
    }

    @Test func filtersNarrowDown() {
        var query = TaskQuery()
        query.groupIDs = [work]
        #expect(query.matches(facts("in a subgroup", path: [sub, work])))
        #expect(!query.matches(facts("quick entry")))
        query = TaskQuery()
        query.deadline = .week
        #expect(query.matches(facts("soon", due: 3)))
        #expect(query.matches(facts("late", due: -2)))
        #expect(!query.matches(facts("later", due: 10)))
        #expect(!query.matches(facts("none")))
        query = TaskQuery()
        query.minLevel = 7
        query.maxEstimate = 0.5
        query.tags = ["calls"]
        #expect(query.matches(facts("x", tags: ["calls"], level: 8, estimate: 0.25)))
        #expect(!query.matches(facts("y", tags: ["calls"], level: 6)))
        #expect(!query.matches(facts("z", tags: ["calls"], level: 9, estimate: 2)))
        #expect(query.filterCount == 3)
        query = TaskQuery()
        query.planned = .unplanned
        query.ongoingOnly = true
        #expect(query.matches(facts("o", ongoing: true)))
        #expect(!query.matches(facts("p", planned: 0, ongoing: true)))
    }

    @Test func searchLooksAtTitleAndNotes() {
        var query = TaskQuery()
        query.search = "Konto"
        #expect(query.matches(TaskQuery.Facts(title: "check the konto", isDone: false, groupPath: [], tags: [], level: 3,
                                              daysUntilDue: nil, plannedIn: nil, isOngoing: false, estimate: 0)))
        #expect(!query.matches(facts("other")))
    }

    @Test func sortsByPriorityThenDeadline() {
        let query = TaskQuery.standard
        let items = [facts("low later", level: 3, due: 5), facts("high", level: 9), facts("low soon", level: 3, due: 1)]
        let sorted = items.sorted { query.precedes($0, $1) }.map(\.title)
        #expect(sorted == ["high", "low soon", "low later"])
    }

    @Test func roundTripsAndToleratesOldData() {
        var query = TaskQuery()
        query.tags = ["a"]
        query.grouping = .deadline
        query.maxEstimate = 1
        #expect(TaskQuery(raw: query.raw) == query)
        #expect(TaskQuery(raw: "{\"sort\":\"title\"}").sort == .title)
        #expect(TaskQuery(raw: "{\"sort\":\"title\"}").status == .open)
        #expect(TaskQuery(raw: "not json") == .standard)
        #expect(TaskQuery.presets.first?.query == .standard)
    }
}

@Suite("Backups")
struct BackupTests {
    @Test func roundTrips() throws {
        let group = Backup.Group(uuid: UUID(), name: "Work", symbol: "briefcase", colorName: "blue", sortOrder: 1,
                                 isCollapsed: false, isProject: false, notes: "", dueDate: nil, createdAt: Date(timeIntervalSince1970: 0),
                                 parentUUID: nil, isActive: true, traitImportance: 0.8, traitEstimate: nil, traitTagsRaw: "",
                                 traitDueDays: 3, extrasRaw: "")
        let task = Backup.Task(uuid: UUID(), title: "Call", notes: "n", isDone: false, completedAt: nil,
                               createdAt: Date(timeIntervalSince1970: 100), sortOrder: 2, indent: 1, priorityRaw: 2, dueDate: nil,
                               dueHasTime: false, deferredUntil: nil, tagsRaw: "a,b", groupUUID: group.uuid, estimate: 0.25,
                               focusSeconds: 0, urgency: 0, importance: 0.3, plannedDay: nil, recurrenceRaw: "",
                               remindersRaw: "", traitProposalGroupID: nil, extrasRaw: "{\"ongoing\":\"1\"}")
        let backup = Backup(createdAt: Date(timeIntervalSince1970: 1_000), groups: [group], tasks: [task], views: [])
        let restored = try Backup.decode(backup.encoded())
        #expect(restored.groups == [group])
        #expect(restored.tasks == [task])
        #expect(restored.version == Backup.currentVersion)
    }

    @Test func keepsTheNewestFiles() {
        let names = ["Theo Backup 2026-11-01 0900.json", "Theo Backup 2026-11-03 0900.json", "Theo Backup 2026-11-02 0900.json", "other.txt"]
        #expect(Backup.expired(names, keep: 2) == ["Theo Backup 2026-11-01 0900.json"])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(Backup.fileName(for: Date(timeIntervalSince1970: 0), calendar: calendar) == "Theo Backup 1970-01-01 0000.json")
    }
}
