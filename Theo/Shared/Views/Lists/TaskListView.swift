import SwiftUI
import SwiftData

/// The core list used by every page. It renders the flat row model (headings + tasks),
/// handles inline editing, drag-to-reorder across groups, swipes, context menus and
/// keyboard shortcuts.
struct TaskListView<Header: View>: View {
    let rows: [ListRow]
    var allowsReorder = true
    /// Group that receives drops when the page has no headings (single group pages).
    var defaultGroupID: UUID?
    @ViewBuilder var header: () -> Header

    @Environment(AppModel.self) private var app
    @AppStorage(Prefs.newTaskPlacement) private var placementRaw = NewTaskPlacement.bottom.rawValue
    @AppStorage(Prefs.quickEntryCollapsed) private var quickCollapsed = false
    @FocusState private var focusedID: String?
    @State private var pendingEditID: String?
    @State private var groupPendingDelete: TaskGroup?
    @State private var lastSplit: (id: String, time: Date)?

    private var placement: NewTaskPlacement { NewTaskPlacement(rawValue: placementRaw) ?? .bottom }

    var body: some View {
        @Bindable var app = app
        List(selection: $app.selectedRowIDs) {
            header()
                .listRowSeparator(.hidden)
                .selectionDisabled()
            ForEach(rows) { row in
                rowView(row)
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
                app.store.discardIfEmpty(task)
            }
        }
        .onChange(of: app.isSelecting) { _, selecting in
            if selecting { focusedID = nil }
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
                    withAnimation(.snappy) { app.store.indent(task, by: delta) }
                }
            )
            .moveDisabled(!allowsReorder || task.isDone || isEditing(task))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    withAnimation(.snappy) { app.toggle(task) }
                } label: {
                    Label(task.isDone ? "Not Done" : "Done", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(.green)
                if !task.isDone {
                    Button {
                        app.deferToTomorrow([task])
                    } label: {
                        Label("Not Today", systemImage: "moon.zzz")
                    }
                    .tint(.indigo)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    app.delete([task])
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    app.moveBatch = TaskBatch(tasks: [task])
                } label: {
                    Label("Move", systemImage: "folder")
                }
                .tint(.blue)
                Button {
                    app.dateBatch = TaskBatch(tasks: [task])
                } label: {
                    Label("Deadline", systemImage: "calendar")
                }
                .tint(.orange)
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
    @ViewBuilder
    private func keyboardTools(_ task: TaskItem) -> some View {
        Button {
            withAnimation(.snappy) { app.store.indent(task, by: -1) }
        } label: {
            Image(systemName: "decrease.indent")
        }
        Button {
            withAnimation(.snappy) { app.store.indent(task, by: 1) }
        } label: {
            Image(systemName: "increase.indent")
        }
        Menu {
            ForEach(Priority.allCases.reversed()) { priority in
                Button {
                    app.store.setPriority([task], priority)
                } label: {
                    Label(priority.title, systemImage: priority.symbol)
                }
            }
        } label: {
            Image(systemName: "exclamationmark.circle")
        }
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
            Image(systemName: "calendar")
        }
        Button {
            focusedID = nil
            app.tagBatch = TaskBatch(tasks: [task])
        } label: {
            Image(systemName: "number")
        }
        Spacer()
        Button {
            focusedID = nil
        } label: {
            Image(systemName: "keyboard.chevron.compact.down")
        }
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
            // Return on an empty line ends editing, like leaving a checklist in Notes.
            focusedID = nil
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
            case .task(let task, _, _):
                app.store.drop(task: task, at: newIndex, in: newRows, defaultGroupID: defaultGroupID)
            case .header(let info):
                if case .group(let group) = info.kind {
                    app.store.drop(group: group, at: newIndex, in: newRows)
                }
            case .placeholder:
                break
            }
        }
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
    init(rows: [ListRow], allowsReorder: Bool = true, defaultGroupID: UUID? = nil) {
        self.rows = rows
        self.allowsReorder = allowsReorder
        self.defaultGroupID = defaultGroupID
        self.header = { EmptyView() }
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
