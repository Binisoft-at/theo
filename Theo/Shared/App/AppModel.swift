import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case today
    case upcoming
    case priority
    case quickEntry
    case history
    case trash
    case group(UUID)
    case tag(String)
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var symbol: String = "checkmark.circle.fill"
    var undo: (() -> Void)?

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

/// A sheet that acts on one or more tasks.
struct TaskBatch: Identifiable {
    let id = UUID()
    let tasks: [TaskItem]
}

enum GroupEditorTarget: Identifiable {
    case new
    case edit(TaskGroup)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let group): group.uuid.uuidString
        }
    }
}

/// App-wide UI state shared by all windows (and the macOS menu bar extra).
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let sync: SyncMonitor

    var selection: SidebarItem? = .today
    var compactColumn: NavigationSplitViewColumn = .detail
    var detailPath = NavigationPath()

    var detailTask: TaskItem?
    var moveBatch: TaskBatch?
    var dateBatch: TaskBatch?
    var tagBatch: TaskBatch?
    var groupEditor: GroupEditorTarget?
    var showImport = false
    var showSettings = false
    var toast: Toast?

    /// Set to focus the quick entry field; the field resets it once focused.
    var wantsQuickEntryFocus = false
    /// Selected rows in the current list (macOS + iOS edit mode).
    var selectedRowIDs: Set<String> = []
    /// iOS multi-select mode.
    var isSelecting = false

    /// The model used by the scene; lets UIKit callbacks (Home Screen quick actions) reach it.
    static weak var shared: AppModel?

    /// Start of the current logical day, refreshed by `refreshDay()`.
    var dayStart: Date

    init(container: ModelContainer) {
        self.container = container
        self.sync = SyncMonitor()
        self.dayStart = DayBoundary().start(of: Date())
        applyLaunchArguments()
        AppModel.shared = self
    }

    var store: TaskStore { TaskStore(context: container.mainContext) }

    func refreshDay() {
        let start = DayBoundary().start(of: Date())
        if start != dayStart { dayStart = start }
    }

    func go(_ item: SidebarItem) {
        detailPath = NavigationPath()
        selection = item
        compactColumn = .detail
    }

    func requestQuickEntry() {
        switch selection {
        case .history, .trash, .upcoming, .priority, .tag, .none: go(.today)
        default: break
        }
        detailPath = NavigationPath()
        compactColumn = .detail
        wantsQuickEntryFocus = true
    }

    func endSelection() {
        isSelecting = false
        selectedRowIDs = []
    }

    func show(_ message: String, symbol: String = "checkmark.circle.fill", undo: (() -> Void)? = nil) {
        let toast = Toast(message: message, symbol: symbol, undo: undo)
        withAnimation(.snappy) { self.toast = toast }
        let id = toast.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(undo == nil ? 2.2 : 4.5))
            if self.toast?.id == id {
                withAnimation(.snappy) { self.toast = nil }
            }
        }
    }

    // MARK: - Actions used by menus, swipes and keyboard commands

    func delete(_ tasks: [TaskItem]) {
        guard !tasks.isEmpty else { return }
        let deleted = store.delete(tasks)
        let label = deleted.count == 1 ? "Deleted “\(deleted[0].trimmedTitle)”" : "Deleted \(deleted.count) tasks"
        show(label, symbol: "trash.fill") { [weak self] in
            self?.store.restore(deleted)
        }
    }

    func toggle(_ task: TaskItem) {
        store.toggle(task)
    }

    func deferToTomorrow(_ tasks: [TaskItem]) {
        let boundary = DayBoundary()
        let tomorrow = boundary.dayStart(byAdding: 1, to: dayStart)
        store.deferTasks(tasks, until: tomorrow)
        show(tasks.count == 1 ? "Moved to tomorrow" : "Moved \(tasks.count) tasks to tomorrow", symbol: "moon.zzz.fill") { [weak self] in
            self?.store.deferTasks(tasks, until: nil)
        }
    }

    var selectedTasks: [TaskItem] {
        let ids = selectedRowIDs.compactMap { id -> UUID? in
            guard id.hasPrefix("t-") else { return nil }
            return UUID(uuidString: String(id.dropFirst(2)))
        }
        return ids.compactMap { store.task(id: $0) }.filter { $0.deletedAt == nil }
    }

    // MARK: - Launch arguments (screenshots)

    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-TheoScreen"), index + 1 < args.count {
            switch args[index + 1] {
            case "upcoming": selection = .upcoming
            case "priority": selection = .priority
            case "history": selection = .history
            case "quick": selection = .quickEntry
            case "sidebar":
                selection = nil
                compactColumn = .sidebar
            default: selection = .today
            }
        }
    }
}
