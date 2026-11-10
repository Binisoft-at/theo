import SwiftUI
import SwiftData
import TheoCore

/// Pick what each day is for: choose a day, then tap tasks to plan them. Unfinished tasks
/// from earlier days, tasks due by then and the most important ones come first; everything
/// else follows by group.
struct PlanView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil && $0.isDone == false }, sort: \TaskItem.sortOrder)
    private var allOpen: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @State private var selected: Date?
    /// How "Browse All Tasks" is sorted into sections, which are open, and what's searched.
    @AppStorage("plan.browse") private var browseRaw = PlanBrowse.group.rawValue
    @State private var expanded: Set<String> = []
    @State private var browseSearch = ""

    /// Logical start of the selected day (defaults to today).
    private var day: Date { selected ?? app.dayStart }

    /// Groups that are switched off stay out of planning.
    private var openTasks: [TaskItem] { allOpen.activeOnly(groups) }

    var body: some View {
        let day = self.day
        let openTasks = self.openTasks
        let planned = rankedTop(openTasks.filter { $0.isPlanned(for: day) }, day: day)
        let rest = openTasks.filter { !$0.isPlanned(for: day) }
        let leftOver = rankedTop(rest.filter { $0.isLeftOver(before: day) }, day: day)
        let leftOverIDs = Set(leftOver.map(\.uuid))
        let due = rankedTop(rest.filter { task in
            guard !leftOverIDs.contains(task.uuid), let date = task.dueDate else { return false }
            return DateText.dayDelta(date, today: day) <= 0
        }, day: day)
        let suggested = leftOverIDs.union(due.map(\.uuid))
        // Ongoing work, to pick for the day (it never finishes, so it's always on offer).
        let ongoing = rankedTop(rest.filter { $0.isOngoing && !suggested.contains($0.uuid) }, day: day)
        let important = Array(rankedTop(rest.filter { !suggested.contains($0.uuid) && $0.plannedDay == nil && !$0.isOngoing }, day: day).prefix(5))

        VStack(spacing: 0) {
            DayStrip(selected: day, tasks: openTasks) { selected = $0 }
            List {
                Section {
                    summary(planned: planned, day: day)
                }
                Section {
                    if planned.isEmpty {
                        Text("Nothing planned yet. Tap a task below to add it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(planned, id: \.uuid) { task in
                        PlanRow(task: task, isPlanned: true, day: day)
                    }
                } header: {
                    Text(dayTitle(day))
                }
                if !leftOver.isEmpty {
                    section("Unfinished from earlier", tasks: leftOver, day: day)
                }
                if !due.isEmpty {
                    section("Due by then", tasks: due, day: day)
                }
                if !ongoing.isEmpty {
                    section("Ongoing", tasks: ongoing, day: day)
                }
                if !important.isEmpty {
                    section("Most important", tasks: important, day: day)
                }
                let shownAbove = suggested.union(important.map(\.uuid)).union(ongoing.map(\.uuid))
                browseSections(rest.filter { !shownAbove.contains($0.uuid) }, day: day)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
        .navigationTitle("Plan")
        .safeAreaInset(edge: .bottom) {
            QuickEntryBar(defaultGroupID: nil, placeholder: "Add a task for \(shortDay(day))", plansFor: day)
        }
    }

    private func summary(planned: [TaskItem], day: Date) -> some View {
        let estimate = PageBuilder.estimateTotals(planned).open
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateText.pageTitle(day))
                    .font(.headline)
                Text(planned.isEmpty ? "Nothing planned" : "\(planned.count) planned" + (estimate > 0 ? " · " + PowerHours.format(estimate) : ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !Calendar.current.isDate(day, inSameDayAs: app.dayStart) {
                Button("Today") { selected = nil }
                    .buttonStyle(.glass)
            }
        }
    }

    private func section(_ title: String, tasks: [TaskItem], day: Date) -> some View {
        Section {
            ForEach(tasks, id: \.uuid) { task in
                PlanRow(task: task, isPlanned: false, day: day)
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button("Add All") {
                    withAnimation(.snappy) { app.plan(tasks, for: day) }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Browse All Tasks

    /// Top-level lines among `tasks` (matching the search), with their block's numbers.
    private func browseData(_ tasks: [TaskItem], needle: String) -> (shown: [TaskItem], styles: [UUID: RowStyle]) {
        var styles: [UUID: RowStyle] = [:]
        var roots: [TaskItem] = []
        for section in Dictionary(grouping: allOpen.activeOnly(groups), by: \.groupID).values {
            for row in PageBuilder.taskRows(section, options: PageBuilder.Options()) {
                guard case .task(let task, let depth, let style) = row, depth == 0 else { continue }
                styles[task.uuid] = style
                roots.append(task)
            }
        }
        let wanted = Set(tasks.map(\.uuid))
        let shown = roots.filter { wanted.contains($0.uuid) && (needle.isEmpty || $0.trimmedTitle.lowercased().contains(needle)) }
        return (shown, styles)
    }

    /// A line's Power Hours: its subtasks' total when it has them, else its own.
    private static func hours(_ task: TaskItem, _ styles: [UUID: RowStyle]) -> Double {
        if let style = styles[task.uuid], style.subtaskCount > 0, style.blockEstimate > 0 { return style.blockEstimate }
        return task.estimate
    }

    /// Every other open task, a section per group (or priority, deadline, size). Only top-level
    /// lines are listed, with their subtasks counted and their Power Hours added up; planning
    /// one plans its subtasks too. Sections open on tap; a search opens them all.
    @ViewBuilder
    private func browseSections(_ tasks: [TaskItem], day: Date) -> some View {
        let browse = PlanBrowse(rawValue: browseRaw) ?? .group
        let needle = browseSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let data = browseData(tasks, needle: needle)
        let sections = browse.sections(data.shown, groups: groups.activeOnly, today: day).filter { !$0.tasks.isEmpty }

        Section {
            Picker("Browse by", selection: $browseRaw) {
                ForEach(PlanBrowse.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            TextField("Search all tasks", text: $browseSearch)
        } header: {
            Text("Browse All Tasks · \(data.shown.count)")
        } footer: {
            Text("Tap a section to open it, then tap a task to plan it (its subtasks come along).")
        }
        ForEach(sections, id: \.key) { section in
            let isOpen = !needle.isEmpty || expanded.contains(section.key)
            let hours = section.tasks.reduce(0) { $0 + Self.hours($1, data.styles) }
            Section {
                if isOpen {
                    ForEach(rankedTop(section.tasks, day: day), id: \.uuid) { task in
                        PlanRow(task: task, isPlanned: false, day: day, style: data.styles[task.uuid])
                    }
                }
            } header: {
                Button {
                    withAnimation(.snappy) {
                        if expanded.contains(section.key) { expanded.remove(section.key) } else { expanded.insert(section.key) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.symbol)
                            .foregroundStyle(section.color)
                        Text(section.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(hours > 0 ? "\(section.tasks.count) · \(PowerHours.format(hours))" : "\(section.tasks.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Highest score first.
    private func rankedTop(_ tasks: [TaskItem], day: Date) -> [TaskItem] {
        tasks.sorted { $0.matrixScore(today: day) > $1.matrixScore(today: day) }
    }

    private func dayTitle(_ day: Date) -> String {
        switch DateText.dayDelta(day, today: app.dayStart) {
        case 0: "Planned for today"
        case 1: "Planned for tomorrow"
        default: "Planned for " + day.formatted(.dateTime.weekday(.wide))
        }
    }

    private func shortDay(_ day: Date) -> String {
        switch DateText.dayDelta(day, today: app.dayStart) {
        case 0: "today"
        case 1: "tomorrow"
        default: day.formatted(.dateTime.weekday(.wide))
        }
    }
}

/// The next two weeks; each day shows how much is planned.
struct DayStrip: View {
    let selected: Date
    let tasks: [TaskItem]
    let onSelect: (Date) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<15, id: \.self) { offset in
                    let day = DayBoundary.current.dayStart(byAdding: offset, to: app.dayStart)
                    let planned = tasks.filter { $0.isPlanned(for: day) }
                    let estimate = PageBuilder.estimateTotals(planned).open
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selected)
                    Button {
                        withAnimation(.snappy) { onSelect(day) }
                    } label: {
                        VStack(spacing: 2) {
                            Text(offset == 0 ? "Today" : day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption.weight(.semibold))
                            Text(day.formatted(.dateTime.day()))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                            Text(planned.isEmpty ? " " : (estimate > 0 ? PowerHours.number(estimate) : "\(planned.count)"))
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                        }
                        .frame(width: 54, height: 64)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.1)))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(planned.isEmpty ? "Nothing planned" : "\(planned.count) planned")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

/// A task in the planner: tap it to put it on (or take it off) the selected day.
struct PlanRow: View {
    let task: TaskItem
    let isPlanned: Bool
    let day: Date
    /// Subtask count and Power Hours total for a top-level line.
    var style: RowStyle?

    @Environment(AppModel.self) private var app

    private var rowStyle: RowStyle {
        var value = style ?? RowStyle()
        value.showGroup = true
        return value
    }

    var body: some View {
        Button {
            withAnimation(.snappy) { app.store.plan([task], for: isPlanned ? nil : day) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isPlanned ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isPlanned ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if task.priority != .normal {
                            Text(task.priority.marks)
                                .font(.body.weight(.heavy))
                                .foregroundStyle(task.priority.color)
                        }
                        Text(task.trimmedTitle.isEmpty ? "New Task" : task.trimmedTitle)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    TaskMetaLine(task: task, style: rowStyle, today: app.dayStart, showAge: false)
                    if let style, style.subtaskCount > 0 {
                        Text("\(style.subtaskCount - style.subtasksDone) of \(style.subtaskCount) subtasks open")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let planned = task.plannedDay, !isPlanned {
                    Text(DateText.due(planned, hasTime: false, today: app.dayStart))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isPlanned)
        .accessibilityHint(isPlanned ? "Takes it off this day" : "Plans it for this day")
    }
}

/// How Plan's "Browse All Tasks" is split into sections.
enum PlanBrowse: String, CaseIterable, Identifiable {
    case group, priority, deadline, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .group: "Group"
        case .priority: "Priority"
        case .deadline: "Deadline"
        case .size: "Size"
        }
    }

    func sections(_ tasks: [TaskItem], groups: [TaskGroup], today: Date) -> [LabeledSection] {
        switch self {
        case .group:
            // Every group and subgroup on its own, in sidebar order, named with its path.
            var result: [LabeledSection] = [
                (key: "quick", title: "Quick Entry", symbol: "tray.and.arrow.down.fill", color: .teal, tasks: tasks.filter { $0.groupID == nil })
            ]
            for item in GroupTree.ordered(groups) {
                result.append((key: item.group.uuid.uuidString, title: GroupTree.path(of: item.group, in: groups), symbol: item.group.symbol,
                               color: item.group.color.color, tasks: tasks.filter { $0.groupID == item.group.uuid }))
            }
            return result
        case .priority:
            return Sections.byPriority(tasks, groups: groups, includeNone: true)
        case .deadline:
            return Sections.byDeadline(tasks, groups: groups, today: today, includeNone: true)
        case .size:
            return Sections.bySize(tasks)
        }
    }
}
