import Foundation

/// What the practice page has to show before a tour step counts as done.
public enum TutorialGoal: String, Sendable, CaseIterable {
    /// Nothing to do: read, then continue.
    case none
    case addTask
    /// A new task that got a deadline and a priority from what was typed.
    case addTaskWithDetails
    case complete
    case prioritize
    case addSubtask
    case toggleSubtasks
    case reorder
    case deferTask
    case deleteAndUndo
    case addGroup
    case openDetails
}

/// A summary of the practice page, taken after every change.
public struct TutorialSnapshot: Equatable, Sendable {
    public var taskCount = 0
    public var doneCount = 0
    public var prioritySum = 0
    public var prioritizedCount = 0
    public var datedCount = 0
    public var subtaskCount = 0
    public var deferredCount = 0
    public var deletedCount = 0
    public var groupCount = 0
    public var collapsedCount = 0
    /// Open task IDs in page order.
    public var order: [String] = []
    public var detailsOpen = false

    public init() {}
}

public struct TutorialStep: Identifiable, Sendable {
    public let id: String
    /// Tour version that introduced the step. Steps newer than what someone has seen make up
    /// their "What's new" tour.
    public let since: Int
    public let symbol: String
    public let title: String
    /// Instructions for iPhone and iPad.
    public let body: String
    /// Instructions for the Mac (pointer and keyboard).
    public let macBody: String
    public let goal: TutorialGoal

    public init(id: String, since: Int, symbol: String, title: String, body: String, macBody: String? = nil, goal: TutorialGoal) {
        self.id = id
        self.since = since
        self.symbol = symbol
        self.title = title
        self.body = body
        self.macBody = macBody ?? body
        self.goal = goal
    }
}

/// Follows the current step by comparing the page with how it looked when the step started.
public struct TutorialTracker: Sendable {
    public private(set) var baseline: TutorialSnapshot
    private var sawDelete = false

    public init(baseline: TutorialSnapshot) {
        self.baseline = baseline
    }

    /// Starts the next step from the page as it is now.
    public mutating func restart(at snapshot: TutorialSnapshot) {
        baseline = snapshot
        sawDelete = false
    }

    /// Whether `goal` has been reached, given the page as it is now. Call it after every change.
    public mutating func isMet(_ goal: TutorialGoal, now: TutorialSnapshot) -> Bool {
        let base = baseline
        switch goal {
        case .none:
            return false
        case .addTask:
            return now.taskCount > base.taskCount
        case .addTaskWithDetails:
            return now.taskCount > base.taskCount && now.datedCount > base.datedCount && now.prioritizedCount > base.prioritizedCount
        case .complete:
            return now.doneCount > base.doneCount
        case .prioritize:
            return now.prioritySum != base.prioritySum
        case .addSubtask:
            return now.subtaskCount > base.subtaskCount
        case .toggleSubtasks:
            return now.collapsedCount != base.collapsedCount
        case .reorder:
            return now.order != base.order && now.order.sorted() == base.order.sorted()
        case .deferTask:
            return now.deferredCount > base.deferredCount
        case .deleteAndUndo:
            if now.deletedCount > base.deletedCount { sawDelete = true }
            return sawDelete && now.deletedCount <= base.deletedCount
        case .addGroup:
            return now.groupCount > base.groupCount
        case .openDetails:
            return now.detailsOpen
        }
    }
}

/// The interactive tour. Add new steps at the end of their topic with `since` set to a new
/// `version`; people who already took the tour then get just those steps as "What's new".
public enum TutorialCatalog {
    public static let version = 1

    public static let welcome = TutorialStep(
        id: "welcome", since: 1, symbol: "hand.wave",
        title: "Welcome to Theo",
        body: "Two minutes, hands on. This is a practice page, so nothing you do here touches your real tasks. Each step ticks itself off when you've tried it.",
        goal: .none
    )

    public static let whatsNew = TutorialStep(
        id: "whats-new", since: 1, symbol: "sparkles",
        title: "What's new in Theo",
        body: "A few new things to try, on a practice page. Nothing here touches your real tasks.",
        goal: .none
    )

    public static let finish = TutorialStep(
        id: "finish", since: 1, symbol: "checkmark.seal",
        title: "You're all set",
        body: "Replay this tour any time from Settings or the ⋯ menu on Today. New features show up here as a short \u{201C}What's new\u{201D} tour.",
        goal: .none
    )

    public static let steps: [TutorialStep] = [
        welcome,
        TutorialStep(
            id: "add", since: 1, symbol: "plus.circle",
            title: "Add a task",
            body: "Type anything into the bar at the bottom and press Return. The keyboard stays up, so keep going: one line, one task.",
            macBody: "Click the bar at the bottom (or press ⌘N), type, and press Return. Keep typing to add more.",
            goal: .addTask
        ),
        TutorialStep(
            id: "shortcuts", since: 1, symbol: "text.badge.star",
            title: "Say it naturally",
            body: "Type \u{201C}Call mom tomorrow 5pm !!\u{201D}. Theo picks up the deadline and the priority and shows them as chips. Tap a chip to undo a guess. The buttons above the bar set them too.",
            goal: .addTaskWithDetails
        ),
        TutorialStep(
            id: "complete", since: 1, symbol: "checkmark.circle",
            title: "Check it off",
            body: "Tap the circle next to a task. It sinks to the bottom, like in Notes. Tap it again to bring it back.",
            macBody: "Click the circle next to a task, or select it and press Space.",
            goal: .complete
        ),
        TutorialStep(
            id: "priority", since: 1, symbol: "exclamationmark.3",
            title: "Priority in one tap",
            body: "Touch and hold a task and tap ! , !! or !!!. Or swipe right and tap Priority. While typing a line, \u{201C}!!\u{201D} at the end works too.",
            macBody: "Right-click a task and click ! , !! or !!!, or select it and press ⌥⌘1, 2 or 3. Typing \u{201C}!!\u{201D} at the end of a line works too.",
            goal: .prioritize
        ),
        TutorialStep(
            id: "subtask", since: 1, symbol: "arrow.turn.down.right",
            title: "Break it down",
            body: "Touch and hold \u{201C}Call grandma\u{201D} → Add Subtask. While editing a line, ⇥ above the keyboard indents it, and in the bottom bar \u{201C}- \u{201D} files a line under the task you just added.",
            macBody: "Right-click \u{201C}Call grandma\u{201D} and choose Add Subtask (⌥⌘N). While editing a line, Tab indents and Shift-Tab outdents. In the bottom bar, start with \u{201C}- \u{201D} to add a subtask to the task you just added.",
            goal: .addSubtask
        ),
        TutorialStep(
            id: "fold", since: 1, symbol: "chevron.down.circle",
            title: "Fold subtasks away",
            body: "Tap the 0/2 badge on \u{201C}Plan a hike\u{201D} to hide its subtasks. Tap it again to show them.",
            macBody: "Click the 0/2 badge on \u{201C}Plan a hike\u{201D} to hide its subtasks. Click again to show them.",
            goal: .toggleSubtasks
        ),
        TutorialStep(
            id: "reorder", since: 1, symbol: "arrow.up.arrow.down",
            title: "Higher means more important",
            body: "Touch and hold a task, then drag it up. Like in your Notes, position on the page is priority.",
            macBody: "Drag a task higher, or select it and press ⌥⌘↑. Like in your Notes, position on the page is priority.",
            goal: .reorder
        ),
        TutorialStep(
            id: "not-today", since: 1, symbol: "moon.zzz",
            title: "Not today",
            body: "Swipe right on a task and tap Not Today. It disappears until tomorrow, then comes back on its own.",
            macBody: "Right-click a task and choose Not Today (⌥⌘L). It comes back tomorrow on its own.",
            goal: .deferTask
        ),
        TutorialStep(
            id: "undo", since: 1, symbol: "arrow.uturn.backward",
            title: "Mistakes are fine",
            body: "Swipe left on a task and tap Delete, then tap Undo in the message that pops up. Shaking your iPhone undoes the last change, too.",
            macBody: "Select a task and press ⌘⌫, then click Undo in the message, or press ⌘Z.",
            goal: .deleteAndUndo
        ),
        TutorialStep(
            id: "group", since: 1, symbol: "folder.badge.plus",
            title: "Groups are headings",
            body: "Tap the folder button at the top to add a heading like Work or Home. Tap a heading to fold it, and drag tasks between headings.",
            macBody: "Press ⇧⌘N (File → New Group…) to add a heading like Work or Home. In the main window it's also the folder button in the toolbar. Click a heading to fold it, and drag tasks between headings.",
            goal: .addGroup
        ),
        TutorialStep(
            id: "details", since: 1, symbol: "info.circle",
            title: "Everything else",
            body: "Tap a task to edit it, then tap ⓘ for notes, deadline, tags and subtasks. Touch and hold opens the full menu.",
            macBody: "Select a task and press ⌘I (or right-click → Details…) for notes, deadline, tags and subtasks.",
            goal: .openDetails
        ),
        TutorialStep(
            id: "everywhere", since: 1, symbol: "applewatch",
            title: "Everywhere you are",
            body: "Upcoming, Priority, History and each group are one tap back. Search finds everything. Theo syncs with your Mac through iCloud, and on Apple Watch you can check things off and add tasks by voice.",
            macBody: "Upcoming, Priority, History and each group are in the sidebar (⌘1–6). The menu bar icon adds tasks from anywhere. Theo syncs with your iPhone through iCloud, and on Apple Watch you can check things off and add tasks by voice.",
            goal: .none
        ),
        finish,
    ]

    /// The tour for someone who last saw `seenVersion`: everything on first run, otherwise
    /// only the steps added since (empty when there's nothing new).
    public static func steps(newerThan seenVersion: Int) -> [TutorialStep] {
        guard seenVersion > 0 else { return steps }
        let new = steps.filter { $0.since > seenVersion && $0.id != welcome.id && $0.id != finish.id }
        guard !new.isEmpty else { return [] }
        return [whatsNew] + new + [finish]
    }
}
