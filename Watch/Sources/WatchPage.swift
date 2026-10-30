import SwiftUI
import TheoCore

struct WatchRow: Identifiable {
    let task: TaskItem
    let depth: Int
    var id: UUID { task.uuid }
}

struct WatchSection: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let color: Color
    let rows: [WatchRow]
}

/// Builds the wrist version of the daily page from the same rules as iPhone and Mac.
enum WatchPage {
    /// Open tasks per section (Quick Entry, then groups in page order), nested like the page.
    /// Empty sections are left out to save space.
    static func sections(_ page: [TaskItem], groups: [TaskGroup]) -> [WatchSection] {
        Sections.byGroup(page, groups: groups).compactMap { section -> WatchSection? in
            let rows = Checklist.displayOrder(section.tasks, showCompleted: true)
                .filter { !$0.item.isDone }
                .map { WatchRow(task: $0.item, depth: $0.depth) }
            guard !rows.isEmpty else { return nil }
            return WatchSection(id: section.key, title: section.title, symbol: section.symbol, color: section.color, rows: rows)
        }
    }

    /// Everything finished on this page, most recent first.
    static func completed(_ page: [TaskItem]) -> [TaskItem] {
        page.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// All rows of one group page: open tasks (also ones hidden with "Not Today"), then the ones
    /// finished today.
    static func groupRows(_ tasks: [TaskItem], groupID: UUID?, dayStart: Date) -> [WatchRow] {
        let items = tasks.filter { $0.groupID == groupID && (!$0.isDone || $0.isOnPage(of: dayStart)) }
        return Checklist.displayOrder(items, showCompleted: true).map { WatchRow(task: $0.item, depth: $0.depth) }
    }
}

struct WatchSectionHeader: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
    }
}
