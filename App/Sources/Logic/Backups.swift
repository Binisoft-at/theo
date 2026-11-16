import Foundation
import SwiftData
import TheoCore
#if os(macOS)
import AppKit
#endif

/// Daily safety copies of everything, on top of iCloud: a JSON file per day (the last 30 are
/// kept) in Theo's Documents folder. On iPhone that's Files → On My iPhone → Theo → Backups
/// (and part of the phone's own iCloud backup); on the Mac, "Show in Finder" in Settings. Any
/// copy can be shared, and restored, which replaces everything after saving one more copy of
/// what's there now.
@MainActor
@Observable
final class BackupManager {
    static let keep = 30
    private static let lastKey = "backups.last"

    private let container: ModelContainer
    private let enabled: Bool
    /// Newest first.
    private(set) var files: [URL] = []
    private(set) var lastBackup: Date?
    private(set) var lastError: String?

    init(container: ModelContainer, enabled: Bool) {
        self.container = container
        self.enabled = enabled
        lastBackup = UserDefaults.standard.object(forKey: Self.lastKey) as? Date
        if enabled { refreshList() }
    }

    static var folder: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents.appendingPathComponent("Backups", isDirectory: true)
    }

    private var store: TaskStore { TaskStore(context: container.mainContext) }

    /// Why a backup wasn't written.
    enum Problem: LocalizedError {
        /// Theo runs on a temporary in-memory store: there's nothing safe to copy, and a restore
        /// wouldn't be kept.
        case storeNotOpen
        /// Nothing to copy while earlier copies exist: an empty file must not push a good one out.
        case empty

        var errorDescription: String? {
            switch self {
            case .storeNotOpen: "Theo couldn't open your tasks, so backups and restores are paused. Quit and reopen Theo."
            case .empty: "Skipped an empty backup: there were no tasks or groups to copy."
            }
        }
    }

    /// Once a day, quietly: at launch, when the app comes back (iPhone) or becomes active (Mac),
    /// and when a new day starts while it's open. A cheap date check when nothing is due.
    func backUpIfDue() {
        guard enabled, Persistence.storeKind != .memory else { return }
        if let lastBackup, Date().timeIntervalSince(lastBackup) < 20 * 3600 { return }
        _ = try? backUpNow()
    }

    @discardableResult
    func backUpNow() throws -> URL {
        guard Persistence.storeKind != .memory else {
            lastError = Problem.storeNotOpen.errorDescription
            throw Problem.storeNotOpen
        }
        guard let folder = Self.folder else { throw CocoaError(.fileNoSuchFile) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let now = Date()
            let backup = snapshot(at: now)
            if backup.tasks.isEmpty && backup.groups.isEmpty && Self.hasBackups(in: folder) {
                throw Problem.empty
            }
            let url = folder.appendingPathComponent(Backup.fileName(for: now))
            try backup.encoded().write(to: url, options: .atomic)
            lastBackup = now
            UserDefaults.standard.set(now, forKey: Self.lastKey)
            prune(folder)
            refreshList()
            lastError = nil
            return url
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Whether the folder already holds at least one backup file.
    private static func hasBackups(in folder: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { $0.hasPrefix("Theo Backup ") && $0.hasSuffix(".json") }
    }

    func refreshList() {
        guard let folder = Self.folder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            files = []
            return
        }
        files = names.filter { $0.hasPrefix("Theo Backup ") && $0.hasSuffix(".json") }
            .sorted(by: >)
            .map { folder.appendingPathComponent($0) }
    }

    private func prune(_ folder: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in Backup.expired(names, keep: Self.keep) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    #if os(macOS)
    func revealInFinder() {
        guard let folder = Self.folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([files.first ?? folder])
    }
    #endif

    // MARK: - Snapshot and restore

    func snapshot(at date: Date = Date()) -> Backup {
        let store = self.store
        let groups = store.liveGroups().map { group in
            Backup.Group(
                uuid: group.uuid, name: group.name, symbol: group.symbol, colorName: group.colorName, sortOrder: group.sortOrder,
                isCollapsed: group.isCollapsed, isProject: group.isProject, notes: group.notes, dueDate: group.dueDate,
                createdAt: group.createdAt, parentUUID: group.parentUUID, isActive: group.isActive,
                traitImportance: group.traitImportance, traitEstimate: group.traitEstimate, traitTagsRaw: group.traitTagsRaw,
                traitDueDays: group.traitDueDays, extrasRaw: group.extrasRaw
            )
        }
        let tasks = store.liveTasks().map { task in
            Backup.Task(
                uuid: task.uuid, title: task.title, notes: task.notes, isDone: task.isDone, completedAt: task.completedAt,
                createdAt: task.createdAt, sortOrder: task.sortOrder, indent: task.indent, priorityRaw: task.priorityRaw,
                dueDate: task.dueDate, dueHasTime: task.dueHasTime, deferredUntil: task.deferredUntil, tagsRaw: task.tagsRaw,
                groupUUID: task.group?.deletedAt == nil ? task.group?.uuid : nil, estimate: task.estimate,
                focusSeconds: task.focusSeconds, urgency: task.urgency, importance: task.importance, plannedDay: task.plannedDay,
                recurrenceRaw: task.recurrenceRaw, remindersRaw: task.remindersRaw,
                traitProposalGroupID: task.traitProposalGroupID, extrasRaw: task.extrasRaw
            )
        }
        let views = store.liveViews().map { view in
            Backup.View(uuid: view.uuid, name: view.name, symbol: view.symbol, colorName: view.colorName,
                        sortOrder: view.sortOrder, isFavorite: view.isFavorite, queryRaw: view.queryRaw, createdAt: view.createdAt)
        }
        return Backup(createdAt: date, groups: groups, tasks: tasks, views: views)
    }

    /// Replaces everything with `backup`, after one more backup of what's there now. Returns
    /// how many tasks came back.
    @discardableResult
    func restore(_ backup: Backup) throws -> Int {
        // Restoring into the temporary in-memory store would look fine and then vanish on quit.
        guard Persistence.storeKind != .memory else { throw Problem.storeNotOpen }
        if enabled {
            do {
                try backUpNow()
            } catch Problem.empty {
                // Nothing there now, so nothing to keep before replacing it.
                lastError = nil
            }
        }
        let context = container.mainContext
        // Out with the current data for good (it's in the backup just made), so no two records
        // share an ID.
        for task in (try? context.fetch(FetchDescriptor<TaskItem>())) ?? [] { context.delete(task) }
        for group in (try? context.fetch(FetchDescriptor<TaskGroup>())) ?? [] { context.delete(group) }
        for view in (try? context.fetch(FetchDescriptor<SavedView>())) ?? [] { context.delete(view) }
        var groupsByID: [UUID: TaskGroup] = [:]
        for item in backup.groups {
            let group = TaskGroup(name: item.name, symbol: item.symbol, sortOrder: item.sortOrder)
            group.uuid = item.uuid
            group.colorName = item.colorName
            group.isCollapsed = item.isCollapsed
            group.isProject = item.isProject
            group.notes = item.notes
            group.dueDate = item.dueDate
            group.createdAt = item.createdAt
            group.parentUUID = item.parentUUID
            group.isActive = item.isActive
            group.traitImportance = item.traitImportance
            group.traitEstimate = item.traitEstimate
            group.traitTagsRaw = item.traitTagsRaw
            group.traitDueDays = item.traitDueDays
            group.extrasRaw = item.extrasRaw
            context.insert(group)
            groupsByID[item.uuid] = group
        }
        for item in backup.tasks {
            let task = TaskItem(title: item.title, sortOrder: item.sortOrder, indent: item.indent)
            task.uuid = item.uuid
            context.insert(task)
            task.notes = item.notes
            task.isDone = item.isDone
            task.completedAt = item.completedAt
            task.createdAt = item.createdAt
            task.priorityRaw = item.priorityRaw
            task.dueDate = item.dueDate
            task.dueHasTime = item.dueHasTime
            task.deferredUntil = item.deferredUntil
            task.tagsRaw = item.tagsRaw
            task.group = item.groupUUID.flatMap { groupsByID[$0] }
            task.estimate = item.estimate
            task.focusSeconds = item.focusSeconds
            task.urgency = item.urgency
            task.importance = item.importance
            task.plannedDay = item.plannedDay
            task.recurrenceRaw = item.recurrenceRaw
            task.remindersRaw = item.remindersRaw
            task.traitProposalGroupID = item.traitProposalGroupID
            task.extrasRaw = item.extrasRaw
        }
        for item in backup.views {
            let view = SavedView(name: item.name, query: TaskQuery(raw: item.queryRaw), sortOrder: item.sortOrder)
            view.uuid = item.uuid
            view.symbol = item.symbol
            view.colorName = item.colorName
            view.isFavorite = item.isFavorite
            view.queryRaw = item.queryRaw
            view.createdAt = item.createdAt
            context.insert(view)
        }
        try context.save()
        return backup.tasks.count
    }

    func restore(from url: URL) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try restore(Backup.decode(Data(contentsOf: url)))
    }
}
