import SwiftUI

/// Context-menu content for one or more tasks (long press on iOS, right click on macOS).
struct TaskMenuItems: View {
    let tasks: [TaskItem]
    var onEdit: (() -> Void)?

    @Environment(AppModel.self) private var app

    private var single: TaskItem? { tasks.count == 1 ? tasks.first : nil }
    private var allDone: Bool { tasks.allSatisfy(\.isDone) }

    var body: some View {
        Button {
            withAnimation(.snappy) { app.store.setDone(tasks, !allDone) }
        } label: {
            Label(allDone ? "Mark as Not Done" : "Mark as Done", systemImage: allDone ? "circle" : "checkmark.circle")
        }

        if let single, let onEdit {
            Button(action: onEdit) {
                Label("Edit Title", systemImage: "pencil")
            }
            Button {
                app.detailTask = single
            } label: {
                Label("Details…", systemImage: "info.circle")
            }
        }

        Menu {
            ForEach(Priority.allCases.reversed()) { priority in
                Button {
                    app.store.setPriority(tasks, priority)
                } label: {
                    if single?.priority == priority {
                        Label(priority.title, systemImage: "checkmark")
                    } else {
                        Text(priority.title)
                    }
                }
            }
        } label: {
            Label("Priority", systemImage: "exclamationmark.circle")
        }

        Menu {
            ForEach(QuickDate.allCases) { quick in
                Button {
                    app.store.setDue(tasks, quick.date(from: app.dayStart))
                } label: {
                    Label(quick.title, systemImage: quick.symbol)
                }
            }
            Button {
                app.dateBatch = TaskBatch(tasks: tasks)
            } label: {
                Label("Choose Date…", systemImage: "calendar")
            }
            if tasks.contains(where: { $0.dueDate != nil }) {
                Divider()
                Button(role: .destructive) {
                    app.store.setDue(tasks, nil)
                } label: {
                    Label("Remove Deadline", systemImage: "calendar.badge.minus")
                }
            }
        } label: {
            Label("Deadline", systemImage: "calendar")
        }

        Menu {
            Button {
                app.store.move(tasks, toGroup: nil)
            } label: {
                Label("Quick Entry", systemImage: "tray.and.arrow.down")
            }
            ForEach(app.store.liveGroups()) { group in
                Button {
                    app.store.move(tasks, toGroup: group.uuid)
                } label: {
                    Label(group.displayName, systemImage: group.symbol)
                }
            }
            Divider()
            Button {
                app.moveBatch = TaskBatch(tasks: tasks)
            } label: {
                Label("New Group…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("Move to", systemImage: "folder")
        }

        Button {
            app.tagBatch = TaskBatch(tasks: tasks)
        } label: {
            Label("Tags…", systemImage: "number")
        }

        if !allDone {
            if tasks.contains(where: { $0.deferredUntil != nil && ($0.deferredUntil ?? .distantPast) > app.dayStart }) {
                Button {
                    app.store.deferTasks(tasks, until: nil)
                } label: {
                    Label("Show Today", systemImage: "sun.max")
                }
            } else {
                Button {
                    app.deferToTomorrow(tasks)
                } label: {
                    Label("Not Today", systemImage: "moon.zzz")
                }
            }
        }

        if let single {
            Divider()
            Menu {
                Button {
                    withAnimation(.snappy) { app.store.moveToEdge(single, top: true) }
                } label: {
                    Label("Move to Top", systemImage: "arrow.up.to.line")
                }
                Button {
                    withAnimation(.snappy) { app.store.move(single, .up) }
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
                Button {
                    withAnimation(.snappy) { app.store.move(single, .down) }
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
                Button {
                    withAnimation(.snappy) { app.store.moveToEdge(single, top: false) }
                } label: {
                    Label("Move to Bottom", systemImage: "arrow.down.to.line")
                }
                Divider()
                Button {
                    withAnimation(.snappy) { app.store.indent(single, by: 1) }
                } label: {
                    Label("Indent", systemImage: "increase.indent")
                }
                Button {
                    withAnimation(.snappy) { app.store.indent(single, by: -1) }
                } label: {
                    Label("Outdent", systemImage: "decrease.indent")
                }
            } label: {
                Label("Arrange", systemImage: "arrow.up.arrow.down")
            }
            Button {
                app.store.duplicate(single)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }

        Divider()
        Button(role: .destructive) {
            app.delete(tasks)
        } label: {
            Label(tasks.count > 1 ? "Delete \(tasks.count) Tasks" : "Delete", systemImage: "trash")
        }
    }
}
