import SwiftUI
import SwiftData
import TheoCore
#if os(macOS)
import AppKit
#endif

@main
struct TheoApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(TheoAppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(TheoMacAppDelegate.self) private var macDelegate
    #endif

    @State private var app: AppModel

    init() {
        let container = Persistence.makeContainer()
        let model = AppModel(container: container)
        _app = State(initialValue: model)
        if !Persistence.isDemo {
            TaskStore(context: container.mainContext).purgeExpired()
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(app)
                .modelContainer(app.container)
        }
        .defaultSize(width: 1100, height: 760)
        #if os(macOS)
        // Apps with a menu bar extra otherwise start without their main window.
        .defaultLaunchBehavior(.presented)
        #endif
        .commands {
            TheoCommands(app: app)
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(app)
                .modelContainer(app.container)
                .tint((AccentChoice(rawValue: UserDefaults.standard.string(forKey: Prefs.accent) ?? "") ?? .notes).color)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(app)
                .modelContainer(app.container)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

/// Menu bar and iPad keyboard shortcuts.
struct TheoCommands: Commands {
    let app: AppModel

    /// Task commands act on the tour's practice page while the tour is open.
    private var target: AppModel { app.commandTarget }

    #if os(macOS)
    /// Text is being typed somewhere (the bottom bar, a line, the details, the search field or
    /// the menu bar panel): field editors and multi-line fields are text views.
    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }
    #endif

    /// Runs a Task command on the selected tasks. On the Mac a ⌘ shortcut reaches the menu before
    /// the field being typed in, so while text is edited the commands do nothing: typing never
    /// finishes, moves or changes a task that may not even be in sight.
    private func run(_ action: (AppModel) -> Void) {
        #if os(macOS)
        guard !isEditingText else { return }
        #endif
        action(target)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { app.commandTarget.requestQuickEntry() }
                .keyboardShortcut("n")
            Button("New Group…") { app.commandTarget.groupEditor = .new }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Import from Notes…") { app.showImport = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("Bigger Text") { TextSizeChoice.step(1) }
                .keyboardShortcut("+")
            Button("Smaller Text") { TextSizeChoice.step(-1) }
                .keyboardShortcut("-")
            Button("Standard Text Size") { TextSizeChoice.reset() }
                .keyboardShortcut("0")
            #if os(macOS)
            Button(app.showInspector ? "Hide Details" : "Show Details") { app.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            #endif
            Divider()
        }

        CommandMenu("Go") {
            // Searches every task from any page (the toolbar field on the Mac and iPad, the
            // Search tab on iPhone).
            Button("Find…") { app.wantsSearchFocus = true }
                .keyboardShortcut("f")
            Divider()
            Button("Today") { app.commandTarget.go(.today) }
                .keyboardShortcut("1")
            Button("Plan") { app.commandTarget.go(.plan) }
                .keyboardShortcut("2")
            Button("Upcoming") { app.commandTarget.go(.upcoming) }
                .keyboardShortcut("3")
            Button("Matrix") { app.commandTarget.go(.matrix) }
                .keyboardShortcut("4")
            Button("Quick Entry") { app.commandTarget.go(.quickEntry) }
                .keyboardShortcut("5")
            Button("History") { app.commandTarget.go(.history) }
                .keyboardShortcut("6")
            Button("Recently Deleted") { app.commandTarget.go(.trash) }
                .keyboardShortcut("7")
            Button("Priority") { app.commandTarget.go(.priority) }
                .keyboardShortcut("8")
            Button("Day Review") { app.commandTarget.reviewDay = DayRef(start: app.commandTarget.dayStart) }
                .keyboardShortcut("9")
            Divider()
            Button("Overview") { app.commandTarget.go(.overview) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("All Tasks") { app.commandTarget.go(.allTasks) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Divider()
            Button("Focus Timer") { app.commandTarget.showFocus = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Button("Theo Tour") { app.startTour() }
        }

        CommandMenu("Task") {
            Button("Mark as Done / Not Done") {
                run { target in
                    let tasks = target.selectedTasks
                    if tasks.count == 1 {
                        // The row's checkbox: Undo when it does more than tick the line.
                        target.toggle(tasks[0])
                    } else if !tasks.isEmpty && tasks.allSatisfy(\.isDone) {
                        target.store.setDone(tasks, false)
                    } else {
                        target.complete(tasks)
                    }
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            Button("New Subtask") {
                run { target in
                    if let task = target.selectedTasks.first { target.addSubtask(to: task) }
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Details…") {
                run { target in
                    if let task = target.selectedTasks.first { target.showDetails(task) }
                }
            }
            .keyboardShortcut("i")
            Divider()
            Button("Move Up") {
                run { target in
                    if let task = target.selectedTasks.first { withAnimation(.snappy) { target.store.move(task, .up) } }
                }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Move Down") {
                run { target in
                    if let task = target.selectedTasks.first { withAnimation(.snappy) { target.store.move(task, .down) } }
                }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Make Subtask of Line Above") {
                run { target in
                    if let task = target.selectedTasks.first { target.indentRequest = IndentRequest(taskID: task.uuid, delta: 1) }
                }
            }
            .keyboardShortcut("]")
            Button("Outdent") {
                run { target in
                    if let task = target.selectedTasks.first { target.indentRequest = IndentRequest(taskID: task.uuid, delta: -1) }
                }
            }
            .keyboardShortcut("[")
            Divider()
            Menu("Priority") {
                ForEach(Priority.allCases.reversed()) { priority in
                    Button(priority.title) {
                        run { target in target.store.setPriority(target.selectedTasks, priority) }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(priority.rawValue)")), modifiers: [.command, .option])
                }
            }
            Button("Raise Priority") {
                run { target in
                    for task in target.selectedTasks { target.store.setPriority([task], task.priority.next) }
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Start Focus") {
                run { target in target.startFocus(on: target.selectedTasks.first) }
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Place in Matrix…") {
                run { target in
                    if let task = target.selectedTasks.first { target.matrixTask = task }
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            Menu("Estimate") {
                ForEach(PowerHours.presets, id: \.self) { value in
                    Button(PowerHours.format(value)) {
                        run { target in target.store.setEstimate(target.selectedTasks, value) }
                    }
                }
                Button("None") {
                    run { target in target.store.setEstimate(target.selectedTasks, 0) }
                }
            }
            Button("Fold / Unfold Subtasks") {
                run { target in
                    if let task = target.selectedTasks.first { withAnimation(.snappy) { target.toggleSubtasks(task) } }
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Due Today") {
                run { target in target.store.setDue(target.selectedTasks, QuickDate.today.date(from: target.dayStart)) }
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            Button("Due Tomorrow") {
                run { target in target.store.setDue(target.selectedTasks, QuickDate.tomorrow.date(from: target.dayStart)) }
            }
            .keyboardShortcut("t", modifiers: [.command, .option, .shift])
            Button("Do Today") {
                run { target in target.plan(target.selectedTasks, for: target.dayStart) }
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            Button("Plan for Tomorrow") {
                run { target in target.deferToTomorrow(target.selectedTasks) }
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            Button("Move to…") {
                run { target in
                    let tasks = target.selectedTasks
                    if !tasks.isEmpty { target.moveBatch = TaskBatch(tasks: tasks) }
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Delete") {
                #if os(macOS)
                if isEditingText {
                    // ⌘⌫ while typing deletes back to the start of the line, as everywhere on the Mac.
                    _ = NSApp.sendAction(#selector(NSStandardKeyBindingResponding.deleteToBeginningOfLine(_:)), to: nil, from: nil)
                    return
                }
                #endif
                target.delete(target.selectedTasks)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}
