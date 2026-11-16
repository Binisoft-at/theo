import Foundation
import Testing
@testable import TheoCore

/// Which notifications go away when tasks are finished, deleted or lose their time, and
/// what a banner's Tomorrow / Next Week does to the deadline.
@Suite("Reminder hygiene")
struct ReminderHygieneTests {
    let openTask = UUID()
    let finishedTask = UUID()

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return calendar
    }

    /// 16 November 2026 plus `offset` days, at `hour`.
    private func day(_ offset: Int, hour: Int = 9) -> Date {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: start)!
    }

    @Test func identifiersNameTheirTask() {
        #expect(Reminders.taskID(in: Reminders.identifier(task: openTask, offset: 15)) == openTask)
        #expect(Reminders.taskID(in: Reminders.identifier(task: openTask, offset: -10)) == openTask)
        #expect(Reminders.taskID(in: Reminders.snoozeIdentifier(task: openTask)) == openTask)
        #expect(Reminders.taskID(in: "theo.snooze." + openTask.uuidString) == openTask)
        #expect(Reminders.taskID(in: "theo.focus") == nil)
        #expect(Reminders.taskID(in: "theo.task.not-a-task") == nil)
    }

    @Test func recognisesSnoozes() {
        #expect(Reminders.isSnooze(Reminders.snoozeIdentifier(task: openTask)))
        #expect(Reminders.isSnooze("theo.snooze." + openTask.uuidString))
        #expect(!Reminders.isSnooze(Reminders.identifier(task: openTask, offset: 0)))
        #expect(!Reminders.isSnooze("theo.focus"))
    }

    @Test func rebuildDropsEverySnoozeOfAFinishedTask() {
        let ids = [
            Reminders.identifier(task: openTask, offset: 0),
            Reminders.identifier(task: finishedTask, offset: -10),
            Reminders.snoozeIdentifier(task: openTask),
            Reminders.snoozeIdentifier(task: finishedTask),
            "theo.snooze." + openTask.uuidString,
            "theo.snooze." + finishedTask.uuidString,
            "theo.focus",
        ]
        let removed = Set(Reminders.pendingToRemove(ids, keep: [openTask]))
        let expected: Set<String> = [
            Reminders.identifier(task: openTask, offset: 0),
            Reminders.identifier(task: finishedTask, offset: -10),
            Reminders.snoozeIdentifier(task: finishedTask),
            "theo.snooze." + finishedTask.uuidString,
        ]
        #expect(removed == expected)
    }

    @Test func deliveredBannersOfFinishedTasksGo() {
        let items: [(id: String, taskID: UUID?)] = [
            (id: "a", taskID: openTask),
            (id: "b", taskID: finishedTask),
            (id: "theo.focus", taskID: nil),
        ]
        #expect(Reminders.staleIdentifiers(items, keep: [openTask]) == ["b"])
        #expect(Reminders.staleIdentifiers(items, keep: [openTask, finishedTask]).isEmpty)
        #expect(Reminders.staleIdentifiers(items, keep: []) == ["a", "b"])
    }

    @Test func tomorrowNeverPullsADeadlineCloser() {
        let today = day(0, hour: 4)
        #expect(Reminders.pushesDeadline(day(0, hour: 16), by: 1, today: today, calendar: calendar))
        #expect(Reminders.pushesDeadline(day(-3), by: 1, today: today, calendar: calendar))
        #expect(!Reminders.pushesDeadline(day(1), by: 1, today: today, calendar: calendar))
        #expect(!Reminders.pushesDeadline(day(2), by: 1, today: today, calendar: calendar))
        #expect(Reminders.pushesDeadline(day(3), by: 7, today: today, calendar: calendar))
        #expect(!Reminders.pushesDeadline(nil, by: 1, today: today, calendar: calendar))
    }

    @Test func ongoingTaskCheckedOffNeedsNoMoreReminders() {
        let due = day(0, hour: 16)
        // Checked off at the time: the follow-up nudges stop.
        #expect(Reminders.isSettled(lastDone: due, due: due, offsets: [0, -10, -20]))
        // A reminder an hour ahead, checked off when it came.
        #expect(Reminders.isSettled(lastDone: day(0, hour: 15), due: due, offsets: [60, 0]))
        // Checked off in the morning, before any reminder: they still come.
        #expect(!Reminders.isSettled(lastDone: day(0, hour: 9), due: due, offsets: [60, 0]))
        #expect(!Reminders.isSettled(lastDone: nil, due: due, offsets: [0]))
        #expect(!Reminders.isSettled(lastDone: due, due: due, offsets: []))
    }
}
