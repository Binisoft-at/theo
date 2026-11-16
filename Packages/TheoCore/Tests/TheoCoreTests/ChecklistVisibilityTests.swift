import Foundation
import Testing
@testable import TheoCore

/// A checklist line for the visibility tests.
struct VisibilityLine: ChecklistItem {
    var name: String
    var sortOrder: Double
    var indent: Int = 0
    var isDone = false
    var completedAt: Date?
}

@Suite("Checklist nesting on a page that shows only some lines")
struct ChecklistVisibilityTests {
    /// Depths of `lines` (in manual order) when only the named lines are on the page.
    private func depths(_ lines: [VisibilityLine], showing names: Set<String>) -> [Int?] {
        Checklist.visibleDepths(ordered: lines) { names.contains(lines[$0].name) }
    }

    @Test func hiddenParentPutsTheSubtaskAtTheTop() {
        // "b" isn't on the page, its subtask is: it must not hang under "a".
        let lines = [
            VisibilityLine(name: "a", sortOrder: 0),
            VisibilityLine(name: "b", sortOrder: 1),
            VisibilityLine(name: "b1", sortOrder: 2, indent: 1),
        ]
        #expect(depths(lines, showing: ["a", "b1"]) == [0, nil, 0])
    }

    @Test func shownParentKeepsTheSubtaskNested() {
        let lines = [
            VisibilityLine(name: "a", sortOrder: 0),
            VisibilityLine(name: "a1", sortOrder: 1, indent: 1),
        ]
        #expect(depths(lines, showing: ["a", "a1"]) == [0, 1])
    }

    @Test func grandchildUnderAHiddenMiddleSitsUnderTheTop() {
        let lines = [
            VisibilityLine(name: "top", sortOrder: 0),
            VisibilityLine(name: "middle", sortOrder: 1, indent: 1),
            VisibilityLine(name: "grandchild", sortOrder: 2, indent: 2),
        ]
        #expect(depths(lines, showing: ["top", "grandchild"]) == [0, nil, 1])
    }

    @Test func siblingAfterAHiddenBlockKeepsItsLevel() {
        let lines = [
            VisibilityLine(name: "parent", sortOrder: 0),
            VisibilityLine(name: "hidden", sortOrder: 1, indent: 1),
            VisibilityLine(name: "under hidden", sortOrder: 2, indent: 2),
            VisibilityLine(name: "sibling", sortOrder: 3, indent: 1),
            VisibilityLine(name: "next", sortOrder: 4),
        ]
        #expect(depths(lines, showing: ["parent", "under hidden", "sibling", "next"]) == [0, nil, 1, 1, 0])
    }

    @Test func everythingShownMatchesTheStoredDepths() {
        let lines = [
            VisibilityLine(name: "a", sortOrder: 0, indent: 2),
            VisibilityLine(name: "b", sortOrder: 1, indent: 1),
            VisibilityLine(name: "c", sortOrder: 2, indent: 3),
            VisibilityLine(name: "d", sortOrder: 3, indent: 2),
            VisibilityLine(name: "e", sortOrder: 4),
        ]
        let all = Set(lines.map(\.name))
        #expect(depths(lines, showing: all) == Checklist.depths(of: lines).map { Optional($0) })
    }

    @Test func nothingShownGivesNoDepths() {
        let lines = [
            VisibilityLine(name: "a", sortOrder: 0),
            VisibilityLine(name: "a1", sortOrder: 1, indent: 1),
        ]
        #expect(depths(lines, showing: []) == [nil, nil])
    }

    @Test func parentsFollowTheDepths() {
        #expect(Checklist.parents(depths: [0, 1, 2, 1, 0, 1]) == [nil, 0, 1, 0, nil, 4])
        #expect(Checklist.parents(depths: []) == [])
    }

    @Test func reindentedLinesNoLongerNestUnderAStranger() {
        let lines = [
            VisibilityLine(name: "a", sortOrder: 0),
            VisibilityLine(name: "b", sortOrder: 1),
            VisibilityLine(name: "b1", sortOrder: 2, indent: 1),
        ]
        let shown = ["a", "b1"]
        // Without the full section, "b1" lands under "a".
        let naive = Checklist.displayOrder(lines.filter { shown.contains($0.name) }, showCompleted: true)
        #expect(naive.map(\.depth) == [0, 1])

        // With it, each shown line takes its depth on the page as its indent.
        let pageDepths = depths(lines, showing: Set(shown))
        var reindented: [VisibilityLine] = []
        for (index, line) in lines.enumerated() {
            guard let depth = pageDepths[index] else { continue }
            var copy = line
            copy.indent = depth
            reindented.append(copy)
        }
        let order = Checklist.displayOrder(reindented, showCompleted: true)
        #expect(order.map(\.item.name) == ["a", "b1"])
        #expect(order.map(\.depth) == [0, 0])
    }
}
