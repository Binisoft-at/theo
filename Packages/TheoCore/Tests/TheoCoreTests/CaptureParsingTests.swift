import Foundation
import Testing
@testable import TheoCore

/// One line typed into the composer and what it should become. `due` is "2026-11-13" or
/// "2026-12-15 14:00" (Vienna time); nil means no deadline.
struct CaptureDateCase: Sendable, CustomStringConvertible {
    let text: String
    let title: String
    let due: String?

    var description: String { text }
}

/// A repeat typed into the composer.
struct CaptureRepeatCase: Sendable, CustomStringConvertible {
    let text: String
    let recurrence: Recurrence
    let title: String

    var description: String { text }
}

/// A fixed week: today is Wednesday 11 November 2026 in Vienna (the logical day starts at 4:00),
/// and it's 08:00.
enum CaptureFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    static let english = Locale(identifier: "en_US")

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static let today = date(2026, 11, 11, 4)
    static let clock = date(2026, 11, 11, 8)

    static func parse(
        _ text: String,
        options: QuickParser.Options = .all,
        now: Date = CaptureFixture.today,
        clock: Date = CaptureFixture.clock
    ) -> ParsedEntry {
        QuickParser.parse(text, groups: [], options: options, now: now, clock: clock, calendar: CaptureFixture.calendar)
    }

    static func stamp(_ date: Date?, hasTime: Bool) -> String? {
        guard let date else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var text = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        if hasTime { text += String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0) }
        return text
    }

    /// German and English, the way they get typed. A bare "dd.mm" only counts within the next
    /// six months (183 days) or after a connector ("am", "bis"): numbers in notes are often
    /// references to the past.
    static let dateCases: [CaptureDateCase] = [
        CaptureDateCase(text: "Rechnung zahlen morgen", title: "Rechnung zahlen", due: "2026-11-12"),
        CaptureDateCase(text: "morgen Zahnarzt", title: "Zahnarzt", due: "2026-11-12"),
        CaptureDateCase(text: "Zahnarzt morgen 9 Uhr", title: "Zahnarzt", due: "2026-11-12 09:00"),
        CaptureDateCase(text: "Steuer abgeben bis Freitag", title: "Steuer abgeben", due: "2026-11-13"),
        CaptureDateCase(text: "Bericht bis Fr", title: "Bericht", due: "2026-11-13"),
        CaptureDateCase(text: "Fr 15 Uhr Zahnarzt", title: "Zahnarzt", due: "2026-11-13 15:00"),
        CaptureDateCase(text: "Termin am Mittwoch", title: "Termin", due: "2026-11-11"),
        CaptureDateCase(text: "Meeting nächsten Freitag", title: "Meeting", due: "2026-11-20"),
        CaptureDateCase(text: "Meeting next monday", title: "Meeting", due: "2026-11-16"),
        CaptureDateCase(text: "Treffen um 14 Uhr am Freitag", title: "Treffen", due: "2026-11-13 14:00"),
        CaptureDateCase(text: "Arzt am 15.12. um 14 Uhr", title: "Arzt", due: "2026-12-15 14:00"),
        CaptureDateCase(text: "Rechnung 15.12", title: "Rechnung", due: "2026-12-15"),
        CaptureDateCase(text: "Steuer bis 15.12.2026", title: "Steuer", due: "2026-12-15"),
        CaptureDateCase(text: "Antrag bis zum 15.01.", title: "Antrag", due: "2027-01-15"),
        CaptureDateCase(text: "Vertrag am 09.09", title: "Vertrag", due: "2027-09-09"),
        CaptureDateCase(text: "Anfrage 09.09 keine Antwort", title: "Anfrage 09.09 keine Antwort", due: nil),
        CaptureDateCase(text: "Milch 1.5 Liter", title: "Milch 1.5 Liter", due: nil),
        CaptureDateCase(text: "Version 2.11 testen", title: "Version 2.11 testen", due: nil),
        CaptureDateCase(text: "Fenster putzen übermorgen", title: "Fenster putzen", due: "2026-11-13"),
        CaptureDateCase(text: "Pakete holen in 3 Tagen", title: "Pakete holen", due: "2026-11-14"),
        CaptureDateCase(text: "Kündigen in zwei Wochen", title: "Kündigen", due: "2026-11-25"),
        CaptureDateCase(text: "Abrechnung Monatsende", title: "Abrechnung", due: "2026-11-30"),
        CaptureDateCase(text: "Review end of month", title: "Review", due: "2026-11-30"),
        CaptureDateCase(text: "Report next week", title: "Report", due: "2026-11-16"),
        CaptureDateCase(text: "Plan party this weekend", title: "Plan party", due: "2026-11-14"),
        CaptureDateCase(text: "Call Anna tomorrow 5pm", title: "Call Anna", due: "2026-11-12 17:00"),
        CaptureDateCase(text: "Call at 14:30", title: "Call", due: "2026-11-11 14:30"),
        CaptureDateCase(text: "Anruf um 9", title: "Anruf", due: "2026-11-11 09:00"),
        CaptureDateCase(text: "Morgenroutine planen", title: "Morgenroutine planen", due: nil),
        CaptureDateCase(text: "Spaziergang am Morgen", title: "Spaziergang am Morgen", due: nil),
        CaptureDateCase(text: "guten Morgen sagen", title: "guten Morgen sagen", due: nil),
        CaptureDateCase(text: "Rechnung zahlen Morgen", title: "Rechnung zahlen Morgen", due: nil),
        CaptureDateCase(text: "Mail an Fr. Müller", title: "Mail an Fr. Müller", due: nil),
        CaptureDateCase(text: "do the laundry", title: "do the laundry", due: nil),
        CaptureDateCase(text: "Diät ab Montag", title: "Diät ab Montag", due: nil),
        CaptureDateCase(text: "Montagsmeeting vorbereiten", title: "Montagsmeeting vorbereiten", due: nil),
    ]
}

@Suite("Capture parsing")
struct CaptureParsingTests {
    // MARK: Dates

    @Test(arguments: CaptureFixture.dateCases)
    func readsTypedDates(_ testCase: CaptureDateCase) {
        let entry = CaptureFixture.parse(testCase.text)
        #expect(entry.title == testCase.title)
        #expect(CaptureFixture.stamp(entry.due, hasTime: entry.dueHasTime) == testCase.due)
    }

    @Test func chipKnowsWhichWordsWereTaken() throws {
        let text = "Steuer abgeben bis Freitag"
        let match = try #require(RelativeDate.find(in: text, today: CaptureFixture.today, calendar: CaptureFixture.calendar))
        #expect(String(text[match.range]) == "bis Freitag")
        #expect(match.hasDay)
        #expect(!match.hasTime)
        #expect(CaptureFixture.parse(text).dueText == "bis Freitag")
    }

    @Test func aTimeThatHasPassedIsTomorrow() {
        let entry = CaptureFixture.parse("Anruf um 9", clock: CaptureFixture.date(2026, 11, 11, 10))
        #expect(entry.title == "Anruf")
        #expect(CaptureFixture.stamp(entry.due, hasTime: entry.dueHasTime) == "2026-11-12 09:00")
        // A named day keeps its time even when it has passed.
        let today = CaptureFixture.parse("Anruf heute um 9", clock: CaptureFixture.date(2026, 11, 11, 10))
        #expect(CaptureFixture.stamp(today.due, hasTime: today.dueHasTime) == "2026-11-11 09:00")
    }

    /// At 01:30 the logical day is still Tuesday 10 November, so "morgen" is Wednesday 11.
    @Test func afterMidnightTomorrowFollowsTheLogicalDay() {
        let logicalDay = CaptureFixture.date(2026, 11, 10, 4)
        let lateNight = CaptureFixture.date(2026, 11, 11, 1, 30)
        let entry = CaptureFixture.parse("Zahnarzt anrufen morgen", now: logicalDay, clock: lateNight)
        #expect(entry.title == "Zahnarzt anrufen")
        #expect(CaptureFixture.stamp(entry.due, hasTime: entry.dueHasTime) == "2026-11-11")
        let english = CaptureFixture.parse("Call the dentist tomorrow", now: logicalDay, clock: lateNight)
        #expect(CaptureFixture.stamp(english.due, hasTime: english.dueHasTime) == "2026-11-11")
        // "um 2" at 01:30 is in half an hour, not yesterday at 2.
        let soon = CaptureFixture.parse("Backup prüfen um 2", now: logicalDay, clock: lateNight)
        #expect(CaptureFixture.stamp(soon.due, hasTime: soon.dueHasTime) == "2026-11-11 02:00")
    }

    @Test func turningDatesOffKeepsTheWords() {
        let entry = CaptureFixture.parse("Meet Anna friday", options: QuickParser.Options.all.subtracting([.dates, .exactDates]))
        #expect(entry.title == "Meet Anna friday")
        #expect(entry.due == nil)
    }

    @Test func dottedDayMonthIsNeverATime() {
        #expect(!QuickParser.containsTime("15.12"))
        #expect(!QuickParser.containsTime("am 15.12.2026"))
        #expect(QuickParser.containsTime("14:30"))
        #expect(QuickParser.containsTime("5pm"))
        #expect(QuickParser.containsTime("14 Uhr"))
    }

    // MARK: Repeats

    @Test func everyMondayIsWeeklyFromTheNextMonday() {
        let entry = CaptureFixture.parse("Team call every monday")
        #expect(entry.recurrence == .weekly)
        #expect(entry.title == "Team call")
        #expect(CaptureFixture.stamp(entry.due, hasTime: entry.dueHasTime) == "2026-11-16")

        let german = CaptureFixture.parse("jeden Montag Meeting")
        #expect(german.recurrence == .weekly)
        #expect(german.title == "Meeting")
        #expect(CaptureFixture.stamp(german.due, hasTime: german.dueHasTime) == "2026-11-16")

        // Today counts: on a Wednesday "every Wednesday" starts today.
        let wednesday = CaptureFixture.parse("Gym every wednesday")
        #expect(CaptureFixture.stamp(wednesday.due, hasTime: wednesday.dueHasTime) == "2026-11-11")
    }

    @Test func weekdayRepeatTakesTheTimeTyped() {
        let entry = CaptureFixture.parse("Standup jeden Montag 9 Uhr")
        #expect(entry.recurrence == .weekly)
        #expect(entry.title == "Standup")
        #expect(CaptureFixture.stamp(entry.due, hasTime: entry.dueHasTime) == "2026-11-16 09:00")
    }

    @Test func dontRepeatGivesTheWordsBack() {
        let entry = CaptureFixture.parse("Team call every monday", options: QuickParser.Options.all.subtracting(.recurrence))
        #expect(entry.recurrence == nil)
        #expect(entry.due == nil)
        #expect(entry.title == "Team call every monday")
    }

    @Test(arguments: [
        CaptureRepeatCase(text: "alle 2 Wochen Bericht", recurrence: .everyDays(14), title: "Bericht"),
        CaptureRepeatCase(text: "Review budget every other week", recurrence: .everyDays(14), title: "Review budget"),
        CaptureRepeatCase(text: "Rasen mähen jede zweite Woche", recurrence: .everyDays(14), title: "Rasen mähen"),
        CaptureRepeatCase(text: "Plants biweekly", recurrence: .everyDays(14), title: "Plants"),
        CaptureRepeatCase(text: "Bericht zweiwöchentlich", recurrence: .everyDays(14), title: "Bericht"),
        CaptureRepeatCase(text: "Report every 3 weeks", recurrence: .everyDays(21), title: "Report"),
        CaptureRepeatCase(text: "Gym alle drei Tage", recurrence: .everyDays(3), title: "Gym"),
        CaptureRepeatCase(text: "jeden Morgen Zähne putzen", recurrence: .daily, title: "Zähne putzen"),
        CaptureRepeatCase(text: "Stretch every evening", recurrence: .daily, title: "Stretch"),
    ])
    func readsRepeats(_ testCase: CaptureRepeatCase) {
        let entry = CaptureFixture.parse(testCase.text)
        #expect(entry.recurrence == testCase.recurrence)
        #expect(entry.title == testCase.title)
        // "jeden Morgen" is a repeat, never "tomorrow".
        #expect(entry.due == nil)
    }

    @Test func repeatTitles() {
        #expect(Recurrence.everyDays(14).title == "Every 2 Weeks")
        #expect(Recurrence.everyDays(21).title == "Every 3 Weeks")
        #expect(Recurrence.everyDays(7).title == "Every Week")
        #expect(Recurrence.everyDays(3).title == "Every 3 Days")
        let monday = CaptureFixture.date(2026, 11, 16)
        #expect(Recurrence.weekly.title(firstDue: monday, calendar: CaptureFixture.calendar, locale: CaptureFixture.english) == "Every Monday")
        #expect(Recurrence.weekly.title(firstDue: nil, calendar: CaptureFixture.calendar) == "Every Week")
        #expect(Recurrence.daily.title(firstDue: monday, calendar: CaptureFixture.calendar) == "Every Day")
        let common = Recurrence.common
        let weeklyIndex = common.firstIndex(of: Recurrence.weekly)
        #expect(weeklyIndex.map { common[$0 + 1] } == Recurrence.everyDays(14))
    }

    // MARK: Pasted lists

    @Test func tickedLinesAreMarkedDone() {
        let text = """
        - [x] Paid the rent
        - [ ] Pay the phone bill
        ☑ Booked flights
          ✅ Packed the bags
        * [X] Sent the invitations
        Buy milk
        """
        let lines = Composer.lines(text)
        #expect(lines.map(\.title) == ["Paid the rent", "Pay the phone bill", "Booked flights", "Packed the bags", "Sent the invitations", "Buy milk"])
        #expect(lines.map(\.done) == [true, false, true, true, true, false])
        #expect(lines.map(\.level) == [0, 0, 0, 1, 0, 0])
    }

    // MARK: Confirmation

    @Test func summaryShowsWhatWasUnderstood() {
        let friday = CaptureFixture.date(2026, 11, 13)
        let summary = CaptureSummary.describe(
            groupName: "Work", due: friday, dueHasTime: false, today: CaptureFixture.today,
            priority: .medium, estimate: 0.5, defaultEstimate: 0.25, recurrence: .daily, ongoing: true,
            calendar: CaptureFixture.calendar, locale: CaptureFixture.english
        )
        #expect(summary == "Work · due Friday · !! · 0.5 PH · ↻ Every Day · ∞")
    }

    @Test func summaryLeavesOutDefaults() {
        let summary = CaptureSummary.describe(
            groupName: "Home", due: nil, dueHasTime: false, today: CaptureFixture.today,
            priority: .normal, estimate: 0.25, defaultEstimate: 0.25, recurrence: nil, ongoing: false,
            calendar: CaptureFixture.calendar, locale: CaptureFixture.english
        )
        #expect(summary == "Home")
    }

    @Test func summaryNamesTheWeekdayOfAWeeklyRepeat() {
        let monday = CaptureFixture.date(2026, 11, 16)
        let summary = CaptureSummary.describe(
            groupName: nil, due: monday, dueHasTime: false, today: CaptureFixture.today,
            priority: .normal, estimate: nil, defaultEstimate: 0.25, recurrence: .weekly, ongoing: false,
            calendar: CaptureFixture.calendar, locale: CaptureFixture.english
        )
        #expect(summary == "due Monday · ↻ Every Monday")
        let tomorrow = CaptureSummary.describe(
            groupName: "Work", due: CaptureFixture.date(2026, 11, 12), dueHasTime: false, today: CaptureFixture.today,
            priority: .normal, estimate: 1, defaultEstimate: 1, recurrence: nil, ongoing: false,
            calendar: CaptureFixture.calendar, locale: Locale(identifier: "de_AT")
        )
        #expect(tomorrow == "Work · due tomorrow")
    }
}
