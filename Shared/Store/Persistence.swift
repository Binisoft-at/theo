import Foundation
import SwiftData
import CoreData

enum Persistence {
    static let schema = Schema([TaskItem.self, TaskGroup.self, SavedView.self])

    /// Why the CloudKit store couldn't be opened (shown in Settings), if it couldn't.
    nonisolated(unsafe) static var startupError: String?

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
                #if DEBUG && !os(watchOS)
                initializeCloudKitSchemaIfNeeded(containerID: containerID, storeURL: config.url)
                #endif
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                print("Theo: CloudKit store unavailable (\(error)). Falling back to local store.")
                startupError = error.localizedDescription
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

    #if DEBUG && !os(watchOS)
    /// Development builds push the *complete* CloudKit schema once (every record type and field,
    /// even ones no saved record has used yet), so "run a development build, then deploy the
    /// schema to Production" never leaves fields missing in Production.
    private static func initializeCloudKitSchemaIfNeeded(containerID: String, storeURL: URL) {
        let key = "cloudKitSchemaInitialized.\(containerID)"
        guard !UserDefaults.standard.bool(forKey: key),
              let model = NSManagedObjectModel.makeManagedObjectModel(for: [TaskItem.self, TaskGroup.self, SavedView.self]) else { return }
        do {
            try autoreleasepool {
                let description = NSPersistentStoreDescription(url: storeURL)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
                description.shouldAddStoreAsynchronously = false
                let container = NSPersistentCloudKitContainer(name: "Theo", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]
                let load = LoadResult()
                container.loadPersistentStores { _, error in load.error = error }
                if let error = load.error { throw error }
                try container.initializeCloudKitSchema()
                for store in container.persistentStoreCoordinator.persistentStores {
                    try container.persistentStoreCoordinator.remove(store)
                }
            }
            UserDefaults.standard.set(true, forKey: key)
            print("Theo: CloudKit development schema initialized for \(containerID)")
        } catch {
            print("Theo: CloudKit schema initialization skipped: \(error)")
        }
    }
    #endif
}

#if DEBUG && !os(watchOS)
/// Carries the synchronous `loadPersistentStores` result out of its completion handler.
private final class LoadResult: @unchecked Sendable {
    var error: Error?
}
#endif
