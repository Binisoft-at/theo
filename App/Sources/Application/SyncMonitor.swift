import Foundation
import CoreData
import Observation

/// Watches the CloudKit mirroring events so Settings can show whether sync works.
@MainActor
@Observable
final class SyncMonitor {
    var lastSuccess: Date?
    var lastError: String?
    var activeEvents = 0
    /// Updated off the main thread: `ubiquityIdentityToken` can block for seconds.
    var hasICloudAccount = true
    var eventCount = 0

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        lastError = Persistence.startupError
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
