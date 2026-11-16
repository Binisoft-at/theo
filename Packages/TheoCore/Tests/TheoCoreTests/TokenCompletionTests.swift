import Foundation
import Testing
@testable import TheoCore

/// Made-up groups: Work › Admin, Work › Clients, Home › Admin, Theo Launch, Büro.
enum CompletionGroupsFixture {
    static let work = UUID()
    static let workAdmin = UUID()
    static let clients = UUID()
    static let home = UUID()
    static let homeAdmin = UUID()
    static let launch = UUID()
    static let office = UUID()

    static let groups: [QuickParser.GroupRef] = [
        QuickParser.GroupRef(id: work, name: "Work"),
        QuickParser.GroupRef(id: workAdmin, name: "Admin", parentID: work),
        QuickParser.GroupRef(id: clients, name: "Clients", parentID: work),
        QuickParser.GroupRef(id: home, name: "Home"),
        QuickParser.GroupRef(id: homeAdmin, name: "Admin", parentID: home),
        QuickParser.GroupRef(id: launch, name: "Theo Launch"),
        QuickParser.GroupRef(id: office, name: "Büro"),
    ]
}

@Suite("Token completion: the word being typed")
struct ActiveTokenTests {
    @Test func groupWordAtTheEnd() throws {
        let text = "Call the bank @wo"
        let token = try #require(TokenCompletion.activeToken(in: text))
        #expect(token.kind == .group)
        #expect(token.prefix == "wo")
        #expect(String(text[token.range]) == "@wo")
    }

    @Test func tagWordAtTheEnd() throws {
        let text = "Send the quote #inv"
        let token = try #require(TokenCompletion.activeToken(in: text))
        #expect(token.kind == .tag)
        #expect(token.prefix == "inv")
        #expect(String(text[token.range]) == "#inv")
    }

    @Test func sigilAloneOffersEverything() throws {
        let token = try #require(TokenCompletion.activeToken(in: "@"))
        #expect(token.kind == .group)
        #expect(token.prefix == "")
        let tag = try #require(TokenCompletion.activeToken(in: "Water plants #"))
        #expect(tag.kind == .tag)
        #expect(tag.prefix == "")
    }

    @Test func pathIsOneWord() throws {
        let token = try #require(TokenCompletion.activeToken(in: "File receipts @Work/Ad"))
        #expect(token.prefix == "Work/Ad")
    }

    @Test func lastLineOfSeveral() throws {
        let text = "First line\nSecond #ho"
        let token = try #require(TokenCompletion.activeToken(in: text))
        #expect(token.prefix == "ho")
        #expect(String(text[token.range]) == "#ho")
    }

    @Test(arguments: [
        "",
        "Call the bank @work ",
        "Learn C#",
        "Learn C#x",
        "mail@home",
        "Fix issue #42 today",
        "Call bank // ask about #fe",
        "@@work",
        "#a#b",
        "Plain words",
    ])
    func noActiveToken(text: String) {
        #expect(TokenCompletion.activeToken(in: text) == nil)
    }

    @Test func completeReplacesTheWordAndAddsASpace() {
        #expect(TokenCompletion.complete("Call the bank @wo", with: "@Work") == "Call the bank @Work ")
        #expect(TokenCompletion.complete("#inv", with: "#invoices") == "#invoices ")
        #expect(TokenCompletion.complete("Line one\nFile @wo/ad", with: "@Work/Admin") == "Line one\nFile @Work/Admin ")
        #expect(TokenCompletion.complete("Nothing to complete ", with: "@Work") == "Nothing to complete ")
    }

    @Test func typedInFull() {
        #expect(TokenCompletion.isTyped("@Home", in: "Mow the lawn @home"))
        #expect(TokenCompletion.isTyped("@Büro", in: "Order paper @buro"))
        #expect(!TokenCompletion.isTyped("@Home", in: "Mow the lawn @hom"))
        #expect(!TokenCompletion.isTyped("@Home", in: "Mow the lawn @home "))
    }
}

@Suite("Token completion: ranking")
struct CompletionRankingTests {
    @Test func exactThenPrefixThenContains() {
        let candidates = ["Administration", "Admin", "Badminton", "Work/Admin", "Home office"]
        // Equal (also the last part of a path), then starting a word, then containing it.
        #expect(TokenCompletion.ranked(candidates, query: "admin") == [1, 3, 0, 2])
    }

    @Test func caseAndAccentsDontMatter() {
        #expect(TokenCompletion.ranked(["Bureau", "Büro"], query: "BU") == [1, 0])
        #expect(TokenCompletion.ranked(["Bureau", "Büro"], query: "bü") == [1, 0])
        #expect(TokenCompletion.ranked(["Café"], query: "CAFE") == [0])
    }

    @Test func startOfAWordBeatsInsideAWord() {
        // "la" starts "Launch" but sits inside "Relaunch"; the longer name still comes first.
        #expect(TokenCompletion.ranked(["Relaunch", "Theo Launch"], query: "la") == [1, 0])
        #expect(TokenCompletion.ranked(["home-office", "Postbox"], query: "of") == [0])
    }

    @Test func spacesAreIgnored() {
        #expect(TokenCompletion.ranked(["Theo Launch", "Theory"], query: "theola") == [0])
    }

    @Test func equalMatchesKeepTheirOrder() {
        #expect(TokenCompletion.ranked(["abce", "abcd", "abcf"], query: "ab") == [0, 1, 2])
        #expect(TokenCompletion.ranked(["Gardening", "Garage"], query: "gar") == [1, 0])
    }

    @Test func nothingTypedKeepsEverythingInOrder() {
        #expect(TokenCompletion.ranked(["Work", "Home", "Admin"], query: "") == [0, 1, 2])
        #expect(TokenCompletion.ranked(["Work", "Home"], query: "/") == [0, 1])
        #expect(TokenCompletion.ranked(["Work", "Home"], query: "-") == [])
    }

    @Test func pathQueries() {
        let candidates = ["Work", "Work/Admin", "Work/Clients", "Home/Admin", "Work › Archive"]
        // "Work/" lists what's inside Work, not Work itself.
        #expect(TokenCompletion.ranked(candidates, query: "Work/") == [1, 2, 4])
        #expect(TokenCompletion.ranked(candidates, query: "work/ad") == [1])
        #expect(TokenCompletion.ranked(candidates, query: "wo") == [0, 1, 2, 4])
        #expect(TokenCompletion.ranked(candidates, query: "home/admin") == [3])
    }

    @Test func noMatchIsEmpty() {
        #expect(TokenCompletion.ranked(["Work", "Home"], query: "xyz").isEmpty)
    }
}

@Suite("Token completion: groups and tags")
struct CompletionSuggestionTests {
    typealias Fixture = CompletionGroupsFixture

    @Test func everyGroupWithTheWordThatFindsIt() {
        let suggestions = TokenCompletion.groups(matching: "", in: Fixture.groups, limit: 10)
        #expect(suggestions.map(\.id) == Fixture.groups.map(\.id))
        #expect(suggestions.map(\.insertion) == [
            "@Work", "@Work/Admin", "@Clients", "@Home", "@Home/Admin", "@TheoLaunch", "@Büro",
        ])
        #expect(suggestions[1].path == ["Work", "Admin"])
    }

    @Test func insertionsReadBackAsTheSameGroup() throws {
        for group in Fixture.groups {
            let word = try #require(TokenCompletion.insertion(for: group.id, in: Fixture.groups))
            let entry = QuickParser.parse("Sort the mail " + word, groups: Fixture.groups)
            #expect(entry.groupID == group.id)
            #expect(entry.title == "Sort the mail")
        }
    }

    @Test func limitAndRanking() {
        let admins = TokenCompletion.groups(matching: "adm", in: Fixture.groups)
        #expect(admins.map(\.id) == [Fixture.workAdmin, Fixture.homeAdmin])
        #expect(TokenCompletion.groups(matching: "", in: Fixture.groups, limit: 2).count == 2)
        #expect(TokenCompletion.groups(matching: "zzz", in: Fixture.groups).isEmpty)
    }

    @Test func pathTyped() {
        let inside = TokenCompletion.groups(matching: "Work/", in: Fixture.groups)
        #expect(inside.map(\.id) == [Fixture.workAdmin, Fixture.clients])
    }

    @Test func nameWithoutLettersIsNotOffered() {
        let party = UUID()
        let groups = Fixture.groups + [QuickParser.GroupRef(id: party, name: "🎉")]
        #expect(TokenCompletion.insertion(for: party, in: groups) == nil)
        let offered = TokenCompletion.groups(matching: "", in: groups, limit: 20).map(\.id)
        #expect(offered.count == Fixture.groups.count)
        #expect(!offered.contains(party))
    }

    @Test func deepPathsUseJustEnough() {
        let clients = UUID()
        let deepWork = UUID()
        let deepAdmin = UUID()
        let groups = Fixture.groups + [
            QuickParser.GroupRef(id: clients, name: "Clients Old"),
            QuickParser.GroupRef(id: deepWork, name: "Work", parentID: clients),
            QuickParser.GroupRef(id: deepAdmin, name: "Admin", parentID: deepWork),
        ]
        #expect(TokenCompletion.insertion(for: Fixture.workAdmin, in: groups) == "@Work/Admin")
        #expect(TokenCompletion.insertion(for: deepAdmin, in: groups) == "@ClientsOld/Work/Admin")
        #expect(TokenCompletion.insertion(for: Fixture.work, in: groups) == "@Work")
        #expect(TokenCompletion.insertion(for: deepWork, in: groups) == "@ClientsOld/Work")
    }

    @Test func tagCountsCountEachTaskOnce() {
        let counts = TokenCompletion.tagCounts([["invoices", "work"], ["invoices"], ["home"], ["invoices", "invoices"], [""]])
        #expect(counts == ["invoices": 3, "work": 1, "home": 1])
    }

    @Test func tagsRankedThenMostUsed() {
        let counts = ["invoices": 3, "inbox": 5, "admin": 2, "garden": 9]
        let found = TokenCompletion.tags(matching: "in", counts: counts)
        #expect(found.map(\.tag) == ["inbox", "invoices", "admin"])
        #expect(found.first?.count == 5)
        #expect(found.first?.insertion == "#inbox")
    }

    @Test func nothingTypedShowsMostUsedFirst() {
        let found = TokenCompletion.tags(matching: "", counts: ["alpha": 1, "beta": 3, "gamma": 3], limit: 2)
        #expect(found.map(\.tag) == ["beta", "gamma"])
    }
}

@Suite("Group paths in quick entry")
struct GroupPathParsingTests {
    typealias Fixture = CompletionGroupsFixture

    @Test(arguments: ["@Work/Admin", "@work/admin", "@WORK/ADMIN", "@wo/adm"])
    func pathFindsTheSubgroup(word: String) {
        let entry = QuickParser.parse("Send the invoice \(word)", groups: Fixture.groups)
        #expect(entry.groupID == Fixture.workAdmin)
        #expect(entry.groupName == "Admin")
        #expect(entry.title == "Send the invoice")
    }

    @Test func theOtherAdmin() {
        let entry = QuickParser.parse("Renew the insurance @home/admin", groups: Fixture.groups)
        #expect(entry.groupID == Fixture.homeAdmin)
    }

    @Test(arguments: ["@buro", "@Büro", "@BURO"])
    func accentsDontMatter(word: String) {
        let entry = QuickParser.parse("Order paper \(word)", groups: Fixture.groups)
        #expect(entry.groupID == Fixture.office)
    }

    @Test func plainUniqueNameStillWorks() {
        let entry = QuickParser.parse("Call the client @Clients", groups: Fixture.groups)
        #expect(entry.groupID == Fixture.clients)
        let unique = [
            QuickParser.GroupRef(id: Fixture.work, name: "Work"),
            QuickParser.GroupRef(id: Fixture.workAdmin, name: "Admin", parentID: Fixture.work),
        ]
        #expect(QuickParser.parse("Tidy up @Admin", groups: unique).groupID == Fixture.workAdmin)
        #expect(QuickParser.parse("Tidy up @adm", groups: unique).groupID == Fixture.workAdmin)
    }

    @Test func trailingSlashIsTheGroupItself() {
        let entry = QuickParser.parse("Plan the week @Work/", groups: Fixture.groups)
        #expect(entry.groupID == Fixture.work)
    }

    @Test func topLevelWinsTheSameName() {
        let archive = UUID()
        let oldWork = UUID()
        let work = UUID()
        let groups = [
            QuickParser.GroupRef(id: archive, name: "Archive"),
            QuickParser.GroupRef(id: oldWork, name: "Work", parentID: archive),
            QuickParser.GroupRef(id: work, name: "Work"),
        ]
        #expect(QuickParser.parse("Plan the week @work", groups: groups).groupID == work)
        #expect(QuickParser.parse("Plan the week @archive/work", groups: groups).groupID == oldWork)
    }

    @Test func unknownPathStaysInTitle() {
        let entry = QuickParser.parse("Read @Garden/Shed notes", groups: Fixture.groups)
        #expect(entry.groupID == nil)
        #expect(entry.title == "Read @Garden/Shed notes")
    }

    @Test func slashInANameWithoutParents() {
        let quarter = UUID()
        let groups = [QuickParser.GroupRef(id: quarter, name: "Q3/Q4")]
        #expect(QuickParser.parse("Review targets @q3/q4", groups: groups).groupID == quarter)
    }

    @Test func pathsStopAtLoopsAndMissingParents() {
        let a = UUID()
        let b = UUID()
        let orphan = UUID()
        let groups = [
            QuickParser.GroupRef(id: a, name: "A", parentID: b),
            QuickParser.GroupRef(id: b, name: "B", parentID: a),
            QuickParser.GroupRef(id: orphan, name: "Orphan", parentID: UUID()),
        ]
        let paths = QuickParser.GroupRef.paths(groups)
        #expect(paths[a] == ["B", "A"])
        #expect(paths[b] == ["A", "B"])
        #expect(paths[orphan] == ["Orphan"])
    }
}
