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
    case estimate
    case placeInMatrix
    case startFocus
    case addReminder
    case addSubproject
    case planTask
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
    public var estimateSum = 0.0
    /// Sum of every task's urgency and importance; changes when one is placed on the matrix.
    public var matrixSum = 0.0
    public var focusRunning = false
    /// Tasks whose deadline has a time (and so a reminder).
    public var timedCount = 0
    public var subgroupCount = 0
    /// Tasks planned for today.
    public var plannedCount = 0

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
        case .estimate:
            return abs(now.estimateSum - base.estimateSum) > 0.001
        case .placeInMatrix:
            return abs(now.matrixSum - base.matrixSum) > 0.001
        case .startFocus:
            return now.focusRunning
        case .addReminder:
            return now.timedCount > base.timedCount
        case .addSubproject:
            return now.subgroupCount > base.subgroupCount
        case .planTask:
            return now.plannedCount > base.plannedCount
        }
    }
}

/// The interactive tour. Add new steps at the end of their topic with `since` set to a new
/// `version`; people who already took the tour then get just those steps as "What's new".
public enum TutorialCatalog {
    public static let version = 5

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
            body: "Touch and hold a task and tap ! , !! or !!!. In the bottom bar, hold the ! chip and slide to an importance from 1 to 10. While typing a line, \u{201C}!!\u{201D} at the end works too.",
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
            body: "Lists are ranked by importance and urgency. Touch and hold a task and drag it up: Theo raises its importance so it stays where you put it.",
            macBody: "Lists are ranked by importance and urgency. Drag a task higher: Theo raises its importance so it stays where you put it.",
            goal: .reorder
        ),
        TutorialStep(
            id: "not-today", since: 1, symbol: "moon.zzz",
            title: "Not today",
            body: "Swipe left on a task and tap Tomorrow. It moves to tomorrow's plan.",
            macBody: "Right-click a task and choose Not Today (⌥⌘L). It moves to tomorrow's plan.",
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
            id: "estimate", since: 2, symbol: "timer",
            title: "Time it in Power Hours",
            body: "One PH is 50 focused minutes. Type \u{201C}0,5ph\u{201D} in the bottom bar, tap the PH chip, or touch and hold a task → Estimate. Today adds up what's planned and what's done.",
            macBody: "One PH is 50 focused minutes. Type \u{201C}0,5ph\u{201D} in the bottom bar, click the PH chip, or right-click a task → Estimate. Today adds up what's planned and what's done.",
            goal: .estimate
        ),
        TutorialStep(
            id: "matrix", since: 3, symbol: "square.grid.3x3",
            title: "Urgent and important",
            body: "Drag the ⊞ handle at the right of the bottom bar onto the grid: left is due today, right is 14 days out (or no date), up is more important (1–10). It snaps into place, and the task shows up ranked everywhere. For an existing task: touch and hold → Place in Matrix.",
            macBody: "Drag the ⊞ handle at the right of the bottom bar onto the grid: left is due today, right is 14 days out (or no date), up is more important (1–10). It snaps into place, and the task shows up ranked everywhere. For an existing task: right-click → Place in Matrix (⌥⌘M).",
            goal: .placeInMatrix
        ),
        TutorialStep(
            id: "focus", since: 2, symbol: "scope",
            title: "Focus for a Power Hour",
            body: "Touch and hold a task → Start Focus. 50 minutes of focus, then a break, and the time is booked on the task. Close the timer and it keeps running.",
            macBody: "Select a task and press ⌥⌘F (or right-click → Start Focus). 50 minutes of focus, then a break, and the time is booked on the task.",
            goal: .startFocus
        ),
        TutorialStep(
            id: "reminder", since: 2, symbol: "bell.badge",
            title: "Never miss a time",
            body: "Add \u{201C}call the bank tomorrow 9am\u{201D}. Tasks with a time remind you. In a task's details you can add earlier reminders, follow-ups and repeats like \u{201C}every week\u{201D}.",
            goal: .addReminder
        ),
        TutorialStep(
            id: "subproject", since: 2, symbol: "folder.badge.plus",
            title: "Projects inside projects",
            body: "Touch and hold the Work heading → New Subproject. Subprojects sit under their parent and fold away with it.",
            macBody: "Right-click the Work heading → New Subproject. Subprojects sit under their parent and fold away with it.",
            goal: .addSubproject
        ),
        TutorialStep(
            id: "plan", since: 3, symbol: "calendar.badge.plus",
            title: "Plan your day",
            body: "Today only shows what you picked for it. Open Plan, choose a day and tap tasks to add them: unfinished ones from earlier days and anything due are suggested first.",
            macBody: "Today only shows what you picked for it. Open Plan (⌘2), choose a day and click tasks to add them: unfinished ones from earlier days and anything due are suggested first.",
            goal: .planTask
        ),
        TutorialStep(
            id: "insert", since: 4, symbol: "plus.square.dashed",
            title: "Drop a task in between",
            body: "Drag the + at the left of the bottom bar up between two tasks, no holding needed. A new line opens right where you let go, ranked between its neighbours (right under a task with subtasks, it becomes the first one).",
            goal: .addTask
        ),
        TutorialStep(
            id: "swipe-subtask", since: 3, symbol: "arrow.turn.down.right",
            title: "Swipe right for a subtask",
            body: "Swipe right on a task to tuck it under the task above it. Swipe right again on a subtask to take it back out.",
            macBody: "Swipe right on a task (two fingers on the trackpad) to tuck it under the task above it, or select it and press ⌘].",
            goal: .addSubtask
        ),
        TutorialStep(
            id: "hold-estimate", since: 4, symbol: "hand.point.up.left",
            title: "Hold and point",
            body: "Hold the send button ↑ and the Power Hours fan out in an arc above it: slide toward one and let go to add the task with it. The ! chip does the same for importance 1–10. Every task starts with 0,25 PH, which you can change in Settings.",
            goal: .estimate
        ),
        TutorialStep(
            id: "group-traits", since: 4, symbol: "wand.and.stars",
            title: "Groups pass things on",
            body: "Edit a group to give its tasks an importance, Power Hours, tags or a deadline. New tasks there take them. A task you move in keeps its own values and shows \u{201C}Suggested\u{201D} instead. On a group's page, tap a subgroup to switch it off: its tasks stay out of Today until you switch it back on.",
            macBody: "Edit a group to give its tasks an importance, Power Hours, tags or a deadline. New tasks there take them. A task you move in keeps its own values and shows \u{201C}Suggested\u{201D} instead. Right-click a group in the sidebar → Switch Off to keep its tasks out of Today.",
            goal: .none
        ),
        TutorialStep(
            id: "review", since: 4, symbol: "chart.bar.xaxis",
            title: "How the day went",
            body: "Tap the ring at the top of Today: Power Hours done and what they went into, how the day compares with the ones before, and every finished task, ready to export as CSV. Pick what it shows in Settings. Today's ⋯ → Group By sorts the page by group, subgroup, priority, deadline, tag or size.",
            macBody: "Press ⌘9 (or click the ring at the top of Today): Power Hours done and what they went into, how the day compares with the ones before, and every finished task, ready to export as CSV. Pick what it shows in Settings. Today's ⋯ → Group By sorts the page by group, subgroup, priority, deadline, tag or size.",
            goal: .none
        ),
        TutorialStep(
            id: "ongoing", since: 5, symbol: "infinity",
            title: "Work that never ends",
            body: "Some tasks are never finished, like checking the account or answering mail. Type \u{201C}laufend\u{201D} or \u{221E} with one (or touch and hold → Ongoing). Checking it off logs it for the day, Power Hours and all, and the task stays for next time. Plan offers it under Ongoing. For a fixed rhythm, give it a deadline and a repeat instead.",
            macBody: "Some tasks are never finished, like checking the account or answering mail. Type \u{201C}laufend\u{201D} or \u{221E} with one (or right-click → Ongoing). Checking it off logs it for the day, Power Hours and all, and the task stays for next time. Plan offers it under Ongoing. For a fixed rhythm, give it a deadline and a repeat instead.",
            goal: .none
        ),
        TutorialStep(
            id: "overdue", since: 3, symbol: "calendar.badge.clock",
            title: "Late is fine",
            body: "Overdue tasks rise to the top with a calm \u{201C}was due …\u{201D}. Tap it to move the date, or swipe left → +1 Day.",
            macBody: "Overdue tasks rise to the top with a calm \u{201C}was due …\u{201D}. Click it to move the date.",
            goal: .none
        ),
        TutorialStep(
            id: "everywhere", since: 1, symbol: "applewatch",
            title: "Everywhere you are",
            body: "Today, Plan, Lists and Search are in the tab bar; Upcoming, the Matrix, History and each group are under Lists. Search finds everything. Theo syncs with your Mac through iCloud, and on Apple Watch you can check things off and add tasks by voice.",
            macBody: "Today, Plan, Upcoming, the Matrix, History and each group are in the sidebar (⌘1–7), with their shortcuts in grey. ⇧⌘F opens the focus timer. The menu bar icon adds tasks from anywhere. Theo syncs with your iPhone through iCloud, and on Apple Watch you can check things off and add tasks by voice.",
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
