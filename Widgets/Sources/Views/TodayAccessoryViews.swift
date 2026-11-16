import SwiftUI
import WidgetKit

#if os(iOS) || os(watchOS)
// Lock Screen (iPhone, iPad) and watch face. These families draw in one colour on the Lock
// Screen and tinted faces, so they rely on shape and text, not on colour.

/// The open count in a ring that fills as the day gets done.
struct TodayCircularView: View {
    let page: WidgetSnapshot.Page?

    var body: some View {
        if let page {
            Gauge(value: WidgetStyle.progress(page)) {
                Image(systemName: "sun.max.fill")
            } currentValueLabel: {
                Text("\(page.open)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel(WidgetStyle.summary(page))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "sun.max.fill")
                    .font(.title3)
            }
            .accessibilityLabel(WidgetStyle.noSnapshotText)
        }
    }
}

/// "☀ 3 open · 2,5 PH left" and the next task underneath.
struct TodayRectangularView: View {
    let page: WidgetSnapshot.Page?

    private var detail: String {
        guard let page else { return WidgetStyle.noSnapshotText }
        guard let line = WidgetStyle.next(page) else { return WidgetStyle.emptyDetail(page) }
        let marks = WidgetStyle.marks(line.priority)
        return marks.isEmpty ? line.title : marks + " " + line.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(WidgetStyle.summary(page), systemImage: "sun.max.fill")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .widgetAccentable()
            Text(detail)
                .font(.body)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line above the clock: "3 open · 2,5 PH left".
struct TodayInlineView: View {
    let page: WidgetSnapshot.Page?

    var body: some View {
        Label(WidgetStyle.summary(page), systemImage: "sun.max.fill")
    }
}
#endif
