import SwiftUI
import SwiftData
import TheoCore

/// Floating Liquid Glass composer at the bottom of a page. Type, hit Return, keep typing.
///
/// - Typed shortcuts: `!!`, `#tag`, `@group` and natural dates ("morgen 9 Uhr", "bis Freitag"),
///   previewed as chips. A chip shows which words it took; × or "No Deadline" puts them back.
/// - While an `@group` or `#tag` is typed, matching groups (with their path) or tags take the
///   chips' place; a tap puts the full word in ("@Work/Admin "). On the Mac ↓ ↑ pick one, Tab or
///   Return take it, Esc hides them.
/// - Buttons above the field set priority, deadline and group without typing.
/// - A leading "- " files the line as a subtask of the task added just before.
/// - Pasting several lines adds several tasks and keeps their indentation as subtasks.
/// - The ⊞ handle drags the task onto the Eisenhower matrix (urgency × importance); let go
///   to add it right there.
/// - Every add can be undone from the confirmation line, which also says what was understood.
struct QuickEntryBar: View {
    /// Where new tasks go when no `@group` is typed (nil = Quick Entry).
    var defaultGroupID: UUID?
    var placeholder = "Add a task"
    /// New tasks are planned for this day (Today, Plan).
    var plansFor: Date?

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @AppStorage(Prefs.newTaskPlacement) private var placementRaw = NewTaskPlacement.bottom.rawValue

    @State private var text = ""
    @State private var disabled: QuickParser.Options = []
    @State private var priorityChoice: Priority?
    @State private var dueChoice: DueChoice = .fromText
    @State private var groupChoice: GroupChoice = .fromText
    @State private var subtaskOff = false
    /// nil = from the text ("0,5PH"), 0 = none.
    @State private var estimateChoice: Double?
    @State private var recurrenceChoice: RecurrenceChoice = .fromText
    @State private var matrixChoice: MatrixGeometry.Cell?
    /// 1...10 from holding the ! chip; overrides the priority marks.
    @State private var importanceChoice: Int?
    @State private var showCustomEstimate = false
    @State private var customEstimateText = ""
    /// The last top-level task added here; "- " lines go under it.
    @State private var lastParent: TaskItem?
    @State private var confirmation: Confirmation?
    @State private var addedCount = 0
    /// The `@group` / `#tag` pick Tab or Return takes on the Mac (a position in the strip).
    @State private var highlight = 0
    /// Esc hid the picks for exactly this text; typing on brings them back.
    @State private var suggestionsHiddenFor: String?
    @FocusState private var focused: Bool

    enum DueChoice: Equatable {
        case fromText
        case cleared
        case date(Date)
    }

    enum RecurrenceChoice: Equatable {
        case fromText
        case never
        case set(Recurrence)
    }

    enum GroupChoice: Equatable {
        case fromText
        case quickEntry
        case group(UUID)
    }

    struct Confirmation: Identifiable {
        let id = UUID()
        let message: String
        let tasks: [TaskItem]
        /// One task was added: "Show" goes to it.
        var showsReveal = false
        /// Planned for today although it's due later: "Off Plan" takes it off today's plan.
        var offersOffPlan = false

        var hasExtraButtons: Bool { showsReveal || offersOffPlan }
    }

    // MARK: - What the entry will create

    private var options: QuickParser.Options { QuickParser.Options.all.subtracting(disabled) }

    /// In page order (each subgroup after its parent) and with parents, so "@Work/Admin" finds
    /// the subgroup. The picks above the field come from the same list, so a pick files where it says.
    private var groupRefs: [QuickParser.GroupRef] {
        GroupTree.ordered(groups).map { item in
            QuickParser.GroupRef(id: item.group.uuid, name: item.group.displayName, parentID: item.group.parentUUID)
        }
    }

    /// The same test `add()` uses to tell a pasted list from one line.
    private var isMultiline: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: \.isNewline) }

    private var liveParent: TaskItem? {
        guard let lastParent, lastParent.modelContext != nil, !lastParent.isDeleted, lastParent.deletedAt == nil else { return nil }
        return lastParent
    }

    /// Set while the text starts with "- " and there's a task to file it under.
    private var subtaskParent: TaskItem? {
        guard !subtaskOff, !isMultiline, Composer.subtaskBody(text) != nil else { return nil }
        return liveParent
    }

    /// The text read on the logical day, so "morgen" typed at 01:30 is the day after today's page.
    private var parsed: ParsedEntry {
        let source = subtaskParent != nil ? (Composer.subtaskBody(text) ?? text) : text
        return QuickParser.parse(source, groups: groupRefs, options: options, now: app.dayStart)
    }

    /// What the chips show. A pasted list is read line by line when it's added, so its chips
    /// show only what's picked for every line.
    private var chipEntry: ParsedEntry { isMultiline ? ParsedEntry(title: "") : parsed }

    /// The pasted lines that become tasks: ticked-off lines ("- [x] ") are left out together
    /// with the lines under them.
    static func openLines(_ lines: [Composer.Line]) -> [Composer.Line] {
        var result: [Composer.Line] = []
        var skipBelow: Int?
        for line in lines {
            if let level = skipBelow {
                if line.level > level { continue }
                skipBelow = nil
            }
            if line.done {
                skipBelow = line.level
                continue
            }
            result.append(line)
        }
        return result
    }

    private var effectivePriority: Priority { priorityChoice ?? chipEntry.priority }

    private var effectiveDue: (date: Date, hasTime: Bool)? {
        switch dueChoice {
        case .fromText:
            let entry = chipEntry
            return entry.due.map { (date: $0, hasTime: entry.dueHasTime) }
        case .cleared:
            return nil
        case .date(let date):
            return (date: date, hasTime: false)
        }
    }

    /// The deadline came from words in the text (not from a pick or an "every Monday").
    private var dueFromText: Bool { dueChoice == .fromText && chipEntry.dueText != nil }

    /// The repeat came from words in the text.
    private var repeatFromText: Bool { recurrenceChoice == .fromText && chipEntry.recurrence != nil }

    /// Power Hours picked or typed (0 = explicitly none); nil leaves it to the default.
    private var chosenEstimate: Double? { estimateChoice ?? chipEntry.estimate }
    /// What the task will get: picked or typed, else its group's trait, else the default.
    private var effectiveEstimate: Double {
        chosenEstimate ?? targetTraits.estimate ?? PowerHours.defaultForNewTasks
    }
    /// Traits of the group the task will land in.
    private var targetTraits: GroupTraits {
        let groupID = subtaskParent?.groupID ?? targetGroupID
        return app.store.traits(of: groups.first(where: { $0.uuid == groupID }))
    }

    private var effectiveRecurrence: Recurrence? {
        switch recurrenceChoice {
        case .fromText: chipEntry.recurrence
        case .never: nil
        case .set(let recurrence): recurrence
        }
    }

    /// Group chosen with the button, or the page's group.
    private var baseGroupID: UUID? {
        switch groupChoice {
        case .fromText: defaultGroupID
        case .quickEntry: nil
        case .group(let id): id
        }
    }

    private var targetGroupID: UUID? {
        if case .fromText = groupChoice, let typed = chipEntry.groupID { return typed }
        return baseGroupID
    }

    private func groupName(_ id: UUID?) -> String {
        groups.first(where: { $0.uuid == id })?.displayName ?? "Quick Entry"
    }

    // MARK: - Views

    var body: some View {
        VStack(spacing: 8) {
            if let confirmation {
                confirmationRow(confirmation)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if focused {
                aboveField
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            field
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        #if os(macOS)
        // As wide as the list above it, not the whole window.
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        #endif
        .animation(.snappy(duration: 0.25), value: text.isEmpty)
        .animation(.snappy(duration: 0.25), value: focused)
        .animation(.snappy(duration: 0.25), value: confirmation?.id)
        .onChange(of: app.wantsQuickEntryFocus) { _, wants in
            if wants { focusNow() }
        }
        .onAppear {
            if app.wantsQuickEntryFocus { focusNow() }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused && text.isEmpty { groupChoice = .fromText }
        }
        .alert("Estimate", isPresented: $showCustomEstimate) {
            TextField("Power Hours, e.g. 1,5", text: $customEstimateText)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Button("Set") {
                if let value = PowerHours.parse(customEstimateText) { estimateChoice = value }
                customEstimateText = ""
            }
            Button("Cancel", role: .cancel) { customEstimateText = "" }
        } message: {
            Text("1 PH = 50 minutes of focused work.")
        }
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty {
                disabled = []
                subtaskOff = false
            }
            // Each letter typed ranks the picks anew: the best one is highlighted again.
            highlight = 0
            if suggestionsHiddenFor != newValue { suggestionsHiddenFor = nil }
            // Return in the multi-line field arrives as a trailing line break.
            if newValue.hasSuffix("\n") {
                text = String(newValue.dropLast())
                add()
            }
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            insertHandle
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .theoFont(.body)
                .lineLimit(1...5)
                .focused($focused)
                .onSubmit(add)
                #if os(iOS)
                .submitLabel(.done)
                #elseif os(macOS)
                // While the @group / #tag picks show: ↓ ↑ move, Tab or Return take one, Esc hides them.
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onKeyPress(.tab, phases: .down) { press in acceptHighlighted(press, isReturn: false) }
                .onKeyPress(.return, phases: .down) { press in acceptHighlighted(press, isReturn: true) }
                .onKeyPress(.escape) { hideSuggestions() }
                #endif
            matrixHandle
            if !text.isEmpty {
                // Tap adds; hold and point at a value on the arc picks the Power Hours, letting go
                // adds with them.
                HoldSlidePicker(options: Self.estimateOptions, title: "PH", onTap: add) { index in
                    pickEstimate(index)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .theoFont(.title2)
                        .foregroundStyle(.tint)
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(isMultiline ? "Add \(Self.openLines(Composer.lines(text)).count) Tasks" : "Add Task")
                .accessibilityHint("Touch and hold, then slide toward a value to set the Power Hours")
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }

    /// While an `@group` or `#tag` is typed, the picks for it take the chips' place.
    @ViewBuilder
    private var aboveField: some View {
        let items = suggestions
        if items.isEmpty {
            controls
        } else {
            ComposerSuggestionStrip(items: items, highlightedID: highlightedID(in: items)) { item in
                accept(item)
            }
        }
    }

    // MARK: - @group and #tag picks

    /// What the strip above the field offers for the `@group` or `#tag` being typed (up to 6).
    private var suggestions: [ComposerSuggestion] {
        guard focused, suggestionsHiddenFor != text, let token = TokenCompletion.activeToken(in: text) else { return [] }
        switch token.kind {
        case .group:
            // A "- " subtask goes under its parent, whatever group is typed.
            return subtaskParent == nil ? groupSuggestions(token.prefix) : []
        case .tag:
            return tagSuggestions(token.prefix)
        }
    }

    /// Groups with their colour and path ("Work › Admin"); switched-off ones dimmed.
    private func groupSuggestions(_ query: String) -> [ComposerSuggestion] {
        let off = GroupTree.inactiveIDs(groups)
        let matches = TokenCompletion.groups(matching: query, in: groupRefs)
        return matches.compactMap { match -> ComposerSuggestion? in
            guard let group = groups.first(where: { $0.uuid == match.id }) else { return nil }
            return ComposerSuggestion(
                id: "g-" + group.uuid.uuidString,
                title: match.path.joined(separator: " › "),
                insertion: match.insertion,
                color: group.color.color,
                isGroup: true,
                count: nil,
                dimmed: off.contains(group.uuid)
            )
        }
    }

    /// Tags of the open tasks, with how many have each.
    private func tagSuggestions(_ query: String) -> [ComposerSuggestion] {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false })
        let openTasks = (try? app.store.context.fetch(descriptor)) ?? []
        let counts = TokenCompletion.tagCounts(openTasks.map { $0.tags })
        return TokenCompletion.tags(matching: query, counts: counts).map { found in
            ComposerSuggestion(
                id: "t-" + found.tag,
                title: "#" + found.tag,
                insertion: found.insertion,
                color: TheoColor.forTag(found.tag).color,
                isGroup: false,
                count: found.count,
                dimmed: false
            )
        }
    }

    /// The pick Tab or Return takes; only the Mac has one.
    private func highlightedID(in items: [ComposerSuggestion]) -> String? {
        #if os(macOS)
        guard !items.isEmpty else { return nil }
        return items[min(max(highlight, 0), items.count - 1)].id
        #else
        return nil
        #endif
    }

    /// Puts the pick in place of the word being typed ("@wo" → "@Work/Admin ") and keeps typing.
    private func accept(_ item: ComposerSuggestion) {
        text = TokenCompletion.complete(text, with: item.insertion)
        if item.isGroup {
            // A group picked here wins over one chosen on the group chip.
            disabled.remove(.group)
            groupChoice = .fromText
        } else {
            disabled.remove(.tags)
        }
        highlight = 0
        focused = true
    }

    #if os(macOS)
    /// ↓ / ↑ move the highlight through the picks (and round again).
    private func moveHighlight(by step: Int) -> KeyPress.Result {
        let count = suggestions.count
        guard count > 0 else { return .ignored }
        let current = min(max(highlight, 0), count - 1)
        highlight = (current + step + count) % count
        return .handled
    }

    /// Tab or Return take the highlighted pick while the strip shows. Return adds the task as
    /// always when there's no strip, when the word is typed in full already ("@home" for Home),
    /// or with ⇧, ⌥, ⌘ or ⌃ held.
    private func acceptHighlighted(_ press: KeyPress, isReturn: Bool) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.shift, .option, .command, .control]) else { return .ignored }
        let items = suggestions
        guard let id = highlightedID(in: items), let item = items.first(where: { $0.id == id }) else { return .ignored }
        if isReturn && TokenCompletion.isTyped(item.insertion, in: text) { return .ignored }
        accept(item)
        return .handled
    }

    /// Esc hides the picks until the text changes.
    private func hideSuggestions() -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        suggestionsHiddenFor = text
        return .handled
    }
    #endif

    /// One-tap priority, deadline, group and subtask, plus what was understood from the text.
    private var controls: some View {
        let entry = chipEntry
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if isMultiline {
                    chipLabel("\(Self.openLines(Composer.lines(text)).count) tasks", symbol: "list.bullet.indent", color: .accentColor, active: true)
                } else {
                    subtaskChip
                }
                priorityChip
                HStack(spacing: 2) {
                    dueChip
                    if dueFromText {
                        // The chip is a menu, so the × that gives the words back sits next to it.
                        Button {
                            disabled.formUnion([.dates, .exactDates])
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .imageScale(.medium)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 24, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Not a date")
                        .accessibilityHint("Keeps “\(entry.dueText ?? "")” in the title")
                        .transition(.opacity)
                    }
                }
                estimateChip
                if effectiveDue != nil || effectiveRecurrence != nil {
                    repeatChip
                }
                if let matrixChoice {
                    removableChip(MatrixGeometry.describe(matrixChoice), color: .accentColor) {
                        self.matrixChoice = nil
                    }
                }
                if subtaskParent == nil {
                    groupChip
                }
                if entry.ongoing {
                    removableChip("∞ Ongoing", color: .teal) { disabled.insert(.ongoing) }
                }
                if !isMultiline {
                    // A description in one tap: everything after " // " goes there.
                    Button {
                        if !text.contains(" // ") {
                            text = text.trimmingCharacters(in: .whitespaces) + " // "
                        }
                        focused = true
                    } label: {
                        chipLabel(entry.notes.isEmpty ? "Description" : "Description ✓", symbol: "text.alignleft",
                                  color: .indigo, active: !entry.notes.isEmpty)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adds “ // ” to the text; what you type after it becomes the description")
                }
                ForEach(entry.tags, id: \.self) { tag in
                    removableChip("#" + tag, color: TheoColor.forTag(tag).color) { disabled.insert(.tags) }
                }
                if text.isEmpty {
                    Text(liveParent == nil ? "Try “tomorrow 9am !! #home”" : "Start with “- ” for a subtask")
                        .theoFont(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var subtaskChip: some View {
        if let parent = subtaskParent {
            Button {
                subtaskOff = true
            } label: {
                chipLabel("Under “\(parent.trimmedTitle)”", symbol: "arrow.turn.down.right", color: .accentColor, active: true, removable: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds it as a normal task instead")
        } else if let parent = liveParent, Composer.subtaskBody(text) == nil {
            Button {
                subtaskOff = false
                text = "- " + text
            } label: {
                chipLabel("Subtask", symbol: "arrow.turn.down.right", color: .accentColor, active: false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds it under “\(parent.trimmedTitle)”")
        }
    }

    /// Tap steps through ! / !! / !!!; hold and slide picks an importance level 1–10.
    private var priorityChip: some View {
        let level = effectivePriority
        let title: String
        if let importanceChoice {
            title = "Importance \(importanceChoice)"
        } else {
            title = level == .normal ? "Priority" : level.marks
        }
        return HoldSlidePicker(options: (1...Matrix.levels).map(String.init), title: "Importance") {
            importanceChoice = nil
            priorityChoice = level.next
        } onPick: { index in
            importanceChoice = index + 1
        } label: {
            chipLabel(title, symbol: level == .normal && importanceChoice == nil ? "exclamationmark" : nil,
                      color: importanceChoice.map { Matrix.priority(forImportance: Matrix.importance(forLevel: $0)).color } ?? level.color,
                      active: level != .normal || importanceChoice != nil)
        }
        .accessibilityLabel("Priority")
        .accessibilityValue(importanceChoice.map { "Importance \($0)" } ?? level.title)
        .accessibilityHint("Tap to raise, touch and hold and slide toward a number to pick an importance from 1 to 10")
    }

    static let estimateOptions = PowerHours.presets.map { PowerHours.number($0) } + ["Custom…"]

    private func pickEstimate(_ index: Int) {
        guard index < PowerHours.presets.count else {
            showCustomEstimate = true
            return
        }
        estimateChoice = PowerHours.presets[index]
        add()
    }

    /// Drag the + up between two tasks to add one right there (what's typed, or an empty line to
    /// type into). It moves at once, no hold needed; a ghost follows the finger. A tap just
    /// starts typing.
    private var insertHandle: some View {
        Image(systemName: subtaskParent != nil ? "arrow.turn.down.right" : "plus.circle.fill")
            .theoFont(.title2)
            .foregroundStyle(.tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: addedCount)
            .frame(minWidth: 30, minHeight: 30)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { drag in
                        if app.insertDragLocation == nil {
                            let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            app.insertDragTitle = isMultiline ? "" : (typed.isEmpty ? "" : dragEntry.title)
                        }
                        app.insertDragLocation = drag.location
                    }
                    .onEnded { drag in
                        app.insertDragLocation = nil
                        dropBetween(at: drag.location)
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: app.insertDragLocation != nil) { _, new in new }
            .accessibilityLabel("New task")
            .accessibilityHint("Drag up between two tasks to add one there")
    }

    /// What the dragged + carries: the text read without "@group" (where it's dropped decides
    /// the group, so a typed "@home" stays in the title) plus the picks from the chips. A held
    /// importance travels as its priority band, a matrix cell as its band and deadline.
    private var dragEntry: ParsedEntry {
        let source = Composer.subtaskBody(text) ?? text
        var entry = QuickParser.parse(source, groups: groupRefs, options: options.subtracting(.group), now: app.dayStart)
        entry.groupID = nil
        entry.groupName = nil
        if let priorityChoice { entry.priority = priorityChoice }
        switch dueChoice {
        case .fromText:
            break
        case .cleared:
            entry.due = nil
            entry.dueHasTime = false
        case .date(let date):
            entry.due = date
            entry.dueHasTime = false
        }
        if let estimateChoice { entry.estimate = estimateChoice }
        switch recurrenceChoice {
        case .fromText: break
        case .never: entry.recurrence = nil
        case .set(let recurrence): entry.recurrence = recurrence
        }
        if let matrixChoice {
            entry.priority = Matrix.priority(forImportance: Matrix.importance(forLevel: matrixChoice.level))
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: app.dayStart)
            entry.due = matrixChoice.days.map { calendar.date(byAdding: .day, value: $0, to: today) ?? today }
            entry.dueHasTime = false
        } else if let importanceChoice {
            entry.priority = Matrix.priority(forImportance: Matrix.importance(forLevel: importanceChoice))
        }
        return entry
    }

    private func dropBetween(at location: CGPoint) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry: ParsedEntry? = !typed.isEmpty && !isMultiline ? dragEntry : nil
        guard app.insertHandler?(location, entry) == true else { return }
        if entry != nil {
            text = ""
            resetChoices()
        }
    }

    private var dueChip: some View {
        let due = effectiveDue
        return Menu {
            ForEach(QuickDate.allCases) { quick in
                Button {
                    dueChoice = .date(quick.date(from: app.dayStart))
                } label: {
                    Label(quick.title, systemImage: quick.symbol)
                }
            }
            if due != nil {
                Divider()
                Button(role: .destructive) {
                    // A date read from the text gives its words back to the title.
                    if dueFromText {
                        disabled.formUnion([.dates, .exactDates])
                    } else {
                        dueChoice = .cleared
                    }
                } label: {
                    Label("No Deadline", systemImage: "calendar.badge.minus")
                }
            }
        } label: {
            chipLabel(dueTitle, symbol: "calendar", color: .orange, active: due != nil)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Deadline")
    }

    /// "Date", "Tomorrow", or for a date read from the text the words it took and the day they
    /// mean: "bis Freitag → Fri 13 Nov".
    private var dueTitle: String {
        guard let due = effectiveDue else { return "Date" }
        guard dueFromText, let words = chipEntry.dueText else {
            return DateText.due(due.date, hasTime: due.hasTime, today: app.dayStart)
        }
        let shown = words.count > 28 ? String(words.prefix(27)) + "…" : words
        var day = DateText.shortDay(due.date)
        if due.hasTime { day += " " + due.date.formatted(date: .omitted, time: .shortened) }
        return "\(shown) → \(day)"
    }

    private var groupChip: some View {
        let id = targetGroupID
        let group = groups.first { $0.uuid == id }
        return Menu {
            Button {
                groupChoice = .quickEntry
                disabled.insert(.group)
            } label: {
                Label("Quick Entry", systemImage: "tray.and.arrow.down")
            }
            ForEach(GroupTree.ordered(groups), id: \.group.uuid) { item in
                Button {
                    groupChoice = .group(item.group.uuid)
                    disabled.insert(.group)
                } label: {
                    Label(GroupTree.path(of: item.group, in: groups), systemImage: item.group.symbol)
                }
            }
        } label: {
            chipLabel(
                groupName(id),
                symbol: group?.symbol ?? "tray.and.arrow.down",
                color: group?.color.color ?? .secondary,
                active: id != defaultGroupID
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Group")
    }

    private var estimateChip: some View {
        let value = effectiveEstimate
        return Menu {
            ForEach(PowerHours.presets, id: \.self) { preset in
                Button {
                    estimateChoice = preset
                } label: {
                    Label(PowerHours.format(preset), systemImage: preset == value ? "checkmark" : "timer")
                }
            }
            Button {
                showCustomEstimate = true
            } label: {
                Label("Custom…", systemImage: "slider.horizontal.3")
            }
            if value > 0 {
                Divider()
                Button(role: .destructive) {
                    estimateChoice = 0
                } label: {
                    Label("No Estimate", systemImage: "xmark.circle")
                }
            }
        } label: {
            // The default shows dimmed; a picked or typed estimate in colour.
            chipLabel(value > 0 ? PowerHours.format(value) : "No PH", symbol: "timer", color: .teal, active: chosenEstimate != nil && value > 0)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Estimate in Power Hours")
    }

    private var repeatChip: some View {
        let recurrence = effectiveRecurrence
        return Menu {
            ForEach(Recurrence.common, id: \.self) { option in
                Button {
                    recurrenceChoice = .set(option)
                } label: {
                    Label(option.title, systemImage: option == recurrence ? "checkmark" : "repeat")
                }
            }
            if recurrence != nil {
                Divider()
                Button(role: .destructive) {
                    // A repeat read from the text gives its words back to the title.
                    if repeatFromText {
                        disabled.insert(.recurrence)
                    } else {
                        recurrenceChoice = .never
                    }
                } label: {
                    Label("Don't Repeat", systemImage: "xmark.circle")
                }
            }
        } label: {
            chipLabel(recurrence.map { $0.title(firstDue: effectiveDue?.date) } ?? "Repeat", symbol: "repeat", color: .indigo, active: recurrence != nil)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Repeat")
    }

    /// Drag it onto the full-screen grid; tapping only explains it, so it never gets in the way.
    private var matrixHandle: some View {
        Image(systemName: "square.grid.3x3")
            .theoFont(.body, weight: .medium)
            .foregroundStyle(matrixChoice == nil ? Color.secondary.opacity(0.7) : Color.accentColor)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        let title = parsed.title.trimmingCharacters(in: .whitespaces)
                        app.matrixDrag = MatrixDrag(title: title, location: value.location)
                    }
                    .onEnded { value in
                        dropOnMatrix(at: value.location)
                    }
            )
            .onTapGesture {
                app.show("Drag the grid handle to set when it's due and how important it is", symbol: "square.grid.3x3")
            }
            .accessibilityLabel("Urgency and importance")
            .accessibilityHint("Drag onto the grid to set the deadline and importance")
    }

    private func dropOnMatrix(at location: CGPoint) {
        let frame = app.matrixCanvasFrame
        app.matrixDrag = nil
        guard frame.width > 0, frame.contains(location) else { return }
        matrixChoice = MatrixGeometry.cell(at: CGPoint(x: location.x - frame.minX, y: location.y - frame.minY), in: frame.size)
        // Dropping a typed task files it right away; without text it sets up the next one.
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { add() }
    }

    private func removableChip(_ title: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        Button(action: onRemove) {
            chipLabel(title, symbol: nil, color: color, active: true, removable: true)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, symbol: String?, color: Color, active: Bool, removable: Bool = false) -> some View {
        let glass: Glass = active ? Glass.regular.tint(color.opacity(0.15)).interactive() : Glass.regular.interactive()
        return HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(title)
                .lineLimit(1)
            if removable { Image(systemName: "xmark").imageScale(.small).opacity(0.6) }
        }
        .theoFont(.caption, weight: .semibold)
        .foregroundStyle(active ? color : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(glass, in: .capsule)
    }

    private func confirmationRow(_ confirmation: Confirmation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
            Text(confirmation.message)
                .theoFont(.footnote, weight: .medium)
                .lineLimit(2)
            Spacer(minLength: 4)
            HStack(spacing: 12) {
                if confirmation.offersOffPlan, let task = confirmation.tasks.first {
                    Button("Off Plan") {
                        app.plan([task], for: nil)
                        self.confirmation = nil
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Takes it off today's plan; it stays due on its day")
                }
                if confirmation.showsReveal, let task = confirmation.tasks.first {
                    Button("Show") {
                        app.reveal(task)
                    }
                }
                Button("Undo") {
                    undo(confirmation)
                }
            }
            .theoFont(.footnote, weight: .semibold)
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    // MARK: - Actions

    private func focusNow() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            focused = true
            app.wantsQuickEntryFocus = false
        }
    }

    private func add() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            focused = false
            return
        }
        let created: [TaskItem]
        var parent: TaskItem?
        if raw.contains(where: \.isNewline) {
            created = addLines(Self.openLines(Composer.lines(raw)))
        } else {
            var entry = parsed
            guard !entry.title.isEmpty else { return }
            entry.priority = effectivePriority
            entry.due = effectiveDue?.date
            entry.dueHasTime = effectiveDue?.hasTime ?? false
            entry.estimate = chosenEstimate
            entry.recurrence = effectiveRecurrence
            // Something that repeats needs a first date: today.
            if entry.recurrence != nil && entry.due == nil {
                entry.due = Calendar.current.startOfDay(for: app.dayStart)
            }
            if let subtaskParent {
                let task = withAnimation(.snappy) { app.store.addSubtask(entry, to: subtaskParent) }
                if app.collapsedTaskIDs.contains(subtaskParent.uuid) { app.toggleSubtasks(subtaskParent) }
                created = [task]
                parent = subtaskParent
            } else {
                let groupID = targetGroupID
                entry.groupID = groupID
                let placement = NewTaskPlacement(rawValue: placementRaw) ?? .bottom
                let task = withAnimation(.snappy) { app.store.addTask(entry, defaultGroupID: groupID, placement: placement) }
                lastParent = task
                created = [task]
            }
        }
        guard !created.isEmpty else { return }
        for task in created {
            if let group = task.group, group.isCollapsed { app.store.setCollapsed(group, false) }
            if let matrixChoice {
                app.store.placeOnMatrix(task, days: matrixChoice.days, level: matrixChoice.level, today: app.dayStart)
            } else if let importanceChoice {
                app.store.setImportance([task], Matrix.importance(forLevel: importanceChoice))
            }
            if let plansFor { app.store.plan([task], for: plansFor) }
        }
        show(makeConfirmation(for: created, under: parent))
        addedCount += 1
        text = ""
        resetChoices()
        // The group stays picked while adding several tasks; keep the keyboard up for rapid entry.
        focused = true
    }

    /// "Added to Work · due Friday · !!" for one task (what was understood, read back from the
    /// task itself), with Show; "Added 3 tasks" for a list. A task planned for today that's due
    /// on a later day says "on today" and offers to take it off the plan.
    private func makeConfirmation(for created: [TaskItem], under parent: TaskItem?) -> Confirmation {
        guard created.count == 1, let task = created.first else {
            return Confirmation(message: "Added \(created.count) tasks", tasks: created)
        }
        let summary = CaptureSummary.describe(
            groupName: parent == nil ? groupName(task.groupID) : nil,
            due: task.dueDate,
            dueHasTime: task.dueHasTime,
            today: app.dayStart,
            priority: task.priority,
            estimate: task.estimate,
            defaultEstimate: app.store.traits(of: task.group).estimate ?? PowerHours.defaultForNewTasks,
            recurrence: task.recurrence,
            ongoing: task.isOngoing
        )
        var message: String
        if let parent {
            message = "Added under “\(parent.trimmedTitle)”" + (summary.isEmpty ? "" : " · " + summary)
        } else {
            message = "Added to " + summary
        }
        let plansToday = plansFor.map { DateText.dayDelta($0, today: app.dayStart) == 0 } ?? false
        let dueLater = task.dueDate.map { DateText.dayDelta($0, today: app.dayStart) > 0 } ?? false
        let offersOffPlan = plansToday && dueLater
        if offersOffPlan { message += " · on today" }
        return Confirmation(message: message, tasks: created, showsReveal: true, offersOffPlan: offersOffPlan)
    }

    private func resetChoices() {
        disabled = []
        priorityChoice = nil
        importanceChoice = nil
        dueChoice = .fromText
        estimateChoice = nil
        recurrenceChoice = .fromText
        matrixChoice = nil
        subtaskOff = false
    }

    /// A pasted list: each line is a task, indented lines become subtasks of the line above.
    /// What's picked on the chips applies to every line; otherwise each line keeps what it says.
    private func addLines(_ lines: [Composer.Line]) -> [TaskItem] {
        var created: [TaskItem] = []
        var parents: [TaskItem] = []
        withAnimation(.snappy) {
            for line in lines {
                var entry = QuickParser.parse(line.title, groups: groupRefs, options: options, now: app.dayStart)
                guard !entry.title.isEmpty else { continue }
                if let priorityChoice { entry.priority = priorityChoice }
                // 0 stays "no estimate" instead of falling back to the default.
                if let estimateChoice { entry.estimate = estimateChoice }
                switch dueChoice {
                case .fromText:
                    break
                case .cleared:
                    entry.due = nil
                    entry.dueHasTime = false
                case .date(let date):
                    entry.due = date
                    entry.dueHasTime = false
                }
                switch recurrenceChoice {
                case .fromText: break
                case .never: entry.recurrence = nil
                case .set(let recurrence): entry.recurrence = recurrence
                }
                // Something that repeats needs a first date: today.
                if entry.recurrence != nil && entry.due == nil {
                    entry.due = Calendar.current.startOfDay(for: app.dayStart)
                }
                let task: TaskItem
                if line.level > 0, line.level <= parents.count {
                    task = app.store.addSubtask(entry, to: parents[line.level - 1])
                } else {
                    let groupID = entry.groupID ?? baseGroupID
                    entry.groupID = groupID
                    task = app.store.addTask(entry, defaultGroupID: groupID, placement: .bottom)
                }
                parents = Array(parents.prefix(line.level)) + [task]
                created.append(task)
            }
        }
        // "- " lines typed next go under the last top-level task of the list.
        if let last = created.last(where: { $0.indent == 0 }) { lastParent = last }
        return created
    }

    private func show(_ confirmation: Confirmation) {
        self.confirmation = confirmation
        let id = confirmation.id
        let seconds = confirmation.hasExtraButtons ? 5.0 : 4.0
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if self.confirmation?.id == id { self.confirmation = nil }
        }
    }

    private func undo(_ confirmation: Confirmation) {
        withAnimation(.snappy) { app.store.purge(confirmation.tasks) }
        if let lastParent, confirmation.tasks.contains(where: { $0 === lastParent }) { self.lastParent = nil }
        self.confirmation = nil
    }
}

/// One pick above the composer: a group (its colour and path) or a tag (how many open tasks
/// have it).
private struct ComposerSuggestion: Identifiable {
    let id: String
    /// "Work › Admin" or "#invoices".
    let title: String
    /// What replaces the word being typed: "@Work/Admin", "#invoices".
    let insertion: String
    let color: Color
    let isGroup: Bool
    /// Open tasks with the tag.
    let count: Int?
    /// A switched-off group.
    let dimmed: Bool

    var accessibilityText: String {
        if isGroup { return dimmed ? title + ", switched off" : title }
        let tasks = count == 1 ? "1 open task" : "\(count ?? 0) open tasks"
        return title + ", " + tasks
    }
}

/// The `@group` / `#tag` picks while one is typed: a tap puts it in the text. Scrolls sideways
/// when there's no room; on the Mac the highlighted one is what Tab or Return takes.
private struct ComposerSuggestionStrip: View {
    let items: [ComposerSuggestion]
    let highlightedID: String?
    let onPick: (ComposerSuggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    pickButton(item)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func pickButton(_ item: ComposerSuggestion) -> some View {
        Button {
            onPick(item)
        } label: {
            ComposerSuggestionLabel(item: item, highlighted: item.id == highlightedID)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityText)
        .accessibilityHint(item.isGroup ? "Files the task in this group" : "Adds this tag")
    }
}

/// A capsule like the chips: colour dot and path for a group, the tag and its count for a tag.
private struct ComposerSuggestionLabel: View {
    let item: ComposerSuggestion
    let highlighted: Bool

    var body: some View {
        let glass: Glass = highlighted ? Glass.regular.tint(Color.accentColor.opacity(0.25)).interactive() : Glass.regular.interactive()
        let ring: Color = highlighted ? Color.accentColor.opacity(0.7) : Color.clear
        return HStack(spacing: 5) {
            if item.isGroup {
                Circle()
                    .fill(item.color)
                    .frame(width: 8, height: 8)
            }
            Text(item.title)
                .lineLimit(1)
                .foregroundStyle(item.isGroup ? Color.primary : item.color)
            if let count = item.count {
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
        }
        .theoFont(.caption, weight: .semibold)
        .opacity(item.dimmed ? 0.5 : 1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(glass, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(ring, lineWidth: 1.5)
        }
        .contentShape(Capsule())
    }
}
