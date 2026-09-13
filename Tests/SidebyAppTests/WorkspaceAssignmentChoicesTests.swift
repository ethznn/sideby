import XCTest
import SidebyCore
@testable import SidebyApp

final class WorkspaceAssignmentChoicesTests: XCTestCase {
    private var plan: ContextPlan {
        ContextPlan(contexts: [
            .init(id: "a", order: 1, name: "Build", displaySpaceIndexes: ["desk": 0]),
            .init(id: "b", order: 2, name: "Review", displaySpaceIndexes: ["desk": 3]),
            .init(id: "c", order: 3, name: "Other", displaySpaceIndexes: ["other": 1])
        ], currentContextID: "a")
    }

    func testAssignmentOptionsIncludeUnassignedLiveDesktops() {
        let options = WorkspaceAssignmentChoices.options(plan: plan, displayID: "desk", observedSpaceCount: 2)
        XCTAssertEqual(options.map(\.spaceIndex), [0, 1])
    }

    func testUnreadableOrEmptyDisplayDoesNotInventSelectableDesktops() {
        XCTAssertTrue(WorkspaceAssignmentChoices.options(plan: plan, displayID: "desk", observedSpaceCount: nil).isEmpty)
        XCTAssertTrue(WorkspaceAssignmentChoices.options(plan: plan, displayID: "desk", observedSpaceCount: 0).isEmpty)
    }

    func testSelectingADesktopPreservesOtherWorkspaces() {
        var plan = plan
        let choice = WorkspaceAssignmentChoices.options(plan: plan, displayID: "desk", observedSpaceCount: 4)[1]
        XCTAssertTrue(plan.assignDisplaySpace(displayID: "desk", spaceIndex: choice.spaceIndex, toContextID: "a"))
        XCTAssertEqual(plan.contexts.first { $0.id == "a" }?.spaceIndex(for: "desk"), 1)
        XCTAssertEqual(plan.contexts.first { $0.id == "b" }?.spaceIndex(for: "desk"), 3)
    }
}
