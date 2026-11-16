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
                allDone
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
                    Label {
                        Text("Nothing Planned")
                    } icon: {
                        Image(systemName: "calendar.badge.plus")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Tint.planned)
                    }
                } description: {
                    Text("Plan your day on iPhone or Mac, or add a task above.")
                }
                .allowsHitTesting(false)
                .padding(.top, 60)
                .transition(.opacity)
            }
        }
    }

    /// Everything on today's plan is checked off: a quiet note, not a button.
    private var allDone: some View {
        Label {
            Text("All done for today.")
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
        }
        .listRowBackground(Color.clear)
    }
}

/// "3 of 8 done" beside a ring that fills as tasks get done, like the iPhone's Today header (top
/// of Today and of project pages). With nothing on the page, just the caption.
struct WatchProgressRow: View {
    let caption: String
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            if total > 0 {
                WatchProgressRing(progress: Double(done) / Double(total))
                    .frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if total > 0 {
                    Text("\(done) of \(total) done")
                        .font(.headline)
                        .rollingNumber(done)
                }
            }
            Spacer(minLength: 0)
        }
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }
}

/// Progress as a ring in the accent, like the iPhone's: it fills in as tasks get done, and a
/// check springs into the middle once everything is.
struct WatchProgressRing: View {
    let progress: Double

    private var isComplete: Bool { progress >= 1 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(TintShapeStyle.tint.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(TintShapeStyle.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.tint)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        // Half the line width, so the ring's outer edge meets the frame.
        .padding(2.5)
        .animation(Motion.resolved(Motion.layout), value: progress)
        .animation(Motion.resolved(Motion.celebrate), value: isComplete)
        .accessibilityHidden(true)
    }
}

/// Finished tasks, collapsed by default. Tap one to bring it back.
struct WatchDoneSection: View {
    let tasks: [TaskItem]
    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            Button {
                Motion.animate { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Label {
                        Text("Done Today")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    Spacer(minLength: 4)
                    Text("\(tasks.count)")
                        .fontDesign(.rounded)
                        .foregroundStyle(.secondary)
                        .rollingNumber(tasks.count)
                    // Turns to point down while the list is open.
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
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
