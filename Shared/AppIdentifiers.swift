import Foundation

/// Identifiers from Config/Base.xcconfig, exposed to code through Info.plist. Shared by the app
/// targets (and future watch app / extensions), so nothing is hard-coded in Swift.
enum AppIdentifiers {
    /// The app's own container (Theo's data).
    static var appCloudKitContainer: String? { value(for: "AppCloudKitContainer") }
    /// Cross-app container for small events and summaries only, never an app's schema.
    static var sharedCloudKitContainer: String? { value(for: "SharedCloudKitContainer") }
    static var sharedAppGroup: String? { value(for: "SharedAppGroup") }

    private static func value(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
}
