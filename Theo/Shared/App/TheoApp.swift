import SwiftUI
import SwiftData

@main
struct TheoApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(TheoAppDelegate.self) private var appDelegate
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
            Image(systemName: "checkmark.circle")
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

/// Menu bar and iPad keyboard shortcuts.
struct TheoCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { app.requestQuickEntry() }
                .keyboardShortcut("n")
            Button("New Group…") { app.groupEditor = .new }
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
        }

        CommandMenu("Task") {
            Button("Mark as Done / Not Done") {
                let tasks = app.selectedTasks
                app.store.setDone(tasks, !tasks.allSatisfy(\.isDone))
            }
            .keyboardShortcut(.return, modifiers: .command)
            Button("Details…") {
                if let task = app.selectedTasks.first { app.detailTask = task }
            }
            .keyboardShortcut("i")
            Divider()
            Button("Move Up") {
                if let task = app.selectedTasks.first { withAnimation(.snappy) { app.store.move(task, .up) } }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Move Down") {
                if let task = app.selectedTasks.first { withAnimation(.snappy) { app.store.move(task, .down) } }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Indent") {
                if let task = app.selectedTasks.first { withAnimation(.snappy) { app.store.indent(task, by: 1) } }
            }
            .keyboardShortcut("]")
            Button("Outdent") {
                if let task = app.selectedTasks.first { withAnimation(.snappy) { app.store.indent(task, by: -1) } }
            }
            .keyboardShortcut("[")
            Divider()
            Menu("Priority") {
                ForEach(Priority.allCases.reversed()) { priority in
                    Button(priority.title) { app.store.setPriority(app.selectedTasks, priority) }
                        .keyboardShortcut(KeyEquivalent(Character("\(priority.rawValue)")), modifiers: [.command, .option])
                }
            }
            Button("Due Today") { app.store.setDue(app.selectedTasks, QuickDate.today.date(from: app.dayStart)) }
                .keyboardShortcut("t", modifiers: [.command, .option])
            Button("Due Tomorrow") { app.store.setDue(app.selectedTasks, QuickDate.tomorrow.date(from: app.dayStart)) }
                .keyboardShortcut("t", modifiers: [.command, .option, .shift])
            Button("Not Today") { app.deferToTomorrow(app.selectedTasks) }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button("Move to…") {
                let tasks = app.selectedTasks
                if !tasks.isEmpty { app.moveBatch = TaskBatch(tasks: tasks) }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Delete") { app.delete(app.selectedTasks) }
                .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}
