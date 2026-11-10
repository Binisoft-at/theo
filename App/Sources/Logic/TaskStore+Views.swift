import Foundation
import SwiftData
import TheoCore

/// Saved views and favourites.
extension TaskStore {
    func liveViews() -> [SavedView] {
        let descriptor = FetchDescriptor<SavedView>(
            predicate: #Predicate<SavedView> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\SavedView.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addView(name: String, query: TaskQuery) -> SavedView {
        let order = (liveViews().map(\.sortOrder).max() ?? 0) + 1
        let view = SavedView(name: name, query: query, sortOrder: order)
        context.insert(view)
        save()
        return view
    }

    func updateView(_ view: SavedView, query: TaskQuery) {
        view.query = query
        view.touch()
        save()
    }

    func renameView(_ view: SavedView, to name: String) {
        view.name = name
        view.touch()
        save()
    }

    func deleteView(_ view: SavedView) {
        view.deletedAt = Date()
        view.touch()
        save()
    }

    func setFavorite(_ view: SavedView, _ favorite: Bool) {
        view.isFavorite = favorite
        view.touch()
        save()
    }

    func setFavorite(_ group: TaskGroup, _ favorite: Bool) {
        group.isFavorite = favorite
        group.touch()
        save()
    }
}
