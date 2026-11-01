import Foundation
import Testing
@testable import TheoCore

private struct Line: ChecklistItem, Estimated {
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
            Line(sortOrder: 0, indent: 0, estimate: 2),   // parent with a total ...
            Line(sortOrder: 1, indent: 1, estimate: 1),   // ... and estimated subtasks
            Line(sortOrder: 2, indent: 1, estimate: 1),
            Line(sortOrder: 3, indent: 0, estimate: 3),   // parent with plain subtasks
            Line(sortOrder: 4, indent: 1, estimate: 0),
            Line(sortOrder: 5, indent: 0, estimate: 0.25),
        ]
        #expect(PowerHours.total(lines) == 5.25)
    }

    @Test func totalCanBeFiltered() {
        let lines = [
            Line(sortOrder: 0, indent: 0, isDone: true, estimate: 0.5),
            Line(sortOrder: 1, indent: 0, estimate: 1),
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
    @Test func defaultsSitInLater() {
        #expect(Matrix.quadrant(urgency: Matrix.defaultUrgency, importance: Matrix.defaultImportance) == .later)
    }

    @Test func scoreFollowsEisenhowerOrder() {
        let doFirst = Matrix.score(urgency: 0.75, importance: 0.75)
        let schedule = Matrix.score(urgency: 0.25, importance: 0.75)
        let delegate = Matrix.score(urgency: 0.75, importance: 0.25)
        let later = Matrix.score(urgency: 0.25, importance: 0.25)
        #expect(doFirst > schedule && schedule > delegate && delegate > later)
    }

    @Test func distanceInsideAQuadrantCounts() {
        #expect(Matrix.score(urgency: 0.9, importance: 0.95) > Matrix.score(urgency: 0.6, importance: 0.6))
    }

    @Test func priorityRaisesImportance() {
        #expect(Matrix.effectiveImportance(0.25, priority: .normal) == 0.25)
        #expect(Matrix.effectiveImportance(0.25, priority: .high) > 0.5)
        #expect(Matrix.effectiveImportance(0.9, priority: .high) == 1)
    }

    @Test func deadlinesRaiseUrgency() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextMonth = calendar.date(byAdding: .day, value: 30, to: today)!
        #expect(Matrix.effectiveUrgency(0.25, due: tomorrow, today: today, calendar: calendar) > 0.5)
        #expect(Matrix.effectiveUrgency(0.25, due: nextMonth, today: today, calendar: calendar) == 0.25)
        #expect(Matrix.effectiveUrgency(0.25, due: nil, today: today, calendar: calendar) == 0.25)
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
