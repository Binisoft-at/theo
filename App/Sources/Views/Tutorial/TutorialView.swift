import SwiftUI
import SwiftData
import TheoCore

/// The interactive tour: the real Today page on a throwaway practice store, with a coach card
/// on top. Each step watches the page and ticks itself off once you've done what it describes.
struct TutorialView: View {
    let steps: [TutorialStep]
    let onFinish: () -> Void

    @State private var sandbox = TutorialSandbox()
    /// The real app's model (this view sits outside the sandbox environment).
    @Environment(AppModel.self) private var hostApp
    @AppStorage(Prefs.accent) private var accentRaw = AccentChoice.notes.rawValue

    private var accent: Color { (AccentChoice(rawValue: accentRaw) ?? .notes).color }

    var body: some View {
        TutorialStage(steps: steps, accent: accent, onClose: onFinish)
            .environment(sandbox.app)
            .modelContainer(sandbox.container)
            // Practice-page settings (grouping, folded sections ...) never touch the real ones.
            .defaultAppStorage(sandbox.defaults)
            .tint(accent)
            // Menu-bar commands (⌘N, ⌥⌘1 ...) act on the practice page while the tour is open.
            .onAppear { hostApp.tourModel = sandbox.app }
            .onDisappear { hostApp.tourModel = nil }
    }
}

/// An in-memory store seeded with a few tasks, its own app model and its own settings.
@MainActor
final class TutorialSandbox {
    let container: ModelContainer
    let app: AppModel
    let defaults: UserDefaults

    init() {
        let config = ModelConfiguration("TheoTour", schema: Persistence.schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
        // An in-memory store only fails to open when the process is out of memory.
        container = try! ModelContainer(for: Persistence.schema, configurations: config)
        let suite = (Bundle.main.bundleIdentifier ?? "theo") + ".tour"
        defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
        defaults.removePersistentDomain(forName: suite)
        app = AppModel(container: container, isSandbox: true)
        Self.seed(container.mainContext)
    }

    /// Practice tasks the steps refer to ("Call grandma", "Plan a hike" with two subtasks ...).
    static func seed(_ context: ModelContext) {
        let store = TaskStore(context: context)
        let today = DayBoundary.current.start(of: Date())

        @discardableResult
        func add(_ title: String, _ group: TaskGroup?, priority: Priority = .normal, dueToday: Bool = false) -> TaskItem {
            let task = store.addTask(ParsedEntry(title: title), defaultGroupID: group?.uuid, placement: .bottom)
            task.priority = priority
            if dueToday { task.dueDate = Calendar.current.startOfDay(for: today) }
            return task
        }

        add("Water the plants", nil)
        add("Reply to Anna's email", nil)
        add("Call grandma", nil)

        let weekend = store.addGroup(name: "Weekend", symbol: "sun.max", color: .orange)
        let hike = add("Plan a hike", weekend)
        store.addSubtask(ParsedEntry(title: "Check the weather"), to: hike)
        store.addSubtask(ParsedEntry(title: "Pack snacks"), to: hike)
        add("Buy flowers", weekend)

        let work = store.addGroup(name: "Work", symbol: "briefcase", color: .blue)
        add("Prepare slides for Monday", work, priority: .medium)
        add("Send the invoice", work, dueToday: true)

        // Everything but Work is on today's plan, so the Plan step has something to pick.
        let key = Calendar.current.startOfDay(for: today)
        for task in store.liveTasks() where task.group?.uuid != work.uuid {
            task.plannedDay = key
        }
        store.save()
    }
}

/// The practice page plus the coach card, inside the sandbox's environment.
struct TutorialStage: View {
    let steps: [TutorialStep]
    let accent: Color
    let onClose: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt != nil })
    private var deletedTasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    @State private var index = 0
    @State private var tracker = TutorialTracker(baseline: TutorialSnapshot())
    @State private var isMet = false

    private var step: TutorialStep { steps[min(index, steps.count - 1)] }

    var body: some View {
        let snapshot = currentSnapshot
        NavigationStack {
            // Below the navigation bar, so its buttons stay reachable for the steps that use them.
            TodayView(dayStart: app.dayStart)
                .safeAreaInset(edge: .top, spacing: 0) {
                    TutorialCoach(
                        step: step,
                        index: index,
                        count: steps.count,
                        isMet: isMet,
                        onBack: back,
                        onNext: next,
                        onClose: onClose
                    )
                }
        }
        .modifier(AppChrome(app: app, accent: accent))
        .onAppear {
            app.container.mainContext.undoManager = undoManager
            applyLaunchStep()
            tracker.restart(at: snapshot)
        }
        .onChange(of: snapshot) { _, newValue in
            evaluate(newValue)
        }
    }

    private var currentSnapshot: TutorialSnapshot {
        var snapshot = TutorialSnapshot()
        snapshot.taskCount = tasks.count
        snapshot.doneCount = tasks.filter(\.isDone).count
        snapshot.prioritySum = tasks.reduce(0) { $0 + $1.priorityRaw }
        snapshot.prioritizedCount = tasks.filter { $0.priority != .normal }.count
        snapshot.datedCount = tasks.filter { $0.dueDate != nil }.count
        snapshot.subtaskCount = tasks.filter { $0.indent > 0 }.count
        snapshot.deferredCount = tasks.filter { ($0.plannedDay ?? .distantPast) > app.todayKey }.count
        snapshot.plannedCount = tasks.filter { !$0.isDone && $0.isPlanned(for: app.dayStart) }.count
        snapshot.deletedCount = deletedTasks.count
        snapshot.groupCount = groups.count
        snapshot.collapsedCount = app.collapsedTaskIDs.count
        snapshot.order = tasks.filter { !$0.isDone }.sorted(by: Sections.pageOrder(groups)).map(\.uuid.uuidString)
        snapshot.detailsOpen = app.detailTask != nil
        snapshot.estimateSum = tasks.reduce(0) { $0 + $1.estimate }
        snapshot.matrixSum = tasks.reduce(0) { $0 + $1.urgency + $1.importance }
        snapshot.focusRunning = app.focus != nil
        snapshot.timedCount = tasks.filter { $0.dueHasTime && $0.dueDate != nil }.count
        snapshot.subgroupCount = groups.filter { $0.parentUUID != nil }.count
        return snapshot
    }

    private func evaluate(_ snapshot: TutorialSnapshot) {
        guard !isMet, step.goal != .none, tracker.isMet(step.goal, now: snapshot) else { return }
        withAnimation(.snappy) { isMet = true }
        let current = index
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if index == current, isMet { next() }
        }
    }

    private func next() {
        guard index < steps.count - 1 else {
            onClose()
            return
        }
        withAnimation(.snappy) {
            index += 1
            isMet = false
        }
        tracker.restart(at: currentSnapshot)
    }

    private func back() {
        guard index > 0 else { return }
        withAnimation(.snappy) {
            index -= 1
            isMet = false
        }
        tracker.restart(at: currentSnapshot)
    }

    /// `-TheoTourStep <id>` opens the tour at a given step (screenshots).
    private func applyLaunchStep() {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-TheoTourStep"), flag + 1 < args.count,
              let target = steps.firstIndex(where: { $0.id == args[flag + 1] }) else { return }
        index = target
    }
}

/// The floating card that explains the current step.
struct TutorialCoach: View {
    let step: TutorialStep
    let index: Int
    let count: Int
    let isMet: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void

    @State private var isFolded = false

    private var instructions: String {
        #if os(macOS)
        step.macBody
        #else
        step.body
        #endif
    }

    private var nextTitle: String {
        if index == count - 1 { return "Done" }
        if step.goal == .none { return index == 0 ? "Let's Go" : "Continue" }
        return isMet ? "Next" : "Skip"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: isMet ? "checkmark.circle.fill" : step.symbol)
                    .font(.title2)
                    .foregroundStyle(isMet ? Color.green : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(isMet ? "Nice, that's it!" : step.title)
                        .font(.headline)
                    Text("Step \(index + 1) of \(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    withAnimation(.snappy) { isFolded.toggle() }
                } label: {
                    Image(systemName: isFolded ? "chevron.down" : "chevron.up")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isFolded ? "Show Instructions" : "Hide Instructions")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close Tour")
            }
            if !isFolded {
                Text(instructions)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                HStack(spacing: 12) {
                    ProgressView(value: Double(index + 1), total: Double(count))
                    if index > 0 {
                        Button("Back", action: onBack)
                            .buttonStyle(.borderless)
                    }
                    if step.goal != .none && !isMet {
                        // Skipping is fine, but doing the step is the main path.
                        Button(action: onNext) {
                            Text(nextTitle)
                                .frame(minWidth: 52)
                        }
                        .buttonStyle(.glass)
                    } else {
                        Button(action: onNext) {
                            Text(nextTitle)
                                .frame(minWidth: 64)
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .sensoryFeedback(.success, trigger: isMet) { _, new in new }
        .animation(.snappy, value: index)
    }
}
