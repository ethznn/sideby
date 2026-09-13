import XCTest
@testable import SidebyCore

final class WorkspaceRecoveryStateTests: XCTestCase {
    private let target = ContextDefinition(
        id: "work", order: 2, name: "Work", displayIDs: ["builtin", "external"],
        displaySpaceIndexes: ["builtin": 1, "external": 2]
    )

    func testPartialSwitchRetriesOnlyDisplaysThatStillNeedToMove() {
        let state = WorkspaceRecoveryState(targetContext: target, selectedDisplayIDs: ["builtin", "external"], displays: [
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 1),
            InstantCaptureDisplay(displayID: "external", spaceCount: 4, currentSpaceIndex: 0)
        ])
        XCTAssertEqual(state.alignedDisplayIDs, ["builtin"])
        XCTAssertEqual(state.pendingDisplayIDs, ["external"])
        XCTAssertTrue(state.unavailableDisplayIDs.isEmpty)
        XCTAssertTrue(state.invalidDisplayIDs.isEmpty)
        XCTAssertTrue(state.canRetry)
        XCTAssertFalse(state.isResolved)
    }

    func testResolutionRequiresEveryRequiredDisplayToBeObservedAtItsTargetIndex() {
        let state = WorkspaceRecoveryState(targetContext: target, selectedDisplayIDs: ["builtin", "external"], displays: [
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 1),
            InstantCaptureDisplay(displayID: "external", spaceCount: 4, currentSpaceIndex: 2)
        ])
        XCTAssertEqual(state.alignedDisplayIDs, ["builtin", "external"])
        XCTAssertTrue(state.pendingDisplayIDs.isEmpty)
        XCTAssertFalse(state.canRetry)
        XCTAssertTrue(state.isResolved)
    }

    func testMissingDisplayCannotBeMistakenForSuccessfulRecovery() {
        let state = WorkspaceRecoveryState(targetContext: target, selectedDisplayIDs: ["builtin", "external"], displays: [
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 1)
        ])
        XCTAssertEqual(state.unavailableDisplayIDs, ["external"])
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.isResolved)
    }

    func testUnavailableLayoutBlocksAllRequiredDisplays() {
        let state = WorkspaceRecoveryState(targetContext: target, selectedDisplayIDs: ["builtin", "external"], displays: nil)
        XCTAssertEqual(state.unavailableDisplayIDs, ["builtin", "external"])
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.isResolved)
    }

    func testDeletedTargetSpaceBlocksRetryEvenWhenAnotherDisplayIsPending() {
        let state = WorkspaceRecoveryState(targetContext: target, selectedDisplayIDs: ["builtin", "external"], displays: [
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 0),
            InstantCaptureDisplay(displayID: "external", spaceCount: 2, currentSpaceIndex: 1)
        ])
        XCTAssertEqual(state.pendingDisplayIDs, ["builtin"])
        XCTAssertEqual(state.invalidDisplayIDs, ["external"])
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.isResolved)
    }

    func testOnlySelectedTargetMembersAffectRecovery() {
        let state = WorkspaceRecoveryState(targetContext: target, selectedDisplayIDs: ["builtin", "unrelated"], displays: [
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 1),
            InstantCaptureDisplay(displayID: "unrelated", spaceCount: 0, currentSpaceIndex: -1)
        ])
        XCTAssertEqual(state.alignedDisplayIDs, ["builtin"])
        XCTAssertTrue(state.unavailableDisplayIDs.isEmpty)
        XCTAssertTrue(state.isResolved)
    }

    func testNoRequiredDisplayCannotBeMistakenForSuccessfulRecovery() {
        let state = WorkspaceRecoveryState(targetContext: target, selectedDisplayIDs: ["unrelated"], displays: [])
        XCTAssertFalse(state.canRetry)
        XCTAssertFalse(state.isResolved)
    }

    func testMalformedOrDuplicateDisplayObservationIsUnavailable() {
        let malformedDisplays: [[InstantCaptureDisplay]] = [
            [InstantCaptureDisplay(displayID: "builtin", spaceCount: 0, currentSpaceIndex: 0)],
            [InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: -1)],
            [InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 3)],
            [
                InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 1),
                InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 1)
            ]
        ]
        for displays in malformedDisplays {
            let state = WorkspaceRecoveryState(targetContext: target, selectedDisplayIDs: ["builtin"], displays: displays)
            XCTAssertEqual(state.unavailableDisplayIDs, ["builtin"])
            XCTAssertFalse(state.canRetry)
            XCTAssertFalse(state.isResolved)
        }
    }
}
