import Foundation
import Testing
@testable import TheoCore

@Suite("Repeat rules")
struct RepeatRulesTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date(timeIntervalSince1970: 0)
    }

    @Test func aRepeatWithoutADateStartsToday() {
        var entry = ParsedEntry(title: "Water the plants")
        entry.recurrence = .weekly
        let today = day(2026, 11, 16, 15)
        let first = entry.withFirstOccurrence(today: today, calendar: calendar)
        #expect(first.due == day(2026, 11, 16))
        #expect(first.dueHasTime == false)
        #expect(first.recurrence == .weekly)
    }

    @Test func aGivenDateOrNoRepeatStaysAsItIs() {
        var timed = ParsedEntry(title: "Team sync")
        timed.recurrence = .weekly
        timed.due = day(2026, 11, 20, 9)
        timed.dueHasTime = true
        #expect(timed.withFirstOccurrence(today: day(2026, 11, 16), calendar: calendar) == timed)

        let once = ParsedEntry(title: "Buy stamps")
        #expect(once.withFirstOccurrence(today: day(2026, 11, 16), calendar: calendar).due == nil)
    }

    @Test func monthlyKeepsItsDayOfTheMonth() {
        var due = day(2027, 1, 31, 9)
        var days: [Int] = []
        for _ in 0..<3 {
            due = Recurrence.monthly.next(after: due, anchorDay: 31, calendar: calendar)
            days.append(calendar.component(.day, from: due))
        }
        #expect(days == [28, 31, 30])
        #expect(calendar.component(.month, from: due) == 4)
        #expect(calendar.component(.hour, from: due) == 9)
    }

    @Test func yearlyComesBackToTheLeapDay() {
        var due = day(2028, 2, 29)
        for year in 2029...2032 {
            due = Recurrence.yearly.next(after: due, anchorDay: 29, calendar: calendar)
            #expect(calendar.component(.year, from: due) == year)
            #expect(calendar.component(.month, from: due) == 2)
            #expect(calendar.component(.day, from: due) == (year == 2032 ? 29 : 28))
        }
    }

    @Test func otherRepeatsIgnoreTheAnchor() {
        let due = day(2026, 11, 13, 8)
        #expect(Recurrence.daily.next(after: due, anchorDay: 31, calendar: calendar) == day(2026, 11, 14, 8))
        #expect(Recurrence.weekly.keepsDayOfMonth == false)
        #expect(Recurrence.monthly.keepsDayOfMonth)
    }

    @Test func anOverdueDailyRepeatComesBackTomorrow() {
        let threeDaysAgo = day(2026, 11, 13)
        let tomorrow = day(2026, 11, 17)
        #expect(Recurrence.daily.nextOccurrence(after: threeDaysAgo, notBefore: tomorrow, anchorDay: nil, calendar: calendar) == tomorrow)
    }

    @Test func aWeeklyRepeatDoneLateKeepsItsWeekday() {
        let lastMonday = day(2026, 11, 9, 10)
        let dayAfterWednesday = day(2026, 11, 12)
        let next = Recurrence.weekly.nextOccurrence(after: lastMonday, notBefore: dayAfterWednesday, anchorDay: nil, calendar: calendar)
        #expect(next == day(2026, 11, 16, 10))
    }

    @Test func aMonthlyRepeatDoneEarlyMovesOneMonth() {
        let dueFirstOfDecember = day(2026, 12, 1)
        let tomorrow = day(2026, 11, 17)
        let next = Recurrence.monthly.nextOccurrence(after: dueFirstOfDecember, notBefore: tomorrow, anchorDay: 1, calendar: calendar)
        #expect(next == day(2027, 1, 1))
    }

    @Test func inlineDueWordsAreLowerCase() {
        let current = Calendar.current
        let today = current.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12)) ?? Date()
        let yesterday = current.date(byAdding: .day, value: -1, to: today) ?? today
        let tomorrow = current.date(byAdding: .day, value: 1, to: today) ?? today
        let later = current.date(byAdding: .day, value: 20, to: today) ?? today
        #expect(DateText.dueInline(yesterday, hasTime: false, today: today) == "yesterday")
        #expect(DateText.dueInline(today, hasTime: false, today: today) == "today")
        #expect(DateText.dueInline(tomorrow, hasTime: false, today: today) == "tomorrow")
        #expect(DateText.dueInline(later, hasTime: false, today: today) == DateText.due(later, hasTime: false, today: today))
    }

    @Test func inlineMarksRankAsImportant() {
        let parsed = QuickParser.parse("Renew the passport !!!", groups: [], options: [.priority])
        #expect(parsed.priority == .high)
        let importance = Matrix.importance(for: parsed.priority, current: Matrix.defaultImportance)
        #expect(Matrix.level(forImportance: importance) >= 9)
    }
}
