import SwiftUI
import SwiftData

/// Theo on Apple Watch. Reads and writes the same SwiftData store as the iPhone and Mac apps,
/// synced through Theo's own private iCloud container, so it works without the phone nearby.
@main
struct TheoWatchApp: App {
    @State private var model: WatchModel
    private let container: ModelContainer
    /// Keeps the complications' snapshot of today's page current (not for the demo data, nor
    /// for a store that couldn't be opened).
    private let widgets: WidgetSnapshotWriter?

    init() {
        let container = Persistence.makeContainer()
        self.container = container
        _model = State(initialValue: WatchModel())
        if Persistence.isDemo || Persistence.storeKind == .memory {
            widgets = nil
        } else {
            widgets = WidgetSnapshotWriter(container: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .modelContainer(container)
                .tint((AccentChoice(rawValue: UserDefaults.standard.string(forKey: Prefs.accent) ?? "") ?? .notes).color)
                .modifier(WatchSnapshotRefresh(writer: widgets))
        }
    }
}
