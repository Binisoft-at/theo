import Foundation
import SwiftData
import TheoCore

/// Sample content for screenshots (`-TheoDemo`). Never used for real stores, so nothing is
/// ever duplicated through iCloud.
@MainActor
enum DemoData {
    static func seed(_ context: ModelContext) {
        let store = TaskStore(context: context)
        let boundary = DayBoundary.current
        let today = boundary.start(of: Date())
        let cal = Calendar.current

        let work = store.addGroup(name: "Work", symbol: "briefcase", color: .blue)
        let launch = store.addGroup(name: "Theo Launch", symbol: "sparkles", color: .purple, isProject: true)
        launch.dueDate = cal.date(byAdding: .day, value: 9, to: cal.startOfDay(for: today))
        let home = store.addGroup(name: "Home", symbol: "house", color: .orange)
        let health = store.addGroup(name: "Health", symbol: "figure.run", color: .green)

        func add(_ title: String, _ group: TaskGroup?, indent: Int = 0, priority: Priority = .normal,
                 dueDays: Int? = nil, hour: Int? = nil, tags: [String] = [], doneHoursAgo: Double? = nil,
                 createdDaysAgo: Int = 0, notes: String = "") {
            let entry = ParsedEntry(title: title)
            let task = store.addTask(entry, defaultGroupID: group?.uuid, placement: .bottom)
            task.indent = indent
            task.priority = priority
            task.tags = tags
            task.notes = notes
            if let dueDays {
                let day = cal.date(byAdding: .day, value: dueDays, to: cal.startOfDay(for: today)) ?? today
                if let hour {
                    task.dueDate = cal.date(byAdding: .hour, value: hour, to: day)
                    task.dueHasTime = true
                } else {
                    task.dueDate = day
                }
            }
            task.createdAt = cal.date(byAdding: .day, value: -createdDaysAgo, to: Date()) ?? Date()
            if let doneHoursAgo {
                task.isDone = true
                task.completedAt = Date().addingTimeInterval(-doneHoursAgo * 3600)
            }
        }

        add("Call dentist to move appointment", nil, priority: .medium, dueDays: 0, hour: 16)
        add("Buy birthday gift for Ana", nil, tags: ["family"], createdDaysAgo: 2)
        add("Look into standing desk", nil)

        add("Finish Q4 roadmap draft", work, priority: .high, dueDays: 1, tags: ["focus"], createdDaysAgo: 3,
            notes: "Share with Lena before the planning meeting")
        add("Collect numbers from finance", work, indent: 1)
        add("Write summary slide", work, indent: 1)
        add("Reply to Marco about the offsite", work, dueDays: 0)
        add("Review pull requests", work, tags: ["dev"])
        add("1:1 prep notes", work, doneHoursAgo: 2)

        add("Design app icon", launch, priority: .high, doneHoursAgo: 1)
        add("TestFlight build", launch, priority: .high, dueDays: 2)
        add("Write App Store description", launch, priority: .low, dueDays: 6)
        add("Record demo video", launch, dueDays: 8)

        add("Pay electricity bill", home, priority: .medium, dueDays: -1, tags: ["bills"], createdDaysAgo: 4)
        add("Groceries", home)
        add("Oat milk, eggs, spinach", home, indent: 1)
        add("Fix squeaky door", home, doneHoursAgo: 5)

        add("30 min run", health, dueDays: 0, hour: 18)
        add("Book physio session", health, priority: .low)

        // A subgroup that's switched off (its task stays off Today and the other lists).
        let admin = store.addGroup(name: "Admin", symbol: "tray.full", color: .graphite, parent: work.uuid)
        add("Expense report", admin)

        // History for the previous days.
        for day in 1...6 {
            for index in 0..<(2 + day % 3) {
                let entry = ParsedEntry(title: ["Inbox zero", "Gym", "Read 20 pages", "Meal prep", "Team standup notes", "Plan weekend"][(day + index) % 6])
                let task = store.addTask(entry, defaultGroupID: [work, home, health][index % 3].uuid, placement: .bottom)
                task.isDone = true
                task.completedAt = cal.date(byAdding: .day, value: -day, to: Date())
                task.createdAt = cal.date(byAdding: .day, value: -day - 1, to: Date()) ?? Date()
            }
        }

        // Importance levels and estimates, and most of it planned for today.
        let samples: [(level: Int, estimate: Double, planned: Bool)] = [
            (9, 0.5, true), (6, 1, true), (4, 0.25, true), (2, 0, false), (7, 0.75, true),
            (5, 2, false), (8, 0.25, true), (3, 0, true), (10, 1, true), (4, 0.5, false),
        ]
        // Sorted by title so every launch (and every screenshot) gets the same values. The level
        // stays within the band of the priority each task was written with above.
        let todayKey = cal.startOfDay(for: today)
        let open = store.liveTasks().filter { !$0.isDone }.sorted { $0.title < $1.title }
        for (index, task) in open.enumerated() {
            let sample = samples[index % samples.count]
            let level = switch task.priority {
            case .high: 9 + index % 2
            case .medium: 7 + index % 2
            case .low: 5 + index % 2
            case .normal: 2 + index % 3
            }
            task.importance = Matrix.importance(forLevel: level)
            task.priority = Matrix.priority(forImportance: task.importance)
            task.estimate = sample.estimate
            task.plannedDay = sample.planned ? todayKey : nil
        }
        // Work hands its tasks 1 PH and #work; a task that had its own estimate shows the
        // suggestion instead of being changed.
        admin.isActive = false
        work.ownTraits = GroupTraits(estimate: 1, tags: ["work"])
        if let reviews = open.first(where: { $0.title == "Review pull requests" }) {
            reviews.estimate = 0.5
            reviews.plannedDay = todayKey
            reviews.traitProposalGroupID = work.uuid
        }
        store.save()
    }
}
