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
        // `!isDone` too: the query can lag a moment behind a tick, and a line must not show twice.
        let today = openTasks.activeOnly(groups).filter { !$0.isDone && PageBuilder.isOnToday($0, dayStart: app.dayStart) }
        let tickedHere = ticked.filter { $0.modelContext != nil && !$0.isDeleted && $0.deletedAt == nil && $0.isDone }
        let all = blocks(today + tickedHere)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateText.pageTitle(app.dayStart))
                    .theoFont(.headline)
                // The numbers roll as tasks are ticked off here.
                summary(today)
                    .theoFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .rollingNumber(today.count)
            }

            field

            if all.isEmpty {
                emptyToday
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
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .theoFont(.subheadline)
        }
        // The field and the lines without a font of their own follow Theo's text size too.
        .theoFont(.body)
        .padding(16)
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
                    // Each task added gets a small bounce, like the bar at the bottom of the window.
                    .symbolEffect(.bounce, value: confirmationID)
                TextField("Quick entry — e.g. “Call Ana tomorrow 5pm !!”", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(add)
            }
            .padding(12)
            .glassEffect(.regular, in: .capsule)
            if let confirmation {
                // What was understood slides out from under the field.
                Label {
                    Text(confirmation)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Tint.done)
                }
                .theoFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
            }
        }
    }

    /// The first open blocks, "+N more", then what was ticked off here.
    private func list(open: [MenuBarBlock], done: [MenuBarBlock]) -> some View {
        ScrollView {
            // A task and its subtasks sit closer together than one task to the next.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(open.prefix(Self.shownBlocks)) { block in
                    blockView(block)
                }
                if open.count > Self.shownBlocks {
                    Button {
                        MainWindow.reopen()
                        app.go(.today)
                    } label: {
                        // Lined up with the titles (the lines' hover inset, the circle, the gap).
                        Text("+\(open.count - Self.shownBlocks) more · Open Theo")
                            .theoFont(.caption, weight: .medium)
                            .foregroundStyle(.tint)
                            .padding(.leading, 38)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                if !done.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                    ForEach(done) { block in
                        blockView(block)
                    }
                }
            }
        }
        // The lines' hover fill reaches a little past the column the header and field stand in.
        .padding(.horizontal, -6)
        .frame(maxHeight: 360)
    }

    /// Nothing left on today's page: Today's sun and a quiet line.
    private var emptyToday: some View {
        VStack(spacing: 6) {
            Image(systemName: "sun.max.fill")
                .theoFont(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Tint.today)
            Text("Nothing open today")
                .theoFont(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Rows

    /// Today's tasks the way Today ranks them, cut into top-level blocks.
    private func blocks(_ tasks: [TaskItem]) -> [MenuBarBlock] {
        var options = PageBuilder.Options()
        options.rankDay = app.dayStart
        options.collapsedTasks = app.collapsedTaskIDs
        // Nest by the real parents, so a subtask planned without its parent stands on its own.
        options.fullSections = Dictionary(grouping: app.store.liveTasks(), by: \.groupID)
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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(block.lines) { line in
                lineView(line)
                    .modifier(MenuLineHover())
            }
        }
    }

    private func lineView(_ line: MenuBarLine) -> some View {
        let task = line.task
        return HStack(alignment: .top, spacing: 8) {
            CheckCircle(done: task.isDone, priority: task.priority, size: line.depth > 0 ? 14 : 16) {
                tick(task)
            }
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    show(task)
                } label: {
                    // The marks and the title in one font, so a subtask's marks are its size.
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if task.priority != .normal {
                            Text(task.priority.marks)
                                .fontWeight(.heavy)
                                .foregroundStyle(task.isDone ? Color.secondary : task.priority.color)
                        }
                        Text(task.trimmedTitle.isEmpty ? "New Task" : task.trimmedTitle)
                            .strikethrough(task.isDone, color: .secondary)
                            .foregroundStyle(task.isDone ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                            .lineLimit(2)
                    }
                    .theoFont(line.depth > 0 ? .callout : .body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show in Theo")
                if let metaLine = meta(line) {
                    metaLine
                        .theoFont(.caption)
                        .lineLimit(1)
                }
            }
        }
        // Subtasks step in under their parent.
        .padding(.leading, CGFloat(line.depth) * 14)
    }

    /// Deadline (orange when it's today or has passed: calm, it's at the top anyway), Power
    /// Hours, ∞ and the group with its icon in the group's colour.
    private func meta(_ line: MenuBarLine) -> Text? {
        let task = line.task
        let today = app.dayStart
        var parts: [Text] = []
        if let due = task.dueDate {
            let delta = DateText.dayDelta(due, today: today)
            let color: Color = task.isDone ? .secondary : (delta < 0 ? Tint.overdue : (delta == 0 ? Tint.today : .secondary))
            let label = DateText.due(due, hasTime: task.dueHasTime, today: today)
            parts.append(Text("\(Image(systemName: "calendar")) \(label)").foregroundStyle(color))
        }
        if task.isOngoing && !task.isDone {
            parts.append(Text("\(Image(systemName: "infinity"))").foregroundStyle(Tint.ongoing))
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
            let icon = Text(Image(systemName: group.symbol)).foregroundStyle(group.color.color)
            parts.append(Text("\(icon) \(group.displayName)").foregroundStyle(Color.secondary))
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
            let late = Text("\(overdue) overdue").foregroundStyle(Tint.overdue)
            line = Text("\(line) · \(late)")
        }
        return line
    }

    // MARK: - Actions

    /// The circle: ticks a task off (it stays here, struck through), or takes a tick back.
    private func tick(_ task: TaskItem) {
        if task.isDone {
            // Reopens it; for an ongoing task's logged copy, the log goes away again.
            Motion.animate(Motion.list) {
                app.toggle(task)
                ticked.removeAll { $0 === task }
            }
            return
        }
        Motion.animate(Motion.list) { app.toggle(task) }
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
        // Theo may have slept overnight: reveal picks Today or the group page by the current day.
        app.refreshDay()
        let wasVisible = MainWindow.isVisible
        MainWindow.reopen()
        if wasVisible {
            app.reveal(task)
        } else {
            let model = app
            Task { @MainActor in
                // A reopened window builds its pages first; the page change must reach them.
                var waited = 0
                while !MainWindow.isVisible && waited < 30 {
                    try? await Task.sleep(for: .milliseconds(100))
                    waited += 1
                }
                try? await Task.sleep(for: .milliseconds(150))
                model.reveal(task)
            }
        }
    }

    private func add() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let refs = groups.map { QuickParser.GroupRef(id: $0.uuid, name: $0.displayName, parentID: $0.parentUUID) }
        let entry = QuickParser.parse(raw, groups: refs, now: app.dayStart)
        guard !entry.title.isEmpty else { return }
        let placement = NewTaskPlacement(rawValue: UserDefaults.standard.string(forKey: Prefs.newTaskPlacement) ?? "") ?? .bottom
        let task = Motion.animate(Motion.list) { app.store.addTask(entry, defaultGroupID: nil, placement: placement) }
        // A global capture field: on today's plan unless the deadline is on a later day (read
        // from the task, so a repeat's first date counts).
        let planned = task.dueDate.map { DateText.dayDelta($0, today: app.dayStart) <= 0 } ?? true
        if planned { app.store.plan([task], for: app.dayStart) }
        text = ""
        confirm(task, planned: planned)
    }

    /// "Added to Work · due Friday · !!" (what was understood, read back from the task, as the
    /// composer says it) plus "· on today" when it went on today's plan, for three seconds.
    private func confirm(_ task: TaskItem, planned: Bool) {
        let group = task.group.flatMap { $0.deletedAt == nil ? $0 : nil }
        let understood = CaptureSummary.describe(
            groupName: group?.displayName ?? "Quick Entry",
            due: task.dueDate,
            dueHasTime: task.dueHasTime,
            today: app.dayStart,
            priority: task.priority,
            estimate: task.estimate,
            defaultEstimate: app.store.traits(of: group).estimate ?? PowerHours.defaultForNewTasks,
            recurrence: task.recurrence,
            ongoing: task.isOngoing
        )
        let message = "Added to " + understood + (planned ? " · on today" : "")
        let id = UUID()
        confirmationID = id
        Motion.animate(Motion.layout) { confirmation = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard confirmationID == id else { return }
            Motion.animate(Motion.layout) { confirmation = nil }
        }
    }
}

/// A soft fill under a line while the pointer is over it, the way a menu marks the item it's
/// on, so the line reads as something to click.
private struct MenuLineHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(isHovered ? 0.12 : 0))
            }
            .onHover { inside in
                Motion.animate(Motion.hover) { isHovered = inside }
            }
    }
}
#endif
