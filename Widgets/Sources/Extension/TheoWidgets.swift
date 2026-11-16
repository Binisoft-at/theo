import SwiftUI
import WidgetKit

/// Theo's widgets on iPhone, iPad and the Mac. They read the snapshot Theo writes into the
/// shared App Group (`WidgetSnapshot`); checking tasks off from here isn't possible yet, as the
/// task store isn't shared with the extension.
@main
struct TheoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        #if os(iOS)
        AddToTheoControl()
        #endif
    }
}

/// "Today": small, medium and large on the Home Screen and the Mac desktop, and on iPhone and
/// iPad also circular, rectangular and inline on the Lock Screen.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetLinks.todayKind, provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("What's open on today's plan, the Power Hours left and what's next.")
        .supportedFamilies(TodayWidget.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
        return [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }
}

struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayWidgetEntry

    var body: some View {
        #if os(iOS)
        if TodayWidgetEntryView.isAccessory(family) {
            accessory
                .widgetURL(WidgetLinks.today)
        } else {
            system
        }
        #else
        system
        #endif
    }

    private var system: some View {
        TodayWidgetView(page: entry.page, size: TodayWidgetEntryView.size(for: family))
    }

    private static func size(for family: WidgetFamily) -> TodayWidgetSize {
        switch family {
        case .systemMedium: return .medium
        case .systemLarge: return .large
        default: return .small
        }
    }

    #if os(iOS)
    private static func isAccessory(_ family: WidgetFamily) -> Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    @ViewBuilder
    private var accessory: some View {
        switch family {
        case .accessoryCircular: TodayCircularView(page: entry.page)
        case .accessoryRectangular: TodayRectangularView(page: entry.page)
        default: TodayInlineView(page: entry.page)
        }
    }
    #endif
}

#if os(iOS)
/// Control Center, the Lock Screen's controls and the Action button: "Add to Theo" opens Theo
/// with the cursor in the new-task field.
struct AddToTheoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TheoAddTask") {
            ControlWidgetButton(action: AddToTheoIntent()) {
                Label("Add to Theo", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Add to Theo")
        .description("Opens Theo with the cursor in the new-task field.")
    }
}
#endif
