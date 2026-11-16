import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers
import TheoCore

/// A look back at one day (today while it's still going): the Power Hours done and on what,
/// how that compares with the days before, a quiet share of the day's tasks that got done, and
/// the finished tasks, which export as CSV. What's shown is set here (Show menu) or in Settings.
struct DayReviewView: View {
    let day: Date

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<TaskItem> { $0.deletedAt == nil })
    private var tasks: [TaskItem]
    @Query(filter: #Predicate<TaskGroup> { $0.deletedAt == nil }, sort: \TaskGroup.sortOrder)
    private var groups: [TaskGroup]

    @AppStorage(Prefs.reviewPowerHours) private var showPowerHours = true
    @AppStorage(Prefs.reviewBreakdown) private var showBreakdown = true
    @AppStorage(Prefs.reviewComparison) private var showComparison = true
    @AppStorage(Prefs.reviewShare) private var showShare = true
    @AppStorage(Prefs.reviewTasks) private var showTasks = true
    @AppStorage(Prefs.reviewCompareDays) private var compareDays = 7
    @State private var savingRange: ReviewExport.Range?

    private var boundary: DayBoundary { DayBoundary.current }
    private var isToday: Bool { Calendar.current.isDate(day, inSameDayAs: app.dayStart) }

    var body: some View {
        let byDay = finishedByDay()
        let done = (byDay[day] ?? []).sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let powerHours = PageBuilder.estimateTotals(done).done
        let open = stillOpen(done: done)
        let history = (1...max(1, compareDays)).map { offset -> DayReview.Day in
            let start = boundary.dayStart(byAdding: -offset, to: day)
            let items = byDay[start] ?? []
            return DayReview.Day(start: start, powerHours: PageBuilder.estimateTotals(items).done, done: items.count)
        }

        List {
            Section {
                summary(powerHours: powerHours, done: done.count, open: open.count, history: history)
            }
            if showComparison {
                Section {
                    comparisonChart(today: DayReview.Day(start: day, powerHours: powerHours, done: done.count), history: history)
                } header: {
                    sectionTitle("Compared with the \(compareDays) days before")
                }
            }
            if showBreakdown && !done.isEmpty {
                Section {
                    breakdown(done)
                } header: {
                    sectionTitle("Worked On")
                }
            }
            if showTasks {
                Section {
                    if done.isEmpty {
                        Text(isToday ? "Nothing finished yet today." : "Nothing was finished that day.")
                            .theoFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(done, id: \.uuid) { task in
                        FinishedRow(task: task, groups: groups)
                    }
                } header: {
                    sectionTitle("Finished · \(done.count)")
                }
            }
        }
        .navigationTitle(isToday ? "Today So Far" : DateText.pageTitle(day))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                exportMenu(byDay: byDay)
            }
            ToolbarItem(placement: .primaryAction) {
                showMenu
            }
        }
        .fileExporter(
            isPresented: Binding(get: { savingRange != nil }, set: { if !$0 { savingRange = nil } }),
            document: savingRange.map { CSVDocument(text: ReviewExport.csv(range: $0, day: day, byDay: byDay, groups: groups)) },
            contentType: .commaSeparatedText,
            defaultFilename: savingRange.map { ReviewExport.fileName(range: $0, day: day) }
        ) { _ in
            savingRange = nil
        }
    }

    // MARK: - Data

    /// Finished tasks by the (logical) day they were finished.
    private func finishedByDay() -> [Date: [TaskItem]] {
        var result: [Date: [TaskItem]] = [:]
        for task in tasks where task.isDone {
            guard let completed = task.completedAt else { continue }
            result[boundary.start(of: completed), default: []].append(task)
        }
        return result
    }

    /// What was on the day's page and isn't done (today: still open; earlier: left open then).
    private func stillOpen(done: [TaskItem]) -> [TaskItem] {
        let end = boundary.end(ofDayStarting: day)
        let finished = Set(done.map(\.uuid))
        return tasks.filter { task in
            guard !finished.contains(task.uuid) else { return false }
            if isToday { return !task.isDone && PageBuilder.isOnToday(task, dayStart: day) }
            return task.isPlanned(for: day) && (!task.isDone || (task.completedAt ?? .distantPast) >= end)
        }
    }

    // MARK: - Sections

    /// A section's title, as on the other pages: a headline in the text colour.
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .theoFont(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
            .modifier(RollingFigures(text: title))
    }

    private func summary(powerHours: Double, done: Int, open: Int, history: [DayReview.Day]) -> some View {
        let average = DayReview.average(history)
        let ratio = DayReview.ratio(powerHours, average: average)
        let rank = DayReview.rank(of: powerHours, among: history)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                if showPowerHours {
                    powerHoursFigure(powerHours)
                }
                tasksFigure(done)
                Spacer(minLength: 0)
                if showShare, done + open > 0 {
                    shareRing(DayReview.share(done: done, open: open))
                }
            }
            if showComparison, showPowerHours, average > 0 {
                comparisonLine(delta: powerHours - average, average: average)
                if rank == 1, powerHours > 0, let ratio, ratio > 1.05 {
                    bestDayLine
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The day's Power Hours, big and rounded, with the unit smaller beside it.
    private func powerHoursFigure(_ powerHours: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(PowerHours.number(powerHours))
                    .theoFont(.largeTitle, weight: .bold, design: .rounded)
                    .rollingNumber(powerHours)
                Text("PH")
                    .theoFont(.title2, weight: .semibold, design: .rounded)
                    .foregroundStyle(.secondary)
            }
            Text(isToday ? "worked so far" : "worked")
                .theoFont(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func tasksFigure(_ done: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(done)")
                .theoFont(showPowerHours ? .title2 : .largeTitle, weight: .bold, design: .rounded)
                .rollingNumber(done)
            Text(done == 1 ? "task done" : "tasks done")
                .theoFont(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Quietly: how much of the day's page got done.
    private func shareRing(_ share: Double) -> some View {
        VStack(spacing: 4) {
            ZStack {
                ProgressRing(progress: share)
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .theoFont(.caption2, weight: .semibold, design: .rounded)
                    .rollingNumber(share)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 44, height: 44)
            Text("of the page")
                .theoFont(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int((share * 100).rounded())) percent of the day's tasks done")
    }

    /// The day against the average: green and pointing up when it's ahead, a calm grey when
    /// it's behind. The arrow sits right before its words; a second line wraps under them.
    private func comparisonLine(delta: Double, average: Double) -> some View {
        let ahead = delta >= 0
        let text = "\(DayReview.signed(delta)) against your \(compareDays)-day average of \(PowerHours.format((average * 100).rounded() / 100))"
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: ahead ? "arrow.up.right" : "arrow.down.right")
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Text(text)
                .modifier(RollingFigures(text: text))
        }
        .theoFont(.subheadline, weight: .medium)
        .foregroundStyle(ahead ? Tint.done : Color.secondary)
    }

    private var bestDayLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text("Your best day in \(compareDays + 1) days")
        }
        .theoFont(.caption, weight: .semibold)
    }

    private func comparisonChart(today: DayReview.Day, history: [DayReview.Day]) -> some View {
        let days = (history.reversed() + [today])
        let average = DayReview.average(history)
        // A week gets short weekday names (Tue and Thu look different, unlike "T" and "T");
        // 14 or 30 days get a date on every 7th day.
        let isWeek = days.count <= 8
        let labelEvery = isWeek ? 1 : 7
        let labelFormat = isWeek
            ? Date.FormatStyle().weekday(.abbreviated)
            : Date.FormatStyle().day().month(.defaultDigits)
        // The day itself in the accent the user picked, the days before it quiet.
        let todayStyle = AnyShapeStyle(TintShapeStyle.tint)
        let otherStyle = AnyShapeStyle(Color.secondary.opacity(0.3))
        return Chart {
            ForEach(days, id: \.start) { item in
                BarMark(
                    x: .value("Day", item.start, unit: .day),
                    y: .value("Power Hours", showPowerHours ? item.powerHours : Double(item.done))
                )
                .foregroundStyle(item.start == today.start ? todayStyle : otherStyle)
                .cornerRadius(4)
            }
            if average > 0, showPowerHours {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("average")
                            .theoFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: labelEvery)) { _ in
                AxisValueLabel(format: labelFormat)
            }
        }
        .chartYAxisLabel(showPowerHours ? "PH" : "tasks")
        .frame(height: 140)
        .padding(.vertical, 6)
        .animation(Motion.resolved(Motion.layout), value: compareDays)
        .animation(Motion.resolved(Motion.layout), value: showPowerHours)
    }

    /// Power Hours (and tasks) per top-level group.
    private func breakdown(_ done: [TaskItem]) -> some View {
        let rows = Sections.byTopGroup(done, groups: groups)
            .filter { !$0.tasks.isEmpty }
            .map { GroupWork(id: $0.key, title: $0.title, color: $0.color, symbol: $0.symbol,
                             powerHours: PageBuilder.estimateTotals($0.tasks).done, count: $0.tasks.count) }
            .sorted { ($0.powerHours, $0.count) > ($1.powerHours, $1.count) }
        let most = max(rows.map(\.powerHours).max() ?? 0, 0.01)
        return ForEach(rows) { row in
            breakdownRow(row, most: most)
        }
    }

    /// One group's share of the day: its icon in its colour, its name in the text colour, the
    /// figures, and a bar in its colour on a faint track.
    private func breakdownRow(_ row: GroupWork, most: Double) -> some View {
        let figures = (showPowerHours ? PowerHours.format(row.powerHours) + " · " : "") + "\(row.count) done"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(row.title)
                } icon: {
                    Image(systemName: row.symbol)
                        .foregroundStyle(row.color)
                }
                .theoFont(.subheadline, weight: .semibold)
                Spacer()
                Text(figures)
                    .theoFont(.caption, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if showPowerHours {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(row.color.gradient)
                            .frame(width: max(6, geo.size.width * row.powerHours / most))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Menus

    private func exportMenu(byDay: [Date: [TaskItem]]) -> some View {
        Menu {
            Section("Share Finished Tasks as CSV") {
                ForEach(ReviewExport.Range.allCases) { range in
                    ShareLink(
                        item: CSVFile(name: ReviewExport.fileName(range: range, day: day),
                                      text: ReviewExport.csv(range: range, day: day, byDay: byDay, groups: groups)),
                        preview: SharePreview(ReviewExport.fileName(range: range, day: day))
                    ) {
                        Label(range.title, systemImage: range.symbol)
                    }
                }
            }
            Section("Save as File") {
                ForEach(ReviewExport.Range.allCases) { range in
                    Button {
                        savingRange = range
                    } label: {
                        Label(range.title + "…", systemImage: "square.and.arrow.down")
                    }
                }
            }
        } label: {
            Label("Export CSV", systemImage: "square.and.arrow.up")
        }
    }

    /// What the review shows. Sections that come or go slide into place.
    private var showMenu: some View {
        let motion: Animation = Motion.resolved(Motion.layout)
        return Menu {
            Toggle("Power Hours", isOn: $showPowerHours.animation(motion))
            Toggle("Worked On", isOn: $showBreakdown.animation(motion))
            Toggle("Comparison", isOn: $showComparison.animation(motion))
            Toggle("Share of the Page Done", isOn: $showShare.animation(motion))
            Toggle("Finished Tasks", isOn: $showTasks.animation(motion))
            Picker("Compare With", selection: $compareDays.animation(motion)) {
                ForEach([7, 14, 30], id: \.self) { days in
                    Text("\(days) days before").tag(days)
                }
            }
        } label: {
            Label("Show", systemImage: "slider.horizontal.3")
        }
    }
}

/// One top-level group's share of the day.
private struct GroupWork: Identifiable {
    let id: String
    let title: String
    let color: Color
    let symbol: String
    let powerHours: Double
    let count: Int
}

/// A finished task: when, where (the group's icon in its colour, its name as quiet as the
/// time), and how many Power Hours.
private struct FinishedRow: View {
    let task: TaskItem
    let groups: [TaskGroup]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Tint.done)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.trimmedTitle.isEmpty ? "Untitled" : task.trimmedTitle)
                    .theoBodyFont()
                HStack(spacing: 8) {
                    if let completed = task.completedAt {
                        Text(completed.formatted(date: .omitted, time: .shortened))
                            .monospacedDigit()
                    }
                    if let group = task.group, group.deletedAt == nil {
                        Label {
                            Text(GroupTree.path(of: group, in: groups))
                        } icon: {
                            Image(systemName: group.symbol)
                                .foregroundStyle(group.color.color)
                        }
                        .labelStyle(CompactLabelStyle())
                        .lineLimit(1)
                    }
                }
                .theoFont(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if task.estimate > 0 {
                Text(PowerHours.format(task.estimate))
                    .theoFont(.caption, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(Tint.powerHours)
            }
        }
    }
}

/// The finished tasks of a stretch of days as spreadsheet text.
enum ReviewExport {
    enum Range: String, CaseIterable, Identifiable {
        case day, week, month, all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: "This Day"
            case .week: "Last 7 Days"
            case .month: "Last 30 Days"
            case .all: "Everything"
            }
        }

        var symbol: String {
            switch self {
            case .day: "sun.max"
            case .week: "calendar"
            case .month: "calendar.badge.clock"
            case .all: "tray.full"
            }
        }

        /// How many days back from (and including) the reviewed day; nil = all.
        var days: Int? {
            switch self {
            case .day: 1
            case .week: 7
            case .month: 30
            case .all: nil
            }
        }
    }

    static func fileName(range: Range, day: Date) -> String {
        let stamp = dayFormatter.string(from: day)
        return switch range {
        case .day: "Theo finished \(stamp).csv"
        case .week: "Theo finished 7 days to \(stamp).csv"
        case .month: "Theo finished 30 days to \(stamp).csv"
        case .all: "Theo finished tasks.csv"
        }
    }

    static func csv(range: Range, day: Date, byDay: [Date: [TaskItem]], groups: [TaskGroup], locale: Locale = .current) -> String {
        let boundary = DayBoundary.current
        let first = range.days.map { boundary.dayStart(byAdding: -($0 - 1), to: day) }
        let days = byDay.keys.filter { start in start <= day && first.map { start >= $0 } ?? true }.sorted()
        let format = CSV.Format.for(locale)
        var rows: [[String]] = []
        for start in days {
            let tasks = (byDay[start] ?? []).sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            for task in tasks {
                rows.append([
                    dayFormatter.string(from: start),
                    task.completedAt.map { timeFormatter.string(from: $0) } ?? "",
                    task.trimmedTitle,
                    task.group.flatMap { $0.deletedAt == nil ? GroupTree.path(of: $0, in: groups) : nil } ?? "Quick Entry",
                    CSV.number(task.estimate, format: format),
                    CSV.number((task.focusSeconds / 60).rounded(), format: format),
                    "\(task.importanceLevel)",
                    task.dueDate.map { dayFormatter.string(from: $0) } ?? "",
                    task.tags.map { "#" + $0 }.joined(separator: " "),
                ])
            }
        }
        let header = ["Day", "Finished", "Task", "Group", "Power Hours", "Focus Minutes", "Importance", "Deadline", "Tags"]
        // The byte order mark makes Excel read umlauts right; Numbers doesn't mind it.
        return "\u{FEFF}" + CSV.document(header: header, rows: rows, format: format)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

/// A CSV file to share.
struct CSVFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// A CSV file to save.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
