import Foundation
import Testing
@testable import TheoCore

private struct PlanLine: ChecklistItem, Estimated {
    var sortOrder: Double
    var indent: Int
    var isDone = false
    var completedAt: Date?
    var estimate: Double
}

@Suite("Power Hours")
struct PowerHoursTests {
    @Test(arguments: [("mail lesen (0,25PH)", 0.25), ("deploy 0.5ph", 0.5), ("haeb app 2 PH", 2.0), ("pflanzen (1,5PH) heute", 1.5)])
    func findsEstimates(text: String, expected: Double) {
        #expect(PowerHours.find(in: text)?.value == expected)
    }

    @Test func ignoresWordsThatOnlyContainPH() {
        #expect(PowerHours.find(in: "graph the photos") == nil)
        #expect(PowerHours.find(in: "jakup rest 1.6k (?)") == nil)
    }

    @Test func parserTakesTheEstimateOutOfTheTitle() {
        let entry = QuickParser.parse("alex rest (0,5PH)", groups: [])
        #expect(entry.estimate == 0.5)
        #expect(entry.title == "alex rest")
    }

    @Test(arguments: [("1,5", 1.5), ("0.25", 0.25), ("2 PH", 2.0)])
    func parsesCustomInput(text: String, expected: Double) {
        #expect(PowerHours.parse(text) == expected)
    }

    @Test func formatsInTheGivenLocale() {
        #expect(PowerHours.format(0.25, locale: Locale(identifier: "de_AT")) == "0,25 PH")
        #expect(PowerHours.format(2, locale: Locale(identifier: "en_US")) == "2 PH")
    }

    @Test func parentEstimateCountsOnlyWithoutEstimatedSubtasks() {
        let lines = [
            PlanLine(sortOrder: 0, indent: 0, estimate: 2),   // parent with a total ...
            PlanLine(sortOrder: 1, indent: 1, estimate: 1),   // ... and estimated subtasks
            PlanLine(sortOrder: 2, indent: 1, estimate: 1),
            PlanLine(sortOrder: 3, indent: 0, estimate: 3),   // parent with plain subtasks
            PlanLine(sortOrder: 4, indent: 1, estimate: 0),
            PlanLine(sortOrder: 5, indent: 0, estimate: 0.25),
        ]
        #expect(PowerHours.total(lines) == 5.25)
    }

    @Test func totalCanBeFiltered() {
        let lines = [
            PlanLine(sortOrder: 0, indent: 0, isDone: true, estimate: 0.5),
            PlanLine(sortOrder: 1, indent: 0, estimate: 1),
        ]
        #expect(PowerHours.total(lines, where: \.isDone) == 0.5)
    }
}

@Suite("Recurrence")
struct RecurrenceTests {
    let calendar = Calendar(identifier: .gregorian)

    @Test(arguments: [("water plants daily", Recurrence.daily), ("Gym every 3 days", .everyDays(3)), ("standup every weekday", .weekdays),
                      ("Bericht wöchentlich", .weekly), ("Miete jeden Monat", .monthly), ("Steuer every year", .yearly)])
    func findsRecurrence(text: String, expected: Recurrence) {
        #expect(Recurrence.find(in: text)?.recurrence == expected)
    }

    @Test func weeklyIsNotWeekday() {
        #expect(Recurrence.find(in: "review every week")?.recurrence == .weekly)
    }

    @Test func rawRoundTrips() {
        for recurrence in Recurrence.common + [.everyDays(10)] {
            #expect(Recurrence(raw: recurrence.raw) == recurrence)
        }
        #expect(Recurrence(raw: "") == nil)
    }

    @Test func weekdaysSkipTheWeekend() {
        let friday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 9))!
        let next = Recurrence.weekdays.next(after: friday, calendar: calendar)
        #expect(calendar.component(.weekday, from: next) == 2) // Monday
        #expect(calendar.component(.hour, from: next) == 9)
    }

    @Test func parserTakesTheRepeatOutOfTheTitle() {
        let entry = QuickParser.parse("water plants daily", groups: [])
        #expect(entry.recurrence == .daily)
        #expect(entry.title == "water plants")
    }
}

@Suite("Reminders")
struct RemindersTests {
    @Test func defaultIsAtTheTime() {
        #expect(Reminders.offsets(from: "") == [0])
        #expect(Reminders.offsets(from: "off").isEmpty)
        #expect(Reminders.raw(for: [0]) == "")
        #expect(Reminders.raw(for: []) == "off")
    }

    @Test func rawRoundTrips() {
        let offsets = [60, 0, -10, -20]
        #expect(Reminders.offsets(from: Reminders.raw(for: offsets)) == [60, 0, -10, -20])
    }

    @Test func nudgesFollowTheTime() {
        #expect(Reminders.nudges(count: 3, every: 10) == [-10, -20, -30])
    }

    @Test func describesOffsets() {
        #expect(Reminders.describe(0) == "At time")
        #expect(Reminders.describe(15) == "15 min before")
        #expect(Reminders.describe(90) == "1 h 30 min before")
        #expect(Reminders.describe(1440) == "1 day before")
        #expect(Reminders.describe(-10) == "10 min after")
    }

    @Test func onlyFutureFireDates() {
        let due = Date(timeIntervalSince1970: 10_000)
        let now = due.addingTimeInterval(-30 * 60)
        let dates = Reminders.fireDates(due: due, offsets: [60, 15, 0, -10], after: now)
        #expect(dates == [due.addingTimeInterval(-15 * 60), due, due.addingTimeInterval(10 * 60)])
    }
}

@Suite("Matrix")
struct MatrixTests {
    @Test func urgencyFollowsTheDeadline() {
        #expect(Matrix.urgency(daysUntilDue: -3) == 1)
        #expect(Matrix.urgency(daysUntilDue: 0) == 1)
        #expect(Matrix.urgency(daysUntilDue: 7) > Matrix.urgency(daysUntilDue: 14))
        #expect(Matrix.urgency(daysUntilDue: 14) > 0)
        #expect(Matrix.urgency(daysUntilDue: 15) == 0)
        #expect(Matrix.urgency(daysUntilDue: nil) == 0)
    }

    @Test func urgencyRoundTripsToDays() {
        for days in 0...Matrix.horizonDays {
            #expect(Matrix.days(forUrgency: Matrix.urgency(daysUntilDue: days)) == days)
        }
        #expect(Matrix.days(forUrgency: 0) == nil)
    }

    @Test func tenImportanceLevels() {
        #expect(Matrix.level(forImportance: 0) == 1)
        #expect(Matrix.level(forImportance: Matrix.defaultImportance) == 3)
        #expect(Matrix.level(forImportance: 1) == 10)
        #expect(Matrix.importance(forLevel: 7) == 0.7)
    }

    @Test func marksAreACoarseViewOfImportance() {
        #expect(Matrix.priority(forImportance: 0.3) == .normal)
        #expect(Matrix.priority(forImportance: 0.6) == .low)
        #expect(Matrix.priority(forImportance: 0.8) == .medium)
        #expect(Matrix.priority(forImportance: 1) == .high)
        #expect(Matrix.priority(forImportance: Matrix.importance(for: .medium, current: 0.3)) == .medium)
        #expect(Matrix.importance(for: .high, current: 0.9) == 0.9)
    }

    @Test func importanceOutranksUrgency() {
        let importantLater = Matrix.score(importance: 0.9, urgency: 0)
        let urgentUnimportant = Matrix.score(importance: 0.2, urgency: 1)
        #expect(importantLater > urgentUnimportant)
    }

    @Test func solvingImportanceLandsOnTheTarget() {
        let urgency = Matrix.urgency(daysUntilDue: 3)
        let importance = Matrix.importance(toReach: 0.6, urgency: urgency)
        #expect(abs(Matrix.score(importance: importance, urgency: urgency) - 0.6) < 0.0001)
    }

    @Test func betweenAveragesNeighbours() {
        let value = Matrix.between((importance: 0.8, urgency: 1), (importance: 0.4, urgency: 0.5))
        #expect(abs((value?.importance ?? 0) - 0.6) < 1e-9)
        #expect(abs((value?.urgency ?? 0) - 0.75) < 1e-9)
        #expect(Matrix.between(nil, (importance: 0.4, urgency: 0.5))?.importance == 0.4)
        #expect(Matrix.between(nil, nil) == nil)
    }

    @Test func insertionRanksBetweenWithoutInventingADeadline() {
        let above = Matrix.Rank(importance: 0.9, days: nil)
        let below = Matrix.Rank(importance: 0.5, days: nil)
        let new = Matrix.insertion(above: above, below: below)
        #expect(new?.days == nil)
        let score = new?.score ?? 0
        #expect(score < above.score && score > below.score)
    }

    @Test func insertionBetweenDeadlinesTakesOneOfThem() {
        // Both due today: importance alone can't reach their score, so it borrows the deadline.
        let above = Matrix.Rank(importance: 0.9, days: 0)
        let below = Matrix.Rank(importance: 0.8, days: 0)
        let new = Matrix.insertion(above: above, below: below)
        #expect(new?.days == 0)
        let score = new?.score ?? 0
        #expect(score < above.score && score > below.score)
    }

    @Test func insertionAtTheEdgesAndOverdue() {
        let only = Matrix.Rank(importance: 0.3, days: nil)
        let after = Matrix.insertion(above: only, below: nil)
        let before = Matrix.insertion(above: nil, below: only)
        #expect((after?.score ?? 1) < only.score)
        #expect((before?.score ?? 0) > only.score)
        #expect(Matrix.insertion(above: nil, below: nil) == nil)
        // Overdue counts as today; a new task never gets a deadline in the past.
        #expect(Matrix.Rank(importance: 0.5, days: -3).days == 0)
    }

    @Test func columns() {
        #expect(Matrix.column(forDays: -2) == 0)
        #expect(Matrix.column(forDays: 14) == 14)
        #expect(Matrix.column(forDays: 30) == 15)
        #expect(Matrix.column(forDays: nil) == 15)
        #expect(Matrix.days(forColumn: 15) == nil)
        #expect(Matrix.columns == 16)
    }
}

@Suite("Ranked order")
struct RankedOrderTests {
    @Test func openSiblingsFollowTheirRankAndKeepSubtasks() {
        let lines = [
            PlanLine(sortOrder: 0, indent: 0, estimate: 1),   // rank 1
            PlanLine(sortOrder: 1, indent: 1, estimate: 9),   // its subtask
            PlanLine(sortOrder: 2, indent: 0, estimate: 5),   // rank 5
            PlanLine(sortOrder: 3, indent: 0, estimate: 5),   // ties keep manual order
        ]
        let order = Checklist.displayOrder(lines, showCompleted: true, rank: { $0.estimate }).map(\.item.sortOrder)
        #expect(order == [2, 3, 0, 1])
    }
}

@Suite("Exact dates and nested import")
struct ImportExtrasTests {
    @Test func exactDeadlineToken() {
        let entry = QuickParser.parse("mail absenden (0,25PH) 📅 2026-11-04", groups: [], options: [.exactDates, .estimate])
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: entry.due!)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 4)
        #expect(entry.estimate == 0.25)
        #expect(entry.title == "mail absenden")
    }

    @Test func exactDatesNeverGuess() {
        let entry = QuickParser.parse("Empl 09.09 keine antwort", groups: [], options: [.exactDates])
        #expect(entry.due == nil)
        #expect(entry.title == "Empl 09.09 keine antwort")
    }

    @Test func headingLevels() {
        let lines = NotesImport.parse("# haeb tasks\n## 1. Laufend\n- [ ] doks schicken", plainLinesAreHeadings: false)
        #expect(lines.map(\.level) == [1, 2, 1])
        #expect(lines[1].title == "1. Laufend")
    }
}
