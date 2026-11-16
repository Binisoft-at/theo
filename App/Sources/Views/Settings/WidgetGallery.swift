import SwiftUI
import WidgetKit

/// Every widget size (and on iPhone the Lock Screen families) drawn from the current tasks,
/// with the widgets' own views: how they look without a device. Shown instead of the app when
/// Theo starts with `-TheoWidgetGallery` (screenshots use the demo data, `-TheoDemo`). Nothing
/// is written to the widgets from here.
struct WidgetGallery: View {
    @Environment(AppModel.self) private var app

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-TheoWidgetGallery")
    }

    var body: some View {
        let store = app.store
        let snapshot = WidgetSnapshot.build(tasks: store.liveTasks(), groups: store.liveGroups())
        ScrollView {
            tiles(snapshot.today)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            LinearGradient(colors: [Color.indigo.opacity(0.35), Color.orange.opacity(0.25)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    /// iPhone: one screen, small and the Lock Screen side by side. Mac: everything in a row.
    @ViewBuilder
    private func tiles(_ page: WidgetSnapshot.Page) -> some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                small(page)
                WidgetGalleryLockScreen(page: page)
            }
            medium(page)
            large(page)
        }
        #else
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 14) {
                small(page)
                // Before Theo has written anything.
                small(nil)
            }
            medium(page)
            large(page)
        }
        #endif
    }

    private func small(_ page: WidgetSnapshot.Page?) -> some View {
        WidgetGalleryTile(width: 170, height: 170) {
            TodayWidgetView(page: page, size: .small)
        }
    }

    private func medium(_ page: WidgetSnapshot.Page) -> some View {
        WidgetGalleryTile(width: 354, height: 170) {
            TodayWidgetView(page: page, size: .medium)
        }
    }

    private func large(_ page: WidgetSnapshot.Page) -> some View {
        WidgetGalleryTile(width: 354, height: 376) {
            TodayWidgetView(page: page, size: .large)
        }
    }
}

/// A widget at a fixed size with the widget's margins and background.
private struct WidgetGalleryTile<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(width: width, height: height)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.background)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.fill.tertiary)
                }
            }
    }
}

#if os(iOS)
/// The Lock Screen families, white on a dark wallpaper like the real thing.
private struct WidgetGalleryLockScreen: View {
    let page: WidgetSnapshot.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TodayInlineView(page: page)
                .font(.caption)
                .lineLimit(1)
            HStack(spacing: 8) {
                TodayCircularView(page: page)
                    .frame(width: 58, height: 58)
                TodayCircularView(page: nil)
                    .frame(width: 58, height: 58)
            }
            TodayRectangularView(page: page)
                .frame(height: 58)
        }
        .padding(10)
        .frame(width: 186, height: 170, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
#endif
