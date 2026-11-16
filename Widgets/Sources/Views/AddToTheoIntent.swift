#if os(iOS)
import AppIntents
import Foundation

/// The Control Center button's action ("Add to Theo"): opens Theo with the cursor in the
/// new-task field. It's built into the app and into the widget extension, so the system runs it
/// inside the app (it opens the app), where `WidgetLinks.handler` takes it on to the composer.
/// (Apple's `OpenURLIntent` only opens universal links, not a `theo://` link.)
struct AddToTheoIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Theo"
    static let openAppWhenRun: Bool = true
    /// Shortcuts and Siri already offer "Quick Entry"; this one is only for the control.
    static let isDiscoverable: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetLinks.handler?(WidgetLinks.quickEntry)
        return .result()
    }
}
#endif
