import XCTest
@testable import SidebyCore

final class WorkspaceSharedAssignmentTests: XCTestCase {
    private var plan: ContextPlan {
        .init(contexts: [
            .init(id: "a", order: 1, name: "A", displaySpaceIndexes: ["main": 0, "external": 1]),
            .init(id: "b", order: 2, name: "B", displaySpaceIndexes: ["main": 0, "external": 2]),
            .init(id: "c", order: 3, name: "C", displaySpaceIndexes: ["main": 1])
        ], currentContextID: "a")
    }

    func testSharingOnlyChangesTheDestinationAndSurvivesEncoding() throws {
        var plan = plan
        XCTAssertTrue(plan.assignDisplaySpace(displayID: "main", spaceIndex: 0, toContextID: "c"))
        XCTAssertEqual(plan.contexts.map { $0.spaceIndex(for: "main") }, [0, 0, 0])
        XCTAssertEqual(plan.contexts[0].spaceIndex(for: "external"), 1)
        let restored = try JSONDecoder().decode(ContextPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(restored.contexts, plan.contexts)
    }

    func testMovingSharedDesktopSwapsOnlyTheExplicitSourceAndTarget() {
        var plan = plan
        XCTAssertTrue(plan.moveDisplaySpace(displayID: "main", spaceIndex: 0, fromContextID: "b", toContextID: "c"))
        XCTAssertEqual(plan.contexts.map { $0.spaceIndex(for: "main") }, [0, 1, 0])
    }

    func testMovingToEmptyCellLeavesOnlyExplicitSourceEmpty() {
        var plan = plan
        XCTAssertTrue(plan.assignDisplaySpace(displayID: "main", spaceIndex: nil, toContextID: "c"))
        XCTAssertTrue(plan.moveDisplaySpace(displayID: "main", spaceIndex: 0, fromContextID: "b", toContextID: "c"))
        XCTAssertEqual(plan.contexts.map { $0.spaceIndex(for: "main") }, [0, nil, 0])
        XCTAssertEqual(plan.contexts[1].spaceIndex(for: "external"), 2)
    }

    func testStaleSourceSelfDropAndInvalidAssignmentDoNotChangeThePlan() {
        var plan = plan
        let original = plan
        XCTAssertFalse(plan.moveDisplaySpace(displayID: "main", spaceIndex: 1, fromContextID: "b", toContextID: "c"))
        XCTAssertFalse(plan.moveDisplaySpace(displayID: "main", spaceIndex: 0, fromContextID: "b", toContextID: "b"))
        XCTAssertFalse(plan.assignDisplaySpace(displayID: "main", spaceIndex: -1, toContextID: "b"))
        XCTAssertFalse(plan.assignDisplaySpace(displayID: "main", spaceIndex: 0, toContextID: "missing"))
        XCTAssertEqual(plan, original)
    }
}
