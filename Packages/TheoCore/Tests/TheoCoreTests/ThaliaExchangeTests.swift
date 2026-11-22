import Foundation
import Testing
@testable import TheoCore

/// Theo's side of the Binisoft exchange (format v1): which facts Theo builds, how it writes and
/// tidies its day files, and how it reads Thalia's catalog. Neutral sample data only.
@Suite("Thalia exchange")
struct ThaliaExchangeTests {
    let vienna = TimeZone(identifier: "Europe/Vienna")!

    /// "Arbeit" mapped to Thalia's 3 Arbeit, "Arbeit/Kunden" mapped to 3.2 Kunden, "Haushalt" not mapped.
    var groups: [TheoExchange.GroupRecord] {
        [
            TheoExchange.GroupRecord(id: "A1", name: "Arbeit"),
            TheoExchange.GroupRecord(id: "91AB", name: "Kunden", parentID: "A1", category: "3.2", categoryTitle: "Kunden"),
            TheoExchange.GroupRecord(id: "22CD", name: "Haushalt"),
        ]
    }

    func date(_ text: String) -> Date { ExchangeDate.parse(text)! }

    func done(_ id: String, _ title: String, group: String?, at: String, estimate: Double = 0,
              order: Double = 0, indent: Int = 0) -> TheoExchange.TaskRecord {
        TheoExchange.TaskRecord(id: id, title: title, groupID: group, isDone: true, completedAt: date(at),
                                estimate: estimate, sortOrder: order, indent: indent)
    }

    func temporaryFolder() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("theo-exchange-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Theo", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func fixture(_ path: String) throws -> Data {
        let base = try #require(Bundle.module.resourceURL)
        return try Data(contentsOf: base.appendingPathComponent("Fixtures/exchange/" + path))
    }

    // MARK: 1. Facts

    @Test func finishedTasksBecomeStableFactsWithTheirGroup() throws {
        let tasks = [done("6F1A2C", "Rechnung schreiben", group: "91AB", at: "2026-11-22T18:04:00+01:00", estimate: 1.5)]
        let first = TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-22", timeZone: vienna)
        let second = TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-22", timeZone: vienna)
        #expect(first == second)
        let facts = try #require(first["2026-11-22"])
        let task = try #require(facts.first { $0.kind == "task.done" })
        #expect(task.id == "task-6F1A2C")
        #expect(task.ref == "grp-91AB")
        #expect(task.refTitle == "Arbeit/Kunden")
        #expect(task.title == "Rechnung schreiben")
        #expect(task.origin == "app")
        #expect(task.at == "2026-11-22T18:04:00+01:00")
        #expect(task.thalia == ExchangeThaliaHint(category: "3.2", categoryTitle: "Kunden"))
        let ph = try #require(facts.first { $0.kind == "ph" })
        #expect(ph.id == "ph-6F1A2C")
        #expect(ph.value == 1.5)
        #expect(ph.unit == "PH")
        #expect(ph.ref == "grp-91AB")
        #expect(ph.thalia == task.thalia)
        #expect(facts.allSatisfy { $0.isFromApp && $0.isKnown })
    }

    @Test func timesAreWrittenWithTheirOffsetAndWithoutFractions() throws {
        let tasks = [done("T1", "Ablage", group: "22CD", at: "2026-07-01T08:15:30.750Z")]
        let facts = TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-07-01", timeZone: vienna)
        let at = try #require(facts["2026-07-01"]?.first?.at)
        #expect(at == "2026-07-01T10:15:30+02:00")
        let utc = TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-07-01", timeZone: TimeZone(identifier: "UTC")!)
        #expect(utc["2026-07-01"]?.first?.at == "2026-07-01T08:15:30Z")
    }

    // MARK: 2. The day in the device's time zone

    @Test func aTaskFinishedLateInUTCBelongsToTheNextViennaDay() {
        let tasks = [done("T2", "Spät", group: "22CD", at: "2026-11-22T23:30:00Z")]
        let facts = TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-23", timeZone: vienna)
        #expect(facts["2026-11-23"]?.count == 1)
        #expect(facts["2026-11-22"] == nil)
    }

    // MARK: 3. Written files read back

    @Test func writtenFilesReadBackWithoutComplaints() throws {
        let folder = temporaryFolder()
        let tasks = [done("6F1A2C", "Rechnung schreiben", group: "91AB", at: "2026-11-22T18:04:00+01:00", estimate: 1.5)]
        let facts = TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-22", timeZone: vienna)
        try ThaliaExchangeWriter.sync(facts, source: TheoExchange.source, appFolder: folder, today: "2026-11-22",
                                      now: date("2026-11-22T18:04:05+01:00"), timeZone: vienna)
        let data = try Data(contentsOf: BinisoftExchange.dayFileURL(appFolder: folder, day: "2026-11-22"))
        guard case .success(let read) = ExchangeReader.dayFile(data, folder: "Theo", fileName: "2026-11-22.json") else {
            Issue.record("day file not readable")
            return
        }
        #expect(read.skipped.isEmpty)
        #expect(read.file.facts.count == 2)
        #expect(read.file.generatedAt == "2026-11-22T18:04:05+01:00")

        try ThaliaExchangeWriter.writeSource(refs: TheoExchange.refs(groups: groups), appVersion: "1.1.0",
                                             source: TheoExchange.source, app: TheoExchange.appName, appFolder: folder,
                                             now: date("2026-11-22T18:04:05+01:00"), timeZone: vienna)
        let source = try Data(contentsOf: ThaliaExchangeWriter.sourceURL(appFolder: folder))
        guard case .success(let info) = ExchangeReader.source(source, folder: "Theo") else {
            Issue.record("source.json not readable")
            return
        }
        #expect(info.source == "theo")
        #expect(info.app == "Theo")
        #expect(info.appVersion == "1.1.0")
        #expect(info.refs.allSatisfy { $0.kind == "group" })
        #expect(info.refs.map(\.title) == ["Arbeit", "Arbeit/Kunden", "Haushalt", "Ohne Gruppe"])
        #expect(info.refs.last?.id == "ohne-gruppe")
        // The JSON as the exchange writes it: no escaped slashes.
        #expect(String(decoding: source, as: UTF8.self).contains("Arbeit/Kunden"))
    }

    // MARK: 4. Keeping the files in step

    @Test func unchangedFactsLeaveTheFileAlone() throws {
        let folder = temporaryFolder()
        let tasks = [done("T3", "Ablage", group: "22CD", at: "2026-11-22T10:30:00+01:00", estimate: 0.5)]
        let facts = TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-22", timeZone: vienna)
        let url = BinisoftExchange.dayFileURL(appFolder: folder, day: "2026-11-22")
        #expect(try ThaliaExchangeWriter.sync(facts, source: "theo", appFolder: folder, today: "2026-11-22",
                                              now: date("2026-11-22T12:00:00+01:00"), timeZone: vienna))
        let before = try Data(contentsOf: url)
        #expect(try !ThaliaExchangeWriter.sync(facts, source: "theo", appFolder: folder, today: "2026-11-22",
                                               now: date("2026-11-22T13:00:00+01:00"), timeZone: vienna))
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func aReopenedTaskDisappearsAndAnEmptiedDayKeepsAnEmptyFile() throws {
        let folder = temporaryFolder()
        var task = done("T4", "Rechnung schreiben", group: "91AB", at: "2026-11-21T09:00:00+01:00")
        let other = done("T5", "Keller aufräumen", group: "22CD", at: "2026-11-21T10:00:00+01:00")
        try ThaliaExchangeWriter.sync(TheoExchange.facts(tasks: [task, other], groups: groups, today: "2026-11-22", timeZone: vienna),
                                      source: "theo", appFolder: folder, today: "2026-11-22",
                                      now: date("2026-11-22T08:00:00+01:00"), timeZone: vienna)
        // Reopened: gone from the day's file.
        task.isDone = false
        try ThaliaExchangeWriter.sync(TheoExchange.facts(tasks: [task, other], groups: groups, today: "2026-11-22", timeZone: vienna),
                                      source: "theo", appFolder: folder, today: "2026-11-22",
                                      now: date("2026-11-22T09:00:00+01:00"), timeZone: vienna)
        let url = BinisoftExchange.dayFileURL(appFolder: folder, day: "2026-11-21")
        let afterReopen = try Data(contentsOf: url)
        guard case .success(let read) = ExchangeReader.dayFile(afterReopen) else {
            Issue.record("day file not readable")
            return
        }
        #expect(read.file.facts.map(\.id) == ["task-T5"])
        // Nothing left on that day: the file stays, with no facts.
        try ThaliaExchangeWriter.sync([:], source: "theo", appFolder: folder, today: "2026-11-22",
                                      now: date("2026-11-22T10:00:00+01:00"), timeZone: vienna)
        let afterEmpty = try Data(contentsOf: url)
        guard case .success(let empty) = ExchangeReader.dayFile(afterEmpty) else {
            Issue.record("day file not readable")
            return
        }
        #expect(empty.file.facts.isEmpty)
        #expect(String(decoding: afterEmpty, as: UTF8.self).contains("\"facts\":[]"))
        // A day that never had anything gets no file.
        #expect(!FileManager.default.fileExists(atPath: BinisoftExchange.dayFileURL(appFolder: folder, day: "2026-11-20").path))
    }

    @Test func movingTheFinishDateRewritesBothDays() throws {
        let folder = temporaryFolder()
        var task = done("T6", "Ablage", group: "22CD", at: "2026-11-20T09:00:00+01:00")
        try ThaliaExchangeWriter.sync(TheoExchange.facts(tasks: [task], groups: groups, today: "2026-11-22", timeZone: vienna),
                                      source: "theo", appFolder: folder, today: "2026-11-22",
                                      now: date("2026-11-22T08:00:00+01:00"), timeZone: vienna)
        task.completedAt = date("2026-11-21T09:00:00+01:00")
        try ThaliaExchangeWriter.sync(TheoExchange.facts(tasks: [task], groups: groups, today: "2026-11-22", timeZone: vienna),
                                      source: "theo", appFolder: folder, today: "2026-11-22",
                                      now: date("2026-11-22T09:00:00+01:00"), timeZone: vienna)
        func facts(_ day: String) throws -> [String] {
            let data = try Data(contentsOf: BinisoftExchange.dayFileURL(appFolder: folder, day: day))
            guard case .success(let read) = ExchangeReader.dayFile(data) else { return ["unreadable"] }
            return read.file.facts.map(\.id)
        }
        #expect(try facts("2026-11-20") == [])
        #expect(try facts("2026-11-21") == ["task-T6"])
    }

    @Test func dayFilesOlderThan62DaysAreRemoved() throws {
        #expect(BinisoftExchange.expiredDayFiles(["2026-09-20.json", "2026-09-21.json", "2026-11-22.json", ".x.json"],
                                                 today: "2026-11-22") == ["2026-09-20.json"])
        let folder = temporaryFolder()
        let days = BinisoftExchange.daysFolder(appFolder: folder)
        try FileManager.default.createDirectory(at: days, withIntermediateDirectories: true)
        for name in ["2026-09-20.json", "2026-09-21.json", ".x.json"] {
            try Data("{}".utf8).write(to: days.appendingPathComponent(name))
        }
        try ThaliaExchangeWriter.sync([:], source: "theo", appFolder: folder, today: "2026-11-22",
                                      now: date("2026-11-22T08:00:00+01:00"), timeZone: vienna)
        let left = try FileManager.default.contentsOfDirectory(atPath: days.path).sorted()
        #expect(left == [".x.json", "2026-09-21.json"])
    }

    @Test func noFactsForTheFutureOrBeyond62Days() {
        let tasks = [
            done("F1", "Morgen", group: "22CD", at: "2026-11-23T09:00:00+01:00"),
            done("F2", "Alt", group: "22CD", at: "2026-09-20T09:00:00+02:00"),
            done("F3", "Gerade noch", group: "22CD", at: "2026-09-21T09:00:00+02:00"),
        ]
        let facts = TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-22", timeZone: vienna)
        #expect(Array(facts.keys) == ["2026-09-21"])
    }

    // MARK: 5. Thalia's test files

    @Test func thaliasTestFilesReadAndTheoWritesTheSameShape() throws {
        let day = try fixture("Theo/exchange/days/2026-11-22.json")
        guard case .success(let read) = ExchangeReader.dayFile(day, folder: "Theo", fileName: "2026-11-22.json") else {
            Issue.record("fixture day file not readable")
            return
        }
        #expect(read.skipped.isEmpty)
        #expect(read.file.facts.count == 4)
        let sourceData = try fixture("Theo/exchange/source.json")
        guard case .success(let source) = ExchangeReader.source(sourceData, folder: "Theo") else {
            Issue.record("fixture source.json not readable")
            return
        }
        #expect(source.refs.count == 2)
        let catalogData = try fixture("Thalia/exchange/catalog.json")
        guard case .success = ExchangeReader.catalog(catalogData) else {
            Issue.record("fixture catalog not readable")
            return
        }
        // Theo's own output for the same day: the same kinds, ids, groups, categories and units.
        let tasks = [
            done("6F1A2C", "Rechnung schreiben", group: "91AB", at: "2026-11-22T18:04:00+01:00"),
            done("77C0", "Rechnung schreiben", group: "91AB", at: "2026-11-22T18:00:00+01:00", estimate: 1.5),
            done("0B3E11", "Keller aufräumen", group: "22CD", at: "2026-11-22T10:30:00+01:00"),
            done("81D2", "Ablage", group: "22CD", at: "2026-11-22T11:00:00+01:00", estimate: 0.5),
        ]
        let ours = try #require(TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-22", timeZone: vienna)["2026-11-22"])
        for expected in read.file.facts {
            let mine = try #require(ours.first { $0.id == expected.id }, "missing \(expected.id)")
            #expect(mine.kind == expected.kind)
            #expect(mine.ref == expected.ref)
            #expect(mine.refTitle == expected.refTitle)
            #expect(mine.origin == expected.origin)
            #expect(mine.unit == expected.unit)
            #expect(mine.value == expected.value)
            // Thalia's file leaves the category off one fact; Theo puts it on every fact of a mapped group.
            if let category = expected.thalia { #expect(mine.thalia == category) }
        }
        let file = ExchangeDayFile(source: "theo", day: "2026-11-22", generatedAt: "2026-11-22T18:04:05+01:00", facts: ours)
        let encoded = try file.encoded()
        guard case .success(let back) = ExchangeReader.dayFile(encoded, folder: "Theo", fileName: "2026-11-22.json") else {
            Issue.record("own day file not readable")
            return
        }
        #expect(back.file == file)
    }

    // MARK: 6. Only Theo's own records

    @Test func everyFactIsRecordedInTheoItself() {
        let tasks = [done("H1", "Ablage", group: "22CD", at: "2026-11-22T10:00:00+01:00", estimate: 0.25)]
        let facts = TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-22", timeZone: vienna)
        #expect(facts.values.flatMap { $0 }.allSatisfy { $0.origin == ExchangeOrigin.app.rawValue })
    }

    // MARK: 7. FNV-1a

    @Test func fnv1aMatchesTheReferenceValues() {
        #expect(ExchangeHash.hex("") == "cbf29ce484222325")
        #expect(ExchangeHash.hex("a") == "af63dc4c8601ec8c")
        #expect(ExchangeHash.hex("foobar") == "85944171f73967e8")
    }

    // MARK: 8. Theo's own rules

    @Test func groupsCarryTheirCategoryAndSubgroupsInheritIt() throws {
        let local = [
            TheoExchange.GroupRecord(id: "W", name: "Arbeit", category: "3", categoryTitle: "Arbeit"),
            TheoExchange.GroupRecord(id: "WK", name: "Kunden", parentID: "W"),
            TheoExchange.GroupRecord(id: "WI", name: "Intern", parentID: "W", category: "3.2", categoryTitle: "Kunden"),
            TheoExchange.GroupRecord(id: "H", name: "Haushalt"),
        ]
        let tasks = [
            done("1", "a", group: "WK", at: "2026-11-22T09:00:00+01:00"),
            done("2", "b", group: "WI", at: "2026-11-22T09:01:00+01:00"),
            done("3", "c", group: "H", at: "2026-11-22T09:02:00+01:00"),
        ]
        let facts = try #require(TheoExchange.facts(tasks: tasks, groups: local, today: "2026-11-22", timeZone: vienna)["2026-11-22"])
        #expect(facts.first { $0.id == "task-1" }?.thalia?.category == "3")
        #expect(facts.first { $0.id == "task-2" }?.thalia?.category == "3.2")
        #expect(facts.first { $0.id == "task-3" }?.thalia == nil)
        #expect(facts.first { $0.id == "task-1" }?.refTitle == "Arbeit/Kunden")
    }

    @Test func tasksWithoutAGroupAreFiledUnderOhneGruppe() throws {
        let tasks = [
            done("N1", "Notiz", group: nil, at: "2026-11-22T09:00:00+01:00", estimate: 0.25),
            done("N2", "Aus gelöschter Gruppe", group: "gone", at: "2026-11-22T09:05:00+01:00"),
        ]
        let facts = try #require(TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-22", timeZone: vienna)["2026-11-22"])
        #expect(facts.allSatisfy { $0.ref == "ohne-gruppe" && $0.refTitle == "Ohne Gruppe" && $0.thalia == nil })
        #expect(facts.contains { $0.id == "ph-N1" && $0.value == 0.25 })
    }

    @Test func powerHoursCountLikeTheDayReview() throws {
        // A finished line with 1 PH whose finished subtask has 0,5 PH of its own: only the subtask
        // counts; a finished line without estimated subtasks counts itself; no estimate, no ph.
        let tasks = [
            done("P", "Projekt", group: "22CD", at: "2026-11-22T12:00:00+01:00", estimate: 1, order: 1, indent: 0),
            done("S", "Schritt", group: "22CD", at: "2026-11-22T11:00:00+01:00", estimate: 0.5, order: 2, indent: 1),
            done("L", "Allein", group: "22CD", at: "2026-11-22T10:00:00+01:00", estimate: 0.75, order: 3, indent: 0),
            done("Z", "Ohne PH", group: "22CD", at: "2026-11-22T09:00:00+01:00", estimate: 0, order: 4, indent: 0),
        ]
        let facts = try #require(TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-22", timeZone: vienna)["2026-11-22"])
        let ph = facts.filter { $0.kind == "ph" }
        #expect(Set(ph.map(\.id)) == ["ph-S", "ph-L"])
        #expect(ph.reduce(0) { $0 + ($1.value ?? 0) } == PowerHours.total(tasks))
        #expect(facts.filter { $0.kind == "task.done" }.count == 4)
    }

    @Test func switchedOffGroupsAndTheirSubgroupsDeliverNothing() {
        let local = [
            TheoExchange.GroupRecord(id: "O", name: "Pausiert", isActive: false),
            TheoExchange.GroupRecord(id: "OS", name: "Darunter", parentID: "O"),
            TheoExchange.GroupRecord(id: "H", name: "Haushalt"),
        ]
        let tasks = [
            done("1", "a", group: "O", at: "2026-11-22T09:00:00+01:00"),
            done("2", "b", group: "OS", at: "2026-11-22T09:00:00+01:00"),
            done("3", "c", group: "H", at: "2026-11-22T09:00:00+01:00"),
        ]
        let facts = TheoExchange.facts(tasks: tasks, groups: local, today: "2026-11-22", timeZone: vienna)
        #expect(facts["2026-11-22"]?.map(\.id) == ["task-3"])
    }

    @Test func factsAreInAFixedOrder() throws {
        let tasks = [
            done("B", "zwei", group: "22CD", at: "2026-11-22T09:00:00+01:00"),
            done("A", "eins", group: "91AB", at: "2026-11-22T09:00:00+01:00"),
            done("C", "früher", group: "22CD", at: "2026-11-22T08:00:00+01:00"),
        ]
        let facts = try #require(TheoExchange.facts(tasks: tasks, groups: groups, today: "2026-11-22", timeZone: vienna)["2026-11-22"])
        #expect(facts.map(\.id) == ["task-C", "task-A", "task-B"])
    }

    @Test func thePickerListsTheCatalogsCategoriesByGoal() throws {
        let data = try fixture("Thalia/exchange/catalog.json")
        guard case .success(let catalog) = ExchangeReader.catalog(data) else {
            Issue.record("fixture catalog not readable")
            return
        }
        let choices = TheoExchange.choices(catalog)
        #expect(choices.map { TheoExchange.label($0.goal) } == ["1 Gesundheit", "3 Arbeit", "5 Lesen"])
        #expect(choices.map { $0.categories.map(TheoExchange.label) } == [["1.2 Sport / Verein"], ["3.2 Kunden"], ["5 Lesen"]])
        #expect(TheoExchange.state(category: "3.2", categoryTitle: "Kunden", catalog: catalog) == .ok)
        #expect(TheoExchange.state(category: "3.2", categoryTitle: "Kundschaft", catalog: catalog) == .check)
        #expect(TheoExchange.state(category: "9.9", categoryTitle: "Weg", catalog: catalog) == .check)
        #expect(TheoExchange.state(category: "3.2", categoryTitle: "Kunden", catalog: nil) == .catalogMissing)
        #expect(TheoExchange.state(category: nil, categoryTitle: nil, catalog: catalog) == .none)
    }

    @Test func categoryKeysSortLikeThalia() {
        let keys = ["2", "1.10", "1.2", "1", "x"]
        #expect(keys.sorted(by: TheoExchange.keyOrder) == ["1", "1.2", "1.10", "2", "x"])
    }

    @Test func sourceJSONIsWrittenWhenGroupsChangeAndOtherwiseOnceADay() throws {
        let folder = temporaryFolder()
        let refs = TheoExchange.refs(groups: groups)
        let morning = date("2026-11-22T08:00:00+01:00")
        #expect(try ThaliaExchangeWriter.writeSource(refs: refs, appVersion: "1.1.0", source: "theo", app: "Theo",
                                                     appFolder: folder, now: morning, timeZone: vienna))
        #expect(try !ThaliaExchangeWriter.writeSource(refs: refs, appVersion: "1.1.0", source: "theo", app: "Theo",
                                                      appFolder: folder, now: date("2026-11-22T20:00:00+01:00"), timeZone: vienna))
        let renamed = TheoExchange.refs(groups: groups + [TheoExchange.GroupRecord(id: "N", name: "Neu")])
        #expect(try ThaliaExchangeWriter.writeSource(refs: renamed, appVersion: "1.1.0", source: "theo", app: "Theo",
                                                     appFolder: folder, now: date("2026-11-22T20:00:00+01:00"), timeZone: vienna))
        #expect(try ThaliaExchangeWriter.writeSource(refs: renamed, appVersion: "1.1.0", source: "theo", app: "Theo",
                                                     appFolder: folder, now: date("2026-11-23T08:00:00+01:00"), timeZone: vienna))
    }

    @Test func theCatalogIsFoundNextToTheosFolder() throws {
        let folder = temporaryFolder()
        #expect(ThaliaExchangeWriter.catalog(appFolder: folder) == nil)
        let thalia = folder.deletingLastPathComponent().appendingPathComponent("Thalia/exchange", isDirectory: true)
        try FileManager.default.createDirectory(at: thalia, withIntermediateDirectories: true)
        try fixture("Thalia/exchange/catalog.json").write(to: thalia.appendingPathComponent("catalog.json"))
        #expect(ThaliaExchangeWriter.catalog(appFolder: folder)?.categories.count == 3)
    }
}
