#if os(macOS)
import SwiftUI
import SwiftData
import AppKit
import Combine
import TheoCore

/// One line in the menu bar list: a task with its depth and the row style Today would use.
private struct MenuBarLine: Identifiable {
    let task: TaskItem
    let depth: Int
    let style: RowStyle

    var id: String { task.rowID }
}

/// A top-level task with the subtasks shown under it.
private struct MenuBarBlock: Identifiable {
    var lines: [MenuBarLine]

    var id: String { lines.first?.id ?? "" }
    var isDone: Bool { lines.first?.task.isDone ?? false }
}

/// Menu bar extra: capture a task from anywhere and tick off today's top items, in the same
/// order as Today.
struct MenuBarView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false }, sort: \TaskItem.sortOrder)
    private var openTasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @State private var text = ""
    @FocusState private var focused: Bool
    /// Ticked off here while the panel is open: they stay, struck through, so a slip can be
    /// taken back with a second click. For an ongoing task it's the logged copy.
    @State private var ticked: [TaskItem] = []
    /// "Added to Work · due Friday", shown under the field for a moment (toasts only appear in
    /// the main window).
    @State private var confirmation: String?
    @State private var confirmationID = UUID()

    /// Top-level tasks listed before "+N more".
    private static let shownBlocks = 10

    var body: some View {
        let today = openTasks.activeOnly(groups).filter { PageBuilder.isOnToday($0, dayStart: app.dayStart) }
        let tickedHere = ticked.filter { $0.deletedAt == nil && $0.isDone }
        let all = blocks(today + tickedHere)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateText.pageTitle(app.dayStart))
                    .font(.headline)
                summary(today)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            field

            if all.isEmpty {
                Text("Nothing open today 🎉")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                list(open: all.filter { !$0.isDone }, done: all.filter(\.isDone))
            }

            Divider()
            HStack {
                Button("Open Theo") {
                    MainWindow.reopen()
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            ticked = []
            confirmation = nil
            focused = true
        }
        .onDisappear {
            // Ticked lines stay struck through only until the panel closes.
            ticked = []
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            // The panel closes when it stops being the key window, and this view may stay alive
            // in between, so this clears them too.
            ticked = []
        }
    }

    /// The capture field, with what the last add did underneath.
    private var field: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if let confirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .transition(.opacity)
            }
        }
    }

    /// The first open blocks, "+N more", then what was ticked off here.
    private func list(open: [MenuBarBlock], done: [MenuBarBlock]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(open.prefix(Self.shownBlocks)) { block in
                    blockView(block)
                }
                if open.count > Self.shownBlocks {
                    Button {
                        MainWindow.reopen()
                        app.go(.today)
                    } label: {
                        Text("+\(open.count - Self.shownBlocks) more · Open Theo")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .padding(.leading, 28)
                    }
                    .buttonStyle(.plain)
                }
                if !done.isEmpty {
                    Divider()
                        .padding(.vertical, 2)
                    ForEach(done) { block in
                        blockView(block)
                    }
                }
            }
        }
        .frame(maxHeight: 360)
    }

    // MARK: - Rows

    /// Today's tasks the way Today ranks them, cut into top-level blocks.
    private func blocks(_ tasks: [TaskItem]) -> [MenuBarBlock] {
        var options = PageBuilder.Options()
        options.rankDay = app.dayStart
        options.collapsedTasks = app.collapsedTaskIDs
        var result: [MenuBarBlock] = []
        for row in PageBuilder.rankedRows(tasks, options: options) {
            guard case .task(let task, let depth, let style) = row else { continue }
            let line = MenuBarLine(task: task, depth: depth, style: style)
            if depth == 0 || result.isEmpty {
                result.append(MenuBarBlock(lines: [line]))
            } else {
                result[result.count - 1].lines.append(line)
            }
        }
        return result
    }

    private func blockView(_ block: MenuBarBlock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(block.lines) { line in
                lineView(line)
            }
        }
    }

    private func lineView(_ line: MenuBarLine) -> some View {
        let task = line.task
        return HStack(alignment: .top, spacing: 8) {
            CheckCircle(done: task.isDone, priority: task.priority, size: line.depth > 0 ? 14 : 16) {
                tick(task)
            }
            VStack(alignment: .leading, spacing: 1) {
                Button {
                    show(task)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if task.priority != .normal {
                            Text(task.priority.marks)
                                .fontWeight(.heavy)
                                .foregroundStyle(task.isDone ? Color.secondary : task.priority.color)
                        }
                        Text(task.trimmedTitle.isEmpty ? "New Task" : task.trimmedTitle)
                            .font(line.depth > 0 ? .callout : .body)
                            .strikethrough(task.isDone, color: .secondary)
                            .foregroundStyle(task.isDone ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show in Theo")
                if let metaLine = meta(line) {
                    metaLine
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
        // Subtasks step in under their parent.
        .padding(.leading, CGFloat(line.depth) * 14)
    }

    /// Deadline (red when overdue, orange today), Power Hours, ∞ and the group, in its colour.
    private func meta(_ line: MenuBarLine) -> Text? {
        let task = line.task
        let today = app.dayStart
        var parts: [Text] = []
        if let due = task.dueDate {
            let delta = DateText.dayDelta(due, today: today)
            let color: Color = task.isDone ? .secondary : (delta < 0 ? .red : (delta == 0 ? .orange : .secondary))
            let label = DateText.due(due, hasTime: task.dueHasTime, today: today)
            parts.append(Text("\(Image(systemName: "calendar")) \(label)").foregroundStyle(color))
        }
        if task.isOngoing && !task.isDone {
            parts.append(Text("\(Image(systemName: "infinity"))").foregroundStyle(Color.teal))
        }
        if !task.isDone {
            let hours = line.style.blockEstimate > 0 ? line.style.blockEstimate : task.estimate
            if hours > 0 {
                // A parent shows the total still open in it, like Today: "Σ 1,5 PH".
                let amount = (line.style.blockEstimate > 0 ? "Σ " : "") + PowerHours.format(hours)
                parts.append(Text("\(Image(systemName: "timer")) \(amount)").foregroundStyle(Color.secondary))
            }
        }
        if line.style.subtasksFolded {
            parts.append(Text("\(Image(systemName: "chevron.right")) \(line.style.subtaskCount) folded").foregroundStyle(Color.secondary))
        }
        if line.depth == 0, let group = task.group, group.deletedAt == nil {
            parts.append(Text(group.displayName).foregroundStyle(group.color.color))
        }
        guard var result = parts.first else { return nil }
        for part in parts.dropFirst() {
            result = Text("\(result)  \(part)")
        }
        return result
    }

    /// "7 open · 3,5 PH left · 1 overdue".
    private func summary(_ today: [TaskItem]) -> Text {
        var line = Text("\(today.count) open")
        let hours = PageBuilder.estimateTotals(today).open
        if hours > 0 {
            line = Text("\(line) · \(PowerHours.number(hours)) PH left")
        }
        let overdue = today.filter { task in
            task.dueDate.map { DateText.dayDelta($0, today: app.dayStart) < 0 } ?? false
        }.count
        if overdue > 0 {
            let late = Text("\(overdue) overdue").foregroundStyle(Color.red)
            line = Text("\(line) · \(late)")
        }
        return line
    }

    // MARK: - Actions

    /// The circle: ticks a task off (it stays here, struck through), or takes a tick back.
    private func tick(_ task: TaskItem) {
        if task.isDone {
            // Reopens it; for an ongoing task's logged copy, the log goes away again.
            withAnimation(.snappy) {
                app.toggle(task)
                ticked.removeAll { $0 === task }
            }
            return
        }
        withAnimation(.snappy) { app.toggle(task) }
        if task.isDone {
            ticked.append(task)
        } else if task.isOngoing, let log = latestLog(of: task) {
            // Ongoing tasks stay open; what got ticked is the copy logged for today.
            ticked.append(log)
        }
    }

    private func latestLog(of task: TaskItem) -> TaskItem? {
        let id = task.uuid
        return app.store.liveTasks()
            .filter { $0.isDone && $0.loggedFor == id }
            .max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    /// A click on a title: Theo comes forward with the task selected and its details open.
    private func show(_ task: TaskItem) {
        let wasVisible = MainWindow.isVisible
        MainWindow.reopen()
        if wasVisible {
            app.reveal(task)
        } else {
            let model = app
            Task { @MainActor in
                // A window that had to open needs a moment before its page can take the selection.
                try? await Task.sleep(for: .milliseconds(500))
                model.reveal(task)
            }
        }
    }

    private func add() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let refs = groups.map { QuickParser.GroupRef(id: $0.uuid, name: $0.displayName) }
        let entry = QuickParser.parse(raw, groups: refs, now: app.dayStart)
        guard !entry.title.isEmpty else { return }
        let placement = NewTaskPlacement(rawValue: UserDefaults.standard.string(forKey: Prefs.newTaskPlacement) ?? "") ?? .bottom
        let task = withAnimation(.snappy) { app.store.addTask(entry, defaultGroupID: nil, placement: placement) }
        // A global capture field: on today's plan unless the typed deadline is on a later day.
        let planned = entry.due.map { DateText.dayDelta($0, today: app.dayStart) <= 0 } ?? true
        if planned { app.store.plan([task], for: app.dayStart) }
        text = ""
        confirm(task, planned: planned)
    }

    /// "Added to Work · due Friday" or "Added to Quick Entry · on today", for three seconds.
    private func confirm(_ task: TaskItem, planned: Bool) {
        var parts = ["Added to " + (task.group.flatMap { $0.deletedAt == nil ? $0.displayName : nil } ?? "Quick Entry")]
        if let due = task.dueDate {
            parts.append("due " + DateText.due(due, hasTime: task.dueHasTime, today: app.dayStart))
        }
        if planned { parts.append("on today") }
        let id = UUID()
        confirmationID = id
        withAnimation(.snappy) { confirmation = parts.joined(separator: " · ") }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard confirmationID == id else { return }
            withAnimation(.snappy) { confirmation = nil }
        }
    }
}
#endif
