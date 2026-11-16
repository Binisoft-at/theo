import SwiftUI
import WidgetKit

// Built into the widget extensions (iPhone/iPad, Mac, watch) and into both apps (the widget
// gallery). The extensions only see the snapshot, not the app's model types, so the colours and
// texts the widgets need are spelled out here.

/// The links the widgets open; RootView hands them to `AppModel.openLink(_:)`.
enum WidgetLinks {
    /// The widgets' kind: one "Today" widget in every size and family.
    static let todayKind = "TheoToday"
    static let today = URL(string: "theo://today")!
    static let quickEntry = URL(string: "theo://quick-entry")!

    static func task(_ id: UUID) -> URL {
        URL(string: "theo://task/" + id.uuidString) ?? today
    }

    /// Set by the app at launch (`WidgetBridge`): where an action that runs inside the app (the
    /// Control Center button) hands its link. Stays nil in the widget extensions.
    @MainActor static var handler: (@MainActor (URL) -> Void)?
}

/// The colours for what things mean, the same as the app's (`Tint` in Shared/Design, which the
/// extensions don't see): Today orange, planned indigo, deadlines blue, a passed deadline a calm
/// orange, Power Hours teal, done green, Off Plan grey.
enum WidgetTint {
    static let today: Color = .orange
    static let planned: Color = .indigo
    static let deadline: Color = .blue
    static let overdue: Color = .orange
    static let powerHours: Color = .teal
    static let done: Color = .green
    static let offPlan: Color = .gray
    static let ongoing: Color = .teal
}

enum WidgetStyle {
    /// A group's colour by its `TheoColor` name; Quick Entry (no group) is grey.
    static func groupColor(_ name: String?) -> Color {
        guard let name else { return .gray }
        switch name {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "graphite": return .gray
        default: return .blue
        }
    }

    /// "!", "!!" or "!!!", as on a row in Theo.
    static func marks(_ priority: Int) -> String {
        String(repeating: "!", count: min(max(priority, 0), 3))
    }

    static func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 3: return .red
        case 2: return .orange
        default: return .blue
        }
    }

    /// "0,5 PH" in the user's locale.
    static func powerHours(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " PH"
    }

    /// Calendar days from the page's day to `date` (negative: before it).
    static func dayDelta(_ date: Date, from day: Date) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: day)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// "16:00" (today with a time), "Today", "Tomorrow", "Fri", "12 Nov".
    static func dueText(_ due: Date, hasTime: Bool, day: Date) -> String {
        switch dayDelta(due, from: day) {
        case 0: return hasTime ? due.formatted(date: .omitted, time: .shortened) : "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case -6 ... -2, 2...6: return due.formatted(.dateTime.weekday(.abbreviated))
        default: return due.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    /// Today orange, later the deadline blue; one that has passed stays calm (orange, as in the
    /// app), it's ranked at the top anyway.
    static func dueColor(_ due: Date, day: Date) -> Color {
        let delta = dayDelta(due, from: day)
        if delta < 0 { return WidgetTint.overdue }
        return delta == 0 ? WidgetTint.today : WidgetTint.deadline
    }

    /// "3 open · 2,5 PH left", "All planned done", "Nothing planned".
    static func summary(_ page: WidgetSnapshot.Page?) -> String {
        guard let page else { return "Open Theo" }
        guard page.open > 0 else { return emptyTitle(page) }
        guard page.powerHoursLeft > 0 else { return "\(page.open) open" }
        return "\(page.open) open · " + powerHours(page.powerHoursLeft) + " left"
    }

    /// How much of the page is done (0...1).
    static func progress(_ page: WidgetSnapshot.Page) -> Double {
        let total = page.open + page.done
        return total == 0 ? 0 : Double(page.done) / Double(total)
    }

    /// The open planned task Today ranks first.
    static func next(_ page: WidgetSnapshot.Page) -> WidgetSnapshot.Line? {
        page.lines.first { $0.isPlanned }
    }

    /// When nothing planned is open.
    static func emptyTitle(_ page: WidgetSnapshot.Page) -> String {
        page.done > 0 ? "All planned done" : "Nothing planned"
    }

    static func emptyDetail(_ page: WidgetSnapshot.Page) -> String {
        guard page.done > 0 else { return "Plan your day in Theo." }
        let hours = page.powerHoursDone > 0 ? " · " + powerHours(page.powerHoursDone) : ""
        return "\(page.done) done today" + hours
    }

    /// No snapshot yet (Theo not opened since installing), or only one for a day that's over.
    static let noSnapshotText = "Open Theo to see your day here."
}

/// Today's sun, in Today's orange.
struct TodaySunIcon: View {
    var body: some View {
        Image(systemName: "sun.max.fill")
            .foregroundStyle(WidgetTint.today)
            .widgetAccentable()
    }
}
