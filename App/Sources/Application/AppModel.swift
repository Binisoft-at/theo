import SwiftUI
import SwiftData
import TheoCore

enum SidebarItem: Hashable {
    case today
    case plan
    case overview
    case allTasks
    /// A saved view (`SavedView`).
    case view(UUID)
    case upcoming
    case priority
    case matrix
    case quickEntry
    case history
    case trash
    case group(UUID)
    case tag(String)
}

struct IndentRequest: Equatable {
    let id = UUID()
    let taskID: UUID
    /// +1 = subtask of the line above, -1 = out one level.
    let delta: Int
}

/// iPhone tab bar.
enum PhoneTab: Hashable {
    case today, plan, overview, lists, search
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
    var phoneTab: PhoneTab = .today

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
    /// Daily safety copies of everything (Settings → Backups).
    let backups: BackupManager

    /// The composer's + being dragged over a list (global position), to insert a task there.
    var insertDragLocation: CGPoint?
    /// What the dragged + carries: the typed title, or empty for a blank line.
    var insertDragTitle = ""
    /// A circular hold-and-slide pick in progress (drawn by the window, above everything).
    var radialPick: RadialPick?
    /// The day whose review is open (today's, or a past day's from History).
    var reviewDay: DayRef?
    /// The Mac's inspector column: the selected task's details, editable in place.
    var showInspector = UserDefaults.standard.object(forKey: "inspector.shown") as? Bool ?? true
    /// The window's visible part in global coordinates, above the keyboard when it's up.
    @ObservationIgnored var visibleFrame: CGRect = .zero
    /// Set by the list on screen: inserts a task where the + was dropped; false if nowhere.
    @ObservationIgnored var insertHandler: ((CGPoint, ParsedEntry?) -> Bool)?
    @ObservationIgnored var insertHandlerOwner: UUID?
    /// Swipe-style indent / outdent requested from the menu bar; the list on screen resolves it.
    var indentRequest: IndentRequest?

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
        // No reminders on the practice page or the screenshot demo data.
        self.reminders = isSandbox || Persistence.isDemo ? nil : ReminderScheduler(container: container)
        self.backups = BackupManager(container: container, enabled: !isSandbox && !Persistence.isDemo)
        guard !isSandbox else { return }
        focus = Self.loadFocus()
        if !Persistence.isDemo {
            store.syncImportanceWithPriority()
            store.applyDefaultEstimateOnce()
        }
        let stored = UserDefaults.standard.stringArray(forKey: Prefs.collapsedTasks) ?? []
        collapsedTaskIDs = Set(stored.compactMap(UUID.init(uuidString:)))
        applyLaunchArguments()
        if let selection, selection != .today { go(selection) }
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
        switch item {
        case .today:
            phoneTab = .today
        case .plan:
            phoneTab = .plan
        case .overview:
            phoneTab = .overview
        default:
            phoneTab = .lists
            phonePath = NavigationPath([item])
        }
    }

    /// The logical day as stored in `plannedDay` (midnight of that calendar day).
    var todayKey: Date { Calendar.current.startOfDay(for: dayStart) }

    func plan(_ tasks: [TaskItem], for day: Date?) {
        let before = tasks.map { (task: $0, day: $0.plannedDay) }
        store.plan(tasks, for: day)
        var label = ""
        if let day {
            let delta = DateText.dayDelta(day, today: dayStart)
            label = delta == 0 ? "today" : (delta == 1 ? "tomorrow" : day.formatted(.dateTime.weekday(.wide).day().month()))
        }
        let message = day == nil
            ? (tasks.count == 1 ? "Taken off the plan" : "\(tasks.count) taken off the plan")
            : (tasks.count == 1 ? "Planned for \(label)" : "\(tasks.count) planned for \(label)")
        show(message, symbol: "calendar.badge.checkmark") { [weak self] in
            for item in before { item.task.plannedDay = item.day }
            self?.store.save()
        }
    }

    func requestQuickEntry() {
        switch selection {
        case .history, .trash, .upcoming, .priority, .matrix, .plan, .overview, .tag, .none: go(.today)
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

    /// "Not Today": onto tomorrow's plan.
    func deferToTomorrow(_ tasks: [TaskItem]) {
        plan(tasks, for: DayBoundary.current.dayStart(byAdding: 1, to: dayStart))
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
            case "plan": selection = .plan
            case "history": selection = .history
            case "quick": selection = .quickEntry
            case "overview":
                selection = .overview
                phoneTab = .overview
            case "alltasks": selection = .allTasks
            case "review":
                selection = .today
                reviewDay = DayRef(start: dayStart)
            case "work":
                if let work = store.liveGroups().first(where: { $0.name == "Work" }) { selection = .group(work.uuid) }
            case "sidebar":
                selection = nil
                compactColumn = .sidebar
                phoneTab = .lists
            default: selection = .today
            }
        }
        if args.contains("-TheoRadialDemo") {
            // The circular picker opened from the send button, pointing at 1 PH.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                let bounds = visibleFrame.isEmpty ? CGRect(x: 0, y: 0, width: 402, height: 874) : visibleFrame
                let origin = CGPoint(x: bounds.maxX - 34, y: bounds.maxY - 120)
                var pick = RadialPick(title: "Power Hours", options: QuickEntryBar.estimateOptions, origin: origin, location: origin, bounds: bounds)
                let target = pick.layout.position(of: 4)
                pick.location = target
                pick.selection = pick.layout.selection(at: target)
                radialPick = pick
            }
        }
    }
}
