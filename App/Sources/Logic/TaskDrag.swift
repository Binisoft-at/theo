import SwiftUI
import TheoCore
#if os(iOS)
import UIKit
#endif

/// Dragging task lines out of a list onto the sidebar (Mac and iPad). The drag carries plain
/// text: "theo-task:" and the tasks' ids, separated by commas. Text without that start (an
/// ordinary text drag) names no task, so dropping it on the sidebar does nothing.
enum TaskDrag {
    static let prefix = "theo-task:"

    /// The text a drag of these tasks carries.
    static func payload(_ ids: [UUID]) -> String {
        prefix + ids.map(\.uuidString).joined(separator: ",")
    }

    /// The tasks named by dropped texts, in order and each once (a Mac drag of several selected
    /// lines brings one text per line, each naming the whole selection).
    static func ids(in texts: [String]) -> [UUID] {
        var seen = Set<UUID>()
        var found: [UUID] = []
        for text in texts where text.hasPrefix(prefix) {
            for part in text.dropFirst(prefix.count).split(separator: ",") {
                let trimmed = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let id = UUID(uuidString: trimmed), !seen.contains(id) else { continue }
                seen.insert(id)
                found.append(id)
            }
        }
        return found
    }

    /// What a list row hands to the system when it's dragged.
    static func itemProvider(for ids: [UUID]) -> NSItemProvider {
        NSItemProvider(object: payload(ids) as NSString)
    }

    /// Lines can be dragged out where the sidebar sits next to the list: on the Mac and iPad.
    /// The iPhone's lists stay as they were.
    @MainActor
    static var isAvailable: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return true
        #endif
    }

    /// Tasks dropped on a sidebar row: a group (or subgroup) or Quick Entry files them there,
    /// Today plans them for today and Plan for tomorrow. Each brings its subtasks, and the
    /// toast offers Undo. Tasks already there are left alone. False when nothing changed or
    /// the row takes no tasks.
    @MainActor
    static func drop(_ texts: [String], on item: SidebarItem, app: AppModel) -> Bool {
        let store = app.store
        let tasks = ids(in: texts).compactMap { store.task(id: $0) }.filter { $0.deletedAt == nil }
        guard !tasks.isEmpty else { return false }
        switch item {
        case .group(let groupID):
            return move(tasks, to: groupID, app: app)
        case .quickEntry:
            return move(tasks, to: nil, app: app)
        case .today:
            let open = openTasks(tasks, notPlannedFor: app.dayStart)
            guard !open.isEmpty else { return false }
            withAnimation(.snappy) { app.plan(open, for: app.dayStart) }
            return true
        case .plan:
            let tomorrow = DayBoundary.current.dayStart(byAdding: 1, to: app.dayStart)
            let open = openTasks(tasks, notPlannedFor: tomorrow)
            guard !open.isEmpty else { return false }
            withAnimation(.snappy) { app.deferToTomorrow(open) }
            return true
        default:
            return false
        }
    }

    @MainActor
    private static func move(_ tasks: [TaskItem], to groupID: UUID?, app: AppModel) -> Bool {
        let moving = tasks.filter { $0.groupID != groupID }
        guard !moving.isEmpty else { return false }
        withAnimation(.snappy) { app.move(moving, toGroup: groupID) }
        return true
    }

    /// The open tasks that aren't on that day's plan yet.
    private static func openTasks(_ tasks: [TaskItem], notPlannedFor day: Date) -> [TaskItem] {
        tasks.filter { !$0.isDone && !$0.isPlanned(for: day) }
    }
}
