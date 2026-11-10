import Foundation

/// A complete copy of Theo's data as one JSON file: every group, task (finished ones too) and
/// saved view, with all their fields. Written automatically every day, and on demand; reading
/// one back restores everything.
public struct Backup: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var createdAt: Date
    public var groups: [Group]
    public var tasks: [Task]
    public var views: [View]

    public init(createdAt: Date = Date(), groups: [Group], tasks: [Task], views: [View]) {
        self.version = Self.currentVersion
        self.createdAt = createdAt
        self.groups = groups
        self.tasks = tasks
        self.views = views
    }

    public struct Group: Codable, Sendable, Equatable {
        public var uuid: UUID
        public var name: String
        public var symbol: String
        public var colorName: String
        public var sortOrder: Double
        public var isCollapsed: Bool
        public var isProject: Bool
        public var notes: String
        public var dueDate: Date?
        public var createdAt: Date
        public var parentUUID: UUID?
        public var isActive: Bool
        public var traitImportance: Double?
        public var traitEstimate: Double?
        public var traitTagsRaw: String
        public var traitDueDays: Int?
        public var extrasRaw: String

        public init(uuid: UUID, name: String, symbol: String, colorName: String, sortOrder: Double, isCollapsed: Bool,
                    isProject: Bool, notes: String, dueDate: Date?, createdAt: Date, parentUUID: UUID?, isActive: Bool,
                    traitImportance: Double?, traitEstimate: Double?, traitTagsRaw: String, traitDueDays: Int?, extrasRaw: String) {
            self.uuid = uuid
            self.name = name
            self.symbol = symbol
            self.colorName = colorName
            self.sortOrder = sortOrder
            self.isCollapsed = isCollapsed
            self.isProject = isProject
            self.notes = notes
            self.dueDate = dueDate
            self.createdAt = createdAt
            self.parentUUID = parentUUID
            self.isActive = isActive
            self.traitImportance = traitImportance
            self.traitEstimate = traitEstimate
            self.traitTagsRaw = traitTagsRaw
            self.traitDueDays = traitDueDays
            self.extrasRaw = extrasRaw
        }
    }

    public struct Task: Codable, Sendable, Equatable {
        public var uuid: UUID
        public var title: String
        public var notes: String
        public var isDone: Bool
        public var completedAt: Date?
        public var createdAt: Date
        public var sortOrder: Double
        public var indent: Int
        public var priorityRaw: Int
        public var dueDate: Date?
        public var dueHasTime: Bool
        public var deferredUntil: Date?
        public var tagsRaw: String
        public var groupUUID: UUID?
        public var estimate: Double
        public var focusSeconds: Double
        public var urgency: Double
        public var importance: Double
        public var plannedDay: Date?
        public var recurrenceRaw: String
        public var remindersRaw: String
        public var traitProposalGroupID: UUID?
        public var extrasRaw: String

        public init(uuid: UUID, title: String, notes: String, isDone: Bool, completedAt: Date?, createdAt: Date,
                    sortOrder: Double, indent: Int, priorityRaw: Int, dueDate: Date?, dueHasTime: Bool,
                    deferredUntil: Date?, tagsRaw: String, groupUUID: UUID?, estimate: Double, focusSeconds: Double,
                    urgency: Double, importance: Double, plannedDay: Date?, recurrenceRaw: String, remindersRaw: String,
                    traitProposalGroupID: UUID?, extrasRaw: String) {
            self.uuid = uuid
            self.title = title
            self.notes = notes
            self.isDone = isDone
            self.completedAt = completedAt
            self.createdAt = createdAt
            self.sortOrder = sortOrder
            self.indent = indent
            self.priorityRaw = priorityRaw
            self.dueDate = dueDate
            self.dueHasTime = dueHasTime
            self.deferredUntil = deferredUntil
            self.tagsRaw = tagsRaw
            self.groupUUID = groupUUID
            self.estimate = estimate
            self.focusSeconds = focusSeconds
            self.urgency = urgency
            self.importance = importance
            self.plannedDay = plannedDay
            self.recurrenceRaw = recurrenceRaw
            self.remindersRaw = remindersRaw
            self.traitProposalGroupID = traitProposalGroupID
            self.extrasRaw = extrasRaw
        }
    }

    public struct View: Codable, Sendable, Equatable {
        public var uuid: UUID
        public var name: String
        public var symbol: String
        public var colorName: String
        public var sortOrder: Double
        public var isFavorite: Bool
        public var queryRaw: String
        public var createdAt: Date

        public init(uuid: UUID, name: String, symbol: String, colorName: String, sortOrder: Double, isFavorite: Bool,
                    queryRaw: String, createdAt: Date) {
            self.uuid = uuid
            self.name = name
            self.symbol = symbol
            self.colorName = colorName
            self.sortOrder = sortOrder
            self.isFavorite = isFavorite
            self.queryRaw = queryRaw
            self.createdAt = createdAt
        }
    }

    // MARK: - File

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Backup.self, from: data)
    }

    /// "Theo Backup 2026-11-10 2130.json".
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "Theo Backup %04ld-%02ld-%02ld %02ld%02ld.json", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// Which of the existing backups (newest first) to delete so `keep` remain.
    public static func expired(_ names: [String], keep: Int) -> [String] {
        let sorted = names.filter { $0.hasPrefix("Theo Backup ") && $0.hasSuffix(".json") }.sorted(by: >)
        return Array(sorted.dropFirst(max(0, keep)))
    }
}
