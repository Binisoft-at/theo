import Foundation
import Observation
import TheoCore

/// Screens the watch app can push.
enum WatchRoute: Hashable {
    case lists
    case upcoming
    case priority
    /// A group page; `nil` is Quick Entry.
    case group(UUID?)
    case task(TaskItem)
}

@MainActor
@Observable
final class WatchModel {
    /// Start of the current logical day, refreshed whenever the app becomes active.
    var dayStart: Date
    var path: [WatchRoute] = []

    init() {
        dayStart = DayBoundary.current.start(of: Date())
        applyLaunchArguments()
    }

    func refreshDay() {
        let start = DayBoundary.current.start(of: Date())
        if start != dayStart { dayStart = start }
    }

    func show(_ route: WatchRoute) {
        path.append(route)
    }

    /// `-TheoScreen lists|upcoming|priority` opens a page directly (screenshots).
    private func applyLaunchArguments() {
        switch UserDefaults.standard.string(forKey: "TheoScreen") {
        case "lists": path = [.lists]
        case "upcoming": path = [.lists, .upcoming]
        case "priority": path = [.lists, .priority]
        default: break
        }
    }
}
