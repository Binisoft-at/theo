import Foundation
import Testing
@testable import TheoCore

@Suite("Deadline time and plan age")
struct DeadlineTimeTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        return calendar
    }()

    private func moment(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? Date(timeIntervalSince1970: 0)
    }

    /// Monday 16 Nov 2026, the logical day starting at 4:00.
    private var monday: Date { moment(16, 4) }

    @Test func midnightTodayBecomesTheNextFullHour() {
        let suggested = DeadlineTime.suggested(for: moment(16), today: monday, now: moment(16, 10, 20), calendar: calendar)
        #expect(suggested == moment(16, 11))
        let onTheHour = DeadlineTime.suggested(for: moment(16), today: monday, now: moment(16, 10), calendar: calendar)
        #expect(onTheHour == moment(16, 11))
    }

    @Test func otherDaysGetNineInTheMorning() {
        #expect(DeadlineTime.suggested(for: moment(18), today: monday, now: moment(16, 10, 20), calendar: calendar) == moment(18, 9))
        #expect(DeadlineTime.suggested(for: moment(13), today: monday, now: moment(16, 10, 20), calendar: calendar) == moment(13, 9))
    }

    @Test func aTimeThatCanStillRemindIsKept() {
        let now = moment(16, 10, 20)
        #expect(DeadlineTime.suggested(for: moment(16, 18), today: monday, now: now, calendar: calendar) == moment(16, 18))
        #expect(DeadlineTime.suggested(for: moment(18, 14, 30), today: monday, now: now, calendar: calendar) == moment(18, 14, 30))
        // A time that has passed today can't remind any more.
        #expect(DeadlineTime.suggested(for: moment(16, 8), today: monday, now: now, calendar: calendar) == moment(16, 11))
    }

    @Test func afterMidnightTodayIsStillTheLogicalDay() {
        let now = moment(17, 1, 30)
        // Due "today" (Monday) while it's 1:30 on Tuesday: the next full hour.
        #expect(DeadlineTime.suggested(for: moment(16), today: monday, now: now, calendar: calendar) == moment(17, 2))
        // Due Tuesday: that's tomorrow in the logical day, so 9:00.
        #expect(DeadlineTime.suggested(for: moment(17), today: monday, now: now, calendar: calendar) == moment(17, 9))
    }

    @Test func planAgeCountsWholeDaysSinceTheRunBegan() {
        #expect(PlanAge.days(since: moment(16), today: monday, calendar: calendar) == 0)
        #expect(PlanAge.days(since: moment(15), today: monday, calendar: calendar) == 1)
        #expect(PlanAge.days(since: moment(13), today: monday, calendar: calendar) == 3)
        // A day that starts at 4:00 still counts from its own date.
        #expect(PlanAge.days(since: moment(13), today: moment(16, 4, 30), calendar: calendar) == 3)
    }

    @Test func planAgeTextNamesTheDay() {
        let english = Locale(identifier: "en_US")
        #expect(PlanAge.describe(since: moment(16), today: monday, calendar: calendar, locale: english) == nil)
        #expect(PlanAge.describe(since: moment(15), today: monday, calendar: calendar, locale: english) == "Planned since Sun (1 day)")
        #expect(PlanAge.describe(since: moment(13), today: monday, calendar: calendar, locale: english) == "Planned since Fri (3 days)")
        let longer = PlanAge.describe(since: moment(6), today: monday, calendar: calendar, locale: english) ?? ""
        #expect(longer.hasPrefix("Planned since Fri"))
        #expect(longer.contains("6"))
        #expect(longer.hasSuffix("(10 days)"))
    }
}
