import Foundation
import Testing
@testable import TheoCore

@Suite("Day review")
struct DayReviewTests {
    private func day(_ offset: Int, _ powerHours: Double) -> DayReview.Day {
        DayReview.Day(start: Date(timeIntervalSince1970: Double(offset) * 86_400), powerHours: powerHours, done: Int(powerHours * 4))
    }

    @Test func averageCountsDaysOff() {
        let days = [day(1, 2), day(2, 0), day(3, 4)]
        #expect(DayReview.average(days) == 2)
        #expect(DayReview.average([]) == 0)
    }

    @Test func comparesWithTheAverage() {
        #expect(DayReview.ratio(3, average: 2) == 1.5)
        #expect(DayReview.ratio(3, average: 0) == nil)
        #expect(DayReview.rank(of: 3, among: [day(1, 2), day(2, 5), day(3, 3)]) == 2)
    }

    @Test func shareOfTasksDone() {
        #expect(DayReview.share(done: 3, open: 1) == 0.75)
        #expect(DayReview.share(done: 0, open: 0) == 0)
    }

    @Test func signedDeltas() {
        let locale = Locale(identifier: "de_AT")
        #expect(DayReview.signed(0.5, locale: locale) == "+0,5 PH")
        #expect(DayReview.signed(-1, locale: locale) == "−1 PH")
        #expect(DayReview.signed(0.001, locale: locale) == "±0 PH")
    }
}

@Suite("CSV")
struct CSVTests {
    @Test func quotesOnlyWhenNeeded() {
        #expect(CSV.field("plain") == "plain")
        #expect(CSV.field("a, b") == "\"a, b\"")
        #expect(CSV.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSV.field("two\nlines") == "\"two\nlines\"")
        #expect(CSV.field("a, b", format: .semicolon) == "a, b")
        #expect(CSV.field("a; b", format: .semicolon) == "\"a; b\"")
    }

    @Test func numbersFollowTheFormat() {
        #expect(CSV.number(0.25) == "0.25")
        #expect(CSV.number(1) == "1")
        #expect(CSV.number(0.5, format: .semicolon) == "0,5")
    }

    @Test func documentHasHeaderAndCRLF() {
        let text = CSV.document(header: ["Task", "PH"], rows: [["Mail, quick", "0.25"]])
        #expect(text == "Task,PH\r\n\"Mail, quick\",0.25\r\n")
        #expect(CSV.Format.for(Locale(identifier: "de_AT")) == .semicolon)
        #expect(CSV.Format.for(Locale(identifier: "en_US")) == .standard)
    }
}
