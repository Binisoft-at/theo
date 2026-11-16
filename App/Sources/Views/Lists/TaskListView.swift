import SwiftUI
#if os(macOS)
import AppKit
#endif
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
    /// A ranked list across groups (Today's default): dragging a line only changes how
    /// important it is, never its group, order or nesting.
    var rankOnly = false
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
    /// The task whose quick-action panel is open (right-click on the Mac, Quick Edit on iPhone).
    @State private var actionTaskID: UUID?
    #if os(macOS)
    @State private var rightClick = RightClickMonitor()
    #endif

    private var placement: NewTaskPlacement { NewTaskPlacement(rawValue: placementRaw) ?? .bottom }

    var body: some View {
        @Bindable var app = app
        List(selection: $app.selectedRowIDs) {
            header()
                .listRowSeparator(.hidden)
                .selectionDisabled()
            ForEach(rows) { row in
                decoratedRow(row)
            }
            .onMove(perform: allowsReorder ? move : nil)
        }
        #if os(iOS)
        .listStyle(.plain)
        // Rows as tall as their content: their edges are where the dividers are.
        .environment(\.defaultMinListRowHeight, 1)
        .environment(\.editMode, .constant(app.isSelecting ? .active : .inactive))
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let task = focusedTask {
                    keyboardTools(task)
                }
            }
            if app.isSelecting {
                ToolbarItemGroup(placement: .topBarLeading) {
                    selectAllButton
                    selectMenu
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { app.endSelection() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if app.isSelecting {
                SelectionBar(rows: rows)
            }
        }
        #else
        .listStyle(.inset)
        .environment(\.defaultMinListRowHeight, 1)
        // A readable width on a big screen: lines don't stretch across the whole window.
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        // The window the list is in: its right-click watcher only takes clicks there.
        .background(ListWindowReader(monitor: rightClick))
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
            let done = !tasks.allSatisfy(\.isDone)
            // Checking off moves the selection on to the next open line.
            let next = done ? nextOpenRow(afterChecking: tasks) : nil
            withAnimation(.snappy) { app.markDone(tasks, done) }
            if let next { app.selectedRowIDs = [next] }
            return .handled
        }
        .onKeyPress(.return) {
            guard focusedID == nil, app.selectedTasks.count == 1, let task = app.selectedTasks.first else { return .ignored }
            beginEdit(task)
            return .handled
        }
        .onKeyPress(.rightArrow) { foldKey(unfold: true) }
        .onKeyPress(.leftArrow) { foldKey(unfold: false) }
        #endif
        .onChange(of: rows.map(\.id)) { oldIDs, newIDs in
            followSelection(from: oldIDs, to: newIDs)
        }
        .onChange(of: focusedID) { oldValue, newValue in
            if let newValue, newValue == pendingEditID { pendingEditID = nil }
            if let oldValue, oldValue != newValue, let task = lookupTask(oldValue) {
                // Between a line's title and its description it's still the same line.
                let staysOnLine = newValue.flatMap(lookupTask)?.uuid == task.uuid
                if !staysOnLine {
                    app.store.applyInlineShortcuts(task)
                    app.store.discardIfEmpty(task)
                }
                // Leaving a line saves it at once, so it syncs to the other devices right away.
                app.store.save()
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
            #if os(macOS)
            startRightClick()
            #endif
        }
        .onDisappear {
            #if os(macOS)
            rightClick.stop()
            #endif
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
                let model = self.app
                // Undo brings the group back with its tasks and subgroups.
                model.show("Deleted “\(group.displayName)” · tasks moved to Quick Entry", symbol: "tray.and.arrow.down.fill") {
                    model.store.restoreGroup(group)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { group in
            Text("“\(group.displayName)” contains \(group.liveTasks.count) task\(group.liveTasks.count == 1 ? "" : "s").")
        }
    }

    // MARK: - Rows

    /// One row with its frame tracking, drop lines, what it carries when dragged out of the list
    /// and (on the Mac) the hover insert zone.
    /// A function of its own, with small typed steps, so the type checker stays fast.
    private func decoratedRow(_ row: ListRow) -> some View {
        let leading: CGFloat = Self.lineLeading(row)
        let isFirst: Bool = rows.first?.id == row.id
        let linesBelow: Bool = insertAfterID == row.id
        let linesAbove: Bool = insertBeforeFirst && isFirst
        let provider: (() -> NSItemProvider?)? = dragProvider(for: row)
        let tracked = rowView(row)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                frames.byID[row.id] = frame
            }
            // A row scrolled out of view keeps no stale position for drops.
            .onDisappear { frames.byID[row.id] = nil }
        let lined = tracked
            .overlay(alignment: .bottom) {
                if linesBelow { InsertionLine(leading: leading, edge: .bottom) }
            }
            .overlay(alignment: .top) {
                if linesAbove { InsertionLine(leading: leading, edge: .top) }
            }
        #if os(macOS)
        // Near a divider it lights up with a + tab; a click on the tab adds a task (or
        // subtask) right there. A click anywhere else on the row still selects it.
        // Only a task as the first row offers its top edge: above a heading there's
        // no section for a new line to join.
        let offersTop: Bool = row.task != nil && isFirst
        let zoned = lined.modifier(HoverInsertZone(leading: leading, offersTop: offersTop) { edge in
            if edge == .top {
                insertTask(between: (above: rowBefore(row), below: row), entry: nil)
            } else {
                insertTask(between: (above: row, below: rowAfter(row)), entry: nil)
            }
        })
        return zoned.itemProvider(provider)
        #else
        return lined.itemProvider(provider)
        #endif
    }

    /// A task line dragged onto the sidebar (Mac and iPad) carries its task, or every selected
    /// line on this list when it's one of them (see `TaskDrag`). Within the list a drag still
    /// reorders (`move`). Headings and placeholders carry nothing, and neither does a line being
    /// edited, so dragging across its text still selects text.
    private func dragProvider(for row: ListRow) -> (() -> NSItemProvider?)? {
        guard TaskDrag.isAvailable, let task = row.task, !isEditing(task) else { return nil }
        return {
            TaskDrag.itemProvider(for: draggedIDs(task))
        }
    }

    /// The tasks a drag of `task` takes, read when the drag starts: the selected lines on this
    /// list in their order when it's one of several selected, else just this one.
    private func draggedIDs(_ task: TaskItem) -> [UUID] {
        let selected = app.selectedRowIDs
        guard selected.count > 1, selected.contains(task.rowID) else { return [task.uuid] }
        return rows.compactMap { row -> UUID? in
            guard let listed = row.task, selected.contains(listed.rowID) else { return nil }
            return listed.uuid
        }
    }

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
                    app.showDetails(task)
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
            // On a ranked list a subtask snaps back under its parent anyway.
            .moveDisabled(!allowsReorder || task.isDone || isEditing(task) || (rankOnly && depth > 0))
            // Swipe right: tuck under the line above (or take a subtask back out).
            .listRowInsets(EdgeInsets(top: 0, leading: Self.rowInset, bottom: 0, trailing: Self.rowInset))
            .popover(isPresented: Binding(get: { actionTaskID == task.uuid }, set: { if !$0 { actionTaskID = nil } }), arrowEdge: .top) {
                TaskActionPanel(tasks: actionTargets(for: task)) { actionTaskID = nil }
                    .presentationCompactAdaptation(.popover)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let parent = lineAbove(task) {
                    Button {
                        withAnimation(.snappy) { app.store.makeSubtask(task, of: parent) }
                    } label: {
                        Label("Subtask", systemImage: "arrow.turn.down.right")
                    }
                    .tint(.indigo)
                }
                #if os(iOS)
                if depth > 0 {
                    Button {
                        withAnimation(.snappy) { app.store.indent(task, by: -1) }
                    } label: {
                        Label("Outdent", systemImage: "arrow.turn.up.left")
                    }
                    .tint(.gray)
                }
                #endif
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: Self.fullSwipeLeft(depth: depth)) {
                #if os(macOS)
                // Two fingers on the trackpad: swipe right indents, swipe left outdents.
                if depth > 0 {
                    Button {
                        withAnimation(.snappy) { app.store.indent(task, by: -1) }
                    } label: {
                        Label("Outdent", systemImage: "arrow.turn.up.left")
                    }
                    .tint(.indigo)
                }
                #endif
                Button(role: .destructive) {
                    app.delete([task])
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                if !task.isDone {
                    // Onto today's plan from any page; once it's on today, on to tomorrow's.
                    if task.isPlanned(for: app.dayStart) {
                        Button {
                            withAnimation(.snappy) { app.deferToTomorrow([task]) }
                        } label: {
                            Label("Tomorrow", systemImage: "moon.zzz.fill")
                        }
                        .tint(.indigo)
                    } else {
                        Button {
                            withAnimation(.snappy) { app.plan([task], for: app.dayStart) }
                        } label: {
                            Label("Today", systemImage: "sun.max.fill")
                        }
                        .tint(.orange)
                    }
                    if let due = task.dueDate, DateText.dayDelta(due, today: app.dayStart) < 0 {
                        Button {
                            withAnimation(.snappy) { app.store.postpone([task], days: 1, today: app.dayStart) }
                        } label: {
                            Label("+1 Day", systemImage: "calendar.badge.plus")
                        }
                        .tint(.blue)
                    } else {
                        Button {
                            app.dateBatch = TaskBatch(tasks: [task])
                        } label: {
                            Label("Deadline", systemImage: "calendar")
                        }
                        .tint(.blue)
                    }
                }
            }
            #if os(iOS)
            .contextMenu {
                TaskMenuItems(tasks: [task], onEdit: { beginEdit(task) }, onQuickEdit: { actionTaskID = task.uuid })
            }
            #endif

        case .placeholder(_, let text):
            Text(text)
                .theoFont(.callout)
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
                Label("New Subgroup…", systemImage: "folder.badge.plus")
            }
            Button {
                app.go(.group(group.uuid))
            } label: {
                Label("Open as Page", systemImage: "arrow.up.forward.square")
            }
            completeShownButton(info)
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
            completeShownButton(info)
        case .label:
            EmptyView()
        }
    }

    /// A header's Complete finishes only the open lines shown under it (on Today, a group's
    /// tasks for today, not all of them), with Undo. Hidden when none are shown.
    @ViewBuilder
    private func completeShownButton(_ info: SectionHeaderInfo) -> some View {
        let shown = openTasksShown(under: info)
        if !shown.isEmpty {
            Button {
                app.complete(shown)
            } label: {
                Label(shown.count == 1 ? "Complete 1 Task" : "Complete \(shown.count) Shown", systemImage: "checkmark.circle")
            }
        }
    }

    /// The open lines listed under a header, up to the next header (ongoing ones never finish).
    /// A folded section lists none.
    private func openTasksShown(under info: SectionHeaderInfo) -> [TaskItem] {
        let headerID = ListRow.header(info).id
        guard let index = rows.firstIndex(where: { $0.id == headerID }) else { return [] }
        var shown: [TaskItem] = []
        for row in rows[(index + 1)...] {
            switch row {
            case .header:
                return shown
            case .placeholder:
                continue
            case .task(let task, _, _):
                if !task.isDone && !task.isOngoing { shown.append(task) }
            }
        }
        return shown
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
            focusedID = focusedID == TaskRowView.notesFocusID(task) ? task.rowID : TaskRowView.notesFocusID(task)
        } label: {
            Image(systemName: "text.alignleft")
        }
        .accessibilityLabel("Description")
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
                app.showDetails(task)
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
                    .theoFont(.subheadline, weight: .semibold)
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
            if task.isPlanned(for: app.dayStart) {
                Button {
                    app.deferToTomorrow([task])
                } label: {
                    Label("Plan for Tomorrow", systemImage: "moon.zzz.fill")
                }
            } else {
                Button {
                    app.plan([task], for: app.dayStart)
                } label: {
                    Label("Do Today", systemImage: "sun.max.fill")
                }
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
                app.showDetails(task)
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

    /// While selecting: every line on this page, or none again.
    private var selectAllButton: some View {
        let ids = Set(rows.compactMap { $0.task?.rowID })
        let all = !ids.isEmpty && ids.isSubset(of: app.selectedRowIDs)
        return Button(all ? "Select None" : "Select All") {
            app.selectedRowIDs = all ? [] : ids
        }
        .disabled(ids.isEmpty)
    }

    /// While selecting: picks the open lines on this page that need the same thing done.
    private var selectMenu: some View {
        Menu {
            selectPick("Overdue", symbol: "exclamationmark.circle") { task in
                task.dueDate.map { DateText.dayDelta($0, today: app.dayStart) < 0 } ?? false
            }
            selectPick("Due Today", symbol: "calendar") { task in
                task.dueDate.map { DateText.dayDelta($0, today: app.dayStart) == 0 } ?? false
            }
            selectPick("Unfinished from Earlier", symbol: "clock.arrow.circlepath") { task in
                task.isLeftOver(before: app.dayStart)
            }
            selectPick("Not Planned", symbol: "calendar.badge.minus") { task in
                task.plannedDay == nil
            }
        } label: {
            Label("Select", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    /// Selects the open lines on this page that match (instead of what was selected).
    private func selectPick(_ title: String, symbol: String, where matches: (TaskItem) -> Bool) -> some View {
        let ids = Set(rows.compactMap { row -> String? in
            guard let task = row.task, !task.isDone, matches(task) else { return nil }
            return task.rowID
        })
        return Button {
            app.selectedRowIDs = ids
        } label: {
            Label(ids.isEmpty ? title : "\(title) (\(ids.count))", systemImage: symbol)
        }
        .disabled(ids.isEmpty)
    }
    #endif

    // MARK: - Editing

    private var focusedTask: TaskItem? {
        guard let focusedID else { return nil }
        return lookupTask(focusedID)
    }

    private func isEditing(_ task: TaskItem) -> Bool {
        focusedID == task.rowID || focusedID == TaskRowView.notesFocusID(task) || pendingEditID == task.rowID
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
                // Lists are ranked: the task takes just enough importance to stay where it was put.
                let neighbours = Self.neighbours(of: newIndex, depth: depth, in: newRows)
                if rankOnly {
                    rerank(task, between: neighbours, movedUp: newIndex < from)
                } else {
                    app.store.drop(task: task, at: newIndex, in: newRows, defaultGroupID: defaultGroupID)
                    app.store.rank(task, between: neighbours.above, and: neighbours.below, today: app.dayStart)
                }
            case .header(let info):
                if case .group(let group) = info.kind {
                    app.store.drop(group: group, at: newIndex, in: newRows)
                }
            case .placeholder:
                break
            }
        }
    }

    /// A drag on a ranked list across groups (Today): the task only becomes more or less
    /// important, so it ranks where it was dropped. Its group, stored order and nesting stay as
    /// they are. Undo puts its importance (and the marks that follow it) back.
    private func rerank(_ task: TaskItem, between neighbours: (above: TaskItem?, below: TaskItem?), movedUp: Bool) {
        let importance = task.importance
        let priorityRaw = task.priorityRaw
        app.store.rank(task, between: neighbours.above, and: neighbours.below, today: app.dayStart)
        guard task.importance != importance || task.priorityRaw != priorityRaw else { return }
        let model = app
        model.show("Moved \(movedUp ? "up" : "down") · importance \(task.importanceLevel)", symbol: "arrow.up.arrow.down") {
            withAnimation(.snappy) {
                task.importance = importance
                task.priorityRaw = priorityRaw
                task.touch()
                model.store.save()
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
        insertTask(between: point, entry: entry)
        return true
    }

    /// The panel acts on the whole selection when the line is part of it, else on the line.
    private func actionTargets(for task: TaskItem) -> [TaskItem] {
        let selected = app.selectedTasks
        if selected.count > 1, selected.contains(where: { $0 === task }) { return selected }
        return [task]
    }

    #if os(macOS)
    /// A right-click on a task opens the colourful quick actions above it instead of the plain
    /// menu (Control-click still shows the menu). Only clicks in this list's own window count
    /// (see `RightClickMonitor`).
    private func startRightClick() {
        rightClick.handler = { event in
            guard isVisible, let content = event.window?.contentView else { return false }
            var point = content.convert(event.locationInWindow, from: nil)
            if !content.isFlipped { point.y = content.bounds.height - point.y }
            guard let hit = frames.byID.first(where: { $0.key.hasPrefix("t-") && $0.value.contains(point) }),
                  let uuid = UUID(uuidString: String(hit.key.dropFirst(2))) else { return false }
            if !app.selectedRowIDs.contains(hit.key) { app.selectedRowIDs = [hit.key] }
            actionTaskID = uuid
            return true
        }
        rightClick.start()
    }

    /// → unfolds the selected parent's subtasks and ← folds them; ← on a subtask goes up to its
    /// parent. Anything else (editing, several selected) passes the key on.
    private func foldKey(unfold: Bool) -> KeyPress.Result {
        guard focusedID == nil, app.selectedRowIDs.count == 1, let id = app.selectedRowIDs.first,
              let index = rows.firstIndex(where: { $0.id == id }),
              case .task(let task, let depth, let style) = rows[index] else { return .ignored }
        if style.subtaskCount > 0 && style.subtasksFolded == unfold {
            withAnimation(.snappy) { app.toggleSubtasks(task) }
            return .handled
        }
        guard !unfold, depth > 0, let parent = parentRowID(of: index, depth: depth) else { return .ignored }
        app.selectedRowIDs = [parent]
        return .handled
    }

    /// The row of the line a subtask sits under, within its section.
    private func parentRowID(of index: Int, depth: Int) -> String? {
        var j = index - 1
        while j >= 0 {
            switch rows[j] {
            case .header:
                return nil
            case .placeholder:
                break
            case .task(_, let d, _):
                if d < depth { return rows[j].id }
            }
            j -= 1
        }
        return nil
    }

    /// The line to select once `tasks` are checked off: the next open one below the last of
    /// them (their subtasks close with them, so they're skipped), else the closest open one above.
    private func nextOpenRow(afterChecking tasks: [TaskItem]) -> String? {
        let ids = Set(tasks.map(\.rowID))
        var closing = Set<String>()
        var blockDepth: Int?
        for row in rows {
            guard case .task(_, let depth, _) = row else {
                blockDepth = nil
                continue
            }
            if let parentDepth = blockDepth, depth > parentDepth {
                closing.insert(row.id)
                continue
            }
            blockDepth = nil
            if ids.contains(row.id) {
                closing.insert(row.id)
                blockDepth = depth
            }
        }
        let closed = closing
        guard let first = rows.firstIndex(where: { closed.contains($0.id) }),
              let last = rows.lastIndex(where: { closed.contains($0.id) }) else { return nil }
        func isOpenLine(_ row: ListRow) -> Bool {
            guard case .task(let task, _, _) = row else { return false }
            return !task.isDone && !closed.contains(row.id)
        }
        if let below = rows[(last + 1)...].first(where: isOpenLine) { return below.id }
        return rows[..<first].last(where: isOpenLine)?.id
    }

    /// The first open line after the last of `gone` (in the old order) that's still listed,
    /// else the closest one before the first of them.
    private func openRow(near gone: Set<String>, in oldIDs: [String]) -> String? {
        let open = Set(rows.compactMap { row -> String? in
            guard case .task(let task, _, _) = row, !task.isDone else { return nil }
            return row.id
        })
        guard let first = oldIDs.firstIndex(where: { gone.contains($0) }),
              let last = oldIDs.lastIndex(where: { gone.contains($0) }) else { return nil }
        if let after = oldIDs[(last + 1)...].first(where: { open.contains($0) }) { return after }
        return oldIDs[..<first].last(where: { open.contains($0) })
    }
    #endif

    /// Rows that went away (checked off while finished ones are hidden, deleted, moved, planned
    /// for another day) leave the selection, so the next key press or bulk action never acts on
    /// a task that isn't on the page any more. On the Mac the next open line is selected instead.
    /// IDs that weren't on this list before (a task revealed from elsewhere) are left alone.
    private func followSelection(from oldIDs: [String], to newIDs: [String]) {
        // A list kept alive off screen (another tab) leaves the visible page's selection alone.
        guard isVisible else { return }
        let selected = app.selectedRowIDs
        guard !selected.isEmpty else { return }
        let before = Set(oldIDs)
        let after = Set(newIDs)
        let gone = selected.filter { before.contains($0) && !after.contains($0) }
        guard !gone.isEmpty else { return }
        let kept = selected.subtracting(gone)
        #if os(macOS)
        if kept.isEmpty, let next = openRow(near: gone, in: oldIDs) {
            app.selectedRowIDs = [next]
            return
        }
        #endif
        app.selectedRowIDs = kept
    }

    private func rowBefore(_ row: ListRow) -> ListRow? {
        guard let index = rows.firstIndex(where: { $0.id == row.id }), index > 0 else { return nil }
        return rows[index - 1]
    }

    /// Where a row's divider (and so the insert line) starts.
    private static func lineLeading(_ row: ListRow) -> CGFloat {
        if case .task(_, let depth, _) = row { return TaskRowView.textLeading(depth: depth) }
        return 30
    }

    private func rowAfter(_ row: ListRow) -> ListRow? {
        guard let index = rows.firstIndex(where: { $0.id == row.id }), index + 1 < rows.count else { return nil }
        return rows[index + 1]
    }

    /// Adds a task between two rows (see `insertTask(at:entry:)`).
    private func insertTask(between point: (above: ListRow?, below: ListRow?), entry: ParsedEntry?) {
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
            // A blank line has to show to be typed into (and to be dropped again when left
            // empty): a folded section opens first.
            if entry == nil && info.isCollapsed { toggleCollapse(info) }
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
            // Added to the tags the group's traits gave it, so a group's own tag stays.
            if !entry.tags.isEmpty { new.tags = new.tags + entry.tags }
            if let estimate = entry.estimate { new.estimate = estimate }
            // A repeat needs a first date: without a deadline it starts today.
            if entry.recurrence != nil { app.store.setRecurrence([new], entry.recurrence) }
            if entry.ongoing { new.isOngoing = true }
            if !entry.notes.isEmpty { new.notes = entry.notes }
            app.store.save()
        }
        if let plansFor { app.store.plan([new], for: plansFor) }
        if entry == nil { beginEdit(new) }
    }

    /// A neighbour's place in the ranking; finished tasks don't count.
    private func rankOf(_ task: TaskItem?) -> Matrix.Rank? {
        guard let task, !task.isDone else { return nil }
        return Matrix.Rank(importance: task.importance, days: Matrix.daysUntil(task.dueDate, today: app.dayStart))
    }

    /// Side insets of a task row. Its top and bottom have none, so the row's edge is the divider.
    private static var rowInset: CGFloat {
        #if os(macOS)
        10
        #else
        16
        #endif
    }

    /// A full swipe left: Delete on iPhone; on the Mac only Outdent (for subtasks), so a
    /// trackpad swipe never deletes.
    private static func fullSwipeLeft(depth: Int) -> Bool {
        #if os(macOS)
        return depth > 0
        #else
        return true
        #endif
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
        // A description field ("n-" + the task's ID).
        if id.hasPrefix("n-"), let uuid = UUID(uuidString: String(id.dropFirst(2))) {
            return app.store.task(id: uuid)
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
    init(rows: [ListRow], allowsReorder: Bool = true, defaultGroupID: UUID? = nil, plansFor: Date? = nil, rankOnly: Bool = false) {
        self.rows = rows
        self.allowsReorder = allowsReorder
        self.defaultGroupID = defaultGroupID
        self.plansFor = plansFor
        self.rankOnly = rankOnly
        self.header = { EmptyView() }
    }
}

/// Row frames, kept outside SwiftUI state so scrolling doesn't re-render the list.
final class RowFrames {
    var byID: [String: CGRect] = [:]
}

#if os(macOS)
/// Watches right-clicks in the list's window; the handler returns true when it took one.
/// Clicks in other windows (Settings, the menu bar panel, a popover) and clicks while a sheet
/// covers the window (the tour) are left alone.
@MainActor
final class RightClickMonitor {
    var handler: ((NSEvent) -> Bool)?
    /// The window the list is in (set by `ListWindowReader`).
    weak var hostWindow: NSWindow?
    private var token: Any?

    func start() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let monitor = self, let handler = monitor.handler, monitor.accepts(event) else { return event }
                return handler(event) ? nil : event
            }
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    private func accepts(_ event: NSEvent) -> Bool {
        guard let host = hostWindow, event.window === host else { return false }
        return host.attachedSheet == nil
    }
}

/// Tells the list's right-click watcher which window the list is in.
struct ListWindowReader: NSViewRepresentable {
    let monitor: RightClickMonitor

    func makeNSView(context: Context) -> ListWindowView {
        let view = ListWindowView()
        view.monitor = monitor
        return view
    }

    func updateNSView(_ view: ListWindowView, context: Context) {
        view.monitor = monitor
        if let window = view.window { monitor.hostWindow = window }
    }
}

/// An empty view that reports the window it moves into. It never takes clicks.
final class ListWindowView: NSView {
    weak var monitor: RightClickMonitor?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        monitor?.hostWindow = window
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The Mac's hover insert: with the pointer near a row's bottom edge (or the first row's top
/// edge) the divider there lights up with a + tab, and a click on the tab adds a task right
/// there. The tab sits inside this row and is the only part that takes clicks, so a click
/// anywhere else still selects the row and a double-click still edits it.
struct HoverInsertZone: ViewModifier {
    let leading: CGFloat
    /// The first row also offers its top edge (a task above it).
    let offersTop: Bool
    let onInsert: (VerticalEdge) -> Void

    @State private var edge: VerticalEdge?
    @State private var height: CGFloat = 0

    /// How close to an edge the pointer has to come to light it up.
    private static let zone: CGFloat = 5
    /// The clickable + tab, a little larger than the drawn one.
    private static let tabWidth: CGFloat = 18
    private static let tabHeight: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if let edge {
                    ZStack(alignment: edge == .top ? .topLeading : .bottomLeading) {
                        InsertionLine(leading: leading, edge: edge)
                        Button {
                            onInsert(edge)
                        } label: {
                            Color.clear
                                .frame(width: Self.tabWidth, height: Self.tabHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, max(0, leading - Self.tabWidth))
                        .help("Add a task here")
                        .accessibilityLabel("Add a task here")
                    }
                    .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                height = newHeight
            }
            .onContinuousHover { phase in
                let next: VerticalEdge?
                switch phase {
                case .active(let point):
                    next = Self.litEdge(at: point.y, height: height, current: edge, offersTop: offersTop)
                case .ended:
                    next = nil
                }
                if next != edge { edge = next }
            }
            .animation(.easeOut(duration: 0.1), value: edge)
    }

    /// The edge the pointer is at. Once lit, an edge stays lit over its whole tab, so the tab
    /// doesn't vanish while the pointer moves onto it.
    private static func litEdge(at y: CGFloat, height: CGFloat, current: VerticalEdge?, offersTop: Bool) -> VerticalEdge? {
        guard height > 0 else { return nil }
        let bottomReach = current == .bottom ? tabHeight : zone
        let topReach = current == .top ? tabHeight : zone
        if y >= height - bottomReach { return .bottom }
        if offersTop && y <= topReach { return .top }
        return nil
    }
}
#endif

/// Where a new task will land: the divider itself in the accent colour, from where the text
/// starts to the end, with a small + tab sitting on it just before the text.
struct InsertionLine: View {
    var leading: CGFloat = 34
    var edge: VerticalEdge = .bottom

    var body: some View {
        ZStack(alignment: edge == .bottom ? .bottomLeading : .topLeading) {
            Rectangle()
                .fill(.tint)
                .frame(height: 2)
                .padding(.leading, leading)
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.tint))
                .padding(.leading, max(0, leading - 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

#if os(iOS)
/// Bulk actions while selecting tasks on iPhone and iPad: how many are selected, then one
/// labelled button per action, in the quick-action panel's colours. Today, Tomorrow, Deadline,
/// PH and Priority keep the selection so several changes can follow each other; Done, Move and
/// Delete end it.
struct SelectionBar: View {
    /// The page's rows: the bar acts only on selected lines that are on the page.
    let rows: [ListRow]

    @Environment(AppModel.self) private var app

    var body: some View {
        let selected = app.selectedRowIDs
        let tasks = rows.compactMap(\.task).filter { selected.contains($0.rowID) }
        VStack(spacing: 8) {
            Text(tasks.isEmpty ? "Tap tasks to select them" : "\(tasks.count) selected")
                .theoFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    actions(tasks)
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func actions(_ tasks: [TaskItem]) -> some View {
        let open = tasks.filter { !$0.isDone }
        let allDone = !tasks.isEmpty && open.isEmpty
        actionButton(allDone ? "Reopen" : "Done", allDone ? "arrow.uturn.backward" : "checkmark", .green, enabled: !tasks.isEmpty) {
            if allDone {
                withAnimation(.snappy) { app.store.setDone(tasks, false) }
            } else if open.contains(where: { !$0.isOngoing }) {
                app.complete(open)
            } else {
                // Only ongoing tasks: each one is logged for today, as its checkbox does.
                withAnimation(.snappy) { app.store.setDone(open, true) }
            }
            app.endSelection()
        }
        if !open.isEmpty && open.allSatisfy({ $0.isPlanned(for: app.dayStart) }) {
            actionButton("Off Plan", "calendar.badge.minus", .gray) {
                withAnimation(.snappy) { app.plan(open, for: nil) }
            }
        } else {
            actionButton("Today", "sun.max.fill", .orange, enabled: !open.isEmpty) {
                withAnimation(.snappy) { app.plan(open, for: app.dayStart) }
            }
        }
        actionButton("Tomorrow", "moon.zzz.fill", .indigo, enabled: !open.isEmpty) {
            withAnimation(.snappy) { app.deferToTomorrow(open) }
        }
        actionButton("Deadline", "calendar", .blue, enabled: !tasks.isEmpty) {
            app.dateBatch = TaskBatch(tasks: tasks)
        }
        Menu {
            ForEach(PowerHours.presets, id: \.self) { value in
                Button(PowerHours.format(value)) {
                    app.store.setEstimate(tasks, value)
                }
            }
            Divider()
            Button(role: .destructive) {
                app.store.setEstimate(tasks, 0)
            } label: {
                Label("No Estimate", systemImage: "xmark.circle")
            }
        } label: {
            actionLabel("PH", "timer", .teal)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(tasks.isEmpty)
        .opacity(tasks.isEmpty ? 0.4 : 1)
        .accessibilityLabel("Power Hours")
        actionButton("Move", "folder.fill", .brown, enabled: !tasks.isEmpty) {
            app.moveBatch = TaskBatch(tasks: tasks)
        }
        Menu {
            ForEach(Priority.allCases.reversed()) { priority in
                Button {
                    app.store.setPriority(tasks, priority)
                } label: {
                    Label(priority == .normal ? "No Priority" : "\(priority.title) \(priority.marks)", systemImage: priority.symbol)
                }
            }
        } label: {
            actionLabel("Priority", "exclamationmark", .purple)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(tasks.isEmpty)
        .opacity(tasks.isEmpty ? 0.4 : 1)
        .accessibilityLabel("Priority")
        actionButton("Delete", "trash.fill", .red, enabled: !tasks.isEmpty) {
            app.delete(tasks)
            app.endSelection()
        }
    }

    private func actionButton(_ title: String, _ symbol: String, _ color: Color, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, symbol, color)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title)
    }

    /// A round, coloured icon with its name underneath, like the quick-action panel's.
    private func actionLabel(_ title: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(color.gradient))
            Text(title)
                .theoFont(.caption2, weight: .medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: 54)
        .contentShape(Rectangle())
    }
}
#endif
