import Foundation
import Testing
@testable import TheoCore

// MARK: - Quick entry parsing

@Suite("QuickParser")
struct QuickParserTests {
    let groups = [
        QuickParser.GroupRef(id: UUID(), name: "Home"),
        QuickParser.GroupRef(id: UUID(), name: "Theo Launch"),
    ]

    @Test func plainTextStaysUntouched() {
        let entry = QuickParser.parse("Look into standing desk", groups: groups)
        #expect(entry.title == "Look into standing desk")
        #expect(!entry.hasExtras)
    }

    @Test(arguments: [("!", Priority.low), ("!!", .medium), ("!!!", .high), ("p1", .high), ("P2", .medium)])
    func priorityMarks(mark: String, expected: Priority) {
        let entry = QuickParser.parse("Pay rent \(mark)", groups: groups)
        #expect(entry.priority == expected)
        #expect(entry.title == "Pay rent")
    }

    @Test func tagsAreCleanedAndDeduplicated() {
        let entry = QuickParser.parse("Buy gift #Family #family #gifts", groups: groups)
        #expect(entry.tags == ["family", "gifts"])
        #expect(entry.title == "Buy gift")
    }

    @Test func numericHashtagIsNotATag() {
        let entry = QuickParser.parse("Fix issue #42", groups: groups)
        #expect(entry.tags.isEmpty)
        #expect(entry.title == "Fix issue #42")
    }

    @Test func groupMatchesByPrefixIgnoringSpaces() {
        let entry = QuickParser.parse("Record demo @theolaun", groups: groups)
        #expect(entry.groupID == groups[1].id)
        #expect(entry.groupName == "Theo Launch")
        #expect(entry.title == "Record demo")
    }

    @Test func unknownGroupStaysInTitle() {
        let entry = QuickParser.parse("Email @bob", groups: groups)
        #expect(entry.groupID == nil)
        #expect(entry.title == "Email @bob")
    }

    @Test func dateWithTimeBecomesDeadline() {
        let entry = QuickParser.parse("Call mom tomorrow at 5pm", groups: groups)
        #expect(entry.due != nil)
        #expect(entry.dueHasTime)
        #expect(entry.title == "Call mom")
    }

    @Test func dateWithoutTimeIsStartOfDay() throws {
        let entry = QuickParser.parse("Submit report tomorrow", groups: groups)
        let due = try #require(entry.due)
        #expect(!entry.dueHasTime)
        #expect(Calendar.current.startOfDay(for: due) == due)
        #expect(entry.title == "Submit report")
    }

    @Test func dateOnlyTextIsKeptAsTitle() {
        let entry = QuickParser.parse("tomorrow", groups: groups)
        #expect(entry.title == "tomorrow")
        #expect(entry.due == nil)
    }

    @Test func disabledOptionsKeepRawText() {
        let entry = QuickParser.parse("Plan trip friday !! #travel", groups: groups, options: [])
        #expect(entry.title == "Plan trip friday !! #travel")
        #expect(!entry.hasExtras)
    }
}

// MARK: - Days and dates

@Suite("DayBoundary")
struct DayBoundaryTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return calendar
    }()

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func lateNightBelongsToPreviousDay() {
        let boundary = DayBoundary(startHour: 4, calendar: calendar)
        #expect(boundary.start(of: date(2026, 10, 30, 1, 30)) == date(2026, 10, 29, 4))
        #expect(boundary.start(of: date(2026, 10, 30, 4, 0)) == date(2026, 10, 30, 4))
        #expect(boundary.start(of: date(2026, 10, 30, 23, 59)) == date(2026, 10, 30, 4))
    }

    @Test func midnightBoundary() {
        let boundary = DayBoundary(startHour: 0, calendar: calendar)
        #expect(boundary.start(of: date(2026, 10, 30, 0, 10)) == date(2026, 10, 30, 0))
    }

    @Test func startHourIsClamped() {
        #expect(DayBoundary(startHour: 30, calendar: calendar).startHour == 12)
        #expect(DayBoundary(startHour: -3, calendar: calendar).startHour == 0)
    }

    @Test func daysBetweenLogicalDays() {
        let boundary = DayBoundary(startHour: 4, calendar: calendar)
        #expect(boundary.days(from: date(2026, 10, 27, 10), to: date(2026, 10, 30, 2)) == 2)
        #expect(boundary.days(from: date(2026, 10, 30, 5), to: date(2026, 10, 30, 23)) == 0)
    }

    @Test func dayStartArithmetic() {
        let boundary = DayBoundary(startHour: 4, calendar: calendar)
        let start = date(2026, 10, 30, 4)
        #expect(boundary.end(ofDayStarting: start) == date(2026, 10, 31, 4))
        #expect(boundary.dayStart(byAdding: -1, to: start) == date(2026, 10, 29, 4))
    }

    @Test func quickDates() {
        // Friday, 30 October 2026.
        let friday = date(2026, 10, 30, 12)
        #expect(QuickDate.today.date(from: friday, calendar: calendar) == date(2026, 10, 30, 0))
        #expect(QuickDate.tomorrow.date(from: friday, calendar: calendar) == date(2026, 10, 31, 0))
        #expect(QuickDate.weekend.date(from: friday, calendar: calendar) == date(2026, 10, 31, 0))
        #expect(QuickDate.nextWeek.date(from: friday, calendar: calendar) == date(2026, 11, 2, 0))
        // On a Monday, "next week" is the following Monday.
        #expect(QuickDate.nextWeek.date(from: date(2026, 11, 2, 9), calendar: calendar) == date(2026, 11, 9, 0))
    }

    @Test func dayDelta() {
        #expect(DateText.dayDelta(date(2026, 10, 31, 9), today: date(2026, 10, 30, 23), calendar: calendar) == 1)
        #expect(DateText.dayDelta(date(2026, 10, 29, 9), today: date(2026, 10, 30, 1), calendar: calendar) == -1)
    }
}

// MARK: - Notes import

@Suite("NotesImport")
struct NotesImportTests {
    @Test func parsesHeadingsTasksAndNesting() {
        let text = """
        # Work
        - [ ] Finish roadmap
          - [ ] Collect numbers
        - [x] Standup notes
        Home:
        ◦ Groceries
        """
        let lines = NotesImport.parse(text, plainLinesAreHeadings: false)
        #expect(lines.map(\.title) == ["Work", "Finish roadmap", "Collect numbers", "Standup notes", "Home", "Groceries"])
        #expect(lines.map(\.isHeading) == [true, false, false, false, true, false])
        #expect(lines.map(\.indent) == [0, 0, 1, 0, 0, 0])
        #expect(lines.map(\.done) == [false, false, false, true, false, false])
    }

    @Test func plainLinesCanBeHeadings() {
        let lines = NotesImport.parse("Errands\n- Post office", plainLinesAreHeadings: true)
        #expect(lines.map(\.isHeading) == [true, false])
    }

    @Test func emptyLinesAreSkipped() {
        #expect(NotesImport.parse("\n   \n- [ ] Only task\n\n", plainLinesAreHeadings: false).count == 1)
    }
}

// MARK: - Tags

@Suite("Tags")
struct TagsTests {
    @Test func clean() {
        #expect(Tags.clean("  ##Deep Work ") == "deep-work")
        #expect(Tags.clean("a,b") == "ab")
    }

    @Test func normalizeKeepsOrder() {
        #expect(Tags.normalize(["B", "a", "#b", ""]) == ["b", "a"])
    }
}

// MARK: - Checklist ordering

struct Line: ChecklistItem, Equatable {
    var name: String
    var sortOrder: Double
    var indent: Int = 0
    var isDone = false
    var completedAt: Date?
}

@Suite("Checklist")
struct ChecklistTests {
    @Test func depthsAreClampedToOneLevelBelowThePreviousLine() {
        let lines = [
            Line(name: "a", sortOrder: 0, indent: 2),
            Line(name: "b", sortOrder: 1, indent: 3),
            Line(name: "c", sortOrder: 2, indent: 1),
        ]
        #expect(Checklist.depths(of: lines) == [0, 1, 1])
    }

    @Test func blockEndCoversSubtasks() {
        let depths = [0, 1, 2, 1, 0]
        #expect(Checklist.blockEnd(after: 0, depths: depths) == 4)
        #expect(Checklist.blockEnd(after: 1, depths: depths) == 3)
        #expect(Checklist.blockEnd(after: 4, depths: depths) == 5)
    }

    @Test func completedLinesSinkWithTheirSubtasks() {
        let now = Date()
        let lines = [
            Line(name: "done parent", sortOrder: 0, isDone: true, completedAt: now),
            Line(name: "child", sortOrder: 1, indent: 1),
            Line(name: "open", sortOrder: 2),
            Line(name: "done earlier", sortOrder: 3, isDone: true, completedAt: now.addingTimeInterval(-60)),
        ]
        let order = Checklist.displayOrder(lines, showCompleted: true)
        #expect(order.map(\.item.name) == ["open", "done parent", "child", "done earlier"])
        #expect(order.map(\.depth) == [0, 0, 1, 0])
    }

    @Test func hidingCompletedDropsTheirSubtasks() {
        let lines = [
            Line(name: "open", sortOrder: 0),
            Line(name: "open child", sortOrder: 1, indent: 1),
            Line(name: "done", sortOrder: 2, isDone: true, completedAt: Date()),
            Line(name: "done child", sortOrder: 3, indent: 1),
        ]
        let order = Checklist.displayOrder(lines, showCompleted: false)
        #expect(order.map(\.item.name) == ["open", "open child"])
    }

    @Test func manualOrderWinsOverInputOrder() {
        let lines = [Line(name: "b", sortOrder: 2), Line(name: "a", sortOrder: 1)]
        #expect(Checklist.displayOrder(lines, showCompleted: true).map(\.item.name) == ["a", "b"])
    }
}
