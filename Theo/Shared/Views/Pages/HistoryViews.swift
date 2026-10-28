import SwiftUI
import SwiftData

struct DayRef: Hashable {
    let start: Date
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
        let boundary = DayBoundary()
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
        let boundary = DayBoundary()
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
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    Text(day.start.formatted(date: .numeric, time: .omitted))
                                        .foregroundStyle(.secondary)
                                    Text(preview(day))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                .font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }

    private func preview(_ day: DaySummary) -> String {
        let titles = day.done.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .map(\.trimmedTitle).filter { !$0.isEmpty }
        if titles.isEmpty { return "\(day.added) added" }
        return "\(titles.count) done · " + titles.prefix(4).joined(separator: ", ")
    }

    private static func bucket(_ days: [DaySummary], today: Date) -> [Bucket] {
        let boundary = DayBoundary()
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
        let boundary = DayBoundary()
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
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color.opacity(0.1)))
    }
}

/// A past day reconstructed like the note looked at the end of that day: what got done,
/// and what was still open (and rolled over).
struct DayPageView: View {
    let day: DayRef

    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    var body: some View {
        let start = day.start
        let end = DayBoundary().end(ofDayStarting: start)
        let doneThatDay = tasks.filter { task in
            guard task.isDone, let completed = task.completedAt else { return false }
            return completed >= start && completed < end
        }
        let openAtEnd = tasks.filter { task in
            guard task.createdAt < end else { return false }
            if let completed = task.completedAt { return completed >= end }
            return !task.isDone
        }
        let sections = Sections.byGroup(doneThatDay + openAtEnd, groups: groups).filter { !$0.tasks.isEmpty }

        List {
            Section {
                HStack(spacing: 12) {
                    StatTile(value: "\(doneThatDay.count)", label: "completed", symbol: "checkmark.circle.fill", color: .green)
                    StatTile(value: "\(openAtEnd.count)", label: "rolled over", symbol: "arrow.uturn.forward.circle.fill", color: .orange)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            ForEach(sections, id: \.key) { section in
                Section {
                    let done = section.tasks.filter { doneThatDay.contains($0) }
                    let open = section.tasks.filter { !doneThatDay.contains($0) }
                    ForEach(open) { task in
                        HistoryTaskRow(task: task, doneThen: false, dayEnd: end, today: app.dayStart)
                    }
                    ForEach(done) { task in
                        HistoryTaskRow(task: task, doneThen: true, dayEnd: end, today: app.dayStart)
                    }
                } header: {
                    Label(section.title, systemImage: section.symbol)
                        .foregroundStyle(section.color)
                        .font(.headline)
                        .textCase(nil)
                }
            }
        }
        .navigationTitle(DateText.pageTitle(start))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: markdown(sections: sections, done: doneThatDay)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func markdown(sections: [LabeledSection], done: [TaskItem]) -> String {
        var lines = ["# \(DateText.pageTitle(day.start))", ""]
        for section in sections {
            lines.append("## \(section.title)")
            for task in section.tasks {
                lines.append("- [\(done.contains(task) ? "x" : " ")] \(task.trimmedTitle)")
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

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: doneThen ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(doneThen ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.trimmedTitle.isEmpty ? "Untitled" : task.trimmedTitle)
                    .strikethrough(doneThen, color: .secondary)
                    .foregroundStyle(doneThen ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                if !doneThen {
                    if let completed = task.completedAt {
                        Text("Done later · \(DateText.shortDay(completed))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Still open")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { app.detailTask = task }
    }
}

/// Recently Deleted, like in Notes: restore or remove for good. Items expire after 30 days.
struct TrashView: View {
    @Environment(AppModel.self) private var app
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt != nil })
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt != nil })
    private var groups: [TaskGroup]
    @State private var confirmEmpty = false

    private var visibleTasks: [TaskItem] {
        tasks.filter { !$0.trimmedTitle.isEmpty }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        let items = visibleTasks
        List {
            if !groups.isEmpty {
                Section("Groups") {
                    ForEach(groups) { group in
                        HStack {
                            Label(group.displayName, systemImage: group.symbol)
                                .foregroundStyle(group.color.color)
                            Spacer()
                            Text(remaining(group.deletedAt))
                                .font(.caption)
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
                ForEach(items) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.trimmedTitle)
                            if let group = task.group {
                                Text(group.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(remaining(task.deletedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            app.store.restore([task])
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            app.store.purge([task])
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Restore") { app.store.restore([task]) }
                        Button("Delete Permanently", role: .destructive) { app.store.purge([task]) }
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

    private func remaining(_ deletedAt: Date?) -> String {
        guard let deletedAt else { return "" }
        let days = max(0, 30 - (Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0))
        return days == 1 ? "1 day left" : "\(days) days left"
    }
}
