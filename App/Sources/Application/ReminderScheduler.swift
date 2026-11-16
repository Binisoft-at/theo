import Foundation
import CoreData
import SwiftData
import UserNotifications
import TheoCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Keeps local notifications in step with timed tasks: whenever the store saves (here or, through
/// sync, on another device), the next reminders (at most 60, the system allows 64) are rebuilt
/// from the tasks' deadlines and reminder offsets, and the snoozes and delivered banners of tasks
/// that are done, deleted, without a time or in a switched-off group go away. It also keeps the
/// optional app icon badge (today's open tasks) current. Banners offer Done, Snooze, 1 Hour and
/// Tomorrow; "Still open" nudges offer Done, Tomorrow and Next Week.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let idPrefix = Reminders.idPrefix
    static let category = "theo.task"
    /// Follow-up nudges after the time ("Still open · was due …").
    static let lateCategory = "theo.task.late"
    static let doneAction = "theo.done"
    static let snoozeAction = "theo.snooze"
    static let hourAction = "theo.snooze.hour"
    static let tomorrowAction = "theo.tomorrow"
    static let nextWeekAction = "theo.nextweek"
    /// Settings → App icon badge: "today" shows today's open tasks, "off" (the default) nothing.
    static let badgeModeKey = "badge.mode"

    private let container: ModelContainer
    private var pending: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    /// Counts rebuilds, so an older one still waiting on the notification center stops
    /// instead of adding reminders a newer one already dropped.
    private var generation = 0
    /// The badge as last set (nil until the first rebuild), so it is only set when it changes.
    private var shownBadge: Int?
    /// The badge setting and day start the last rebuild used; a change in Settings rebuilds.
    private var appliedSettings: String?
    /// With the badge on: a rebuild when the next day starts, as "today" changes then.
    private var dayChange: Task<Void, Never>?
    #if os(iOS)
    /// Keeps Theo running briefly after a banner action, so the change reaches iCloud.
    private var backgroundWork: UIBackgroundTaskIdentifier = .invalid
    #endif

    init(container: ModelContainer) {
        self.container = container
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.category,
                actions: [
                    Self.action(Self.doneAction, "Done", symbol: "checkmark"),
                    Self.action(Self.snoozeAction, "Snooze 10 min", symbol: "zzz"),
                    Self.action(Self.hourAction, "1 Hour", symbol: "clock"),
                    Self.action(Self.tomorrowAction, "Tomorrow", symbol: "moon.zzz.fill"),
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: Self.lateCategory,
                actions: [
                    Self.action(Self.doneAction, "Done", symbol: "checkmark"),
                    Self.action(Self.tomorrowAction, "Tomorrow", symbol: "moon.zzz.fill"),
                    Self.action(Self.nextWeekAction, "Next Week", symbol: "calendar"),
                ],
                intentIdentifiers: [],
                options: []
            ),
        ])
        let context = container.mainContext
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            guard (note.object as? ModelContext) === context else { return }
            MainActor.assumeIsolated { self?.scheduleSoon() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSoon() }
        })
        // Turning the badge on or off (or moving the day start) in Settings shows at once.
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.appliedSettings != ReminderScheduler.settingsSignature else { return }
                self.scheduleSoon()
            }
        })
        scheduleSoon()
    }

    /// A banner button that runs in the background, with its SF Symbol.
    private static func action(_ identifier: String, _ title: String, symbol: String) -> UNNotificationAction {
        UNNotificationAction(identifier: identifier, title: title, options: [], icon: UNNotificationActionIcon(systemImageName: symbol))
    }

    private static var badgeShowsToday: Bool {
        UserDefaults.standard.string(forKey: badgeModeKey) == "today"
    }

    private static var settingsSignature: String {
        (UserDefaults.standard.string(forKey: badgeModeKey) ?? "off") + "|" + String(DayBoundary.storedStartHour)
    }

    /// Rebuilds the reminders shortly, once a burst of saves has settled.
    func scheduleSoon() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    /// Rebuilds right away, e.g. before a banner action returns and iOS may suspend Theo.
    /// The delivered banners of the tasks in `cleared` leave Notification Center as well.
    func rescheduleNow(clearingDeliveredOf cleared: Set<UUID> = []) async {
        pending?.cancel()
        pending = nil
        await reschedule(clearingDeliveredOf: cleared)
    }

    private func reschedule(clearingDeliveredOf cleared: Set<UUID> = []) async {
        generation += 1
        let run = generation
        appliedSettings = Self.settingsSignature
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let context = container.mainContext
        // Tasks in switched-off groups stay quiet, as on every list.
        let groups = TaskStore(context: context).liveGroups()
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { task in
            task.deletedAt == nil && task.isDone == false && task.dueHasTime == true
        })
        let tasks = ((try? context.fetch(descriptor)) ?? []).activeOnly(groups)

        // Everything is read from the tasks before the first await: the store can change
        // while this waits on the notification center.
        var keep = Set<UUID>()
        var upcoming: [(date: Date, task: TaskItem, offset: Int)] = []
        for task in tasks {
            guard let due = task.dueDate else { continue }
            let offsets = task.reminderOffsets
            guard !offsets.isEmpty else { continue }
            // An ongoing task checked off for this deadline already: no more nudges for it.
            // (With a repeat, checking it off moves the deadline on, so its reminders follow.)
            if task.isOngoing && task.recurrenceRaw.isEmpty
                && Reminders.isSettled(lastDone: task.lastDoneAt, due: due, offsets: offsets) { continue }
            keep.insert(task.uuid)
            for offset in offsets {
                let date = due.addingTimeInterval(-Double(offset) * 60)
                if date > now { upcoming.append((date, task, offset)) }
            }
        }
        upcoming.sort { $0.date < $1.date }
        let requests = upcoming.prefix(60).map { item in
            UNNotificationRequest(
                identifier: Reminders.identifier(task: item.task.uuid, offset: item.offset),
                content: content(for: item.task, offset: item.offset, firing: item.date),
                trigger: trigger(at: item.date)
            )
        }
        let badgeOn = Self.badgeShowsToday
        let badge = badgeOn ? todayOpenCount(groups: groups) : 0

        // Pending: the reminders are added again below; snoozes stay while their task is open.
        let pendingIDs = await center.pendingNotificationRequests().map(\.identifier)
        guard run == generation else { return }
        let removing = Reminders.pendingToRemove(pendingIDs, keep: keep)
        if !removing.isEmpty { center.removePendingNotificationRequests(withIdentifiers: removing) }

        // Delivered: banners of finished, deleted or untimed tasks leave Notification Center
        // (on every device, as each one rebuilds after a sync).
        let delivered = await center.deliveredNotifications().map { note in
            (id: note.request.identifier, taskID: Reminders.taskID(in: note.request.identifier))
        }
        guard run == generation else { return }
        let stale = Reminders.staleIdentifiers(delivered, keep: keep.subtracting(cleared))
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }

        // Asks for permission the first time something needs it: a reminder, or on iPhone and
        // iPad the badge (the Mac's Dock badge needs none).
        #if os(iOS)
        let needsPermission = !requests.isEmpty || badgeOn
        #else
        let needsPermission = !requests.isEmpty
        #endif
        var allowed = false
        if needsPermission {
            allowed = await isAuthorized(center)
        }
        guard run == generation else { return }
        await updateBadge(badge)
        refreshAtNextDay(badgeOn)
        guard allowed else { return }
        for request in requests {
            guard run == generation else { return }
            try? await center.add(request)
        }
    }

    private func isAuthorized(_ center: UNUserNotificationCenter) async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        #if os(iOS)
        if status == .ephemeral { return true }
        #endif
        return status == .authorized || status == .provisional
    }

    private func content(for task: TaskItem, offset: Int, firing date: Date) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = task.trimmedTitle.isEmpty ? "Task" : task.trimmedTitle
        let time = Self.timeText(task.dueDate ?? date, firing: date)
        switch offset {
        case 0: content.body = "Now · \(time)"
        case 1...: content.body = "\(Reminders.describe(offset).replacingOccurrences(of: " before", with: "")) left · \(time)"
        default: content.body = "Still open · was due \(time)"
        }
        content.sound = .default
        content.categoryIdentifier = offset < 0 ? Self.lateCategory : Self.category
        content.threadIdentifier = task.uuid.uuidString
        content.userInfo = ["task": task.uuid.uuidString]
        return content
    }

    /// "4:00 PM" when the banner comes on the deadline's day, otherwise with the date.
    private static func timeText(_ due: Date, firing date: Date) -> String {
        let sameDay = Calendar.current.isDate(due, inSameDayAs: date)
        return due.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened)
    }

    private func trigger(at date: Date) -> UNCalendarNotificationTrigger {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }

    /// One more reminder in `seconds` (10 minutes or an hour). One per task: a second snooze
    /// replaces the first, and the rebuild drops it once the task is done, deleted or untimed.
    func snooze(taskID: UUID, title: String, due: Date?, seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        let fire = Date().addingTimeInterval(seconds)
        if let due {
            content.body = "Snoozed · due \(Self.timeText(due, firing: fire))"
        } else {
            content.body = "Snoozed reminder"
        }
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.threadIdentifier = taskID.uuidString
        content.userInfo = ["task": taskID.uuidString]
        let request = UNNotificationRequest(
            identifier: Reminders.snoozeIdentifier(task: taskID),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Takes back a task's waiting snooze (old-style ones too) once a banner's Done, Tomorrow or
    /// Next Week has dealt with the task. The rebuild alone keeps it while the task stays open,
    /// e.g. an ongoing task with a repeat, or one moved to tomorrow.
    func cancelSnooze(taskID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            Reminders.snoozeIdentifier(task: taskID),
            Reminders.legacySnoozePrefix + taskID.uuidString,
        ])
    }

    // MARK: - App icon badge

    /// Open tasks on today's page in groups that are on: the number next to Today.
    private func todayOpenCount(groups: [TaskGroup]) -> Int {
        // The day as of now: a rebuild in the background can come before the app's own refresh.
        let today = DayBoundary.current.start(of: Date())
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { task in
            task.deletedAt == nil && task.isDone == false && task.plannedDay != nil
        })
        let planned = ((try? container.mainContext.fetch(descriptor)) ?? []).activeOnly(groups)
        return planned.filter { $0.isPlanned(for: today) }.count
    }

    /// iPhone and iPad: the app icon's badge. Mac: the Dock icon's. 0 clears it.
    private func updateBadge(_ count: Int) async {
        guard count != shownBadge else { return }
        shownBadge = count
        #if os(iOS)
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
        #elseif os(macOS)
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
        #endif
    }

    /// The Mac stays open for days: with the badge on, rebuild when the next day starts. (On
    /// iPhone, opening Theo or a sync rebuilds anyway.)
    private func refreshAtNextDay(_ badgeOn: Bool) {
        dayChange?.cancel()
        dayChange = nil
        guard badgeOn else { return }
        let boundary = DayBoundary.current
        let next = boundary.end(ofDayStarting: boundary.start(of: Date()))
        let seconds = max(60, next.timeIntervalSinceNow + 5)
        dayChange = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.scheduleSoon()
        }
    }

    // MARK: - Background time after a banner action

    #if os(iOS)
    /// A banner action can run while Theo is in the background; iOS may suspend it as soon as
    /// the action returns. Twenty more seconds let the change go out to iCloud, so the Mac stops
    /// reminding too.
    private func holdForSync() {
        guard backgroundWork == .invalid else { return }
        backgroundWork = UIApplication.shared.beginBackgroundTask(withName: "Theo reminder action") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundWork() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.endBackgroundWork()
        }
    }

    private func endBackgroundWork() {
        guard backgroundWork != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundWork)
        backgroundWork = .invalid
    }
    #endif

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let content = response.notification.request.content
        let taskID = content.userInfo["task"] as? String
        let title = content.title
        let delivered = response.notification.date
        await MainActor.run {
            #if os(iOS)
            if action != UNNotificationDefaultActionIdentifier { self.holdForSync() }
            #endif
            AppModel.shared?.handleNotification(action: action, taskID: taskID, title: title, delivered: delivered)
        }
        // Before returning, as Theo may be suspended right after: the task's other reminders
        // (and the next repeat's) are rebuilt now and its banners leave Notification Center.
        var cleared = Set<UUID>()
        if let taskID, let uuid = UUID(uuidString: taskID) { cleared.insert(uuid) }
        await rescheduleNow(clearingDeliveredOf: cleared)
    }
}

extension AppModel {
    /// A reminder's buttons (Done, Snooze, 1 Hour, Tomorrow, Next Week), or a plain tap that
    /// opens the task. `delivered` is when the banner came.
    func handleNotification(action: String, taskID: String?, title: String, delivered: Date) {
        guard let taskID, let uuid = UUID(uuidString: taskID), let task = store.task(id: uuid), task.deletedAt == nil else { return }
        if action == UNNotificationDefaultActionIdentifier {
            openFromNotification(task)
            return
        }
        // Finished meanwhile (here or on another device): the buttons do nothing.
        guard !task.isDone else { return }
        // A banner action can come while Theo slept overnight: use the day as of now.
        let today = DayBoundary.current.start(of: Date())
        let name = task.trimmedTitle.isEmpty ? title : task.trimmedTitle
        switch action {
        case ReminderScheduler.doneAction:
            // An ongoing task already logged since this banner came isn't logged twice.
            if task.isOngoing, let last = task.lastDoneAt, last >= delivered { return }
            store.setDone([task], true)
            reminders?.cancelSnooze(taskID: uuid)
        case ReminderScheduler.snoozeAction:
            reminders?.snooze(taskID: uuid, title: name, due: task.dueDate, seconds: 600)
        case ReminderScheduler.hourAction:
            reminders?.snooze(taskID: uuid, title: name, due: task.dueDate, seconds: 3600)
        case ReminderScheduler.tomorrowAction:
            pushFromNotification(task, days: 1, today: today)
            reminders?.cancelSnooze(taskID: uuid)
        case ReminderScheduler.nextWeekAction:
            pushFromNotification(task, days: 7, today: today)
            reminders?.cancelSnooze(taskID: uuid)
        default:
            break
        }
    }

    /// Tomorrow / Next Week: on that day's plan, with the deadline moved there (keeping its
    /// time) unless it is already that late.
    private func pushFromNotification(_ task: TaskItem, days: Int, today: Date) {
        if Reminders.pushesDeadline(task.dueDate, by: days, today: today) {
            store.postpone([task], days: days, today: today)
        }
        store.plan([task], for: DayBoundary.current.dayStart(byAdding: days, to: today))
    }

    /// iPhone and iPad: the details sheet. Mac: the main window (reopened when it was closed,
    /// Theo keeps running in the menu bar) with the task selected and the inspector open.
    private func openFromNotification(_ task: TaskItem) {
        // Theo may have slept overnight: reveal picks Today or the group page by the current day.
        refreshDay()
        #if os(macOS)
        let hadWindow = MainWindow.isVisible
        MainWindow.reopen()
        guard !hadWindow else {
            reveal(task)
            return
        }
        // A reopened window builds its pages first; the page change must reach them.
        Task { @MainActor [weak self] in
            var waited = 0
            while !MainWindow.isVisible && waited < 30 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
            try? await Task.sleep(for: .milliseconds(150))
            self?.reveal(task)
        }
        #else
        reveal(task)
        #endif
    }
}
