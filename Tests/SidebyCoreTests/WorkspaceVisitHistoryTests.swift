import XCTest
@testable import SidebyCore

final class WorkspaceVisitHistoryTests: XCTestCase {
    func testFirstVerifiedVisitHasNoPreviousWorkspace() {
        var history = WorkspaceVisitHistory()
        history.recordSuccessfulVisit(contextID: "work")
        XCTAssertEqual(history.currentContextID, "work")
        XCTAssertNil(history.previousContextID)
    }

    func testDistinctVerifiedVisitsRememberTheLastWorkspace() {
        var history = WorkspaceVisitHistory()
        history.recordSuccessfulVisit(contextID: "work")
        history.recordSuccessfulVisit(contextID: "research")
        history.recordSuccessfulVisit(contextID: "writing")
        XCTAssertEqual(history.currentContextID, "writing")
        XCTAssertEqual(history.previousContextID, "research")
    }

    func testRepeatedVisitDoesNotOverwritePreviousWorkspace() {
        var history = WorkspaceVisitHistory()
        history.recordSuccessfulVisit(contextID: "work")
        history.recordSuccessfulVisit(contextID: "research")
        history.recordSuccessfulVisit(contextID: "research")
        XCTAssertEqual(history.currentContextID, "research")
        XCTAssertEqual(history.previousContextID, "work")
    }

    func testReturningToPreviousWorkspaceAllowsSwitchingBackAgain() {
        var history = WorkspaceVisitHistory()
        history.recordSuccessfulVisit(contextID: "work")
        history.recordSuccessfulVisit(contextID: "research")
        history.recordSuccessfulVisit(contextID: "work")
        XCTAssertEqual(history.currentContextID, "work")
        XCTAssertEqual(history.previousContextID, "research")
    }

    func testReconcileRemovesDeletedPreviousWorkspace() {
        var history = WorkspaceVisitHistory()
        history.recordSuccessfulVisit(contextID: "work")
        history.recordSuccessfulVisit(contextID: "research")
        history.reconcile(validContextIDs: ["research"])
        XCTAssertEqual(history.currentContextID, "research")
        XCTAssertNil(history.previousContextID)
    }

    func testReconcileDoesNotPromotePreviousWorkspaceToCurrent() {
        var history = WorkspaceVisitHistory()
        history.recordSuccessfulVisit(contextID: "work")
        history.recordSuccessfulVisit(contextID: "research")
        history.reconcile(validContextIDs: ["work"])
        XCTAssertNil(history.currentContextID)
        XCTAssertEqual(history.previousContextID, "work")
    }

    func testEmptyVisitCannotReplaceVerifiedHistory() {
        var history = WorkspaceVisitHistory()
        history.recordSuccessfulVisit(contextID: "work")
        history.recordSuccessfulVisit(contextID: "")
        XCTAssertEqual(history.currentContextID, "work")
        XCTAssertNil(history.previousContextID)
    }
}
