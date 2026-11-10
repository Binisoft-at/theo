import SwiftUI
import SwiftData
import TheoCore

/// The core list used by every page. It renders the flat row model (headings + tasks),
/// handles inline editing, drag-to-reorder across groups, swipes, context menus and
/// keyboard shortcuts.
struct TaskListView<Header: View>: View {
    let rows: [ListRow]
    var allowsReorder = true
    /// Group that receives drops when the page has no headings (single group pages).
    var defaultGroupID: UUID?
    /// New lines made here are planned for this day (Today).
    var plansFor: Date?
    @ViewBuilder var header: () -> Header

    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.newTaskPlacement) private var placementRaw = NewTaskPlacement.bottom.rawValue
    @AppStorage(Prefs.quickEntryCollapsed) private var quickCollapsed = false
    @FocusState private var focusedID: String?
    @State private var pendingEditID: String?
    @State private var groupPendingDelete: TaskGroup?
    @State private var lastSplit: (id: String, time: Date)?
    /// Row frames in global coordinates, for dropping the composer's + between rows.
    @State private var frames = RowFrames()
    @State private var insertAfterID: String?
    @State private var insertBeforeFirst = false
    @State private var isVisible = false
    @State private var token = UUID()

    private var placement: NewTaskPlacement { NewTaskPlacement(rawValue: placementRaw) ?? .bottom }

    var body: some View {
        @Bindable var app = app
        List(selection: $app.selectedRowIDs) {
            header()
                .listRowSeparator(.hidden)
                .selectionDisabled()
            ForEach(rows) { row in
                rowView(row)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        frames.byID[row.id] = frame
                    }
                    // A row scrolled out of view keeps no stale position for drops.
                    .onDisappear { frames.byID[row.id] = nil }
                    .overlay(alignment: .bottom) {
                        if insertAfterID == row.id { InsertionLine() }
                    }
                    .overlay(alignment: .top) {
                        if insertBeforeFirst && rows.first?.id == row.id { InsertionLine() }
                    }
            }
            .onMove(perform: allowsReorder ? move : nil)
        }
        #if os(iOS)
        .listStyle(.plain)
        .environment(\.editMode, .constant(app.isSelecting ? .active : .inactive))
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let task = focusedTask {
                    keyboardTools(task)
                }
            }
            if app.isSelecting {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { app.endSelection() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if app.isSelecting {
                SelectionBar()
            }
        }
        #else
        .listStyle(.inset)
        .contextMenu(forSelectionType: String.self) { ids in
            selectionMenu(ids)
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first, let task = lookupTask(id) {
                beginEdit(task)
            }
        }
        .onDeleteCommand {
            app.delete(app.selectedTasks)
        }
        .onKeyPress(.space) {
            guard focusedID == nil else { return .ignored }
            let tasks = app.selectedTasks
            guard !tasks.isEmpty else { return .ignored }
            withAnimation(.snappy) { app.store.setDone(tasks, !tasks.allSatisfy(\.isDone)) }
            return .handled
        }
        .onKeyPress(.return) {
            guard focusedID == nil, app.selectedTasks.count == 1, let task = app.selectedTasks.first else { return .ignored }
            beginEdit(task)
            return .handled
        }
        #endif
        .onChange(of: focusedID) { oldValue, newValue in
            if let newValue, newValue == pendingEditID { pendingEditID = nil }
            if let oldValue, oldValue != newValue, let task = lookupTask(oldValue) {
                app.store.applyInlineShortcuts(task)
                app.store.discardIfEmpty(task)
            }
        }
        .onChange(of: app.pendingEditTaskID) { _, id in
            guard let id, let task = app.store.task(id: id) else { return }
            app.pendingEditTaskID = nil
            beginEdit(task)
        }
        .onChange(of: app.isSelecting) { _, selecting in
            if selecting { focusedID = nil }
        }
        .onAppear {
            isVisible = true
            registerInsertHandler()
        }
        .onDisappear {
            isVisible = false
            if app.insertHandlerOwner == token {
                app.insertHandler = nil
                app.insertHandlerOwner = nil
            }
        }
        .onChange(of: app.insertDragLocation) { _, location in
            guard isVisible, let location, let point = insertionPoint(at: location) else {
                insertAfterID = nil
                insertBeforeFirst = false
                return
            }
            insertAfterID = point.above?.id
            insertBeforeFirst = point.above == nil
        }
        .onChange(of: app.indentRequest) { _, request in
            guard isVisible, let request, let task = lookupTask("t-" + request.taskID.uuidString) else { return }
            app.indentRequest = nil
            if request.delta > 0 {
                makeSubtaskOfLineAbove(task)
            } else {
                withAnimation(.snappy) { app.store.indent(task, by: -1) }
            }
        }
        .confirmationDialog(
            "Delete Group",
            isPresented: Binding(get: { groupPendingDelete != nil }, set: { if !$0 { groupPendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: groupPendingDelete
        ) { group in
            Button("Delete Group and Its Tasks", role: .destructive) {
                app.store.deleteGroup(group, keepTasks: false)
                let model = self.app
                model.show("Deleted “\(group.displayName)”", symbol: "trash.fill") {
                    model.store.restoreGroup(group)
                }
            }
            Button("Delete Group, Keep Tasks") {
                app.store.deleteGroup(group, keepTasks: true)
                app.show("Tasks moved to Quick Entry", symbol: "tray.and.arrow.down.fill")
            }
            Button("Cancel", role: .cancel) {}
        } message: { group in
            Text("“\(group.displayName)” contains \(group.liveTasks.count) task\(group.liveTasks.count == 1 ? "" : "s").")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(_ row: ListRow) -> some View {
        switch row {
        case .header(let info):
            SectionHeaderRow(
                info: info,
                today: app.dayStart,
                onToggleCollapse: { toggleCollapse(info) },
                onAdd: addAction(for: info)
            )
            .listRowSeparator(.hidden)
            .selectionDisabled()
            .moveDisabled(!(allowsReorder && isGroup(info)))
            .contextMenu { headerMenu(info) }

        case .task(let task, let depth, let style):
            TaskRowView(
                task: task,
                depth: depth,
                style: style,
                today: app.dayStart,
                isEditing: isEditing(task),
                focus: $focusedID,
                onToggle: { app.toggle(task) },
                onBeginEdit: { beginEdit(task) },
                onSplit: { split(task, $0) },
                onInfo: {
                    focusedID = nil
                    app.detailTask = task
                },
                onIndent: { delta in
                    if delta > 0 {
                        makeSubtaskOfLineAbove(task)
                    } else {
                        withAnimation(.snappy) { app.store.indent(task, by: -1) }
                    }
                },
                onToggleSubtasks: {
                    withAnimation(.snappy) { app.toggleSubtasks(task) }
                }
            )
            .moveDisabled(!allowsReorder || task.isDone || isEditing(task))
            // Swipe right: tuck under the line above (or take a subtask back out).
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let parent = lineAbove(task) {
                    Button {
                        withAnimation(.snappy) { app.store.makeSubtask(task, of: parent) }
                    } label: {
                        Label("Subtask", systemImage: "arrow.turn.down.right")
                    }
                    .tint(.indigo)
                }
                if depth > 0 {
                    Button {
                        withAnimation(.snappy) { app.store.indent(task, by: -1) }
                    } label: {
                        Label("Outdent", systemImage: "arrow.turn.up.left")
                    }
                    .tint(.gray)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    app.delete([task])
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                if !task.isDone {
                    Button {
                        app.deferToTomorrow([task])
                    } label: {
                        Label("Tomorrow", systemImage: "moon.zzz")
                    }
                    .tint(.indigo)
                    if let due = task.dueDate, DateText.dayDelta(due, today: app.dayStart) < 0 {
                        Button {
                            withAnimation(.snappy) { app.store.postpone([task], days: 1, today: app.dayStart) }
                        } label: {
                            Label("+1 Day", systemImage: "calendar.badge.plus")
                        }
                        .tint(.orange)
                    } else {
                        Button {
                            app.dateBatch = TaskBatch(tasks: [task])
                        } label: {
                            Label("Deadline", systemImage: "calendar")
                        }
                        .tint(.orange)
                    }
                }
            }
            #if os(iOS)
            .contextMenu {
                TaskMenuItems(tasks: [task], onEdit: { beginEdit(task) })
            }
            #endif

        case .placeholder(_, let text):
            Text(text)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.leading, 30)
                .listRowSeparator(.hidden)
                .selectionDisabled()
                .moveDisabled(true)
        }
    }

    private func isGroup(_ info: SectionHeaderInfo) -> Bool {
        if case .group = info.kind { return true }
        return false
    }

    private func addAction(for info: SectionHeaderInfo) -> (() -> Void)? {
        guard info.kind.acceptsTasks else { return nil }
        let groupID = info.kind.groupID
        return { addBlank(groupID: groupID) }
    }

    @ViewBuilder
    private func headerMenu(_ info: SectionHeaderInfo) -> some View {
        switch info.kind {
        case .group(let group):
            Button {
                addBlank(groupID: group.uuid)
            } label: {
                Label("Add Task", systemImage: "plus")
            }
            Button {
                app.groupEditor = .edit(group)
            } label: {
                Label("Edit Group…", systemImage: "pencil")
            }
            Button {
                app.groupEditor = .subgroup(group)
            } label: {
                Label("New Subproject…", systemImage: "folder.badge.plus")
            }
            Button {
                app.go(.group(group.uuid))
            } label: {
                Label("Open as Page", systemImage: "arrow.up.forward.square")
            }
            Button {
                withAnimation(.snappy) { app.store.completeAll(in: group.uuid) }
            } label: {
                Label("Complete All", systemImage: "checkmark.circle")
            }
            Divider()
            Button(role: .destructive) {
                groupPendingDelete = group
            } label: {
                Label("Delete Group…", systemImage: "trash")
            }
        case .quickEntry:
            Button {
                addBlank(groupID: nil)
            } label: {
                Label("Add Task", systemImage: "plus")
            }
            Button {
                withAnimation(.snappy) { app.store.completeAll(in: nil) }
            } label: {
                Label("Complete All", systemImage: "checkmark.circle")
            }
        case .label:
            EmptyView()
        }
    }

    @ViewBuilder
    private func selectionMenu(_ ids: Set<String>) -> some View {
        let tasks = ids.compactMap { lookupTask($0) }
        if !tasks.isEmpty {
            TaskMenuItems(tasks: tasks, onEdit: tasks.count == 1 ? { beginEdit(tasks[0]) } : nil)
        } else if let id = ids.first, let info = headerInfo(forRowID: id) {
            headerMenu(info)
        }
    }

    #if os(iOS)
    /// The bar above the keyboard while a line is being edited.
    @ViewBuilder
    private func keyboardTools(_ task: TaskItem) -> some View {
        Button {
            withAnimation(.snappy) { app.store.indent(task, by: -1) }
        } label: {
            Image(systemName: "decrease.indent")
        }
        .accessibilityLabel("Outdent")
        Button {
            makeSubtaskOfLineAbove(task)
        } label: {
            Image(systemName: "increase.indent")
        }
        .accessibilityLabel("Make Subtask")
        Button {
            withAnimation(.snappy) { app.addSubtask(to: task) }
        } label: {
            Image(systemName: "arrow.turn.down.right")
        }
        .accessibilityLabel("Add Subtask")
        PriorityButton(priority: task.priority) { level in
            app.store.setPriority([task], level)
        }
        Menu {
            ForEach(PowerHours.presets, id: \.self) { value in
                Button(PowerHours.format(value)) { app.store.setEstimate([task], value) }
            }
            Button {
                focusedID = nil
                app.detailTask = task
            } label: {
                Label("Custom…", systemImage: "slider.horizontal.3")
            }
            if task.estimate > 0 {
                Button(role: .destructive) {
                    app.store.setEstimate([task], 0)
                } label: {
                    Label("No Estimate", systemImage: "xmark.circle")
                }
            }
        } label: {
            if task.estimate > 0 {
                Text(PowerHours.number(task.estimate))
                    .font(.subheadline.weight(.semibold))
            } else {
                Image(systemName: "timer")
            }
        }
        .accessibilityLabel("Estimate")
        Menu {
            ForEach(QuickDate.allCases) { quick in
                Button {
                    app.store.setDue([task], quick.date(from: app.dayStart))
                } label: {
                    Label(quick.title, systemImage: quick.symbol)
                }
            }
            Button {
                focusedID = nil
                app.dateBatch = TaskBatch(tasks: [task])
            } label: {
                Label("Choose Date…", systemImage: "calendar")
            }
            if task.dueDate != nil {
                Button(role: .destructive) {
                    app.store.setDue([task], nil)
                } label: {
                    Label("Remove Deadline", systemImage: "calendar.badge.minus")
                }
            }
        } label: {
            Image(systemName: task.dueDate == nil ? "calendar" : "calendar.badge.checkmark")
        }
        .accessibilityLabel("Deadline")
        Menu {
            Button {
                focusedID = nil
                app.tagBatch = TaskBatch(tasks: [task])
            } label: {
                Label("Tags…", systemImage: "number")
            }
            Button {
                focusedID = nil
                app.moveBatch = TaskBatch(tasks: [task])
            } label: {
                Label("Move to…", systemImage: "folder")
            }
            Button {
                app.deferToTomorrow([task])
            } label: {
                Label("Not Today", systemImage: "moon.zzz")
            }
            Button {
                focusedID = nil
                withAnimation(.snappy) { app.matrixTask = task }
            } label: {
                Label("Place in Matrix…", systemImage: "square.grid.2x2")
            }
            Button {
                focusedID = nil
                app.startFocus(on: task)
            } label: {
                Label("Start Focus", systemImage: "timer")
            }
            Button {
                focusedID = nil
                app.detailTask = task
            } label: {
                Label("Details…", systemImage: "info.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
        Spacer()
        Button {
            focusedID = nil
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
        }
        .accessibilityLabel("Done Editing")
    }
    #endif

    // MARK: - Editing

    private var focusedTask: TaskItem? {
        guard let focusedID else { return nil }
        return lookupTask(focusedID)
    }

    private func isEditing(_ task: TaskItem) -> Bool {
        focusedID == task.rowID || pendingEditID == task.rowID
    }

    private func beginEdit(_ task: TaskItem) {
        guard !app.isSelecting, !task.isDone else { return }
        let id = task.rowID
        pendingEditID = id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            focusedID = id
            try? await Task.sleep(for: .milliseconds(250))
            if pendingEditID == id { focusedID = id }
        }
    }

    /// Return (or a pasted line break) inside a task creates the following line(s).
    private func split(_ task: TaskItem, _ rest: [String]) {
        if let lastSplit, lastSplit.id == task.rowID, Date().timeIntervalSince(lastSplit.time) < 0.3 { return }
        lastSplit = (task.rowID, Date())
        let texts = rest.isEmpty ? [""] : rest
        let restIsEmpty = texts.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        if task.trimmedTitle.isEmpty && restIsEmpty {
            // Return on an empty subtask steps out one level; on an empty top-level line it
            // ends editing. Same as leaving a checklist in Notes.
            if app.store.layout(for: task.groupID).depth(of: task) > 0 {
                withAnimation(.snappy) { app.store.indent(task, by: -1) }
                beginEdit(task)
            } else {
                focusedID = nil
            }
            return
        }
        var anchor = task
        for text in texts {
            anchor = app.store.insertTask(after: anchor, title: text.trimmingCharacters(in: .whitespaces))
        }
        beginEdit(anchor)
    }

    private func addBlank(groupID: UUID?) {
        if groupID == nil {
            quickCollapsed = false
        } else if let group = app.store.group(id: groupID), group.isCollapsed {
            app.store.setCollapsed(group, false)
        }
        let task = app.store.newBlankTask(in: groupID ?? defaultGroupID, placement: placement)
        if let plansFor { app.store.plan([task], for: plansFor) }
        beginEdit(task)
    }

    private func toggleCollapse(_ info: SectionHeaderInfo) {
        withAnimation(.snappy) {
            switch info.kind {
            case .quickEntry: quickCollapsed.toggle()
            case .group(let group): app.store.setCollapsed(group, !group.isCollapsed)
            case .label: break
            }
        }
    }

    // MARK: - Reordering

    private func move(from source: IndexSet, to destination: Int) {
        guard let from = source.first, rows.indices.contains(from) else { return }
        var newRows = rows
        newRows.move(fromOffsets: source, toOffset: destination)
        let moved = rows[from]
        guard let newIndex = newRows.firstIndex(where: { $0.id == moved.id }) else { return }
        withAnimation(.snappy) {
            switch moved {
            case .task(let task, let depth, _):
                app.store.drop(task: task, at: newIndex, in: newRows, defaultGroupID: defaultGroupID)
                // Lists are ranked: the task takes just enough importance to stay where it was put.
                let neighbours = Self.neighbours(of: newIndex, depth: depth, in: newRows)
                app.store.rank(task, between: neighbours.above, and: neighbours.below, today: app.dayStart)
            case .header(let info):
                if case .group(let group) = info.kind {
                    app.store.drop(group: group, at: newIndex, in: newRows)
                }
            case .placeholder:
                break
            }
        }
    }

    /// The nearest task rows at the same depth above and below `index`, within its section.
    private static func neighbours(of index: Int, depth: Int, in rows: [ListRow]) -> (above: TaskItem?, below: TaskItem?) {
        func scan(_ indices: [Int]) -> TaskItem? {
            for i in indices {
                switch rows[i] {
                case .header: return nil
                case .placeholder: continue
                case .task(let task, let d, _):
                    if d < depth { return nil }
                    if d == depth && !task.isDone { return task }
                }
            }
            return nil
        }
        let above = scan(Array((0..<index).reversed()))
        let below = index + 1 < rows.count ? scan(Array((index + 1)..<rows.count)) : nil
        return (above, below)
    }

    /// The line a swipe right tucks this task under: the closest line above at the same level,
    /// in the same group.
    private func lineAbove(_ task: TaskItem) -> TaskItem? {
        guard let index = rows.firstIndex(where: { $0.id == task.rowID }), case .task(_, let depth, _) = rows[index] else { return nil }
        var j = index - 1
        while j >= 0 {
            switch rows[j] {
            case .header:
                return nil
            case .placeholder:
                break
            case .task(let other, let d, _):
                if d < depth { return nil }
                if d == depth { return other.groupID == task.groupID && !other.isDone ? other : nil }
            }
            j -= 1
        }
        return nil
    }

    private func makeSubtaskOfLineAbove(_ task: TaskItem) {
        if let parent = lineAbove(task) {
            withAnimation(.snappy) { app.store.makeSubtask(task, of: parent) }
        } else {
            app.show("Nothing above it to tuck it under", symbol: "arrow.turn.down.right")
        }
    }

    // MARK: - Inserting between rows

    /// Where a drop at `location` (global) lands: between `above` and `below` rows.
    private func insertionPoint(at location: CGPoint) -> (above: ListRow?, below: ListRow?)? {
        let visible = rows.compactMap { row in frames.byID[row.id].map { (row: row, frame: $0) } }
        guard let first = visible.first, let last = visible.last else { return nil }
        let span = first.frame.union(last.frame).insetBy(dx: 0, dy: -30)
        guard location.x >= span.minX, location.x <= span.maxX, location.y >= span.minY, location.y <= span.maxY else { return nil }
        guard let index = visible.firstIndex(where: { location.y < $0.frame.midY }) else {
            return (last.row, nil)
        }
        return (index > 0 ? visible[index - 1].row : nil, visible[index].row)
    }

    private func registerInsertHandler() {
        let owner = token
        app.insertHandlerOwner = owner
        app.insertHandler = { location, entry in
            insertTask(at: location, entry: entry)
        }
    }

    /// Drops a new task between two rows, ranked right between them (see `Matrix.insertion`)
    /// unless what was typed sets its priority or deadline. Dropped right under a task with
    /// subtasks, it becomes that task's first subtask.
    private func insertTask(at location: CGPoint, entry: ParsedEntry?) -> Bool {
        insertAfterID = nil
        insertBeforeFirst = false
        guard isVisible, let point = insertionPoint(at: location) else { return false }
        let aboveTask = point.above?.task
        let belowTask = point.below?.task
        let title = entry?.title ?? ""
        let new: TaskItem
        // Ranked against the lines that end up as its siblings: as a first subtask, just above
        // the old first one; after a line, between it and the next one at the same level.
        var neighbours = (above: rankOf(aboveTask), below: rankOf(belowTask))
        if let aboveTask, let belowTask, belowTask.groupID == aboveTask.groupID, Self.isChild(belowTask, of: aboveTask, in: rows) {
            new = app.store.addSubtask(ParsedEntry(title: title), to: aboveTask, first: true)
            neighbours.above = nil
        } else if let aboveTask {
            new = app.store.insertSibling(after: aboveTask, title: title)
            if Self.depth(of: point.above) != Self.depth(of: point.below) { neighbours.below = nil }
        } else if case .header(let info)? = point.above, info.kind.acceptsTasks {
            new = app.store.addTask(ParsedEntry(title: title), defaultGroupID: info.kind.groupID, placement: .top)
        } else if let belowTask {
            new = app.store.addTask(ParsedEntry(title: title), defaultGroupID: belowTask.groupID, placement: .top)
        } else {
            new = app.store.addTask(ParsedEntry(title: title), defaultGroupID: defaultGroupID, placement: .bottom)
        }
        let typedRank = entry.map { $0.priority != .normal || $0.due != nil } ?? false
        if !typedRank, let rank = Matrix.insertion(above: neighbours.above, below: neighbours.below) {
            if let days = rank.days { app.store.setDueDay(new, days: days, today: app.dayStart) }
            app.store.setImportance([new], rank.importance)
        }
        if let entry {
            if entry.priority != .normal { app.store.setPriority([new], entry.priority) }
            if let due = entry.due { app.store.setDue([new], due, hasTime: entry.dueHasTime) }
            new.tags = entry.tags
            if let estimate = entry.estimate { new.estimate = estimate }
            new.recurrence = entry.recurrence
            if entry.ongoing { new.isOngoing = true }
            app.store.save()
        }
        if let plansFor { app.store.plan([new], for: plansFor) }
        if entry == nil { beginEdit(new) }
        return true
    }

    /// A neighbour's place in the ranking; finished tasks don't count.
    private func rankOf(_ task: TaskItem?) -> Matrix.Rank? {
        guard let task, !task.isDone else { return nil }
        return Matrix.Rank(importance: task.importance, days: Matrix.daysUntil(task.dueDate, today: app.dayStart))
    }

    private static func depth(of row: ListRow?) -> Int? {
        guard case .task(_, let depth, _)? = row else { return nil }
        return depth
    }

    private static func isChild(_ task: TaskItem, of parent: TaskItem, in rows: [ListRow]) -> Bool {
        guard let parentIndex = rows.firstIndex(where: { $0.id == parent.rowID }),
              case .task(_, let parentDepth, _) = rows[parentIndex],
              parentIndex + 1 < rows.count,
              case .task(let next, let nextDepth, _) = rows[parentIndex + 1] else { return false }
        return next === task && nextDepth > parentDepth
    }

    // MARK: - Lookup

    private func lookupTask(_ id: String) -> TaskItem? {
        for row in rows {
            if case .task(let task, _, _) = row, task.rowID == id { return task }
        }
        if id.hasPrefix("t-"), let uuid = UUID(uuidString: String(id.dropFirst(2))) {
            return app.store.task(id: uuid)
        }
        return nil
    }

    private func headerInfo(forRowID id: String) -> SectionHeaderInfo? {
        for row in rows {
            if case .header(let info) = row, row.id == id { return info }
        }
        return nil
    }
}

extension TaskListView where Header == EmptyView {
    init(rows: [ListRow], allowsReorder: Bool = true, defaultGroupID: UUID? = nil, plansFor: Date? = nil) {
        self.rows = rows
        self.allowsReorder = allowsReorder
        self.defaultGroupID = defaultGroupID
        self.plansFor = plansFor
        self.header = { EmptyView() }
    }
}

/// Row frames, kept outside SwiftUI state so scrolling doesn't re-render the list.
final class RowFrames {
    var byID: [String: CGRect] = [:]
}

/// Where a dragged-in task will land.
struct InsertionLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .strokeBorder(.tint, lineWidth: 2)
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(.tint)
                .frame(height: 2)
        }
        .padding(.leading, 6)
        .offset(y: 5)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

#if os(iOS)
/// Bulk actions while selecting multiple tasks on iPhone/iPad.
struct SelectionBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let tasks = app.selectedTasks
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy) { app.store.setDone(tasks, true) }
                    app.endSelection()
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                Button {
                    app.moveBatch = TaskBatch(tasks: tasks)
                } label: {
                    Image(systemName: "folder")
                }
                Button {
                    app.dateBatch = TaskBatch(tasks: tasks)
                } label: {
                    Image(systemName: "calendar")
                }
                Menu {
                    ForEach(Priority.allCases.reversed()) { priority in
                        Button(priority.title) { app.store.setPriority(tasks, priority) }
                    }
                } label: {
                    Image(systemName: "exclamationmark.circle")
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                Button {
                    app.deferToTomorrow(tasks)
                    app.endSelection()
                } label: {
                    Image(systemName: "moon.zzz")
                }
                Button(role: .destructive) {
                    app.delete(tasks)
                    app.endSelection()
                } label: {
                    Image(systemName: "trash")
                }
            }
            .font(.title3)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(tasks.isEmpty)
        }
        .padding(.bottom, 8)
    }
}
#endif
