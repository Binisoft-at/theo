import Foundation
import Testing
@testable import TheoCore

@Suite("Ongoing tasks and import notes")
struct OngoingImportTests {
    @Test(arguments: ["Check the account ∞", "Konto prüfen laufend", "ongoing: inbox zero ongoing", "Mails andauernd"])
    func ongoingWordsMarkTheTask(text: String) {
        let entry = QuickParser.parse(text, groups: [])
        #expect(entry.ongoing)
        #expect(!entry.title.lowercased().contains("∞"))
        #expect(entry.hasExtras)
    }

    @Test func ongoingNeedsItsOption() {
        let entry = QuickParser.parse("Check the account ∞", groups: [], options: [.priority])
        #expect(!entry.ongoing)
        #expect(entry.title == "Check the account ∞")
    }

    @Test func ordinaryWordsStayInTheTitle() {
        let entry = QuickParser.parse("laufende Kosten prüfen", groups: [])
        #expect(!entry.ongoing)
        #expect(entry.title == "laufende Kosten prüfen")
    }

    @Test func descriptionAfterDoubleSlash() {
        let entry = QuickParser.parse("Call bank tomorrow !! // ask about the fee, and the card", groups: [])
        #expect(entry.title == "Call bank")
        #expect(entry.notes == "ask about the fee, and the card")
        #expect(entry.priority == .medium)
        #expect(entry.due != nil)
        let link = QuickParser.parse("Read https://example.com/a//b", groups: [])
        #expect(link.notes.isEmpty)
        #expect(link.title == "Read https://example.com/a//b")
    }

    @Test func noteLinesBelongToTheTaskAbove() {
        let text = """
        # Office
        - [ ] Check the invoices (0,25PH)
          > Two are still missing
          > Ask the bank about the fee
        - [ ] Pay the rest
        """
        let lines = NotesImport.parse(text, plainLinesAreHeadings: false)
        #expect(lines.count == 5)
        #expect(lines[2].isNote && lines[3].isNote)
        #expect(lines[2].title == "Two are still missing")
        #expect(!lines[1].isNote && !lines[4].isNote)
    }
}
