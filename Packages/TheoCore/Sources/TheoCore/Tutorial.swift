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
    /// Open task IDs in the order the page ranks them.
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
    public static let version = 11

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
        body: "Replay this tour any time from Settings or the ⋯ menu on Today. New features show up here as a short \u{201C}What's new\u{201D} tour, and Settings → What's New shows it again.",
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
            id: "dates-de", since: 9, symbol: "calendar",
            title: "Dates, the way you say them",
            body: "Type “Zahnarzt morgen 9 Uhr” and Theo sets the deadline. It also understands “bis Freitag”, “am 15.12.”, “in 3 Tagen”, “jeden Montag” and “alle 2 Wochen”, in English too. The date chip shows which words it took; tap the × next to it to keep them in the title.",
            macBody: "Type “Zahnarzt morgen 9 Uhr” and Theo sets the deadline. It also understands “bis Freitag”, “am 15.12.”, “in 3 Tagen”, “jeden Montag” and “alle 2 Wochen”, in English too. The date chip shows which words it took; click the × next to it to keep them in the title.",
            goal: .addTask
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
            macBody: "Right-click \u{201C}Call grandma\u{201D} and click Subtask (or select it and press ⌥⌘N). While editing a line, Tab indents and Shift-Tab outdents. In the bottom bar, start with \u{201C}- \u{201D} to add a subtask to the task you just added.",
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
            id: "not-today", since: 1, symbol: "moon.zzz.fill",
            title: "Leave it for tomorrow",
            body: "Swipe left on a task and tap Tomorrow. It moves to tomorrow's plan.",
            macBody: "Right-click a task and click Tomorrow, or select it and press ⌥⌘L (Plan for Tomorrow). It moves to tomorrow's plan.",
            goal: .deferTask
        ),
        TutorialStep(
            id: "swipe-today", since: 9, symbol: "sun.max.fill",
            title: "Today in one swipe",
            body: "On any list, swipe left on a task and tap Today to put it on today's plan. On a task that's already on today, the same spot says Tomorrow.",
            macBody: "Swipe left with two fingers on a task and click Today, or select it and press ⌥⌘D. On a task that's already on today, the same spot says Tomorrow.",
            goal: .none
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
            body: "Tap ⋯ → New Group to add a heading like Work or Home. Tap a heading to fold it, and drag tasks between headings.",
            macBody: "Press ⇧⌘N (or Today's ⋯ → New Group…) to add a heading like Work or Home. Click a heading to fold it, and drag tasks between headings.",
            goal: .addGroup
        ),
        TutorialStep(
            id: "details", since: 1, symbol: "info.circle",
            title: "Everything else",
            body: "Tap a task to edit it, then tap ⓘ for the description, deadline, plan and subtasks. The Plan row on top puts it on Today, Tomorrow, Next Week or any day you pick. Touch and hold opens the full menu.",
            macBody: "Select a task and press ⌘I (or right-click → Details) for the description, deadline, plan and subtasks. The Plan row on top puts it on Today, Tomorrow, Next Week or any day you pick. In the main window they sit in the column on the right.",
            goal: .openDetails
        ),
        TutorialStep(
            id: "estimate", since: 2, symbol: "timer",
            title: "Time it in Power Hours",
            body: "One PH is 50 focused minutes. Type \u{201C}0,5ph\u{201D} in the bottom bar, tap the PH chip, or touch and hold a task → Estimate. Today adds up what's planned and what's done.",
            macBody: "One PH is 50 focused minutes. Type \u{201C}0,5ph\u{201D} in the bottom bar, click the PH chip, or right-click a task and pick its Power Hours. Today adds up what's planned and what's done.",
            goal: .estimate
        ),
        TutorialStep(
            id: "matrix", since: 3, symbol: "square.grid.3x3",
            title: "Urgent and important",
            body: "Drag the ⊞ handle at the right of the bottom bar onto the grid: left is due today, right is 14 days out (or no date), up is more important (1–10). It snaps into place, and the task shows up ranked everywhere. For an existing task: touch and hold → Place in Matrix. On the Matrix page, tap a dot to see its name and tap it again to open it.",
            macBody: "Drag the ⊞ handle at the right of the bottom bar onto the grid: left is due today, right is 14 days out (or no date), up is more important (1–10). It snaps into place, and the task shows up ranked everywhere. For an existing task: select it and press ⌥⌘M (Place in Matrix). On the Matrix page, point at a dot to see its name and click it to show it in the details column.",
            goal: .placeInMatrix
        ),
        TutorialStep(
            id: "focus", since: 2, symbol: "scope",
            title: "Focus for a Power Hour",
            body: "Touch and hold a task → Start Focus. 50 minutes of focus, then a break, and the time is booked on the task. Close the timer and it keeps running.",
            macBody: "Select a task and press ⌥⌘F (or right-click → Focus). 50 minutes of focus, then a break, and the time is booked on the task.",
            goal: .startFocus
        ),
        TutorialStep(
            id: "reminder", since: 2, symbol: "bell.badge",
            title: "Never miss a time",
            body: "Add \u{201C}call the bank tomorrow 9am\u{201D}. Tasks with a time remind you, and the reminder's buttons check it off, snooze it or move it to tomorrow. In a task's details you can add earlier reminders, follow-ups and repeats like \u{201C}every week\u{201D}.",
            goal: .addReminder
        ),
        TutorialStep(
            id: "subproject", since: 2, symbol: "folder.badge.plus",
            title: "Groups inside groups",
            body: "Touch and hold the Work heading → New Subgroup. Subgroups sit under their parent and fold away with it.",
            macBody: "Right-click the Work heading and choose New Subgroup. Subgroups sit under their parent and fold away with it.",
            goal: .addSubproject
        ),
        TutorialStep(
            id: "plan", since: 3, symbol: "calendar.badge.plus",
            title: "Plan your day",
            body: "Today only shows what you picked for it. Open Plan, choose a day and tap tasks to add them: unfinished ones from earlier days and anything due are suggested first.",
            macBody: "Today only shows what you picked for it. Open Plan (⌘2), choose a day and click a task's circle to add it: unfinished ones from earlier days and anything due are suggested first.",
            goal: .planTask
        ),
        TutorialStep(
            id: "plan-actions", since: 9, symbol: "calendar.badge.plus",
            title: "Plan with all the tools",
            body: "In Plan, tap a task to put it on the day, and tap again to take it off. Touch and hold it for the menu: Quick Edit opens the colourful panel, Details the whole task. An indigo sun marks what's on today. Planning tomorrow offers “Still open today” with Add All; later days fold earlier plans away under “Already planned earlier”.",
            macBody: "In Plan, click a task's circle (or double-click the task) to plan it, click the task to see it in the details column, and right-click it for the menu with Quick Edit. Planning tomorrow offers “Still open today” with Add All; later days fold earlier plans away under “Already planned earlier”.",
            goal: .none
        ),
        TutorialStep(
            id: "plan-panes", since: 10, symbol: "rectangle.split.2x1",
            title: "Plan side by side",
            body: "On a wide iPad, Plan shows what to plan on the left and the day's plan on the right. Drag a task across to plan it, onto a day in the strip for that day, or back to the left to take it off. Every drop has Undo.",
            macBody: "In a wide window, Plan shows what to plan on the left and the day's plan on the right. Drag a task across to plan it, onto a day in the strip for that day, or back to the left to take it off. Every drop has Undo.",
            goal: .none
        ),
        TutorialStep(
            id: "carry-over", since: 9, symbol: "arrow.uturn.forward",
            title: "Nothing slips overnight",
            body: "If something you planned stays open, Today shows “↪ N unfinished from earlier” at the top: Bring Over puts it back on today. Tasks due by today that aren't planned get an Add. Tap the hint to open Plan; × hides it for the day.",
            macBody: "If something you planned stays open, Today shows “↪ N unfinished from earlier” at the top: Bring Over puts it back on today. Tasks due by today that aren't planned get an Add. Click the hint to open Plan; × hides it for the day.",
            goal: .none
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
            id: "thalia", since: 11, symbol: "arrow.up.forward.app",
            title: "Finished work counts in Thalia",
            body: "Edit a group and pick its \u{201C}Thalia-Kategorie\u{201D}: every task you finish there, with its Power Hours, then counts for that category in Thalia on this iPhone or iPad. Subgroups without their own choice take their group's. Settings → Thalia → \u{201C}An Thalia liefern\u{201D} switches it off on every device.",
            macBody: "Edit a group and pick its \u{201C}Thalia-Kategorie\u{201D}: every task you finish there, with its Power Hours, then counts for that category in Thalia on this Mac. Subgroups without their own choice take their group's. Settings → Thalia → \u{201C}An Thalia liefern\u{201D} switches it off on every device.",
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
            body: "Some tasks are never finished, like checking the account or answering mail. Type \u{201C}laufend\u{201D} or \u{221E} with one (or touch and hold → Ongoing). Checking it off logs it for the day, Power Hours and all, and the task stays for next time. Plan offers it under Ongoing. Give it a deadline and a repeat too, and it comes back on its own.",
            macBody: "Some tasks are never finished, like checking the account or answering mail. Type \u{201C}laufend\u{201D} or \u{221E} with one (or right-click → Ongoing). Checking it off logs it for the day, Power Hours and all, and the task stays for next time. Plan offers it under Ongoing. Give it a deadline and a repeat too, and it comes back on its own.",
            goal: .none
        ),
        TutorialStep(
            id: "all-tasks", since: 6, symbol: "tray.full",
            title: "Every task, any way",
            body: "Lists → All Tasks shows everything, by group and by priority and deadline to start with. Filters narrow it down (group, tag, importance, deadline, planned, size, ongoing). Group By and Sort change the layout, and the chips on top switch in one tap. ⋯ → Save as View keeps a combination in the sidebar. Touch and hold a group or view → Add to Favorites puts it on top.",
            macBody: "All Tasks (⇧⌘A) shows everything, by group and by priority and deadline to start with. Filters narrow it down (group, tag, importance, deadline, planned, size, ongoing). Group By and Sort change the layout, and the chips on top switch in one tap. ⋯ → Save as View keeps a combination in the sidebar. Right-click a group or view → Add to Favorites puts it on top.",
            goal: .none
        ),
        TutorialStep(
            id: "overview", since: 6, symbol: "chart.pie",
            title: "The big picture",
            body: "The Overview tab sums it all up: what's open and how big, what's due in the next two weeks, every group with its size and what's pressing, the priorities, ongoing work and the biggest open blocks. Tap any card to open the list behind it. A task with subtasks shows their Power Hours added up (Σ).",
            macBody: "Overview (⇧⌘O) sums it all up: what's open and how big, what's due in the next two weeks, every group with its size and what's pressing, the priorities, ongoing work and the biggest open blocks. Click any card to open the list behind it. Hover between two lines and click the + to add a task right there; swipe right or left with two fingers to indent or outdent.",
            goal: .none
        ),
        TutorialStep(
            id: "description", since: 7, symbol: "text.alignleft",
            title: "A description in passing",
            body: "Type “ // ” in the bottom bar (or tap Description) and whatever follows becomes the task's description: “Call bank // ask about the fee”. While editing a task, the description sits right under its title; the ≡ button above the keyboard jumps there. Text too small or too big? Settings → Appearance → Text Size.",
            macBody: "Type “ // ” in the bottom bar and whatever follows becomes the task's description: “Call bank // ask about the fee”. While editing a task, the description sits right under its title; ⇧Return jumps there. ⌘+ and ⌘− make all text bigger or smaller, ⌘0 resets it.",
            goal: .none
        ),
        TutorialStep(
            id: "quick-edit", since: 8, symbol: "slider.horizontal.3",
            title: "Change a task in one tap",
            body: "Touch and hold a task → Quick Edit: done, today or tomorrow, subtask, ongoing, focus, priority, deadline, Power Hours and group, each one tap, in colour. On a task that's already on today, the sun says Off Plan. Everything else is under Details.",
            macBody: "Right-click a task: its quick actions open right above it in colour (done, today or tomorrow, subtask, ongoing, focus, priority, deadline, Power Hours, group); on a task that's already on today, the sun says Off Plan. Select a task and its full details sit in the column on the right, with round quick actions on top, editable in place (⌥⌘I shows or hides it). Control-click still opens the full menu.",
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
            id: "capture-anywhere", since: 9, symbol: "mic",
            title: "Add from anywhere",
            body: "Say “Add a task to Theo” to Siri, or put Theo's Quick Entry on the Action button (Settings → Action Button → Shortcut → Theo). The Shortcuts app has Add Task, What's Left Today and Quick Entry, and Add Task understands the same shortcuts as the bottom bar. Ask Siri “What's left in Theo” for the rest of your day.",
            macBody: "Press ⌃⌥⌘N in any app: a small panel opens right there and Theo stays in the background. Type the task as in the bottom bar (“Report bis Freitag !! #work”); the line underneath shows what Theo understood. Return adds it, ⇧Return adds it and keeps the panel open for the next one, Esc closes it. Paste a list for one task per line. Settings → Quick Add changes the key, or opens Theo's window instead. Spotlight adds one too: ⌘Space, type “Add Task”, then the task, then Return. ⌘F searches every task from any page.",
            goal: .none
        ),
        TutorialStep(
            id: "widgets", since: 10, symbol: "square.grid.2x2",
            title: "Today at a glance",
            body: "Put Theo's Today widget on your Home Screen: touch and hold the Home Screen → Edit → Add Widget → Theo. Small shows how many tasks are open and the Power Hours left, medium and large list what's next. Tap a task to open it. It also fits the Lock Screen and the watch face, and Control Center has Add to Theo (Edit → Add a Control → Theo).",
            macBody: "Put Theo's Today widget on your desktop: right-click the desktop → Edit Widgets → Theo. It shows what's open, the Power Hours left and what's next; click a task to open it in Theo.",
            goal: .none
        ),
        TutorialStep(
            id: "bar-and-mac", since: 10, symbol: "at",
            title: "New on the Mac and in the bottom bar",
            body: "Type @ or # in the bottom bar and Theo offers your groups and tags; tap one to put it in. “@Work/Admin” files into a subgroup. On an iPad with the sidebar showing, drag tasks onto it: onto a group or Quick Entry to move them there, onto Today or Plan to plan them for today or tomorrow.",
            macBody: "Type @ or # in the bottom bar and Theo offers your groups and tags: ↓ ↑ to choose, Tab or Return to take one, Esc to hide them. “@Work/Admin” files into a subgroup. Drag tasks onto the sidebar: onto a group or Quick Entry to move them there, onto Today or Plan to plan them for today or tomorrow. ⌃⌥⌘N opens a small Quick Add panel in any app while Theo stays in the background. ⌘+ and ⌘− change the size of all of Theo's text, the details, sheets and menu bar included.",
            goal: .none
        ),
        TutorialStep(
            id: "everywhere", since: 1, symbol: "applewatch",
            title: "Everywhere you are",
            body: "Today, Plan, Overview, Lists and Search are in the tab bar; Upcoming, the Matrix, History and each group are under Lists. Search finds everything. Theo syncs with your Mac through iCloud, and on Apple Watch you can check things off and add tasks by voice.",
            macBody: "Every page is in the sidebar with its shortcut in grey (⌘1–9, ⇧⌘O Overview, ⇧⌘A All Tasks), and the keys worth remembering are listed below it. ⌘F searches everything, ⇧⌘F opens the focus timer, and the menu bar icon adds tasks from anywhere. Theo syncs with your iPhone through iCloud, and on Apple Watch you can check things off and add tasks by voice.",
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
