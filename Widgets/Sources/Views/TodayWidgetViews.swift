import SwiftUI
import WidgetKit

#if os(iOS) || os(macOS)
/// The Home Screen / Mac desktop sizes (the widget's family without the Lock Screen ones, so
/// the app's widget gallery can draw them too).
enum TodayWidgetSize {
    case small, medium, large

    /// Tasks listed (the small one names only the next task).
    var lineLimit: Int {
        switch self {
        case .small: 1
        case .medium: 4
        case .large: 8
        }
    }
}

/// Today on the Home Screen or the Mac desktop: the open count, the Power Hours left and the
/// next tasks ranked like Today. A tap on a task opens it, anywhere else opens Today. The
/// background comes from the widget (`containerBackground`), so it's left out here.
struct TodayWidgetView: View {
    let page: WidgetSnapshot.Page?
    let size: TodayWidgetSize

    var body: some View {
        content
            .widgetURL(WidgetLinks.today)
    }

    @ViewBuilder
    private var content: some View {
        if let page {
            if size == .small {
                TodaySmallView(page: page)
            } else {
                TodayListView(page: page, size: size)
            }
        } else {
            TodayNoSnapshotView()
        }
    }
}

/// Small: the open count in a ring that fills as the day gets done, the next task and the
/// Power Hours left.
struct TodaySmallView: View {
    let page: WidgetSnapshot.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                TodayCountRing(page: page)
                Spacer(minLength: 4)
                TodaySunIcon()
                    .font(.title3)
            }
            Spacer(minLength: 2)
            nextTask
            TodayFootnote(page: page)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var nextTask: some View {
        if let line = WidgetStyle.next(page) {
            Text("Next")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TodayTitleText(line: line, font: .subheadline.weight(.semibold), maxLines: 2)
        } else {
            Text(WidgetStyle.emptyTitle(page))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
        }
    }
}

/// Under the small widget's next task: "2,5 PH left", or what got done.
struct TodayFootnote: View {
    let page: WidgetSnapshot.Page

    private var text: String {
        if page.open == 0 { return WidgetStyle.emptyDetail(page) }
        if page.powerHoursLeft > 0 { return WidgetStyle.powerHours(page.powerHoursLeft) + " left" }
        return "\(page.open) open"
    }

    private var color: Color {
        if page.open == 0 { return page.done > 0 ? .green : .secondary }
        return page.powerHoursLeft > 0 ? .teal : .secondary
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Medium and large: a header, then the open planned tasks, then what Today's carry-over strip
/// offers (left open on an earlier day, or due without a plan) if there's room.
struct TodayListView: View {
    let page: WidgetSnapshot.Page
    let size: TodayWidgetSize

    var body: some View {
        let limit = size.lineLimit
        let planned = Array(page.lines.filter { $0.isPlanned }.prefix(limit))
        // The empty message and the "Not on today's plan" caption take a line each.
        let room = planned.isEmpty ? limit - 2 : limit - planned.count - 1
        let unplanned: [WidgetSnapshot.Line] = room > 0 ? Array(page.lines.filter { !$0.isPlanned }.prefix(room)) : []
        VStack(alignment: .leading, spacing: size == .large ? 7 : 5) {
            if size == .large {
                TodayLargeHeader(page: page)
            } else {
                TodayCompactHeader(page: page)
            }
            if planned.isEmpty {
                TodayEmptyMessage(page: page)
            }
            TodayLineList(lines: planned, day: page.dayStart)
            if !unplanned.isEmpty {
                Text("Not on today's plan")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                TodayLineList(lines: unplanned, day: page.dayStart)
            }
            Spacer(minLength: 0)
            if size == .large {
                TodayMoreText(page: page, shown: planned.count)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Rows that each open their task (`theo://task/<id>`).
struct TodayLineList: View {
    let lines: [WidgetSnapshot.Line]
    let day: Date

    var body: some View {
        ForEach(lines) { line in
            Link(destination: WidgetLinks.task(line.id)) {
                TodayLineRow(line: line, day: day)
            }
        }
    }
}

/// One task: the group's colour dot (or the grey Off Plan symbol when it isn't on the plan),
/// priority marks, title, and its deadline (or Power Hours) at the end.
struct TodayLineRow: View {
    let line: WidgetSnapshot.Line
    let day: Date

    var body: some View {
        HStack(spacing: 6) {
            TodayLineMarker(line: line)
            TodayTitleText(line: line, font: .subheadline, maxLines: 1)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.leading, CGFloat(min(line.depth, 2)) * 12)
    }

    @ViewBuilder
    private var trailing: some View {
        if let due = line.due {
            Text(WidgetStyle.dueText(due, hasTime: line.dueHasTime, day: day))
                .font(.caption.weight(.medium))
                .foregroundStyle(WidgetStyle.dueColor(due, day: day))
                .lineLimit(1)
                .fixedSize()
        } else if line.powerHours > 0 {
            Text(WidgetStyle.powerHours(line.powerHours))
                .font(.caption)
                .foregroundStyle(.teal)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

struct TodayLineMarker: View {
    let line: WidgetSnapshot.Line

    var body: some View {
        marker
            .frame(width: 12)
    }

    @ViewBuilder
    private var marker: some View {
        if line.isPlanned {
            Circle()
                .fill(WidgetStyle.groupColor(line.groupColor))
                .frame(width: 8, height: 8)
                .widgetAccentable()
        } else {
            Image(systemName: "calendar.badge.minus")
                .font(.caption2)
                .foregroundStyle(.gray)
        }
    }
}

/// A task's title with its priority marks in front and ∞ after an ongoing one.
struct TodayTitleText: View {
    let line: WidgetSnapshot.Line
    let font: Font
    let maxLines: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if line.priority > 0 {
                Text(WidgetStyle.marks(line.priority))
                    .font(font.weight(.heavy))
                    .foregroundStyle(WidgetStyle.priorityColor(line.priority))
                    .widgetAccentable()
            }
            Text(line.title)
                .font(font)
                .lineLimit(maxLines)
            if line.isOngoing {
                Image(systemName: "infinity")
                    .font(.caption2)
                    .foregroundStyle(.teal)
            }
        }
    }
}

/// Medium: "☀ Today" and the counts in one line.
struct TodayCompactHeader: View {
    let page: WidgetSnapshot.Page

    var body: some View {
        HStack(spacing: 5) {
            TodaySunIcon()
            Text("Today")
                .font(.headline)
            Spacer(minLength: 4)
            TodayCounts(page: page)
        }
    }
}

/// "3 open  2,5 PH  ⚠ 1" (open, Power Hours left, overdue).
struct TodayCounts: View {
    let page: WidgetSnapshot.Page

    var body: some View {
        HStack(spacing: 7) {
            Text("\(page.open) open")
                .foregroundStyle(.secondary)
            if page.powerHoursLeft > 0 {
                Text(WidgetStyle.powerHours(page.powerHoursLeft))
                    .foregroundStyle(.teal)
            }
            if page.overdue > 0 {
                Label("\(page.overdue)", systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(page.overdue) overdue")
            }
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
}

/// Large: the ring with the day's date, and the numbers on the right.
struct TodayLargeHeader: View {
    let page: WidgetSnapshot.Page

    var body: some View {
        HStack(spacing: 12) {
            TodayCountRing(page: page, diameter: 50)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    TodaySunIcon()
                    Text("Today")
                        .font(.headline)
                }
                Text(page.dayStart.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            TodayLargeNumbers(page: page)
        }
    }
}

struct TodayLargeNumbers: View {
    let page: WidgetSnapshot.Page

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if page.powerHoursLeft > 0 {
                Text(WidgetStyle.powerHours(page.powerHoursLeft) + " left")
                    .foregroundStyle(.teal)
            }
            if page.done > 0 {
                Text("\(page.done) done")
                    .foregroundStyle(.green)
            }
            if page.overdue > 0 {
                Text("\(page.overdue) overdue")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
    }
}

/// Large: how many planned tasks didn't fit.
struct TodayMoreText: View {
    let page: WidgetSnapshot.Page
    let shown: Int

    var body: some View {
        let more = page.open - shown
        if more > 0 {
            Text("+\(more) more on today's plan")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// "All planned done" (green) or "Nothing planned" (indigo, the planning colour).
struct TodayEmptyMessage: View {
    let page: WidgetSnapshot.Page

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: page.done > 0 ? "checkmark.circle.fill" : "calendar.badge.plus")
                .font(.title3)
                .foregroundStyle(page.done > 0 ? Color.green : Color.indigo)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(WidgetStyle.emptyTitle(page))
                    .font(.subheadline.weight(.semibold))
                Text(WidgetStyle.emptyDetail(page))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
}

/// Nothing written yet, or only for a day that's over.
struct TodayNoSnapshotView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TodaySunIcon()
                .font(.title2)
            Spacer(minLength: 0)
            Text("Theo")
                .font(.headline)
            Text(WidgetStyle.noSnapshotText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The open count inside a green ring that fills as tasks get done.
struct TodayCountRing: View {
    let page: WidgetSnapshot.Page
    var diameter: CGFloat = 44

    var body: some View {
        let progress = CGFloat(WidgetStyle.progress(page))
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            Text("\(page.open)")
                .font(.system(size: diameter * 0.42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(2.5)
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(page.open) open, \(page.done) done")
    }
}
#endif
