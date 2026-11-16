import SwiftUI
import TheoCore

extension AppModel {
    /// Shows one task's details: the inspector column on the Mac, the details sheet on
    /// iPhone and iPad. For anything already on the current page (lists, panels, menus).
    func showDetails(_ task: TaskItem) {
        #if os(macOS)
        // The tour's practice page has no inspector column: it shows the sheet.
        if isSandbox {
            detailTask = task
            return
        }
        selectedRowIDs = [task.rowID]
        showInspector = true
        #else
        detailTask = task
        #endif
    }

    /// Takes Theo to a page that lists the task and shows its details there. For callers
    /// outside the current list: notifications, the menu bar, Overview, Siri and Shortcuts.
    /// Mac: Today (when it's planned for today) or its group's page, with the row selected in
    /// the list and the inspector open. iPhone and iPad: the details sheet.
    func reveal(_ task: TaskItem) {
        #if os(macOS)
        if isSandbox {
            detailTask = task
            return
        }
        showInspector = true
        let page: SidebarItem
        if task.isPlanned(for: dayStart) {
            page = .today
        } else if let groupID = task.groupID {
            page = .group(groupID)
        } else {
            page = .quickEntry
        }
        if selection != page {
            // RootView clears the old page's selection on the change, then applies this.
            pendingRevealRowID = task.rowID
            go(page)
        } else {
            // go() clears a running search on a page change; do the same here, so the results
            // don't hide the revealed row.
            searchText = ""
            selectedRowIDs = [task.rowID]
        }
        #else
        detailTask = task
        #endif
    }
}
