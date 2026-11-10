#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import TheoCore

/// Menu bar extra: capture a task from anywhere and tick off today's top items.
struct MenuBarView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false }, sort: \TaskItem.sortOrder)
    private var openTasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let today = openTasks.activeOnly(groups).filter { PageBuilder.isOnToday($0, dayStart: app.dayStart) }
            .sorted(by: Sections.pageOrder(groups))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(DateText.pageTitle(app.dayStart))
                    .font(.headline)
                Spacer()
                Text("\(today.count) open")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.tint)
                TextField("Quick entry — e.g. “Call Ana tomorrow 5pm !!”", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
            }
            .padding(10)
            .glassEffect(.regular, in: .capsule)

            if today.isEmpty {
                Text("Nothing open today 🎉")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(today.prefix(12)) { task in
                            HStack(alignment: .top, spacing: 8) {
                                CheckCircle(done: task.isDone, priority: task.priority, size: 16) {
                                    withAnimation(.snappy) { app.store.toggle(task) }
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(task.trimmedTitle.isEmpty ? "New Task" : task.trimmedTitle)
                                        .lineLimit(2)
                                    if let group = task.group, group.deletedAt == nil {
                                        Text(group.displayName)
                                            .font(.caption)
                                            .foregroundStyle(group.color.color)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()
            HStack {
                Button("Open Theo") {
                    NSApplication.shared.activate()
                    if NSApplication.shared.windows.filter({ $0.canBecomeMain }).isEmpty {
                        openWindow(id: "main")
                    }
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private func add() {
        let raw = text.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let entry = QuickParser.parse(raw, groups: groups.map { QuickParser.GroupRef(id: $0.uuid, name: $0.displayName) })
        let task = app.store.addTask(entry, defaultGroupID: nil, placement: NewTaskPlacement(rawValue: UserDefaults.standard.string(forKey: Prefs.newTaskPlacement) ?? "") ?? .bottom)
        // The menu bar shows today, so what's added there is planned for today.
        app.store.plan([task], for: app.dayStart)
        text = ""
    }
}
#endif
