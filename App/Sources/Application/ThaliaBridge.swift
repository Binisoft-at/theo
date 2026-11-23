import Foundation
import CoreData
import SwiftData
import Observation
import TheoCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import Security
#endif

// Theo → Thalia (Binisoft exchange, format v1; the rules are in TheoCore's `TheoExchange` and
// `ThaliaExchangeWriter`, the plan in docs/thalia-exchange.md). This target is the iPhone/iPad/Mac
// app only: the watch never reads or writes the exchange.

/// Theo's folder in the shared App Group, Thalia's catalog next to it, and the "changed" note.
enum ThaliaFolder {
    /// `<group>/Theo`; nil without the App Group (an unsigned build) and on a Mac whose signed app
    /// doesn't carry the group (macOS would ask about other apps' data otherwise). Call it off the
    /// main thread: on the Mac it reads the app's entitlements.
    static func appFolder() -> URL? {
        #if os(macOS)
        guard hasAppGroupEntitlement else { return nil }
        #endif
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BinisoftExchange.appGroup) else {
            return nil
        }
        return root.appendingPathComponent(TheoExchange.appName, isDirectory: true)
    }

    /// Thalia's catalog on this device, read off the main thread; nil while Thalia hasn't written one
    /// here. With `-TheoThaliaCatalogDemo` (screenshots, demo data only) a neutral sample.
    static func loadCatalog() async -> ExchangeCatalog? {
        if Persistence.isDemo {
            return ProcessInfo.processInfo.arguments.contains("-TheoThaliaCatalogDemo") ? demoCatalog : nil
        }
        return await Task.detached(priority: .userInitiated) {
            appFolder().flatMap { ThaliaExchangeWriter.catalog(appFolder: $0) }
        }.value
    }

    /// Thalia may look right away (it also looks at launch, in the foreground and every 5 minutes).
    static func postChanged() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(BinisoftExchange.changedNotification as CFString),
                                             nil, nil, true)
    }

    #if os(macOS)
    /// Whether the signed app carries `group.at.binisoft.shared`. Worked out once, off the main
    /// thread, on the first use (never during launch).
    static let hasAppGroupEntitlement: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        return (value as? [String])?.contains(BinisoftExchange.appGroup) ?? false
    }()
    #endif

    private static let demoCatalog = ExchangeCatalog(
        generatedAt: "2026-11-22T06:00:00+01:00", week: "2026-W47",
        segment: .init(id: "seg-2", title: "Abschnitt 2"),
        goals: [.init(key: "1", title: "Gesundheit"), .init(key: "3", title: "Arbeit"), .init(key: "5", title: "Lesen")],
        categories: [.init(key: "1.2", goal: "1", title: "Sport / Verein", segment: "seg-2"),
                     .init(key: "3.2", goal: "3", title: "Kunden", segment: "seg-2"),
                     .init(key: "5", goal: "5", title: "Lesen", segment: "seg-2")]
    )
}

/// The switch "An Thalia liefern" (on unless switched off), the same on every iPhone, iPad and Mac
/// through iCloud's key-value store, and what this device last wrote.
@MainActor
@Observable
final class ThaliaSettings {
    static let shared = ThaliaSettings()

    private static let deliverKey = "thalia.deliver"
    /// This device's copy of the switch, for when iCloud isn't there yet.
    private static let localKey = "thalia.deliver.local"
    private static let lastWrittenKey = "thalia.lastWritten"
    /// Set once iCloud has delivered this store's data at least once (see `ThaliaExchange`).
    static let importSeenKey = "thalia.importSeen"

    private(set) var deliver: Bool
    /// When this device last changed a file for Thalia.
    private(set) var lastWritten: Date?
    /// Why nothing reaches Thalia from this device, nil when it does (or nothing was tried yet).
    var unavailable: String?
    /// Whether the switch's value is known here: iCloud had one, this device set it before, or
    /// iCloud had half a minute to deliver it. Until then a new device delivers nothing, so it
    /// can't send what another device switched off.
    private(set) var isKnown: Bool

    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard
        if let value = cloud.object(forKey: Self.deliverKey) as? Bool {
            deliver = value
            isKnown = true
        } else {
            let mine = local.object(forKey: Self.localKey) as? Bool
            deliver = mine ?? true
            isKnown = mine != nil
        }
        lastWritten = local.object(forKey: Self.lastWrittenKey) as? Date
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                          object: cloud, queue: .main) { _ in
            MainActor.assumeIsolated { ThaliaSettings.shared.cloudChanged() }
        }
        cloud.synchronize()
        if !isKnown {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                ThaliaSettings.shared.isKnown = true
            }
        }
    }

    /// Switched on this device: every device follows through iCloud.
    func setDeliver(_ value: Bool) {
        isKnown = true
        guard value != deliver else { return }
        deliver = value
        UserDefaults.standard.set(value, forKey: Self.localKey)
        NSUbiquitousKeyValueStore.default.set(value, forKey: Self.deliverKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        ThaliaBridge.scheduleSoon(after: 0.5)
    }

    /// Switched on another device.
    private func cloudChanged() {
        isKnown = true
        guard let value = NSUbiquitousKeyValueStore.default.object(forKey: Self.deliverKey) as? Bool, value != deliver else { return }
        deliver = value
        UserDefaults.standard.set(value, forKey: Self.localKey)
        ThaliaBridge.scheduleSoon(after: 0.5)
    }

    func noteWritten(_ date: Date) {
        lastWritten = date
        UserDefaults.standard.set(date, forKey: Self.lastWrittenKey)
    }
}

/// Starts the exchange once (from `TheoApp`): only with the store that syncs through iCloud (so every
/// device writes the same), never for the demo, the tour's practice store, the local or in-memory
/// fallback store, and never in previews.
@MainActor
enum ThaliaBridge {
    private static var exchange: ThaliaExchange?

    static func start(app: AppModel) {
        guard exchange == nil, !app.isSandbox, !Persistence.isDemo,
              ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        guard Persistence.storeKind == .cloud else {
            ThaliaSettings.shared.unavailable = "Nur mit iCloud: Theo synchronisiert auf diesem Gerät gerade nicht, darum geht nichts an Thalia."
            return
        }
        _ = ThaliaSettings.shared
        exchange = ThaliaExchange(container: app.container)
    }

    static func scheduleSoon(after seconds: Double = 2) {
        exchange?.scheduleSoon(after: seconds)
    }
}

/// Keeps Theo's day files and `source.json` in step with its synced store: rebuilt (from all of the
/// last 62 days) a couple of seconds after every save, after each iCloud import from another device,
/// when Theo comes to the front, when a new calendar day starts and when the switch or a group's
/// category changes. Building reads the store on the main actor; writing happens off it and never
/// shows an error (problems go to the log).
@MainActor
final class ThaliaExchange {
    private let container: ModelContainer
    private var pending: Task<Void, Never>?
    private var writing = false
    private var writeAgain = false
    /// No App Group on this device (or, on a Mac, not in the signed app): nothing is built anymore.
    private var unavailable = false
    private let startedAt = Date()
    private var observers: [NSObjectProtocol] = []
    #if os(iOS)
    /// Keeps Theo running while it writes as it goes to the background.
    private var backgroundWork: UIBackgroundTaskIdentifier = .invalid
    #endif

    init(container: ModelContainer) {
        self.container = container
        let center = NotificationCenter.default
        // Every save of Theo's store (a group's category is saved with the group).
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let saved = note.object as? ModelContext, saved.container === self.container else { return }
                self.scheduleSoon()
            }
        })
        // Tasks finished on another device arrive through iCloud: right after each import. The
        // first one that succeeds also opens the gate (see `importSeen`).
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil,
                                            queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil else { return }
            let succeeded = event.succeeded
            MainActor.assumeIsolated {
                if succeeded { UserDefaults.standard.set(true, forKey: ThaliaSettings.importSeenKey) }
                self?.scheduleSoon()
            }
        })
        // Another iCloud account: wait for its data before telling Thalia anything.
        observers.append(center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { UserDefaults.standard.set(false, forKey: ThaliaSettings.importSeenKey) }
        })
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSoon() }
        })
        #if os(iOS)
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSoon() }
        })
        // iOS may suspend Theo next (often right after a task is ticked off, on the way to Thalia):
        // the last change shouldn't wait for the next launch.
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.backgroundWork == .invalid {
                    self.backgroundWork = UIApplication.shared.beginBackgroundTask(withName: "Theo for Thalia") { [weak self] in
                        MainActor.assumeIsolated { self?.endBackgroundWork() }
                    }
                }
                self.writeNow()
            }
        })
        #elseif os(macOS)
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSoon() }
        })
        // A task ticked off just before ⌘Q still reaches Thalia.
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeBeforeQuitting() }
        })
        #endif
        scheduleSoon(after: Self.launchDelay)
    }

    /// Nothing is built in the first seconds after launch.
    private static let launchDelay = 5.0

    func scheduleSoon(after seconds: Double = 2) {
        guard !unavailable else { return }
        let wait = max(seconds, Self.launchDelay - Date().timeIntervalSince(startedAt))
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.writeNow()
        }
    }

    func writeNow() {
        pending?.cancel()
        pending = nil
        guard !unavailable else {
            finishBackgroundWork()
            return
        }
        // A new or reinstalled device (or another iCloud account) before iCloud has delivered
        // this store's data: what's here isn't the whole picture yet. The import starts the
        // next write.
        guard UserDefaults.standard.bool(forKey: ThaliaSettings.importSeenKey) else {
            ThaliaSettings.shared.unavailable = "Wartet auf den ersten iCloud-Abgleich auf diesem Gerät."
            finishBackgroundWork()
            return
        }
        // The switch may still be on its way from iCloud on a new device.
        guard ThaliaSettings.shared.isKnown else {
            scheduleSoon(after: 5)
            finishBackgroundWork()
            return
        }
        // One write at a time; a change meanwhile writes once more afterwards.
        guard !writing else {
            writeAgain = true
            return
        }
        let deliver = ThaliaSettings.shared.deliver
        let (tasks, groups) = records(including: deliver)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        writing = true
        Task.detached(priority: .utility) { [weak self] in
            let outcome = Self.write(tasks: tasks, groups: groups, deliver: deliver, appVersion: version, now: Date())
            await self?.finished(outcome)
        }
    }

    private func finished(_ outcome: Outcome) {
        writing = false
        switch outcome {
        case .unavailable:
            unavailable = true
            ThaliaSettings.shared.unavailable = "Auf diesem Gerät nicht verfügbar."
        case .written(let date):
            ThaliaSettings.shared.unavailable = nil
            if let date { ThaliaSettings.shared.noteWritten(date) }
        case .failed:
            break
        }
        if writeAgain {
            writeAgain = false
            #if os(iOS)
            // On the way to the background: right away, while iOS still lets Theo run.
            if backgroundWork != .invalid {
                writeNow()
                return
            }
            #endif
            scheduleSoon(after: 0.5)
        }
        finishBackgroundWork()
    }

    private func finishBackgroundWork() {
        #if os(iOS)
        endBackgroundWork()
        #endif
    }

    #if os(iOS)
    private func endBackgroundWork() {
        guard backgroundWork != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundWork)
        backgroundWork = .invalid
    }
    #endif

    #if os(macOS)
    /// Right away and on the main thread: the app is about to quit, and the files are small.
    private func writeBeforeQuitting() {
        pending?.cancel()
        pending = nil
        guard !unavailable, UserDefaults.standard.bool(forKey: ThaliaSettings.importSeenKey),
              ThaliaSettings.shared.isKnown else { return }
        let deliver = ThaliaSettings.shared.deliver
        let (tasks, groups) = records(including: deliver)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        _ = Self.write(tasks: tasks, groups: groups, deliver: deliver, appVersion: version, now: Date())
    }
    #endif

    /// Theo's synced store as plain values: every group, and the finished tasks of about the last
    /// 62 days (none while the switch is off, so every day Thalia has is written empty).
    private func records(including tasks: Bool) -> ([TheoExchange.TaskRecord], [TheoExchange.GroupRecord]) {
        let store = TaskStore(context: container.mainContext)
        let groups = store.liveGroups().map { group in
            TheoExchange.GroupRecord(id: group.uuid.uuidString, name: group.name, parentID: group.parentUUID?.uuidString,
                                     category: group.extras[TheoExchange.categoryKey],
                                     categoryTitle: group.extras[TheoExchange.categoryTitleKey])
        }
        guard tasks else { return ([], groups) }
        // Only what the last 62 days (and a margin for time zones) can hold; History keeps the rest.
        let since = Date().addingTimeInterval(-Double(BinisoftExchange.keepDays + 2) * 86_400)
        let past = Date.distantPast
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> {
            $0.deletedAt == nil && $0.isDone && ($0.completedAt ?? past) >= since
        })
        let finished = ((try? container.mainContext.fetch(descriptor)) ?? []).compactMap { task -> TheoExchange.TaskRecord? in
            guard let completed = task.completedAt, completed >= since else { return nil }
            return TheoExchange.TaskRecord(id: task.uuid.uuidString, title: task.title, groupID: task.group?.uuid.uuidString,
                                           isDone: true, completedAt: completed, estimate: task.estimate,
                                           sortOrder: task.sortOrder, indent: task.indent)
        }
        return (finished, groups)
    }

    enum Outcome: Sendable {
        case unavailable
        /// When something changed, nil when everything already was as it should be.
        case written(Date?)
        case failed
    }

    /// Off the main actor: build the days, write what changed, tell Thalia.
    nonisolated private static func write(tasks: [TheoExchange.TaskRecord], groups: [TheoExchange.GroupRecord], deliver: Bool,
                                          appVersion: String?, now: Date) -> Outcome {
        guard let folder = ThaliaFolder.appFolder() else { return .unavailable }
        let today = ExchangeDate.day(now)
        let facts = deliver ? TheoExchange.facts(tasks: tasks, groups: groups, today: today) : [:]
        var changed = false
        var failed = false
        do {
            changed = try ThaliaExchangeWriter.sync(facts, source: TheoExchange.source, appFolder: folder, today: today, now: now,
                                                    mayEmptyAll: !deliver)
        } catch let error as ThaliaExchangeWriter.WriteError {
            // Some days were written all the same: Thalia is still told below.
            changed = error.changed
            failed = true
            print("Theo: exchange files for Thalia: \(error)")
        } catch {
            failed = true
            print("Theo: exchange files for Thalia not written: \(error)")
        }
        // No groups at all is a store that isn't filled yet: Thalia keeps the groups it knows.
        if deliver && !groups.isEmpty {
            do {
                let refs = TheoExchange.refs(groups: groups)
                if try ThaliaExchangeWriter.writeSource(refs: refs, appVersion: appVersion, source: TheoExchange.source,
                                                        app: TheoExchange.appName, appFolder: folder, now: now) {
                    changed = true
                }
            } catch {
                failed = true
                print("Theo: source.json for Thalia not written: \(error)")
            }
        }
        if changed { ThaliaFolder.postChanged() }
        if failed && !changed { return .failed }
        return .written(changed ? now : nil)
    }
}
