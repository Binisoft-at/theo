import Foundation
import Testing
@testable import TheoCore

@Suite("Group traits")
struct GroupTraitsTests {
    private let traits = GroupTraits(importance: 0.8, estimate: 1, tags: ["work"], dueDays: 3)

    @Test func aBlankTaskTakesEveryTrait() {
        let task = GroupTraits.TaskValues(importance: nil, estimate: nil, tags: [], hasDeadline: false, dueDays: nil)
        let plan = traits.plan(for: task)
        #expect(plan.apply == traits)
        #expect(plan.propose.isEmpty)
    }

    @Test func ownValuesAreProposalsNotOverwrites() {
        let task = GroupTraits.TaskValues(importance: 0.3, estimate: 2, tags: ["home"], hasDeadline: true, dueDays: 10)
        let plan = traits.plan(for: task)
        #expect(plan.apply == GroupTraits(tags: ["work"]))
        #expect(plan.propose == GroupTraits(importance: 0.8, estimate: 1, dueDays: 3))
    }

    @Test func matchingValuesNeedNothing() {
        let task = GroupTraits.TaskValues(importance: 0.8, estimate: 1, tags: ["work"], hasDeadline: true, dueDays: 3)
        let plan = traits.plan(for: task)
        #expect(plan.apply.isEmpty)
        #expect(plan.propose.isEmpty)
    }

    @Test func subgroupsInheritAndOverride() {
        let parent = GroupTraits(importance: 0.5, estimate: 0.5, tags: ["haeb"])
        let child = GroupTraits(estimate: 2, tags: ["dev", "haeb"])
        let merged = child.inheriting(from: parent)
        #expect(merged.importance == 0.5)
        #expect(merged.estimate == 2)
        #expect(merged.tags == ["haeb", "dev"])
        #expect(merged.dueDays == nil)
    }

    @Test func summaryReadsWell() {
        #expect(GroupTraits(importance: 0.8, dueDays: 1).summary == ["Importance 8", "Due tomorrow"])
        #expect(GroupTraits().isEmpty)
    }
}
