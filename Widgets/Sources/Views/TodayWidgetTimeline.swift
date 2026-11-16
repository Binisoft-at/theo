import SwiftUI
import WidgetKit

/// One moment of the "Today" widget.
struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    /// nil: Theo hasn't written a snapshot yet, or the newest one is for a day that's over.
    let page: WidgetSnapshot.Page?
}

/// Reads the snapshot Theo wrote (`WidgetSnapshot.load()`): an entry for now, one for when the
/// next logical day starts (tomorrow's page, in case Theo doesn't run then) and one for the day
/// after ("open Theo"). Theo reloads the widgets whenever it writes; besides that, they ask
/// again after an hour.
struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: Date(), page: WidgetSamples.page(at: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        let now = Date()
        var page = WidgetSnapshot.load()?.page(at: now)
        // The system's widget gallery shows sample tasks until Theo has written its own.
        if page == nil && context.isPreview {
            page = WidgetSamples.page(at: now)
        }
        completion(TodayWidgetEntry(date: now, page: page))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        let now = Date()
        let entries = TodayWidgetProvider.entries(for: WidgetSnapshot.load(), now: now)
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }

    static func entries(for snapshot: WidgetSnapshot?, now: Date) -> [TodayWidgetEntry] {
        guard let snapshot else { return [TodayWidgetEntry(date: now, page: nil)] }
        var entries = [TodayWidgetEntry(date: now, page: snapshot.page(at: now))]
        if now < snapshot.today.dayEnd {
            entries.append(TodayWidgetEntry(date: snapshot.today.dayEnd, page: snapshot.tomorrow))
        }
        if now < snapshot.tomorrow.dayEnd {
            entries.append(TodayWidgetEntry(date: snapshot.tomorrow.dayEnd, page: nil))
        }
        return entries
    }
}

/// Made-up tasks for the placeholder and the system's widget gallery.
enum WidgetSamples {
    static func page(at now: Date) -> WidgetSnapshot.Page {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
        let lines: [WidgetSnapshot.Line] = [
            sample("Finish the quarterly plan", priority: 3, group: "Work", color: "blue", hours: 1, due: start),
            sample("Reply about the team offsite", priority: 0, group: "Work", color: "blue", hours: 0.25, due: nil),
            sample("Book a physio session", priority: 1, group: "Health", color: "green", hours: 0.25, due: nil),
            sample("Water the plants", priority: 0, group: "Home", color: "orange", hours: 0.1, due: nil),
        ]
        return WidgetSnapshot.Page(
            dayStart: start,
            dayEnd: end,
            open: 4,
            done: 2,
            powerHoursLeft: 1.6,
            powerHoursDone: 0.75,
            overdue: 0,
            lines: lines
        )
    }

    private static func sample(_ title: String, priority: Int, group: String, color: String, hours: Double, due: Date?) -> WidgetSnapshot.Line {
        WidgetSnapshot.Line(
            id: UUID(),
            title: title,
            due: due,
            dueHasTime: false,
            priority: priority,
            groupName: group,
            groupColor: color,
            groupSymbol: nil,
            powerHours: hours,
            isOngoing: false,
            isPlanned: true,
            depth: 0
        )
    }
}
