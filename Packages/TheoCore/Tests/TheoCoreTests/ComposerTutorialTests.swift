import Foundation
import Testing
@testable import TheoCore

@Suite("Composer")
struct ComposerTests {
    @Test(arguments: ["- book flights", "> book flights", "  - book flights", "– book flights"])
    func subtaskMarkers(text: String) {
        #expect(Composer.subtaskBody(text) == "book flights")
    }

    @Test func plainTextIsNotASubtask() {
        #expect(Composer.subtaskBody("book flights") == nil)
        #expect(Composer.subtaskBody("-5 degrees tonight") == nil)
    }

    @Test func markerAloneIsAnEmptySubtask() {
        #expect(Composer.subtaskBody("- ") == "")
    }

    @Test func pastedListKeepsNesting() {
        let text = """
        Plan trip
          - Book flights
          - Find hotel
        \t\tCompare prices
        Pack
        """
        let lines = Composer.lines(text)
        #expect(lines.map(\.title) == ["Plan trip", "Book flights", "Find hotel", "Compare prices", "Pack"])
        #expect(lines.map(\.level) == [0, 1, 1, 2, 0])
    }

    @Test func nestingNeverSkipsALevel() {
        let lines = Composer.lines("\t\tDeep first\n\t\t\t\tDeeper")
        #expect(lines.map(\.level) == [0, 1])
    }

    @Test func blankLinesAndBareMarkersAreDropped() {
        let lines = Composer.lines("Milk\n\n- \n[ ] Eggs\n• Bread")
        #expect(lines.map(\.title) == ["Milk", "Eggs", "Bread"])
    }

    @Test func priorityCycles() {
        #expect(Priority.normal.next == .low)
        #expect(Priority.low.next == .medium)
        #expect(Priority.medium.next == .high)
        #expect(Priority.high.next == .normal)
    }
}

@Suite("Tutorial")
struct TutorialTests {
    @Test func stepIDsAreUnique() {
        let ids = TutorialCatalog.steps.map(\.id) + [TutorialCatalog.whatsNew.id]
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyStepIsReleasedAndWritten() {
        for step in TutorialCatalog.steps {
            #expect(step.since >= 1 && step.since <= TutorialCatalog.version, "\(step.id)")
            #expect(!step.title.isEmpty && !step.body.isEmpty && !step.macBody.isEmpty, "\(step.id)")
        }
    }

    @Test func tourStartsWithWelcomeAndEndsWithFinish() {
        #expect(TutorialCatalog.steps.first?.id == "welcome")
        #expect(TutorialCatalog.steps.last?.id == "finish")
    }

    @Test func firstRunGetsEverything() {
        #expect(TutorialCatalog.steps(newerThan: 0).count == TutorialCatalog.steps.count)
    }

    @Test func upToDateGetsNothing() {
        #expect(TutorialCatalog.steps(newerThan: TutorialCatalog.version).isEmpty)
    }

    @Test func addingATask() {
        var tracker = TutorialTracker(baseline: snapshot(tasks: 3))
        #expect(!tracker.isMet(.addTask, now: snapshot(tasks: 3)))
        #expect(tracker.isMet(.addTask, now: snapshot(tasks: 4)))
    }

    @Test func shortcutsNeedDeadlineAndPriority() {
        var base = snapshot(tasks: 3)
        base.datedCount = 1
        var tracker = TutorialTracker(baseline: base)
        var onlyDate = base
        onlyDate.taskCount = 4
        onlyDate.datedCount = 2
        #expect(!tracker.isMet(.addTaskWithDetails, now: onlyDate))
        var both = onlyDate
        both.prioritizedCount = 1
        #expect(tracker.isMet(.addTaskWithDetails, now: both))
    }

    @Test func reorderIgnoresAddingAndRemoving() {
        var base = TutorialSnapshot()
        base.order = ["a", "b", "c"]
        var tracker = TutorialTracker(baseline: base)
        var added = base
        added.order = ["a", "b", "c", "d"]
        #expect(!tracker.isMet(.reorder, now: added))
        var moved = base
        moved.order = ["c", "a", "b"]
        #expect(tracker.isMet(.reorder, now: moved))
    }

    @Test func deleteThenUndo() {
        var tracker = TutorialTracker(baseline: snapshot(tasks: 3))
        var deleted = snapshot(tasks: 2)
        deleted.deletedCount = 1
        #expect(!tracker.isMet(.deleteAndUndo, now: deleted))
        #expect(tracker.isMet(.deleteAndUndo, now: snapshot(tasks: 3)))
    }

    @Test func undoWithoutDeleteDoesNotCount() {
        var tracker = TutorialTracker(baseline: snapshot(tasks: 3))
        #expect(!tracker.isMet(.deleteAndUndo, now: snapshot(tasks: 3)))
    }

    @Test func restartForgetsThePreviousStep() {
        var tracker = TutorialTracker(baseline: snapshot(tasks: 3))
        var deleted = snapshot(tasks: 2)
        deleted.deletedCount = 1
        _ = tracker.isMet(.deleteAndUndo, now: deleted)
        tracker.restart(at: snapshot(tasks: 3))
        #expect(!tracker.isMet(.deleteAndUndo, now: snapshot(tasks: 3)))
    }

    private func snapshot(tasks: Int) -> TutorialSnapshot {
        var snapshot = TutorialSnapshot()
        snapshot.taskCount = tasks
        return snapshot
    }
}
