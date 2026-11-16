import SwiftUI

/// The complications' snapshot as the watch app comes and goes: rebuilt when it comes to the
/// front (a new day may have started) and written right away before it goes to the background.
/// The writer itself follows saves, syncs and the day change.
struct WatchSnapshotRefresh: ViewModifier {
    let writer: WidgetSnapshotWriter?
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: writer?.scheduleSoon(after: 0.5)
                case .background: writer?.writeNow()
                default: break
                }
            }
    }
}
