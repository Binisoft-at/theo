import Foundation
import UserNotifications
import TheoCore

/// A running focus timer, Pomodoro style: a focus phase (one Power Hour, 50 minutes, by
/// default), then a break.
struct FocusSession: Codable, Equatable {
    enum Phase: String, Codable {
        case focus
        case rest
    }

    var taskID: UUID?
    var title: String
    var phase: Phase
    /// When the current stretch started counting.
    var startedAt: Date
    /// Length of the current stretch in seconds.
    var duration: TimeInterval
    /// Time left while paused (or while a new focus phase waits to be started).
    var pausedRemaining: TimeInterval?
    /// Focus phases finished in this session.
    var rounds = 0

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        return max(0, duration - now.timeIntervalSince(startedAt))
    }

    /// Time counted in the current stretch.
    func elapsed(at now: Date) -> TimeInterval {
        isPaused ? 0 : duration - remaining(at: now)
    }
}

/// Focused time per logical day on this device, for the totals.
enum FocusLog {
    private static let key = "focusLog"

    private static func dayKey(_ date: Date) -> String {
        let start = DayBoundary.current.start(of: date)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: start)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func add(_ seconds: TimeInterval, on date: Date) {
        var log = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        log[dayKey(date), default: 0] += seconds
        UserDefaults.standard.set(log, forKey: key)
    }

    static func seconds(on date: Date) -> TimeInterval {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Double])?[dayKey(date)] ?? 0
    }
}

extension AppModel {
    private static let focusKey = "focusSession"
    private static let focusNotificationID = "theo.focus"

    var focusMinutes: Double {
        let value = UserDefaults.standard.integer(forKey: Prefs.focusMinutes)
        return Double(value > 0 ? value : 50)
    }

    var breakMinutes: Double {
        let value = UserDefaults.standard.integer(forKey: Prefs.breakMinutes)
        return Double(value > 0 ? value : 10)
    }

    static func loadFocus() -> FocusSession? {
        guard let data = UserDefaults.standard.data(forKey: focusKey) else { return nil }
        return try? JSONDecoder().decode(FocusSession.self, from: data)
    }

    func saveFocus() {
        guard !isSandbox else { return }
        if let focus, let data = try? JSONEncoder().encode(focus) {
            UserDefaults.standard.set(data, forKey: Self.focusKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.focusKey)
        }
        scheduleFocusNotification()
    }

    /// Starts focusing on a task (or on nothing in particular) and shows the timer.
    func startFocus(on task: TaskItem?) {
        if let current = focus { logStretch(current, now: Date()) }
        focus = FocusSession(
            taskID: task?.uuid,
            title: task?.trimmedTitle ?? "Focus",
            phase: .focus,
            startedAt: Date(),
            duration: focusMinutes * 60
        )
        saveFocus()
        showFocus = true
    }

    func pauseFocus() {
        guard var session = focus, !session.isPaused else { return }
        let now = Date()
        logStretch(session, now: now)
        session.pausedRemaining = session.remaining(at: now)
        focus = session
        saveFocus()
    }

    func resumeFocus() {
        guard var session = focus, let left = session.pausedRemaining else { return }
        session.startedAt = Date()
        session.duration = left
        session.pausedRemaining = nil
        focus = session
        saveFocus()
    }

    func stopFocus() {
        if let session = focus { logStretch(session, now: Date()) }
        focus = nil
        showFocus = false
        saveFocus()
    }

    func extendFocus(minutes: Double) {
        guard var session = focus else { return }
        if let left = session.pausedRemaining {
            session.pausedRemaining = left + minutes * 60
        } else {
            session.duration += minutes * 60
        }
        focus = session
        saveFocus()
    }

    /// Ends the break early and gets the next focus phase ready.
    func skipBreak() {
        guard focus?.phase == .rest else { return }
        finishPhase(now: Date())
    }

    /// Called every second while a timer is visible, and when the app becomes active.
    func tickFocus(now: Date = Date()) {
        guard let session = focus, !session.isPaused, session.remaining(at: now) <= 0 else { return }
        finishPhase(now: now)
    }

    /// Focus → break starts right away; break → the next focus phase waits for a tap.
    private func finishPhase(now: Date) {
        guard var session = focus else { return }
        logStretch(session, now: now)
        switch session.phase {
        case .focus:
            session.rounds += 1
            session.phase = .rest
            session.duration = breakMinutes * 60
            session.pausedRemaining = nil
        case .rest:
            session.phase = .focus
            session.duration = focusMinutes * 60
            session.pausedRemaining = session.duration
        }
        session.startedAt = now
        focus = session
        saveFocus()
    }

    /// Books focused time on the task and in today's log.
    private func logStretch(_ session: FocusSession, now: Date) {
        guard session.phase == .focus else { return }
        let seconds = session.elapsed(at: now)
        guard seconds >= 5 else { return }
        if !isSandbox { FocusLog.add(seconds, on: now) }
        if let id = session.taskID, let task = store.task(id: id) {
            store.addFocusTime(task, seconds: seconds)
        }
    }

    private func scheduleFocusNotification() {
        guard !isSandbox else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.focusNotificationID])
        guard let session = focus, !session.isPaused else { return }
        let content = UNMutableNotificationContent()
        switch session.phase {
        case .focus:
            content.title = "Focus done"
            content.body = "\(session.title): time for a \(Int(breakMinutes))-minute break."
        case .rest:
            content.title = "Break's over"
            content.body = "Ready for the next Power Hour?"
        }
        content.sound = .default
        let seconds = max(1, session.remaining(at: Date()))
        let request = UNNotificationRequest(
            identifier: Self.focusNotificationID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            try? await center.add(request)
        }
    }
}
