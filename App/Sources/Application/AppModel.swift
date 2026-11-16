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

    /// Something went wrong (a triangle symbol): drawn in red and kept on screen longer.
    var isWarning: Bool { symbol.hasPrefix("exclamationmark") }

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
    /// A new subgroup inside this group.
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
    /// Mac and iPad: the toolbar search over every task. While it holds text, the results
    /// replace the page; a page change clears it.
    var searchText = ""
    /// Set by Find… (⌘F) to put the cursor in the search field; RootView resets it.
    var wantsSearchFocus = false
    /// Selected rows in the current list (macOS + iOS edit mode).
    var selectedRowIDs: Set<String> = []
    /// iOS multi-select mode.
    var isSelecting = false

    /// The model used by the scene; lets UIKit callbacks (Home Screen quick actions), notification
    /// actions and App Intents reach it. Strong, so Siri/Shortcuts still find it when Theo was
    /// launched in the background without a window.
    static var shared: AppModel?
    /// A row to select once the page `reveal(_:)` switched to is on screen (RootView applies it
    /// after it clears the old page's selection).
    @ObservationIgnored var pendingRevealRowID: String?

    /// Start of the current logical day, refreshed by `refreshDay()`.
    var dayStart: Date

    /// Listens for failed saves (`TaskStore.save()` posts "TheoSaveFailed").
    @ObservationIgnored private var saveFailureObserver: NSObjectProtocol?
    /// When the last "Couldn't save" toast showed: at most one a minute.
    @ObservationIgnored private var lastSaveWarning: Date?

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
        // A save that fails keeps failing, and everything after it would be lost on quit: say so.
        saveFailureObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("TheoSaveFailed"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let message = note.userInfo?["message"] as? String ?? "unknown error"
            MainActor.assumeIsolated {
                self?.reportSaveFailure(message)
            }
        }
        applyLaunchArguments()
        if let selection, selection != .today { go(selection) }
        AppModel.shared = self
    }

    var store: TaskStore { TaskStore(context: container.mainContext) }

    func refreshDay() {
        let start = DayBoundary.current.start(of: Date())
        guard start != dayStart else { return }
        dayStart = start
        // A Mac can stay open for days without its window ever going inactive, so the new day
        // also empties expired trash and takes the daily backup.
        guard !isSandbox, !Persistence.isDemo else { return }
        store.purgeExpired()
        backups.backUpIfDue()
    }

    /// The red toast for a failed save, at most once a minute (every later save fails too).
    private func reportSaveFailure(_ message: String) {
        let now = Date()
        if let lastSaveWarning, now.timeIntervalSince(lastSaveWarning) < 60 { return }
        lastSaveWarning = now
        show("Couldn't save: \(message)", symbol: "exclamationmark.triangle.fill")
    }

    func go(_ item: SidebarItem) {
        detailPath = NavigationPath()
        searchText = ""
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
        // Nothing selected (⌥⌘D, ⌥⌘L): no "0 planned" message.
        guard !tasks.isEmpty else { return }
        // The store plans whole blocks (subtasks too) and starts or ends each line's run of
        // plans, so Undo puts back both values for every line it can touch. Old ongoing logs
        // inside a block keep their day, unless one was passed in itself.
        let passed = Set(tasks.map(ObjectIdentifier.init))
        var layouts: [UUID?: SectionLayout] = [:]
        var seen = Set<ObjectIdentifier>()
        var before: [(task: TaskItem, day: Date?, since: Date?)] = []
        for task in tasks {
            let layout = layouts[task.groupID] ?? store.layout(for: task.groupID)
            layouts[task.groupID] = layout
            for line in layout.block(of: task) where !seen.contains(ObjectIdentifier(line)) {
                seen.insert(ObjectIdentifier(line))
                guard line.loggedFor == nil || passed.contains(ObjectIdentifier(line)) else { continue }
                before.append((task: line, day: line.plannedDay, since: line.plannedSince))
            }
        }
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
            for item in before {
                var changed = false
                if item.task.plannedDay != item.day {
                    item.task.plannedDay = item.day
                    changed = true
                }
                if item.task.plannedSince != item.since {
                    item.task.plannedSince = item.since
                    changed = true
                }
                if changed { item.task.touch() }
            }
            self?.store.save()
        }
    }

    /// ⌘N, the Home Screen's New Task and the Quick Add hotkey. Plan, Upcoming and Priority keep
    /// their page, because they have a bar of their own (Plan's plans for the day it shows);
    /// pages without one send the task to Today.
    func requestQuickEntry() {
        switch selection {
        case .history, .trash, .matrix, .overview, .tag, .none: go(.today)
        default: if phonePath.isEmpty { go(selection ?? .today) }
        }
        // Search results have no bar: back to the page.
        searchText = ""
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
        Motion.animate(Motion.layout) { self.toast = toast }
        let id = toast.id
        // Undo and warnings stay long enough to be read and reached.
        let seconds = undo == nil && !toast.isWarning ? 2.2 : 4.5
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if self.toast?.id == id {
                Motion.animate(Motion.layout) { self.toast = nil }
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

    /// The row checkbox (see `check(_:)`).
    func toggle(_ task: TaskItem) {
        check(task)
    }

    /// Files tasks under another group, with Undo. Arriving there can add the group's traits
    /// (importance, PH, tags, a deadline) and a suggestion; Undo takes those back too.
    func move(_ tasks: [TaskItem], toGroup groupID: UUID?) {
        guard !tasks.isEmpty else { return }
        var seen = Set<ObjectIdentifier>()
        var before: [MoveSnapshot] = []
        for task in tasks {
            for line in store.layout(for: task.groupID).block(of: task) where !seen.contains(ObjectIdentifier(line)) {
                seen.insert(ObjectIdentifier(line))
                before.append(MoveSnapshot(line))
            }
        }
        store.move(tasks, toGroup: groupID)
        let name = store.group(id: groupID)?.displayName ?? "Quick Entry"
        show("Moved to \(name)", symbol: "folder.fill") { [weak self] in
            for snapshot in before { snapshot.restore() }
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

    /// "Tomorrow" (Plan for Tomorrow): onto tomorrow's plan.
    func deferToTomorrow(_ tasks: [TaskItem]) {
        plan(tasks, for: DayBoundary.current.dayStart(byAdding: 1, to: dayStart))
    }

    /// The selected tasks in a fixed order (list position, then id), so commands that take the
    /// first one don't pick a different task each time.
    var selectedTasks: [TaskItem] {
        let ids = selectedRowIDs.compactMap { id -> UUID? in
            guard id.hasPrefix("t-") else { return nil }
            return UUID(uuidString: String(id.dropFirst(2)))
        }
        return ids.compactMap { store.task(id: $0) }
            .filter { $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.uuid.uuidString) < ($1.sortOrder, $1.uuid.uuidString) }
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
        // The highest-ranked task on today's page, shown with its details: the Mac's details
        // column (-TheoSelectFirst) or the iPhone's details sheet (-TheoDetailFirst).
        let selectFirst = args.contains("-TheoSelectFirst")
        let detailFirst = args.contains("-TheoDetailFirst")
        if selectFirst || detailFirst {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard let task = topTaskPlannedToday() else { return }
                if detailFirst {
                    detailTask = task
                } else {
                    showDetails(task)
                }
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

    /// The open task planned for today that ranks first (a top-level line when there is one).
    private func topTaskPlannedToday() -> TaskItem? {
        // Today leaves out switched-off groups, so the pick does too.
        let planned = store.liveTasks().activeOnly(store.liveGroups()).filter { !$0.isDone && $0.isPlanned(for: dayStart) }
        let roots = planned.filter { $0.indent == 0 }
        let candidates = roots.isEmpty ? planned : roots
        return candidates.min { a, b in
            let scoreA = a.matrixScore(today: dayStart)
            let scoreB = b.matrixScore(today: dayStart)
            return scoreA != scoreB ? scoreA > scoreB : a.sortOrder < b.sortOrder
        }
    }
}

/// What moving a task to another group can change (its place, and what the new group's traits
/// add), so Undo puts all of it back.
private struct MoveSnapshot {
    let task: TaskItem
    let group: TaskGroup?
    let sortOrder: Double
    let indent: Int
    let importance: Double
    let priorityRaw: Int
    let estimate: Double
    let tagsRaw: String
    let dueDate: Date?
    let dueHasTime: Bool
    let repeatAnchorDay: Int?
    let traitProposalGroupID: UUID?

    init(_ task: TaskItem) {
        self.task = task
        group = task.group
        sortOrder = task.sortOrder
        indent = task.indent
        importance = task.importance
        priorityRaw = task.priorityRaw
        estimate = task.estimate
        tagsRaw = task.tagsRaw
        dueDate = task.dueDate
        dueHasTime = task.dueHasTime
        repeatAnchorDay = task.repeatAnchorDay
        traitProposalGroupID = task.traitProposalGroupID
    }

    func restore() {
        task.group = group
        task.sortOrder = sortOrder
        task.indent = indent
        task.importance = importance
        task.priorityRaw = priorityRaw
        task.estimate = estimate
        task.tagsRaw = tagsRaw
        task.dueDate = dueDate
        task.dueHasTime = dueHasTime
        task.repeatAnchorDay = repeatAnchorDay
        task.traitProposalGroupID = traitProposalGroupID
        task.touch()
    }
}
