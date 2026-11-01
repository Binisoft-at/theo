import SwiftUI
import SwiftData
import TheoCore

enum SidebarItem: Hashable {
    case today
    case upcoming
    case priority
    case matrix
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

/// A request to show the interactive tour (all of it, or only what's new).
struct TourRequest: Identifiable {
    let id = UUID()
    let steps: [TutorialStep]
}

/// A sheet that acts on one or more tasks.
struct TaskBatch: Identifiable {
    let id = UUID()
    let tasks: [TaskItem]
}

enum GroupEditorTarget: Identifiable {
    case new
    /// A new subproject inside this group.
    case subgroup(TaskGroup)
    case edit(TaskGroup)

    var id: String {
        switch self {
        case .new: "new"
        case .subgroup(let parent): "sub-" + parent.uuid.uuidString
        case .edit(let group): group.uuid.uuidString
        }
    }
}

/// A task being dragged onto the Eisenhower canvas from the composer's handle.
struct MatrixDrag: Equatable {
    var title: String
    /// Finger position in global coordinates.
    var location: CGPoint
}

/// App-wide UI state shared by all windows (and the macOS menu bar extra).
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let sync: SyncMonitor
    /// The tour's practice page: nothing is remembered and nothing leaves the page.
    let isSandbox: Bool

    var selection: SidebarItem? = .today
    var compactColumn: NavigationSplitViewColumn = .detail
    var detailPath = NavigationPath()
    /// iPhone: a single Notes-style stack (lists → page → day).
    var phonePath = NavigationPath()

    var detailTask: TaskItem?
    var moveBatch: TaskBatch?
    var dateBatch: TaskBatch?
    var tagBatch: TaskBatch?
    var groupEditor: GroupEditorTarget?
    var showImport = false
    var showSettings = false
    var toast: Toast?
    var tour: TourRequest?
    /// The tour's practice-page model while the tour is open; menu commands go there.
    var tourModel: AppModel?

    /// The running focus timer, if any (kept across launches through `saveFocus()`).
    var focus: FocusSession?
    var showFocus = false
    /// A drag from the composer's matrix handle, shown on the full-screen canvas.
    var matrixDrag: MatrixDrag?
    /// The canvas's frame in global coordinates while it's on screen.
    var matrixCanvasFrame: CGRect = .zero
    /// An existing task being placed on the canvas.
    var matrixTask: TaskItem?
    /// Schedules the notifications for timed tasks (not on the tour's practice page).
    let reminders: ReminderScheduler?

    /// Where menu-bar commands act: the practice page during the tour, otherwise this model.
    var commandTarget: AppModel { tourModel ?? self }

    /// Parents whose subtasks are folded away (this device only).
    private(set) var collapsedTaskIDs: Set<UUID> = []
    /// A task that should start inline editing as soon as its list shows it.
    var pendingEditTaskID: UUID?

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

    init(container: ModelContainer, isSandbox: Bool = false) {
        self.container = container
        self.isSandbox = isSandbox
        self.sync = SyncMonitor()
        self.dayStart = DayBoundary.current.start(of: Date())
        self.reminders = isSandbox ? nil : ReminderScheduler(container: container)
        guard !isSandbox else { return }
        focus = Self.loadFocus()
        let stored = UserDefaults.standard.stringArray(forKey: Prefs.collapsedTasks) ?? []
        collapsedTaskIDs = Set(stored.compactMap(UUID.init(uuidString:)))
        applyLaunchArguments()
        if let selection { phonePath = NavigationPath([selection]) }
        AppModel.shared = self
    }

    var store: TaskStore { TaskStore(context: container.mainContext) }

    func refreshDay() {
        let start = DayBoundary.current.start(of: Date())
        if start != dayStart { dayStart = start }
    }

    func go(_ item: SidebarItem) {
        detailPath = NavigationPath()
        selection = item
        compactColumn = .detail
        phonePath = NavigationPath([item])
    }

    func requestQuickEntry() {
        switch selection {
        case .history, .trash, .upcoming, .priority, .matrix, .tag, .none: go(.today)
        default: if phonePath.isEmpty { go(selection ?? .today) }
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

    /// Files tasks under another group, with Undo.
    func move(_ tasks: [TaskItem], toGroup groupID: UUID?) {
        let moved = tasks.flatMap { store.layout(for: $0.groupID).block(of: $0) }
        let before = moved.map { (task: $0, group: $0.group, order: $0.sortOrder, indent: $0.indent) }
        store.move(tasks, toGroup: groupID)
        let name = store.group(id: groupID)?.displayName ?? "Quick Entry"
        show("Moved to \(name)", symbol: "folder.fill") { [weak self] in
            for item in before {
                item.task.group = item.group
                item.task.sortOrder = item.order
                item.task.indent = item.indent
                item.task.touch()
            }
            self?.store.save()
        }
    }

    /// Folds or unfolds a parent's subtasks.
    func toggleSubtasks(_ task: TaskItem) {
        if collapsedTaskIDs.contains(task.uuid) {
            collapsedTaskIDs.remove(task.uuid)
        } else {
            collapsedTaskIDs.insert(task.uuid)
        }
        saveCollapsed()
    }

    private func saveCollapsed() {
        guard !isSandbox else { return }
        UserDefaults.standard.set(collapsedTaskIDs.map(\.uuidString), forKey: Prefs.collapsedTasks)
    }

    /// Adds an empty subtask under `parent` (unfolding it) and starts editing it.
    func addSubtask(to parent: TaskItem) {
        if collapsedTaskIDs.contains(parent.uuid) {
            collapsedTaskIDs.remove(parent.uuid)
            saveCollapsed()
        }
        let child = store.addSubtask(ParsedEntry(title: ""), to: parent)
        pendingEditTaskID = child.uuid
    }

    // MARK: - Tour

    /// Shows the tour on first launch, or the steps added since the last one someone saw.
    func offerTourIfNeeded() {
        guard !isSandbox, !Persistence.isDemo, tour == nil else { return }
        let steps = TutorialCatalog.steps(newerThan: UserDefaults.standard.integer(forKey: Prefs.tourSeenVersion))
        guard !steps.isEmpty else { return }
        tour = TourRequest(steps: steps)
    }

    func startTour() {
        tour = TourRequest(steps: TutorialCatalog.steps)
    }

    func finishTour() {
        UserDefaults.standard.set(TutorialCatalog.version, forKey: Prefs.tourSeenVersion)
        tour = nil
    }

    func deferToTomorrow(_ tasks: [TaskItem]) {
        let boundary = DayBoundary.current
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
        if args.contains("-TheoTour") { startTour() }
        if let index = args.firstIndex(of: "-TheoScreen"), index + 1 < args.count {
            switch args[index + 1] {
            case "upcoming": selection = .upcoming
            case "priority": selection = .priority
            case "matrix": selection = .matrix
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
