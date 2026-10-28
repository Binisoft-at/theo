import Foundation
import SwiftData
import CoreData
import Observation

enum Persistence {
    static let schema = Schema([TaskItem.self, TaskGroup.self])

    static var cloudKitContainerID: String {
        (Bundle.main.object(forInfoDictionaryKey: "TheoCloudKitContainer") as? String) ?? "iCloud.com.erblinkastrati.theo"
    }

    /// Launch arguments used for screenshots and UI smoke tests.
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-TheoDemo") }

    /// The store syncs through the private iCloud database (like Notes). Builds without the
    /// iCloud entitlement (simulator CI builds) fall back to a local-only store.
    @MainActor
    static func makeContainer() -> ModelContainer {
        if isDemo {
            let config = ModelConfiguration("TheoDemo", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: config) {
                DemoData.seed(container.mainContext)
                return container
            }
        }
        do {
            let config = ModelConfiguration("Theo", schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            print("Theo: CloudKit store unavailable (\(error)). Falling back to local store.")
            SyncMonitor.startupError = error.localizedDescription
        }
        do {
            let config = ModelConfiguration("Theo", schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            print("Theo: local store unavailable (\(error)). Using in-memory store.")
            let config = ModelConfiguration("TheoMemory", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: config)
        }
    }
}

/// Watches the CloudKit mirroring events so Settings can show whether sync works.
@MainActor
@Observable
final class SyncMonitor {
    nonisolated(unsafe) static var startupError: String?

    var lastSuccess: Date?
    var lastError: String?
    var activeEvents = 0
    var hasICloudAccount: Bool = FileManager.default.ubiquityIdentityToken != nil
    var eventCount = 0

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        lastError = SyncMonitor.startupError
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let ended = event.endDate
            let succeeded = event.succeeded
            let message = event.error.map { SyncMonitor.describe($0) }
            MainActor.assumeIsolated {
                self?.handle(ended: ended, succeeded: succeeded, error: message)
            }
        }
    }

    private func handle(ended: Date?, succeeded: Bool, error: String?) {
        eventCount += 1
        hasICloudAccount = FileManager.default.ubiquityIdentityToken != nil
        if let ended {
            activeEvents = max(0, activeEvents - 1)
            if succeeded {
                lastSuccess = ended
                lastError = nil
            } else if let error {
                lastError = error
            }
        } else {
            activeEvents += 1
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var text = ns.localizedDescription
        if let partial = ns.userInfo["CKPartialErrors"] as? [AnyHashable: Error], let first = partial.values.first {
            text += " — " + (first as NSError).localizedDescription
        }
        return text
    }

    var statusText: String {
        if !hasICloudAccount { return "Not signed in to iCloud" }
        if activeEvents > 0 { return "Syncing…" }
        if lastError != nil { return "Sync problem" }
        if let lastSuccess { return "Synced " + lastSuccess.formatted(.relative(presentation: .named)) }
        return "Waiting for iCloud"
    }
}
