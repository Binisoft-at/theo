import Foundation
import CoreData
import SwiftData
import UserNotifications
import TheoCore

/// Keeps local notifications in step with timed tasks: whenever the store saves, the next
/// reminders (at most 60, the system allows 64) are rebuilt from the tasks' deadlines and
/// reminder offsets. Notifications offer Done and Snooze.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let idPrefix = "theo.task."
    static let category = "theo.task"
    static let doneAction = "theo.done"
    static let snoozeAction = "theo.snooze"

    private let container: ModelContainer
    private var pending: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(container: ModelContainer) {
        self.container = container
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.category,
                actions: [
                    UNNotificationAction(identifier: Self.doneAction, title: "Mark as Done", options: []),
                    UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 10 Minutes", options: []),
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
        let context = container.mainContext
        observers.append(NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            guard (note.object as? ModelContext) === context else { return }
            MainActor.assumeIsolated { self?.scheduleSoon() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSoon() }
        })
        scheduleSoon()
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

    private func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { task in
            task.deletedAt == nil && task.isDone == false && task.dueHasTime == true
        })
        let tasks = (try? container.mainContext.fetch(descriptor)) ?? []
        var upcoming: [(date: Date, task: TaskItem, offset: Int)] = []
        for task in tasks {
            guard let due = task.dueDate else { continue }
            for offset in task.reminderOffsets {
                let date = due.addingTimeInterval(-Double(offset) * 60)
                if date > now { upcoming.append((date, task, offset)) }
            }
        }
        upcoming.sort { $0.date < $1.date }
        let chosen = Array(upcoming.prefix(60))

        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard !chosen.isEmpty, await isAuthorized(center) else { return }
        for item in chosen {
            let request = UNNotificationRequest(
                identifier: Self.idPrefix + item.task.uuid.uuidString + "." + String(item.offset),
                content: content(for: item.task, offset: item.offset),
                trigger: trigger(at: item.date)
            )
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

    private func content(for task: TaskItem, offset: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = task.trimmedTitle.isEmpty ? "Task" : task.trimmedTitle
        let time = (task.dueDate ?? Date()).formatted(date: Calendar.current.isDateInToday(task.dueDate ?? Date()) ? .omitted : .abbreviated, time: .shortened)
        switch offset {
        case 0: content.body = "Now · \(time)"
        case 1...: content.body = "\(Reminders.describe(offset).replacingOccurrences(of: " before", with: "")) left · \(time)"
        default: content.body = "Still open · was due \(time)"
        }
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.threadIdentifier = task.uuid.uuidString
        content.userInfo = ["task": task.uuid.uuidString]
        return content
    }

    private func trigger(at date: Date) -> UNCalendarNotificationTrigger {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }

    /// One extra reminder ten minutes from now.
    func snooze(taskID: String, title: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Snoozed reminder"
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = ["task": taskID]
        let request = UNNotificationRequest(
            identifier: "theo.snooze." + taskID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let taskID = response.notification.request.content.userInfo["task"] as? String
        let title = response.notification.request.content.title
        await MainActor.run {
            AppModel.shared?.handleNotification(action: action, taskID: taskID, title: title)
        }
    }
}

extension AppModel {
    /// Done / Snooze from a notification, or a plain tap that opens the task.
    func handleNotification(action: String, taskID: String?, title: String) {
        guard let taskID, let uuid = UUID(uuidString: taskID), let task = store.task(id: uuid), task.deletedAt == nil else { return }
        switch action {
        case ReminderScheduler.doneAction:
            store.setDone([task], true)
        case ReminderScheduler.snoozeAction:
            reminders?.snooze(taskID: taskID, title: title)
        default:
            detailTask = task
        }
    }
}
