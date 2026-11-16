import Foundation

/// What Theo's widgets and complications show: today's page in numbers and its next tasks.
/// The apps write it into the shared App Group (`<group>/Theo/widget-snapshot.json`, see
/// `WidgetSnapshotWriter`); the widget extensions only read it. The task store itself stays
/// in Theo's own container. Foundation only: this file is also built into the extensions.
///
/// It carries tomorrow's page too, which the widgets switch to when the next logical day
/// starts, so they're right in the morning even when Theo hasn't run since the evening.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// Bumped when the format changes; widgets ignore a file with another version.
    static let currentVersion = 1

    /// One task as a widget lists it.
    struct Line: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var title: String
        var due: Date?
        var dueHasTime: Bool
        /// 0 = none, 1 = "!", 2 = "!!", 3 = "!!!".
        var priority: Int
        /// The group's name; nil for Quick Entry.
        var groupName: String?
        /// The group's colour (`TheoColor` raw value, e.g. "blue" or "graphite").
        var groupColor: String?
        /// The group's SF Symbol.
        var groupSymbol: String?
        /// Its estimate in Power Hours; 0 = none.
        var powerHours: Double
        var isOngoing: Bool
        /// On this page's plan. False for what an earlier day left open and what's due without
        /// a plan (Today's carry-over strip), listed after the planned lines.
        var isPlanned: Bool
        /// Nesting on the page: 0 = top level, 1 = subtask, ...
        var depth: Int
    }

    /// One logical day's page.
    struct Page: Codable, Equatable, Sendable {
        /// Start of the logical day (the "New day starts at" hour).
        var dayStart: Date
        /// When the next logical day starts.
        var dayEnd: Date
        /// Open tasks planned for the day (Today's count).
        var open: Int
        /// Tasks finished during the day.
        var done: Int
        var powerHoursLeft: Double
        var powerHoursDone: Double
        /// Open tasks (in groups that are on) whose deadline is before the day.
        var overdue: Int
        /// Open planned tasks ranked like Today, then the carry-over ones; at most `lineLimit`.
        var lines: [Line]
    }

    var version: Int = WidgetSnapshot.currentVersion
    var generatedAt: Date
    var today: Page
    var tomorrow: Page

    /// The page to show at `date`: today's, tomorrow's once the next day has begun, or nil
    /// once that has passed too (Theo hasn't written anything since).
    func page(at date: Date) -> Page? {
        if date < today.dayEnd { return today }
        if date < tomorrow.dayEnd { return tomorrow }
        return nil
    }

    /// Everything but the time it was made: an unchanged snapshot isn't written again.
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        version == other.version && today == other.today && tomorrow == other.tomorrow
    }
}

// MARK: - The file in the App Group

extension WidgetSnapshot {
    /// The group is shared by several Binisoft apps, so Theo keeps its files in a folder.
    static let folderName = "Theo"
    static let fileName = "widget-snapshot.json"

    /// The App Group from Info.plist (`SharedAppGroup`, set from Config/Base.xcconfig).
    static var appGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    /// nil when the App Group isn't available (unsigned simulator builds).
    static var fileURL: URL? {
        guard let group = appGroup,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return container
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// The snapshot last written, if there is one in the current format.
    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> WidgetSnapshot? {
        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == currentVersion else { return nil }
        return snapshot
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    enum WriteError: Error {
        case noAppGroup
    }

    /// Writes the file in one go (a widget never reads half of it).
    func write() throws {
        guard let url = Self.fileURL else { throw WriteError.noAppGroup }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }
}
