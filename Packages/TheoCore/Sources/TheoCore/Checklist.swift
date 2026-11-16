import Foundation

/// A line in a checklist: manual position, nesting level and completion state.
public protocol ChecklistItem {
    var sortOrder: Double { get }
    var indent: Int { get }
    var isDone: Bool { get }
    var completedAt: Date? { get }
}

/// Checklist rules shared by every page, like an Apple Notes checklist:
/// nesting comes from each line's indent (never deeper than one level below the previous
/// line) and completed lines sink to the bottom of their level.
public enum Checklist {
    /// Nesting depth of each item. `items` must already be in manual order.
    public static func depths<Item: ChecklistItem>(of items: [Item]) -> [Int] {
        var depths: [Int] = []
        var previous = -1
        for item in items {
            let depth = max(0, min(item.indent, previous + 1))
            depths.append(depth)
            previous = depth
        }
        return depths
    }

    /// End (exclusive) of the block that starts at `index`: the line plus every deeper line below it.
    public static func blockEnd(after index: Int, depths: [Int]) -> Int {
        var end = index + 1
        while end < depths.count, depths[end] > depths[index] { end += 1 }
        return end
    }

    /// The line each line is a subtask of (its index), nil for top-level lines. `depths` as
    /// `depths(of:)` returns them.
    public static func parents(depths: [Int]) -> [Int?] {
        var open: [Int] = []
        var result: [Int?] = []
        result.reserveCapacity(depths.count)
        for index in depths.indices {
            while let last = open.last, depths[last] >= depths[index] { open.removeLast() }
            result.append(open.last)
            open.append(index)
        }
        return result
    }

    /// Nesting depth of each line once some lines are left off a page: a shown line sits under
    /// its nearest ancestor that is shown too, so a subtask whose parent isn't on the page stands
    /// at the top level instead of under whatever line happens to come before it. nil for the
    /// lines left off. `ordered` is the whole section in manual order; `isVisible` gets an index
    /// into it.
    public static func visibleDepths<Item: ChecklistItem>(ordered items: [Item], isVisible: (Int) -> Bool) -> [Int?] {
        let levels = depths(of: items)
        var ancestors: [(depth: Int, visible: Bool)] = []
        var visibleAncestors = 0
        var result: [Int?] = []
        result.reserveCapacity(items.count)
        for index in items.indices {
            let depth = levels[index]
            while let last = ancestors.last, last.depth >= depth {
                ancestors.removeLast()
                if last.visible { visibleAncestors -= 1 }
            }
            let visible = isVisible(index)
            result.append(visible ? visibleAncestors : nil)
            ancestors.append((depth: depth, visible: visible))
            if visible { visibleAncestors += 1 }
        }
        return result
    }

    /// Display order: nested, open lines ranked by `rank` (highest first, manual order breaks ties;
    /// manual order only without a rank), completed lines (and their subtasks) after the open
    /// ones of the same level, most recently completed first. With `showCompleted == false`
    /// completed lines are left out together with their subtasks.
    public static func displayOrder<Item: ChecklistItem>(_ items: [Item], showCompleted: Bool, rank: ((Item) -> Double)? = nil) -> [(item: Item, depth: Int)] {
        let sorted = items.sorted { $0.sortOrder < $1.sortOrder }
        let levels = Self.depths(of: sorted)

        func children(of parent: Int?) -> [Int] {
            let start = parent.map { $0 + 1 } ?? 0
            let end = parent.map { blockEnd(after: $0, depths: levels) } ?? sorted.count
            let level = parent.map { levels[$0] + 1 } ?? 0
            return (start..<end).filter { levels[$0] == level }
        }

        var output: [(item: Item, depth: Int)] = []
        func visit(_ parent: Int?) {
            let siblings = children(of: parent)
            var open = siblings.filter { !sorted[$0].isDone }
            if let rank {
                let scores = Dictionary(uniqueKeysWithValues: open.map { ($0, rank(sorted[$0])) })
                open.sort { (scores[$0] ?? 0, -$0) > (scores[$1] ?? 0, -$1) }
            }
            let done = siblings.filter { sorted[$0].isDone }
                .sorted { (sorted[$0].completedAt ?? .distantPast) > (sorted[$1].completedAt ?? .distantPast) }
            for index in open {
                output.append((sorted[index], levels[index]))
                visit(index)
            }
            guard showCompleted else { return }
            for index in done {
                output.append((sorted[index], levels[index]))
                visit(index)
            }
        }
        visit(nil)
        return output
    }
}
