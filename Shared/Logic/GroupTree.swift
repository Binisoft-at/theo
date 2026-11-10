import Foundation

/// Groups can sit inside other groups (subprojects). Helpers that walk that tree.
enum GroupTree {
    /// Groups in page order, each subproject right after its parent, with its nesting level.
    /// Groups whose parent is gone (or that form a loop) are shown at the top level.
    static func ordered(_ groups: [TaskGroup]) -> [(group: TaskGroup, level: Int)] {
        let ids = Set(groups.map(\.uuid))
        var children: [UUID?: [TaskGroup]] = [:]
        for group in groups.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let parent = group.parentUUID.flatMap { ids.contains($0) && $0 != group.uuid ? $0 : nil }
            children[parent, default: []].append(group)
        }
        var result: [(group: TaskGroup, level: Int)] = []
        var visited = Set<UUID>()
        func visit(_ parent: UUID?, level: Int) {
            for group in children[parent] ?? [] where !visited.contains(group.uuid) {
                visited.insert(group.uuid)
                result.append((group, level))
                visit(group.uuid, level: level + 1)
            }
        }
        visit(nil, level: 0)
        for group in groups.sorted(by: { $0.sortOrder < $1.sortOrder }) where !visited.contains(group.uuid) {
            visited.insert(group.uuid)
            result.append((group, 0))
            visit(group.uuid, level: 1)
        }
        return result
    }

    /// Every group inside `id`, at any depth.
    static func descendants(of id: UUID, in groups: [TaskGroup]) -> [TaskGroup] {
        var result: [TaskGroup] = []
        var frontier: Set<UUID> = [id]
        var seen: Set<UUID> = [id]
        while !frontier.isEmpty {
            let next = groups.filter { group in
                guard let parent = group.parentUUID else { return false }
                return frontier.contains(parent) && !seen.contains(group.uuid)
            }
            result += next
            frontier = Set(next.map(\.uuid))
            seen.formUnion(frontier)
        }
        return result
    }

    /// Groups that are switched off, together with every group inside them.
    static func inactiveIDs(_ groups: [TaskGroup]) -> Set<UUID> {
        var result = Set<UUID>()
        for group in groups where !group.isActive && !result.contains(group.uuid) {
            result.insert(group.uuid)
            for child in descendants(of: group.uuid, in: groups) { result.insert(child.uuid) }
        }
        return result
    }

    /// Off itself, or inside a group that is.
    static func isOff(_ group: TaskGroup, in groups: [TaskGroup]) -> Bool {
        inactiveIDs(groups).contains(group.uuid)
    }

    /// "haeb tasks › 1. Laufend".
    static func path(of group: TaskGroup, in groups: [TaskGroup]) -> String {
        var names = [group.displayName]
        var current = group
        var seen: Set<UUID> = [group.uuid]
        while let parentID = current.parentUUID, !seen.contains(parentID), let parent = groups.first(where: { $0.uuid == parentID }) {
            names.insert(parent.displayName, at: 0)
            seen.insert(parentID)
            current = parent
        }
        return names.joined(separator: " › ")
    }
}

extension Array where Element == TaskItem {
    /// Leaves out tasks whose group (or a group it sits in) is switched off.
    func activeOnly(_ groups: [TaskGroup]) -> [TaskItem] {
        let off = GroupTree.inactiveIDs(groups)
        guard !off.isEmpty else { return self }
        return filter { task in task.groupID.map { !off.contains($0) } ?? true }
    }
}

extension Array where Element == TaskGroup {
    /// Groups that are on (and not inside a group that's off).
    var activeOnly: [TaskGroup] {
        let off = GroupTree.inactiveIDs(self)
        guard !off.isEmpty else { return self }
        return filter { !off.contains($0.uuid) }
    }
}
