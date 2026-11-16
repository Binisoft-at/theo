import SwiftUI
import SwiftData
import TheoCore

struct DayRef: Hashable, Identifiable {
    let start: Date

    var id: Date { start }
}

/// Past daily pages, grouped like the Notes list (Yesterday, Previous 7 Days, months …).
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var tasks: [TaskItem]

    private struct DaySummary: Identifiable {
        let start: Date
        var done: [TaskItem] = []
        var added = 0
        var id: Date { start }
    }

    private struct Bucket: Identifiable {
        let title: String
        var days: [DaySummary]
        var id: String { title }
    }

    private func summarize() -> [Date: DaySummary] {
        let boundary = DayBoundary.current
        var summaries: [Date: DaySummary] = [:]
        for task in tasks {
            if task.isDone, let completed = task.completedAt {
                let day = boundary.start(of: completed)
                summaries[day, default: DaySummary(start: day)].done.append(task)
            }
            let created = boundary.start(of: task.createdAt)
            summaries[created, default: DaySummary(start: created)].added += 1
        }
        return summaries
    }

    var body: some View {
        let boundary = DayBoundary.current
        let today = app.dayStart
        let summaries = summarize()
        let past = summaries.values.filter { $0.start < today }.sorted { $0.start > $1.start }
        let buckets = Self.bucket(past, today: today)
        let streak = Self.streak(summaries: summaries, today: today)
        let weekDone = summaries.values.filter { $0.start > boundary.dayStart(byAdding: -7, to: today) }.reduce(0) { $0 + $1.done.count }

        List {
            Section {
                HStack(spacing: 12) {
                    StatTile(value: "\(streak)", label: "day streak", symbol: "flame.fill", color: .orange)
                    StatTile(value: "\(weekDone)", label: "done in 7 days", symbol: "checkmark.seal.fill", color: .green)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            if buckets.isEmpty {
                Text("Completed tasks are kept here day by day, like your old daily notes.")
                    .foregroundStyle(.secondary)
            }
            ForEach(buckets) { bucket in
                Section(bucket.title) {
                    ForEach(bucket.days) { day in
                        NavigationLink(value: DayRef(start: day.start)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(DateText.pageTitle(day.start))
                                    .theoFont(.headline)
                                // "3 done · 0,75 PH" in grey, then what got done, lighter.
                                let line = preview(day)
                                Text("\(Text(line.summary).foregroundStyle(.secondary))\(Text(line.titles).foregroundStyle(.tertiary))")
                                    .theoFont(.subheadline)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }

    /// "3 done · 0,75 PH" and " · Water plants, Call the garage, …" (or "2 added" on a day
    /// where nothing got done).
    private func preview(_ day: DaySummary) -> (summary: String, titles: String) {
        let titles = day.done.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .map(\.trimmedTitle).filter { !$0.isEmpty }
        if titles.isEmpty { return ("\(day.added) added", "") }
        let powerHours = PageBuilder.estimateTotals(day.done).done
        let effort = powerHours > 0 ? " · " + PowerHours.format(powerHours) : ""
        return ("\(titles.count) done\(effort)", " · " + titles.prefix(6).joined(separator: ", "))
    }

    private static func bucket(_ days: [DaySummary], today: Date) -> [Bucket] {
        let boundary = DayBoundary.current
        var buckets: [Bucket] = []
        func append(_ title: String, _ day: DaySummary) {
            if let index = buckets.firstIndex(where: { $0.title == title }) {
                buckets[index].days.append(day)
            } else {
                buckets.append(Bucket(title: title, days: [day]))
            }
        }
        let yesterday = boundary.dayStart(byAdding: -1, to: today)
        let week = boundary.dayStart(byAdding: -7, to: today)
        let month = boundary.dayStart(byAdding: -30, to: today)
        for day in days {
            if day.start >= yesterday {
                append("Yesterday", day)
            } else if day.start >= week {
                append("Previous 7 Days", day)
            } else if day.start >= month {
                append("Previous 30 Days", day)
            } else {
                append(day.start.formatted(.dateTime.month(.wide).year()), day)
            }
        }
        return buckets
    }

    private static func streak(summaries: [Date: DaySummary], today: Date) -> Int {
        let boundary = DayBoundary.current
        var count = 0
        var day = today
        if (summaries[day]?.done.isEmpty ?? true) {
            day = boundary.dayStart(byAdding: -1, to: day)
        }
        while let summary = summaries[day], !summary.done.isEmpty {
            count += 1
            day = boundary.dayStart(byAdding: -1, to: day)
        }
        return count
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .theoFont(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .theoFont(.title2, weight: .bold)
                    .monospacedDigit()
                Text(label)
                    .theoFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color.opacity(0.1)))
    }
}

/// A past day: first what got done, group by group in the order it happened; then, folded
/// away, what was still open when the day ended. Today's plans can't tell what was planned
/// back then, so that list holds every task open at the day's end in groups that are on, the
/// ones whose deadline had come by then first.
struct DayPageView: View {
    let day: DayRef

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @State private var showsOpen = false

    var body: some View {
        let start = day.start
        let end = DayBoundary.current.end(ofDayStarting: start)
        let doneThatDay = tasks.filter { task in
            guard task.isDone, let completed = task.completedAt else { return false }
            return completed >= start && completed < end
        }
        let doneSections: [LabeledSection] = Sections.byGroup(doneThatDay, groups: groups)
            .filter { !$0.tasks.isEmpty }
            .map { section -> LabeledSection in
                let byTime = section.tasks.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
                return (key: section.key, title: section.title, symbol: section.symbol, color: section.color, tasks: byTime)
            }
        // Open when the day ended. An ongoing task never finishes (its logs count as done that
        // day), so it isn't "still open".
        let openAtEnd = tasks.activeOnly(groups).filter { task in
            guard task.createdAt < end, !(task.isOngoing && task.loggedFor == nil) else { return false }
            if let completed = task.completedAt { return completed >= end }
            return !task.isDone
        }
        let open = Self.ordered(openAtEnd, day: start)
        let overdue = open.filter { Self.wasDue($0, by: start) }
        let overdueIDs = Set(overdue.map(ObjectIdentifier.init))
        let openTitle = overdue.isEmpty
            ? "\(open.count) still open at day's end"
            : "\(open.count) still open at day's end · \(overdue.count) overdue"

        List {
            Section {
                HStack(spacing: 12) {
                    StatTile(value: "\(doneThatDay.count)", label: "completed", symbol: "checkmark.circle.fill", color: .green)
                    StatTile(value: "\(open.count)", label: "still open", symbol: "circle.dashed", color: .orange)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            if doneSections.isEmpty {
                Text("Nothing was checked off that day.")
                    .foregroundStyle(.secondary)
            }
            ForEach(doneSections, id: \.key) { section in
                Section {
                    ForEach(section.tasks) { task in
                        HistoryTaskRow(task: task, doneThen: true, dayEnd: end, today: app.dayStart)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Label(section.title, systemImage: section.symbol)
                            .foregroundStyle(section.color)
                        Spacer(minLength: 8)
                        let hours = PageBuilder.estimateTotals(section.tasks).done
                        if hours > 0 {
                            Text("Σ " + PowerHours.format(hours))
                                .theoFont(.subheadline, weight: .semibold)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("\(PowerHours.format(hours)) done")
                        }
                    }
                    .theoFont(.headline)
                    .textCase(nil)
                }
            }
            if !open.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $showsOpen) {
                        ForEach(open) { task in
                            HistoryTaskRow(task: task, doneThen: false, dayEnd: end, today: app.dayStart,
                                           dueByThen: overdueIDs.contains(ObjectIdentifier(task)))
                        }
                    } label: {
                        Label(openTitle, systemImage: "circle.dashed")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(DateText.pageTitle(start))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.reviewDay = day
                } label: {
                    Label("Review", systemImage: "chart.bar.xaxis")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: markdown(done: doneSections, overdue: overdue)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    /// Its deadline had come by that day (a task due that day and still open at its end counts).
    private static func wasDue(_ task: TaskItem, by start: Date) -> Bool {
        guard let due = task.dueDate else { return false }
        return DateText.dayDelta(due, today: start) <= 0
    }

    /// The ones whose deadline had come first (earliest deadline first), then the rest ranked
    /// as of that day.
    private static func ordered(_ tasks: [TaskItem], day start: Date) -> [TaskItem] {
        let keyed = tasks.map { (task: $0, due: wasDue($0, by: start), score: $0.matrixScore(today: start)) }
        return keyed.sorted { a, b in
            if a.due != b.due { return a.due }
            if a.due, let dueA = a.task.dueDate, let dueB = b.task.dueDate, dueA != dueB { return dueA < dueB }
            if a.score != b.score { return a.score > b.score }
            return a.task.sortOrder < b.task.sortOrder
        }
        .map { $0.task }
    }

    /// What got done, and what was overdue and still open at the day's end.
    private func markdown(done: [LabeledSection], overdue: [TaskItem]) -> String {
        var lines = ["# \(DateText.pageTitle(day.start))", ""]
        for section in done {
            lines.append("## \(section.title)")
            for task in section.tasks {
                lines.append("- [x] \(task.trimmedTitle)")
            }
            lines.append("")
        }
        if !overdue.isEmpty {
            lines.append("## Overdue, still open at the day's end")
            for task in overdue {
                lines.append("- [ ] \(task.trimmedTitle)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

struct HistoryTaskRow: View {
    let task: TaskItem
    let doneThen: Bool
    let dayEnd: Date
    let today: Date
    /// Still open then, with a deadline that had come by that day.
    var dueByThen = false

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: doneThen ? "checkmark.circle.fill" : "circle")
                .theoFont(.title3)
                .foregroundStyle(doneThen ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(task.trimmedTitle.isEmpty ? "Untitled" : task.trimmedTitle)
                        .theoBodyFont()
                        .strikethrough(doneThen, color: .secondary)
                        .foregroundStyle(doneThen ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                    if task.loggedFor != nil {
                        // A logged round of an ongoing task.
                        Image(systemName: "infinity")
                            .theoFont(.caption, weight: .semibold)
                            .foregroundStyle(.teal)
                            .accessibilityLabel("Ongoing")
                    }
                }
                if !doneThen {
                    HStack(spacing: 8) {
                        if let completed = task.completedAt {
                            Text("Done later · \(DateText.shortDay(completed))")
                                .foregroundStyle(.green)
                        } else {
                            Text("Still open")
                                .foregroundStyle(.orange)
                        }
                        if dueByThen, let due = task.dueDate {
                            Label("Due \(DateText.shortDay(due))", systemImage: "flag.checkered")
                                .foregroundStyle(.red)
                        }
                    }
                    .theoFont(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { app.detailTask = task }
    }
}

/// Recently Deleted, like in Notes: restore or remove for good. Items expire after 30 days.
/// Subtasks deleted together with their parent show under it and come back with it. Logs of
/// ongoing tasks (taken back when their check was undone) stay out of the list.
struct TrashView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt != nil })
    private var tasks: [TaskItem]
    /// The tasks still there, to tell where each deleted line sat in its list.
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var liveTasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt != nil })
    private var groups: [TaskGroup]
    @State private var confirmEmpty = false

    /// A deleted task, how deep it sits under lines deleted with it, and the lines shown under
    /// it (they come back and go away with it).
    private struct TrashRow: Identifiable {
        let task: TaskItem
        let depth: Int
        var block: [TaskItem]

        var id: ObjectIdentifier { ObjectIdentifier(task) }
    }

    /// Newest delete first. Within one delete (same list, same moment) the lines keep their
    /// list order and a subtask sits under its parent when the parent went with it: what
    /// `TaskStore.restoreWithBlock` brings back together.
    private func trashRows() -> [TrashRow] {
        let visible = tasks.filter { !$0.trimmedTitle.isEmpty && $0.loggedFor == nil }
        var batches: [[TaskItem]] = []
        for inList in Dictionary(grouping: visible, by: { $0.group?.uuid }).values {
            var current: [TaskItem] = []
            for task in inList.sorted(by: { ($0.deletedAt ?? .distantPast) < ($1.deletedAt ?? .distantPast) }) {
                if let head = current.first?.deletedAt, let deletedAt = task.deletedAt, deletedAt.timeIntervalSince(head) >= 1 {
                    batches.append(current)
                    current = []
                }
                current.append(task)
            }
            if !current.isEmpty { batches.append(current) }
        }
        let live = Dictionary(grouping: liveTasks, by: \.groupID)
        var deletes: [(deletedAt: Date, list: String, rows: [TrashRow])] = []
        for batch in batches {
            guard let first = batch.first else { continue }
            // The list as it was: what's still there plus what went in this delete.
            let listIsLive = first.group == nil || first.group?.deletedAt == nil
            let layout = SectionLayout((listIsLive ? (live[first.groupID] ?? []) : []) + batch)
            let inBatch = Set(batch.map(ObjectIdentifier.init))
            var shownDepth: [ObjectIdentifier: Int] = [:]
            var ancestors: [Int] = []
            var rows: [TrashRow] = []
            for index in layout.items.indices {
                let depth = layout.depths[index]
                while let last = ancestors.last, layout.depths[last] >= depth { ancestors.removeLast() }
                let item = layout.items[index]
                if inBatch.contains(ObjectIdentifier(item)) {
                    // Under its parent when that went in the same delete, else at the top.
                    let parentDepth = ancestors.last.flatMap { shownDepth[ObjectIdentifier(layout.items[$0])] }
                    let shown = parentDepth.map { $0 + 1 } ?? 0
                    shownDepth[ObjectIdentifier(item)] = shown
                    rows.append(TrashRow(task: item, depth: shown, block: [item]))
                }
                ancestors.append(index)
            }
            for i in rows.indices {
                var j = i + 1
                while j < rows.count, rows[j].depth > rows[i].depth {
                    rows[i].block.append(rows[j].task)
                    j += 1
                }
            }
            deletes.append((deletedAt: first.deletedAt ?? .distantPast, list: first.group?.uuid.uuidString ?? "", rows: rows))
        }
        // Deletes at the same moment (a group's lists) keep a fixed order between redraws.
        return deletes.sorted { ($0.deletedAt, $1.list) > ($1.deletedAt, $0.list) }.flatMap { $0.rows }
    }

    var body: some View {
        let items = trashRows()
        List {
            if !groups.isEmpty {
                Section("Groups") {
                    ForEach(groups) { group in
                        HStack {
                            Label(group.displayName, systemImage: group.symbol)
                                .foregroundStyle(group.color.color)
                            Spacer()
                            Text(remaining(group.deletedAt))
                                .theoFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                app.store.restoreGroup(group)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                app.store.purge([group])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("Restore") { app.store.restoreGroup(group) }
                            Button("Delete Permanently", role: .destructive) { app.store.purge([group]) }
                        }
                    }
                }
            }
            Section(groups.isEmpty ? "" : "Tasks") {
                ForEach(items) { row in
                    let task = row.task
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if row.depth > 0 {
                            Image(systemName: "arrow.turn.down.right")
                                .theoFont(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.trimmedTitle)
                                .foregroundStyle(row.depth > 0 ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                            if row.depth == 0, let line = caption(row) {
                                Text(line)
                                    .theoFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if row.depth == 0 {
                            Text(remaining(task.deletedAt))
                                .theoFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, CGFloat(row.depth) * 18)
                    .swipeActions(edge: .leading) {
                        Button {
                            app.store.restoreWithBlock([task])
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            app.store.purge(row.block)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Restore") { app.store.restoreWithBlock([task]) }
                        Button("Delete Permanently", role: .destructive) { app.store.purge(row.block) }
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty && groups.isEmpty {
                ContentUnavailableView("No Recently Deleted Items", systemImage: "trash",
                                       description: Text("Deleted tasks stay here for 30 days."))
            }
        }
        .navigationTitle("Recently Deleted")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Empty", role: .destructive) { confirmEmpty = true }
                    .disabled(items.isEmpty && groups.isEmpty)
            }
        }
        .confirmationDialog("Delete all items permanently?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                app.store.purge(Array(tasks))
                app.store.purge(Array(groups))
            }
        }
    }

    /// "Work · with 3 subtasks" under a top line.
    private func caption(_ row: TrashRow) -> String? {
        var parts: [String] = []
        if let group = row.task.group { parts.append(group.displayName) }
        let subtasks = row.block.count - 1
        if subtasks > 0 { parts.append(subtasks == 1 ? "with 1 subtask" : "with \(subtasks) subtasks") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func remaining(_ deletedAt: Date?) -> String {
        guard let deletedAt else { return "" }
        let days = max(0, 30 - (Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0))
        return days == 1 ? "1 day left" : "\(days) days left"
    }
}
