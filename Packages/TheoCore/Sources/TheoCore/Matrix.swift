import Foundation

/// The Eisenhower matrix: every task has an urgency and an importance between 0 and 1, set by
/// where it was dropped on the canvas. Priority raises importance and a close deadline raises
/// urgency. Tasks are ranked by a score that weighs importance above urgency.
public enum Matrix {
    /// New tasks sit in the middle of "not urgent, not important".
    public static let defaultUrgency = 0.25
    public static let defaultImportance = 0.25

    public enum Quadrant: Int, CaseIterable, Identifiable, Sendable {
        case doFirst
        case schedule
        case delegate
        case later

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .doFirst: "Do First"
            case .schedule: "Schedule"
            case .delegate: "Delegate"
            case .later: "Later"
            }
        }

        public var subtitle: String {
            switch self {
            case .doFirst: "Urgent · Important"
            case .schedule: "Important · Not urgent"
            case .delegate: "Urgent · Not important"
            case .later: "Not urgent · Not important"
            }
        }

        public var symbol: String {
            switch self {
            case .doFirst: "flame"
            case .schedule: "calendar"
            case .delegate: "person.2"
            case .later: "tray"
            }
        }
    }

    public static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    public static func quadrant(urgency: Double, importance: Double) -> Quadrant {
        switch (urgency >= 0.5, importance >= 0.5) {
        case (true, true): .doFirst
        case (false, true): .schedule
        case (true, false): .delegate
        case (false, false): .later
        }
    }

    /// 0...1, importance weighted above urgency, so "important, not urgent" outranks
    /// "urgent, not important" (the Eisenhower order), and distance inside a quadrant counts.
    public static func score(urgency: Double, importance: Double) -> Double {
        0.6 * clamp(importance) + 0.4 * clamp(urgency)
    }

    /// Each priority level adds importance.
    public static func effectiveImportance(_ importance: Double, priority: Priority) -> Double {
        clamp(importance + 0.15 * Double(priority.rawValue))
    }

    /// How urgent a deadline alone makes a task (0 when there's none or it's far away).
    public static func deadlineUrgency(due: Date?, today: Date, calendar: Calendar = .current) -> Double {
        guard let due else { return 0 }
        switch DateText.dayDelta(due, today: today, calendar: calendar) {
        case ..<0: return 1
        case 0: return 0.85
        case 1: return 0.72
        case 2...3: return 0.6
        case 4...7: return 0.45
        default: return 0
        }
    }

    public static func effectiveUrgency(_ urgency: Double, due: Date?, today: Date, calendar: Calendar = .current) -> Double {
        max(clamp(urgency), deadlineUrgency(due: due, today: today, calendar: calendar))
    }

    /// The stored position that makes a task show up where it was dropped: the priority's
    /// importance boost is taken back out. (A close deadline still keeps it at least that urgent.)
    public static func storedPosition(forDrop urgency: Double, importance: Double, priority: Priority) -> (urgency: Double, importance: Double) {
        (clamp(urgency), clamp(importance - 0.15 * Double(priority.rawValue)))
    }
}
