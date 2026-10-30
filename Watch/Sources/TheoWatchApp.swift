import SwiftUI
import SwiftData

/// Theo on Apple Watch. Reads and writes the same SwiftData store as the iPhone and Mac apps,
/// synced through Theo's own private iCloud container, so it works without the phone nearby.
@main
struct TheoWatchApp: App {
    @State private var model: WatchModel
    private let container: ModelContainer

    init() {
        container = Persistence.makeContainer()
        _model = State(initialValue: WatchModel())
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .modelContainer(container)
                .tint((AccentChoice(rawValue: UserDefaults.standard.string(forKey: Prefs.accent) ?? "") ?? .notes).color)
        }
    }
}
