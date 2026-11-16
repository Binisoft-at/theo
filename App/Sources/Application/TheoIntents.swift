import AppIntents
import Foundation
import SwiftData
import TheoCore
#if os(iOS)
import UIKit
#endif

// Siri, Shortcuts, Spotlight on the Mac and the Action button. The intents run inside the app
// and use the one AppModel (and container) TheoApp builds at launch, also when the system
// starts Theo only to run an intent. They never open a second container: two on the same
// iCloud-synced store can duplicate or damage synced data. Without the model they ask to open
// Theo instead. No extra target, entitlement or Info.plist key is needed; Xcode extracts the
// intents' metadata at build time.

/// Adds one task, understood like a line typed into the composer:
/// "Call Anna tomorrow 5pm !! @Work #calls".
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription("Adds a task to Theo. Understands !!, dates, #tags, @groups, PH and repeats.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Task", requestValueDialog: IntentDialog("What's the task?"))
    var text: String

    @Parameter(title: "Plan for Today", default: false)
    var planForToday: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Theo") {
            \.$planForToday
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = try theoModel()
        app.refreshDay()
        let today = app.dayStart
        // Text shared from another app can run over several lines: the first one is the
        // task, the others become its description, so nothing is lost.
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { throw TheoIntentError.nothingToAdd }
        let store = app.store
        let groups = store.liveGroups()
        let refs = groups.map { QuickParser.GroupRef(id: $0.uuid, name: $0.displayName, parentID: $0.parentUUID) }
        var entry = QuickParser.parse(first, groups: refs, now: today)
        guard !entry.title.isEmpty else { throw TheoIntentError.nothingToAdd }
        let more = lines.dropFirst().joined(separator: "\n")
        if !more.isEmpty {
            entry.notes = entry.notes.isEmpty ? more : entry.notes + "\n" + more
        }
        let placement = NewTaskPlacement(rawValue: UserDefaults.standard.string(forKey: Prefs.newTaskPlacement) ?? "") ?? .bottom
        // The store gives a repeat without a date its first date (today), as everywhere else.
        let task = store.addTask(entry, defaultGroupID: nil, placement: placement)
        if planForToday { store.plan([task], for: today) }

        #if os(iOS)
        // Siri may have started Theo in the background just for this, and iOS suspends it as
        // soon as the answer is back: keep it running a little longer, so the new task reaches
        // iCloud (the Mac shows it) and a timed task gets its reminder (scheduled a second
        // after the save). Siri answers right away.
        IntentBackgroundHold.begin()
        #endif

        let place = task.group.map { GroupTree.path(of: $0, in: groups) } ?? "Quick Entry"
        var parts = ["Added “\(task.trimmedTitle)” to \(place)"]
        if let due = task.dueDate {
            parts.append("due " + DateText.dueInline(due, hasTime: task.dueHasTime, today: today))
        }
        if let recurrence = task.recurrence {
            parts.append("repeats " + recurrence.title.lowercased())
        }
        if task.isOngoing { parts.append("ongoing") }
        if task.isPlanned(for: today) { parts.append("on today's plan") }
        let message = parts.joined(separator: " · ")
        return .result(dialog: "\(message)")
    }
}

/// Opens Theo with the cursor in the composer (the Action button's "Theo → Quick Entry").
struct OpenQuickEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Entry"
    static let description = IntentDescription("Opens Theo with the cursor in the new-task field.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppModel.shared else {
            // RootView asks for the composer as soon as the window is active.
            QuickActions.pendingQuickEntry = true
            return .result()
        }
        #if os(macOS)
        // Theo may be running with no window (only the menu bar icon).
        MainWindow.reopen()
        #elseif os(iOS)
        // Still on its way to the front: RootView asks again once the scene is active. Only
        // then, so a flag left behind can't pop the keyboard up on a later return to Theo.
        if UIApplication.shared.applicationState != .active {
            QuickActions.pendingQuickEntry = true
        }
        #endif
        app.commandTarget.requestQuickEntry()
        return .result()
    }
}

/// "7 open today · 3,5 PH left · next: Pay the invoice", read out by Siri.
struct TodaySummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Left Today"
    static let description = IntentDescription("Tells you how many tasks on today's plan are still open, the Power Hours left and what's next.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let app = try theoModel()
        app.refreshDay()
        let today = app.dayStart
        let store = app.store
        let groups = store.liveGroups()
        // What Today shows: tasks planned for today, outside switched-off groups.
        let live = store.liveTasks().activeOnly(groups)
        let open = live.filter { !$0.isDone && $0.isPlanned(for: today) }
        let earlier = live.filter { $0.isLeftOver(before: today) }.count

        var parts: [String] = []
        if open.isEmpty {
            parts.append("Nothing open on today's plan")
        } else {
            parts.append("\(open.count) open today")
            let left = PageBuilder.estimateTotals(open).open
            if left > 0 { parts.append(PowerHours.format(left) + " left") }
            if let next = Self.topRanked(open, groups: groups, today: today) {
                parts.append("next: \(next.trimmedTitle)")
            }
        }
        // Left open on an earlier day's plan: said out loud, so nothing waits unnoticed.
        if earlier > 0 {
            parts.append(earlier == 1 ? "1 still open from an earlier day" : "\(earlier) still open from earlier days")
        }
        let message = parts.joined(separator: " · ")
        return .result(dialog: "\(message)")
    }

    /// The open task ranked first: highest matrix score; equal scores keep page order, as in Today.
    @MainActor
    private static func topRanked(_ tasks: [TaskItem], groups: [TaskGroup], today: Date) -> TaskItem? {
        var best: TaskItem?
        var bestScore = -Double.infinity
        for task in tasks.sorted(by: Sections.pageOrder(groups)) where !task.trimmedTitle.isEmpty {
            let score = task.matrixScore(today: today)
            if score > bestScore {
                best = task
                bestScore = score
            }
        }
        return best
    }
}

/// The phrases Siri understands and the actions Spotlight and the Shortcuts app offer
/// without any setup. Every phrase has to name the app.
struct TheoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "New \(.applicationName) task",
                "Add to \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TodaySummaryIntent(),
            phrases: [
                "What's left in \(.applicationName)",
                "\(.applicationName) today",
            ],
            shortTitle: "What's Left Today",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: OpenQuickEntryIntent(),
            phrases: [
                "Quick entry in \(.applicationName)",
            ],
            shortTitle: "Quick Entry",
            systemImageName: "square.and.pencil"
        )
    }
}

/// What Siri or Shortcuts says when an intent can't run.
enum TheoIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// The app model isn't there (it is created when Theo launches).
    case notRunning
    case nothingToAdd
    /// The store fell back to memory: anything added would be gone after a restart.
    case storageUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning: "Open Theo once, then try again."
        case .nothingToAdd: "There's no task to add. Say or type it, for example “Call Anna tomorrow at 5”."
        case .storageUnavailable: "Theo couldn't open your tasks, so nothing would be kept. Open Theo to see what's wrong."
        }
    }
}

/// The app's one model, or a friendly error. Never builds a second container.
@MainActor
private func theoModel() throws -> AppModel {
    guard let app = AppModel.shared else { throw TheoIntentError.notRunning }
    if Persistence.storeKind == .memory && !Persistence.isDemo { throw TheoIntentError.storageUnavailable }
    return app
}

#if os(iOS)
/// Twenty more seconds of running after an intent saved something (like after a reminder's
/// banner action): enough for the iCloud upload and the reminder rebuild, well inside the
/// time iOS allows. Another add within that time starts the twenty seconds again.
@MainActor
private enum IntentBackgroundHold {
    private static var work: UIBackgroundTaskIdentifier = .invalid
    private static var timer: Task<Void, Never>?

    static func begin() {
        if work == .invalid {
            work = UIApplication.shared.beginBackgroundTask(withName: "Theo Siri task") {
                MainActor.assumeIsolated { IntentBackgroundHold.end() }
            }
        }
        timer?.cancel()
        timer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            IntentBackgroundHold.end()
        }
    }

    private static func end() {
        timer?.cancel()
        timer = nil
        guard work != .invalid else { return }
        UIApplication.shared.endBackgroundTask(work)
        work = .invalid
    }
}
#endif
