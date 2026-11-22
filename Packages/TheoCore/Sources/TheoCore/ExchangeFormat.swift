import Foundation

// Binisoft exchange, format v1 ("Binisoft-Austausch", TASKS-v10 §1.5).
//
// Reference code for every Binisoft app: copy this file verbatim. Foundation only – no types of any
// one app in here. Test files: Packages/ThaliaCore/Tests/ThaliaCoreTests/Fixtures/exchange/*.json.
//
// The way: the shared App Group `group.at.binisoft.shared`. Each app writes only into its own folder
// (named like the app: "Theo", "George", "Nina", "Finn", "Thalia"):
//
//     <group>/<App>/exchange/source.json            heartbeat: source, app version, format v, generatedAt, refs
//     <group>/<App>/exchange/days/<YYYY-MM-DD>.json  one file per day, written anew from the app's own synced
//                                                    store whenever something on that day changes (also after
//                                                    the app's own CloudKit import), atomically (temp + rename),
//                                                    then the Darwin notification `at.binisoft.exchange.changed`
//     <group>/Thalia/exchange/catalog.json           Thalia's structure only (goals, categories, measures,
//                                                    results) – no values, no progress
//
// A fact missing from an existing day file is gone; a missing day file means "no information". Day files
// older than 62 days are removed by their writer. Never written or read on Apple Watch.
//
// Day file:
//
//     {"v":1,"source":"theo","day":"2026-11-22","generatedAt":"2026-11-22T18:04:05+01:00","facts":[
//       {"id":"task-6F1A2C","kind":"task.done","ref":"grp-91AB","refTitle":"Arbeit/Kunden","title":"Rechnung schreiben",
//        "at":"2026-11-22T18:04:00+01:00","origin":"app","thalia":{"category":"3.2","categoryTitle":"Kunden"}},
//       {"id":"ph-77C0","kind":"ph","ref":"grp-91AB","refTitle":"Arbeit/Kunden","value":1.5,"unit":"PH","origin":"app"}]}
//
// Fact fields: `id` (stable, the same on every device), `kind`, `ref` (stable id in the source: a group,
// a workout template …), `refTitle`, `title?`, `value?`, `unit?`, `metric?` (`ExchangeMetric.table`),
// `currency?` (ISO 4217 for money), `at?`, `origin` (required: "app" = recorded in the source itself,
// "health" = from Apple Health – never used by Thalia, App Review guideline 5.1.3(ii)), `thalia?`
// (`category`, `categoryTitle`, `measure`, `result` – chosen in the source from Thalia's catalog).
// Dates: ISO 8601 with time zone, written without fractions (read with or without).
// Kinds v1: task.done, workout.done, habit.done, ph (power-hours), value (a day's figure with `metric`),
// spending (a group's day total, `value` + `currency`). Unknown kinds and metrics are kept but not used.

/// Constants and file helpers of the exchange.
public enum BinisoftExchange {
    /// The format version this file reads and writes.
    public static let version = 1
    public static let appGroup = "group.at.binisoft.shared"
    /// Posted (Darwin notification center) after writing a day file or `source.json`.
    public static let changedNotification = "at.binisoft.exchange.changed"
    public static let folderName = "exchange"
    public static let daysFolderName = "days"
    public static let sourceFileName = "source.json"
    public static let catalogFileName = "catalog.json"
    /// Writers remove day files older than this.
    public static let keepDays = 62

    /// `<app folder>/exchange` – the app folder is `<group>/<App>`.
    public static func exchangeFolder(appFolder: URL) -> URL {
        appFolder.appendingPathComponent(folderName, isDirectory: true)
    }

    /// `<app folder>/exchange/days`
    public static func daysFolder(appFolder: URL) -> URL {
        exchangeFolder(appFolder: appFolder).appendingPathComponent(daysFolderName, isDirectory: true)
    }

    /// `<app folder>/exchange/days/2026-11-22.json`
    public static func dayFileURL(appFolder: URL, day: String) -> URL {
        daysFolder(appFolder: appFolder).appendingPathComponent(dayFileName(day))
    }

    public static func dayFileName(_ day: String) -> String { day + ".json" }

    /// "2026-11-22.json" → "2026-11-22"; nil for dotfiles, temp files and everything else.
    public static func day(fromFileName name: String) -> String? {
        guard !name.hasPrefix("."), name.hasSuffix(".json") else { return nil }
        let day = String(name.dropLast(5))
        return isDay(day) ? day : nil
    }

    /// "2026-11-22" – a real calendar day.
    public static func isDay(_ text: String) -> Bool { civilDays(text) != nil }

    /// The source id of a name: lower case, letters, digits and "-" only ("Theo" → "theo").
    public static func sourceID(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
            .map(Character.init))
    }

    /// A file's `source` belongs to the folder it is in ("Theo" ↔ "theo").
    public static func matches(folder: String, source: String) -> Bool {
        !source.isEmpty && sourceID(folder) == sourceID(source)
    }

    /// Day file names among `names` older than `keepDays` before `today` ("2026-11-22") – to remove.
    public static func expiredDayFiles(_ names: [String], today: String) -> [String] {
        guard let now = civilDays(today) else { return [] }
        return names.filter { name in
            guard let day = day(fromFileName: name), let ordinal = civilDays(day) else { return false }
            return now - ordinal > keepDays
        }.sorted()
    }

    /// The day `days` after `day` ("2026-11-22", -1 → "2026-11-21").
    public static func day(_ day: String, adding days: Int) -> String? {
        civilDays(day).map { dayString(ordinal: $0 + days) }
    }

    /// Writes `data` atomically (a temp file in the same folder, then rename), creating the folder.
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// JSON as the exchange writes it: compact, keys sorted, slashes unescaped.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    // Days since 1970-01-01 (Howard Hinnant's days_from_civil), so this file needs no calendar type.
    static func civilDays(_ text: String) -> Int? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), day >= 1 else { return nil }
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day <= lengths[month - 1] else { return nil }
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        return era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
    }

    static func dayString(ordinal: Int) -> String {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return String(format: "%04d-%02d-%02d", yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}

/// Where a fact comes from (required): recorded in the source app itself, or from Apple Health.
public enum ExchangeOrigin: String, Sendable, CaseIterable {
    case app
    /// From Apple Health – Thalia never uses these (guideline 5.1.3(ii)); avoid writing them at all.
    case health
}

/// The kinds of v1.
public enum ExchangeKind: String, Sendable, CaseIterable {
    case taskDone = "task.done"
    case workoutDone = "workout.done"
    case habitDone = "habit.done"
    /// Power-hours (`value` in PH, 1 PH = 50 focused minutes).
    case powerHours = "ph"
    /// A day's figure: `metric` from `ExchangeMetric.table`, `value`.
    case value
    /// A group's spending of the day: `value` + `currency`.
    case spending
}

/// A metric of kind `value`, with how the day's values combine.
public struct ExchangeMetric: Equatable, Sendable {
    public enum Aggregation: String, Sendable {
        /// The day's value is the sum (kcal, grams, millilitres).
        case sum
        /// The latest value counts (net worth, savings rate, body weight).
        case last
    }

    public let id: String
    public let agg: Aggregation
    public let unit: String
    /// German name for screens.
    public let title: String

    public init(id: String, agg: Aggregation, unit: String, title: String) {
        self.id = id
        self.agg = agg
        self.unit = unit
        self.title = title
    }

    /// The fixed table of v1.
    public static let table: [ExchangeMetric] = [
        ExchangeMetric(id: "kcal", agg: .sum, unit: "kcal", title: "Kalorien"),
        ExchangeMetric(id: "protein_g", agg: .sum, unit: "g", title: "Protein"),
        ExchangeMetric(id: "carbs_g", agg: .sum, unit: "g", title: "Kohlenhydrate"),
        ExchangeMetric(id: "fat_g", agg: .sum, unit: "g", title: "Fett"),
        ExchangeMetric(id: "water_ml", agg: .sum, unit: "ml", title: "Wasser"),
        ExchangeMetric(id: "net_worth", agg: .last, unit: "€", title: "Vermögen"),
        ExchangeMetric(id: "savings_rate", agg: .last, unit: "%", title: "Sparquote"),
        ExchangeMetric(id: "body_weight_kg", agg: .last, unit: "kg", title: "Gewicht"),
    ]

    public static func named(_ id: String) -> ExchangeMetric? {
        let key = id.lowercased()
        return table.first { $0.id == key }
    }
}

/// What the source chose from Thalia's catalog for a fact (all optional).
public struct ExchangeThaliaHint: Codable, Equatable, Sendable {
    /// A category key ("3.2").
    public var category: String?
    /// Its title when it was chosen – Thalia asks to check the mapping when it no longer matches.
    public var categoryTitle: String?
    /// A measure code of the week.
    public var measure: String?
    /// A result id.
    public var result: String?

    public init(category: String? = nil, categoryTitle: String? = nil, measure: String? = nil, result: String? = nil) {
        self.category = category
        self.categoryTitle = categoryTitle
        self.measure = measure
        self.result = result
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        category = ExchangeRead.text(c, .category)
        categoryTitle = ExchangeRead.text(c, .categoryTitle)
        measure = ExchangeRead.text(c, .measure)
        result = ExchangeRead.text(c, .result)
    }

    enum CodingKeys: String, CodingKey { case category, categoryTitle, measure, result }
}

/// One fact of a day.
public struct ExchangeFact: Codable, Equatable, Sendable {
    /// Stable and the same on every device ("task-6F1A2C").
    public var id: String
    /// "task.done", "workout.done", "habit.done", "ph", "value", "spending" – or a newer one (kept, not used).
    public var kind: String
    /// Stable id in the source (a group, a workout template).
    public var ref: String
    public var refTitle: String
    public var title: String?
    public var value: Double?
    public var unit: String?
    public var metric: String?
    public var currency: String?
    /// ISO 8601 with time zone, as written.
    public var at: String?
    /// "app" or "health" (required; a fact without it is never used).
    public var origin: String
    public var thalia: ExchangeThaliaHint?

    public init(id: String, kind: String, ref: String = "", refTitle: String = "", title: String? = nil, value: Double? = nil,
                unit: String? = nil, metric: String? = nil, currency: String? = nil, at: String? = nil,
                origin: ExchangeOrigin = .app, thalia: ExchangeThaliaHint? = nil) {
        self.id = id
        self.kind = kind
        self.ref = ref
        self.refTitle = refTitle
        self.title = title
        self.value = value
        self.unit = unit
        self.metric = metric
        self.currency = currency
        self.at = at
        self.origin = origin.rawValue
        self.thalia = thalia
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = ExchangeRead.text(c, .id) else { throw ExchangeRead.missing("id", decoder) }
        guard let kind = ExchangeRead.text(c, .kind) else { throw ExchangeRead.missing("kind", decoder) }
        self.id = id
        self.kind = kind
        ref = ExchangeRead.text(c, .ref) ?? ""
        refTitle = ExchangeRead.text(c, .refTitle) ?? ""
        title = ExchangeRead.text(c, .title)
        value = ExchangeRead.number(c, .value)
        unit = ExchangeRead.text(c, .unit)
        metric = ExchangeRead.text(c, .metric)
        currency = ExchangeRead.text(c, .currency)
        at = ExchangeRead.text(c, .at)
        origin = ExchangeRead.text(c, .origin)?.lowercased() ?? ""
        thalia = try? c.decodeIfPresent(ExchangeThaliaHint.self, forKey: .thalia)
    }

    enum CodingKeys: String, CodingKey { case id, kind, ref, refTitle, title, value, unit, metric, currency, at, origin, thalia }

    public var knownKind: ExchangeKind? { ExchangeKind(rawValue: kind.lowercased()) }
    public var knownOrigin: ExchangeOrigin? { ExchangeOrigin(rawValue: origin) }
    /// Recorded in the source app itself – the only facts Thalia uses.
    public var isFromApp: Bool { knownOrigin == .app }
    public var date: Date? { at.flatMap(ExchangeDate.parse) }
    public var knownMetric: ExchangeMetric? { metric.flatMap(ExchangeMetric.named) }
    /// The fact means something to a v1 reader: a known kind, and for `value` a known metric.
    public var isKnown: Bool {
        guard let kind = knownKind else { return false }
        return kind != .value || knownMetric != nil
    }
}

/// One day of one source.
public struct ExchangeDayFile: Codable, Equatable, Sendable {
    public var v: Int
    /// The source id ("theo") – must match the folder.
    public var source: String
    /// "2026-11-22"
    public var day: String
    /// ISO 8601 with time zone; the newer file wins in Thalia's inbox.
    public var generatedAt: String
    public var facts: [ExchangeFact]

    public init(v: Int = BinisoftExchange.version, source: String, day: String, generatedAt: String, facts: [ExchangeFact] = []) {
        self.v = v
        self.source = source
        self.day = day
        self.generatedAt = generatedAt
        self.facts = facts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = Int(ExchangeRead.number(c, .v) ?? Double(BinisoftExchange.version))
        guard let source = ExchangeRead.text(c, .source) else { throw ExchangeRead.missing("source", decoder) }
        guard let day = ExchangeRead.text(c, .day) else { throw ExchangeRead.missing("day", decoder) }
        self.source = source
        self.day = day
        generatedAt = ExchangeRead.text(c, .generatedAt) ?? ""
        facts = ((try? c.decodeIfPresent([ExchangeLossy<ExchangeFact>].self, forKey: .facts)) ?? nil)?.compactMap(\.value) ?? []
    }

    enum CodingKeys: String, CodingKey { case v, source, day, generatedAt, facts }

    public var generatedDate: Date? { ExchangeDate.parse(generatedAt) }

    /// The file as the exchange writes it.
    public func encoded() throws -> Data { try BinisoftExchange.encode(self) }
}

/// A stable id of the source and its title (a group, a workout template, a metric) – in `source.json`,
/// so Thalia can offer them before any fact arrived.
public struct ExchangeRef: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// "group", "workout", "metric", "habit" … (free text).
    public var kind: String?

    public init(id: String, title: String, kind: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = ExchangeRead.text(c, .id) else { throw ExchangeRead.missing("id", decoder) }
        self.id = id
        title = ExchangeRead.text(c, .title) ?? id
        kind = ExchangeRead.text(c, .kind)
    }

    enum CodingKeys: String, CodingKey { case id, title, kind }
}

/// `source.json` – the heartbeat of a source.
public struct ExchangeSourceInfo: Codable, Equatable, Sendable {
    public var v: Int
    public var source: String
    /// The app's display name ("Theo").
    public var app: String?
    public var appVersion: String?
    public var generatedAt: String
    public var refs: [ExchangeRef]

    public init(v: Int = BinisoftExchange.version, source: String, app: String? = nil, appVersion: String? = nil, generatedAt: String,
                refs: [ExchangeRef] = []) {
        self.v = v
        self.source = source
        self.app = app
        self.appVersion = appVersion
        self.generatedAt = generatedAt
        self.refs = refs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = Int(ExchangeRead.number(c, .v) ?? Double(BinisoftExchange.version))
        guard let source = ExchangeRead.text(c, .source) else { throw ExchangeRead.missing("source", decoder) }
        self.source = source
        app = ExchangeRead.text(c, .app)
        appVersion = ExchangeRead.text(c, .appVersion)
        generatedAt = ExchangeRead.text(c, .generatedAt) ?? ""
        refs = ((try? c.decodeIfPresent([ExchangeLossy<ExchangeRef>].self, forKey: .refs)) ?? nil)?.compactMap(\.value) ?? []
    }

    enum CodingKeys: String, CodingKey { case v, source, app, appVersion, generatedAt, refs }

    public var generatedDate: Date? { ExchangeDate.parse(generatedAt) }
    /// "Theo", else the source id with a capital letter.
    public var displayName: String { app ?? ExchangeSourceInfo.displayName(source) }

    /// "theo" → "Theo".
    public static func displayName(_ source: String) -> String {
        guard let first = source.first else { return source }
        return first.uppercased() + source.dropFirst()
    }
}

/// `catalog.json` – Thalia's structure for the sources to choose from. No values, no progress.
public struct ExchangeCatalog: Codable, Equatable, Sendable {
    public struct SegmentEntry: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public struct GoalEntry: Codable, Equatable, Sendable {
        public var key: String
        public var title: String
        public init(key: String, title: String) {
            self.key = key
            self.title = title
        }
    }

    public struct CategoryEntry: Codable, Equatable, Sendable {
        public var key: String
        public var goal: String
        public var title: String
        /// The segment the category belongs to (the current one).
        public var segment: String?
        public init(key: String, goal: String, title: String, segment: String? = nil) {
            self.key = key
            self.goal = goal
            self.title = title
            self.segment = segment
        }
    }

    public struct MeasureEntry: Codable, Equatable, Sendable {
        public var code: String
        public var title: String
        public var unit: String
        /// The measure's source ("app:george:workout=tpl-1", "" = manual).
        public var link: String
        public var category: String
        public init(code: String, title: String, unit: String, link: String, category: String) {
            self.code = code
            self.title = title
            self.unit = unit
            self.link = link
            self.category = category
        }
    }

    public struct ResultEntry: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        /// "check", "count", "value".
        public var kind: String
        public var goal: String
        public init(id: String, title: String, kind: String, goal: String) {
            self.id = id
            self.title = title
            self.kind = kind
            self.goal = goal
        }
    }

    public var v: Int
    public var source: String
    public var generatedAt: String
    /// The week the measures are from.
    public var week: String?
    public var segment: SegmentEntry?
    public var goals: [GoalEntry]
    public var categories: [CategoryEntry]
    public var measures: [MeasureEntry]
    public var results: [ResultEntry]

    public init(v: Int = BinisoftExchange.version, source: String = "thalia", generatedAt: String, week: String? = nil,
                segment: SegmentEntry? = nil, goals: [GoalEntry] = [], categories: [CategoryEntry] = [], measures: [MeasureEntry] = [],
                results: [ResultEntry] = []) {
        self.v = v
        self.source = source
        self.generatedAt = generatedAt
        self.week = week
        self.segment = segment
        self.goals = goals
        self.categories = categories
        self.measures = measures
        self.results = results
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = Int(ExchangeRead.number(c, .v) ?? Double(BinisoftExchange.version))
        source = ExchangeRead.text(c, .source) ?? "thalia"
        generatedAt = ExchangeRead.text(c, .generatedAt) ?? ""
        week = ExchangeRead.text(c, .week)
        segment = try? c.decodeIfPresent(SegmentEntry.self, forKey: .segment)
        goals = ((try? c.decodeIfPresent([ExchangeLossy<GoalEntry>].self, forKey: .goals)) ?? nil)?.compactMap(\.value) ?? []
        categories = ((try? c.decodeIfPresent([ExchangeLossy<CategoryEntry>].self, forKey: .categories)) ?? nil)?.compactMap(\.value) ?? []
        measures = ((try? c.decodeIfPresent([ExchangeLossy<MeasureEntry>].self, forKey: .measures)) ?? nil)?.compactMap(\.value) ?? []
        results = ((try? c.decodeIfPresent([ExchangeLossy<ResultEntry>].self, forKey: .results)) ?? nil)?.compactMap(\.value) ?? []
    }

    enum CodingKeys: String, CodingKey { case v, source, generatedAt, week, segment, goals, categories, measures, results }
}

/// Why a file can't be used – said plainly (German, shown in the receiving app).
public enum ExchangeReadError: Error, Equatable, Sendable {
    case empty
    case notJSON
    case notAnObject
    case missingField(String)
    /// A field of the wrong type.
    case wrongType(String)
    /// A list element that isn't an object.
    case elementNotAnObject
    case unsupportedVersion(Int)
    case sourceMismatch(folder: String, source: String)
    case dayMismatch(fileName: String, day: String)
    case badDay(String)

    public var reason: String {
        switch self {
        case .empty: return "Die Datei ist leer."
        case .notJSON: return "Die Datei ist kein lesbares JSON."
        case .notAnObject: return "Die Datei enthält kein JSON-Objekt."
        case .missingField(let name): return "Das Feld \u{201E}\(name)\u{201C} fehlt."
        case .wrongType(let name): return "Das Feld \u{201E}\(name)\u{201C} hat einen falschen Typ."
        case .elementNotAnObject: return "Kein JSON-Objekt."
        case .unsupportedVersion(let v): return "Formatversion \(v) wird nicht unterstützt."
        case .sourceMismatch(let folder, let source):
            return "Die Quelle \u{201E}\(source)\u{201C} passt nicht zum Ordner \u{201E}\(folder)\u{201C}."
        case .dayMismatch(let fileName, let day): return "Der Tag \(day) passt nicht zum Dateinamen \(fileName)."
        case .badDay(let day): return "\u{201E}\(day)\u{201C} ist kein Tag (erwartet JJJJ-MM-TT)."
        }
    }
}

/// A day file as read, with the facts that couldn't be read (and why).
public struct ExchangeDayRead: Equatable, Sendable {
    public var file: ExchangeDayFile
    /// "Tatsache 3: Das Feld „kind“ fehlt."
    public var skipped: [String]

    public init(file: ExchangeDayFile, skipped: [String] = []) {
        self.file = file
        self.skipped = skipped
    }
}

/// Reading files tolerantly: unknown fields are ignored, a broken fact is skipped with its reason, a
/// broken file is refused with its reason.
public enum ExchangeReader {
    /// A day file. `folder`: the app folder it was found in (the source must match); `fileName`: its
    /// name (the day must match).
    public static func dayFile(_ data: Data, folder: String? = nil, fileName: String? = nil) -> Result<ExchangeDayRead, ExchangeReadError> {
        switch object(data) {
        case .failure(let error): return .failure(error)
        case .success: break
        }
        let decoder = JSONDecoder()
        let file: ExchangeDayFile
        do {
            file = try decoder.decode(ExchangeDayFile.self, from: data)
        } catch {
            return .failure(ExchangeRead.error(error))
        }
        guard file.v >= 1 else { return .failure(.unsupportedVersion(file.v)) }
        guard BinisoftExchange.isDay(file.day) else { return .failure(.badDay(file.day)) }
        if let folder, !BinisoftExchange.matches(folder: folder, source: file.source) {
            return .failure(.sourceMismatch(folder: folder, source: file.source))
        }
        if let fileName, BinisoftExchange.day(fromFileName: fileName) != file.day {
            return .failure(.dayMismatch(fileName: fileName, day: file.day))
        }
        var skipped: [String] = []
        if let raw = try? decoder.decode(RawFacts.self, from: data) {
            for (index, fact) in raw.facts.enumerated() {
                if let reason = fact.error { skipped.append("Tatsache \(index + 1): \(reason)") }
            }
        }
        return .success(ExchangeDayRead(file: file, skipped: skipped))
    }

    /// `source.json`. `folder`: the app folder it was found in (the source must match).
    public static func source(_ data: Data, folder: String? = nil) -> Result<ExchangeSourceInfo, ExchangeReadError> {
        switch object(data) {
        case .failure(let error): return .failure(error)
        case .success: break
        }
        do {
            let info = try JSONDecoder().decode(ExchangeSourceInfo.self, from: data)
            guard info.v >= 1 else { return .failure(.unsupportedVersion(info.v)) }
            if let folder, !BinisoftExchange.matches(folder: folder, source: info.source) {
                return .failure(.sourceMismatch(folder: folder, source: info.source))
            }
            return .success(info)
        } catch {
            return .failure(ExchangeRead.error(error))
        }
    }

    /// Thalia's `catalog.json`.
    public static func catalog(_ data: Data) -> Result<ExchangeCatalog, ExchangeReadError> {
        switch object(data) {
        case .failure(let error): return .failure(error)
        case .success: break
        }
        do {
            let catalog = try JSONDecoder().decode(ExchangeCatalog.self, from: data)
            guard catalog.v >= 1 else { return .failure(.unsupportedVersion(catalog.v)) }
            return .success(catalog)
        } catch {
            return .failure(ExchangeRead.error(error))
        }
    }

    /// Empty, not JSON or not an object.
    static func object(_ data: Data) -> Result<Void, ExchangeReadError> {
        guard !data.isEmpty, !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) else { return .failure(.empty) }
        guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return .failure(.notJSON) }
        guard value is [String: Any] else { return .failure(.notAnObject) }
        return .success(())
    }

    struct RawFacts: Decodable {
        var facts: [ExchangeLossy<ExchangeFact>]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let decoded: [ExchangeLossy<ExchangeFact>]? = (try? c.decodeIfPresent([ExchangeLossy<ExchangeFact>].self, forKey: .facts)) ?? nil
            facts = decoded ?? []
        }

        enum CodingKeys: String, CodingKey { case facts }
    }
}

/// An element of a list that may fail on its own: the list survives, the element is skipped.
public struct ExchangeLossy<T: Decodable>: Decodable {
    public let value: T?
    /// The reason, when the element couldn't be read.
    public let error: String?

    public init(from decoder: Decoder) throws {
        do {
            value = try T(from: decoder)
            error = nil
        } catch {
            value = nil
            self.error = ExchangeRead.error(error).reason
        }
    }
}

/// Tolerant field reading for the types above.
enum ExchangeRead {
    /// A text field (numbers are taken as text); nil when missing, empty or unreadable.
    static func text<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if let text = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil {
            return number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        }
        return nil
    }

    /// A number field (also "1.5" or "1,5" as text); nil when missing or unreadable.
    static func number<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let number = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil { return number.isFinite ? number : nil }
        if let text = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil {
            return Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    static func missing(_ name: String, _ decoder: Decoder) -> DecodingError {
        DecodingError.keyNotFound(AnyKey(name), .init(codingPath: decoder.codingPath, debugDescription: "missing \(name)"))
    }

    static func error(_ error: Error) -> ExchangeReadError {
        guard let decoding = error as? DecodingError else { return .notJSON }
        switch decoding {
        case .keyNotFound(let key, _): return .missingField(key.stringValue)
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            guard let last = context.codingPath.last else { return .notAnObject }
            if last.intValue != nil { return .elementNotAnObject }
            return .wrongType(last.stringValue)
        default: return .notJSON
        }
    }

    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(_ name: String) {
            stringValue = name
            intValue = nil
        }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

/// ISO 8601 dates: read with or without fractional seconds, "Z" or an offset; written with the offset.
public enum ExchangeDate {
    /// "2026-11-22T18:04:05+01:00", "2026-11-22T17:04:05Z", "2026-11-22T18:04:05.250+01:00",
    /// "2026-11-22T18:04:05+0100"; nil for anything else.
    public static func parse(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let chars = Array(t)
        guard chars.count >= 20, chars[10] == "T" || chars[10] == "t" || chars[10] == " " else { return nil }
        let datePart = String(chars[0..<10])
        guard let days = BinisoftExchange.civilDays(datePart) else { return nil }
        func number(_ from: Int, _ count: Int) -> Int? {
            guard from + count <= chars.count else { return nil }
            let slice = chars[from..<(from + count)]
            guard slice.allSatisfy(\.isASCII), slice.allSatisfy(\.isNumber) else { return nil }
            return Int(String(slice))
        }
        guard let hour = number(11, 2), chars[13] == ":", let minute = number(14, 2), chars[16] == ":", let second = number(17, 2),
              hour < 24, minute < 60, second < 61 else { return nil }
        var index = 19
        var fraction = 0.0
        if index < chars.count, chars[index] == "." || chars[index] == "," {
            index += 1
            var digits = ""
            while index < chars.count, chars[index].isASCII, chars[index].isNumber {
                digits.append(chars[index])
                index += 1
            }
            guard !digits.isEmpty else { return nil }
            fraction = Double("0." + digits) ?? 0
        }
        guard index < chars.count else { return nil }
        var offset = 0
        if chars[index] == "Z" || chars[index] == "z" {
            guard index == chars.count - 1 else { return nil }
        } else if chars[index] == "+" || chars[index] == "-" {
            let sign = chars[index] == "-" ? -1 : 1
            let rest = String(chars[(index + 1)...]).replacingOccurrences(of: ":", with: "")
            guard rest.count == 4 || rest.count == 2, let value = Int(rest) else { return nil }
            let hours = rest.count == 4 ? value / 100 : value
            let minutes = rest.count == 4 ? value % 100 : 0
            guard hours < 24, minutes < 60 else { return nil }
            offset = sign * (hours * 3600 + minutes * 60)
        } else {
            return nil
        }
        let seconds = Double(days) * 86_400 + Double(hour * 3600 + minute * 60 + second) - Double(offset) + fraction
        return Date(timeIntervalSince1970: seconds)
    }

    /// "2026-11-22T18:04:05+01:00" in `timeZone` (UTC: "…Z"); `fractional` adds milliseconds.
    public static func string(_ date: Date, timeZone: TimeZone = .current, fractional: Bool = false) -> String {
        let offset = timeZone.secondsFromGMT(for: date)
        let local = date.timeIntervalSince1970 + Double(offset)
        var whole = local.rounded(.down)
        var millis = Int(((local - whole) * 1000).rounded())
        if millis >= 1000 {
            whole += 1
            millis -= 1000
        }
        let days = Int((whole / 86_400).rounded(.down))
        let secondsOfDay = Int(whole) - days * 86_400
        let day = BinisoftExchange.dayString(ordinal: days)
        var text = day + String(format: "T%02d:%02d:%02d", secondsOfDay / 3600, secondsOfDay % 3600 / 60, secondsOfDay % 60)
        if fractional { text += String(format: ".%03d", millis) }
        if offset == 0 { return text + "Z" }
        let sign = offset < 0 ? "-" : "+"
        let minutes = abs(offset) / 60
        return text + sign + String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// The calendar day of `date` in `timeZone` ("2026-11-22").
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        String(string(date, timeZone: timeZone).prefix(10))
    }
}

/// FNV-1a (64 bit) over UTF-8 – the same value on every device and platform, e.g. for stable fact ids
/// from a record id ("task-" + `hex(…)`) or to see whether a day file's content changed.
public enum ExchangeHash {
    public static func fnv1a64(_ text: String) -> UInt64 {
        fnv1a64(bytes: Array(text.utf8))
    }

    public static func fnv1a64(bytes: [UInt8]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// 16 lower-case hex digits.
    public static func hex(_ text: String) -> String {
        let value = String(fnv1a64(text), radix: 16)
        return String(repeating: "0", count: max(0, 16 - value.count)) + value
    }
}
