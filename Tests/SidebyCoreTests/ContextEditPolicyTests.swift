import XCTest
@testable import SidebyCore

final class ContextEditPolicyTests: XCTestCase {
    func testMinimumContextCountUsesSmallestSelectedDisplaySpaceCount() {
        let result = ContextEditPolicy.minimumContextCount(
            selectedDisplayIDs: ["built-in", "external"],
            displays: [
                InstantCaptureDisplay(displayID: "built-in", spaceCount: 3, currentSpaceIndex: 0),
                InstantCaptureDisplay(displayID: "external", spaceCount: 5, currentSpaceIndex: 0),
                InstantCaptureDisplay(displayID: "unselected", spaceCount: 1, currentSpaceIndex: 0)
            ]
        )

        XCTAssertEqual(result, 3)
    }

    func testMinimumContextCountRequiresEverySelectedDisplayExactlyOnce() {
        XCTAssertNil(ContextEditPolicy.minimumContextCount(selectedDisplayIDs: [], displays: []))
        XCTAssertNil(ContextEditPolicy.minimumContextCount(
            selectedDisplayIDs: ["built-in", "external"],
            displays: [InstantCaptureDisplay(displayID: "built-in", spaceCount: 3, currentSpaceIndex: 0)]
        ))
        XCTAssertNil(ContextEditPolicy.minimumContextCount(
            selectedDisplayIDs: ["built-in"],
            displays: [
                InstantCaptureDisplay(displayID: "built-in", spaceCount: 3, currentSpaceIndex: 0),
                InstantCaptureDisplay(displayID: "built-in", spaceCount: 4, currentSpaceIndex: 0)
            ]
        ))
        XCTAssertNil(ContextEditPolicy.minimumContextCount(
            selectedDisplayIDs: ["built-in"],
            displays: [InstantCaptureDisplay(displayID: "built-in", spaceCount: 0, currentSpaceIndex: 0)]
        ))
    }

    func testCanDeleteOnlyAboveValidFloor() {
        XCTAssertTrue(ContextEditPolicy.canDelete(contextCount: 4, minimumContextCount: 3))
        XCTAssertFalse(ContextEditPolicy.canDelete(contextCount: 3, minimumContextCount: 3))
        XCTAssertFalse(ContextEditPolicy.canDelete(contextCount: 4, minimumContextCount: nil))
        XCTAssertFalse(ContextEditPolicy.canDelete(contextCount: 4, minimumContextCount: 0))
    }

    func testConfirmationIsRequiredOnlyForStoredSpaceMappings() {
        let empty = ContextDefinition(id: "empty", order: 1, name: "Empty")
        let populated = ContextDefinition(
            id: "work",
            order: 2,
            name: "Work",
            displayIDs: ["built-in"],
            displaySpaceIndexes: ["built-in": 1]
        )

        XCTAssertFalse(ContextEditPolicy.requiresDeleteConfirmation(for: empty))
        XCTAssertTrue(ContextEditPolicy.requiresDeleteConfirmation(for: populated))
    }
}
