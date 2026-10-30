import Foundation
import SwiftData
import CoreData
import Observation

enum Persistence {
    static let schema = Schema([TaskItem.self, TaskGroup.self])

    /// Launch arguments used for screenshots and UI smoke tests.
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-TheoDemo") }

    /// The store syncs through the private iCloud database (like Notes). Builds without the
    /// iCloud entitlement (simulator CI builds) fall back to a local-only store.
    ///
    /// Both choices are explicit because the entitlements also list the shared Binisoft
    /// identifiers: `.automatic` would pick the first iCloud container and put the store in the
    /// shared App Group container. Theo's data only ever lives in its own container.
    @MainActor
    static func makeContainer() -> ModelContainer {
        if isDemo {
            let config = ModelConfiguration("TheoDemo", schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: config) {
                DemoData.seed(container.mainContext)
                return container
            }
        }
        if let containerID = AppIdentifiers.appCloudKitContainer {
            do {
                let config = ModelConfiguration(
                    "Theo", schema: schema, groupContainer: .none, cloudKitDatabase: .private(containerID)
                )
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                print("Theo: CloudKit store unavailable (\(error)). Falling back to local store.")
                SyncMonitor.startupError = error.localizedDescription
            }
        }
        do {
            let config = ModelConfiguration("Theo", schema: schema, groupContainer: .none, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            print("Theo: local store unavailable (\(error)). Using in-memory store.")
            let config = ModelConfiguration("TheoMemory", schema: schema, isStoredInMemoryOnly: true, groupContainer: .none, cloudKitDatabase: .none)
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
    /// Updated off the main thread: `ubiquityIdentityToken` can block for seconds.
    var hasICloudAccount = true
    var eventCount = 0

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        lastError = SyncMonitor.startupError
        refreshAccount()
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

    func refreshAccount() {
        guard !Persistence.isDemo else { return }
        Task.detached(priority: .utility) { [weak self] in
            let signedIn = FileManager.default.ubiquityIdentityToken != nil
            await MainActor.run { self?.hasICloudAccount = signedIn }
        }
    }

    private func handle(ended: Date?, succeeded: Bool, error: String?) {
        eventCount += 1
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
