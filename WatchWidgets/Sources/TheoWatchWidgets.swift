import SwiftUI
import WidgetKit

/// Theo's complications on the watch face and in the Smart Stack. They read the snapshot the
/// watch app writes into the App Group on the watch (`WidgetSnapshotWriter`, from the watch's
/// own copy of the tasks), so they work without the iPhone nearby.
@main
struct TheoWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayComplication()
    }
}

struct TodayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetLinks.todayKind, provider: TodayWidgetProvider()) { entry in
            TodayComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("What's open on today's plan and what's next.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct TodayComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWidgetEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: TodayRectangularView(page: entry.page)
        case .accessoryInline: TodayInlineView(page: entry.page)
        case .accessoryCorner: TodayCornerView(page: entry.page)
        default: TodayCircularView(page: entry.page)
        }
    }
}

/// A watch face corner: the open count, with the Power Hours left curving along the edge.
struct TodayCornerView: View {
    let page: WidgetSnapshot.Page?

    private var count: String {
        guard let page else { return "–" }
        return "\(page.open)"
    }

    private var label: String {
        guard let page else { return "Open Theo" }
        if page.open == 0 { return WidgetStyle.emptyTitle(page) }
        if page.powerHoursLeft > 0 { return WidgetStyle.powerHours(page.powerHoursLeft) + " left" }
        return "open today"
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Text(count)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .widgetAccentable()
        }
        .widgetLabel {
            Text(label)
        }
    }
}
