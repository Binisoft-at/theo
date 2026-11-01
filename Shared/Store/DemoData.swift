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

        // Spread the open tasks over the matrix and give some an estimate.
        let samples: [(urgency: Double, importance: Double, estimate: Double)] = [
            (0.82, 0.86, 0.5), (0.3, 0.8, 1), (0.74, 0.3, 0.25), (0.2, 0.18, 0), (0.6, 0.66, 0.75),
            (0.15, 0.62, 2), (0.9, 0.42, 0.25), (0.42, 0.33, 0), (0.55, 0.92, 1), (0.08, 0.4, 0.5),
        ]
        for (index, task) in store.liveTasks().filter({ !$0.isDone }).enumerated() {
            let sample = samples[index % samples.count]
            task.urgency = sample.urgency
            task.importance = sample.importance
            task.estimate = sample.estimate
        }
        store.save()
    }
}
