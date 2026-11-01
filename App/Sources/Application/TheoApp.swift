import SwiftUI
import SwiftData
import TheoCore

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

        CommandMenu("Go") {
            Button("Today") { app.go(.today) }
                .keyboardShortcut("1")
            Button("Upcoming") { app.go(.upcoming) }
                .keyboardShortcut("2")
            Button("Priority") { app.go(.priority) }
                .keyboardShortcut("3")
            Button("Quick Entry") { app.go(.quickEntry) }
                .keyboardShortcut("4")
            Button("History") { app.go(.history) }
                .keyboardShortcut("5")
            Button("Recently Deleted") { app.go(.trash) }
                .keyboardShortcut("6")
            Button("Matrix") { app.go(.matrix) }
                .keyboardShortcut("7")
            Divider()
            Button("Focus Timer") { app.commandTarget.showFocus = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Button("Theo Tour") { app.startTour() }
        }

        CommandMenu("Task") {
            Button("Mark as Done / Not Done") {
                let tasks = target.selectedTasks
                target.store.setDone(tasks, !tasks.allSatisfy(\.isDone))
            }
            .keyboardShortcut(.return, modifiers: .command)
            Button("New Subtask") {
                if let task = target.selectedTasks.first { target.addSubtask(to: task) }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Details…") {
                if let task = target.selectedTasks.first { target.detailTask = task }
            }
            .keyboardShortcut("i")
            Divider()
            Button("Move Up") {
                if let task = target.selectedTasks.first { withAnimation(.snappy) { target.store.move(task, .up) } }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Move Down") {
                if let task = target.selectedTasks.first { withAnimation(.snappy) { target.store.move(task, .down) } }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Indent") {
                if let task = target.selectedTasks.first { withAnimation(.snappy) { target.store.indent(task, by: 1) } }
            }
            .keyboardShortcut("]")
            Button("Outdent") {
                if let task = target.selectedTasks.first { withAnimation(.snappy) { target.store.indent(task, by: -1) } }
            }
            .keyboardShortcut("[")
            Divider()
            Menu("Priority") {
                ForEach(Priority.allCases.reversed()) { priority in
                    Button(priority.title) { target.store.setPriority(target.selectedTasks, priority) }
                        .keyboardShortcut(KeyEquivalent(Character("\(priority.rawValue)")), modifiers: [.command, .option])
                }
            }
            Button("Raise Priority") {
                for task in target.selectedTasks { target.store.setPriority([task], task.priority.next) }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Start Focus") {
                target.startFocus(on: target.selectedTasks.first)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Place in Matrix…") {
                if let task = target.selectedTasks.first { target.matrixTask = task }
            }
            .keyboardShortcut("m", modifiers: [.command, .option])
            Menu("Estimate") {
                ForEach(PowerHours.presets, id: \.self) { value in
                    Button(PowerHours.format(value)) { target.store.setEstimate(target.selectedTasks, value) }
                }
                Button("None") { target.store.setEstimate(target.selectedTasks, 0) }
            }
            Button("Fold / Unfold Subtasks") {
                if let task = target.selectedTasks.first { withAnimation(.snappy) { target.toggleSubtasks(task) } }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Due Today") { target.store.setDue(target.selectedTasks, QuickDate.today.date(from: target.dayStart)) }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button("Due Tomorrow") { target.store.setDue(target.selectedTasks, QuickDate.tomorrow.date(from: target.dayStart)) }
                .keyboardShortcut("t", modifiers: [.command, .option, .shift])
            Button("Not Today") { target.deferToTomorrow(target.selectedTasks) }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button("Move to…") {
                let tasks = target.selectedTasks
                if !tasks.isEmpty { target.moveBatch = TaskBatch(tasks: tasks) }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Delete") { target.delete(target.selectedTasks) }
                .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}
