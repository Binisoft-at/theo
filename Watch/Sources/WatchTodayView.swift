import SwiftUI
import SwiftData
import TheoCore

/// Today's page, the same one as on iPhone: Quick Entry, then each group in page order.
/// Tap a task to check it off; finished tasks collect under "Done Today".
struct WatchTodayView: View {
    @Environment(WatchModel.self) private var model
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil }, sort: \TaskItem.sortOrder)
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]
    @AppStorage("watch.showDoneToday") private var showDone = false

    var body: some View {
        let page = tasks.activeOnly(groups).filter { $0.isOnPage(of: model.dayStart) }
        let sections = WatchPage.sections(page, groups: groups, dayStart: model.dayStart)
        let done = WatchPage.completed(page)
        List {
            Section {
                WatchProgressRow(
                    caption: model.dayStart.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
                    done: done.count,
                    total: page.count
                )
                WatchAddTaskRow(groupID: nil, plansFor: model.dayStart)
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        WatchTaskRow(task: row.task, depth: row.depth)
                    }
                } header: {
                    WatchSectionHeader(title: section.title, symbol: section.symbol, color: section.color)
                }
            }
            if sections.isEmpty && !page.isEmpty {
                Text("All done for today.")
                    .foregroundStyle(.secondary)
            }
            if !done.isEmpty {
                WatchDoneSection(tasks: done, isExpanded: $showDone)
            }
        }
        .navigationTitle("Today")
        .onAppear {
            guard model.opensFirstTask, let first = sections.first?.rows.first?.task else { return }
            model.opensFirstTask = false
            model.show(.task(first))
        }
        .overlay {
            if page.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Planned", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Plan your day on iPhone or Mac, or add a task above.")
                }
                .allowsHitTesting(false)
                .padding(.top, 60)
            }
        }
    }
}

/// "3 of 8 done" with a progress bar (top of Today and of project pages).
struct WatchProgressRow: View {
    let caption: String
    let done: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if total > 0 {
                Text("\(done) of \(total) done")
                    .font(.headline)
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(.accentColor)
            }
        }
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }
}

/// Finished tasks, collapsed by default. Tap one to bring it back.
struct WatchDoneSection: View {
    let tasks: [TaskItem]
    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Label("Done Today", systemImage: "checkmark.circle.fill")
                    Spacer()
                    Text("\(tasks.count)")
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if isExpanded {
                ForEach(tasks, id: \.uuid) { task in
                    WatchTaskRow(task: task, showGroup: true)
                }
            }
        }
    }
}
