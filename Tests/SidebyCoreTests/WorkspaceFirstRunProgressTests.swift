import Foundation
import XCTest
@testable import SidebyCore

final class WorkspaceFirstRunProgressTests: XCTestCase {
    func testGuideStartsOnlyOnFirstVerifiedVisit() {
        var progress = WorkspaceFirstRunProgress()
        XCTAssertNil(progress.originContextID)
        XCTAssertNil(progress.awayContextID)
        XCTAssertFalse(progress.isComplete)
        progress.recordSuccessfulVisit(contextID: "work")
        XCTAssertEqual(progress.originContextID, "work")
        XCTAssertNil(progress.awayContextID)
        XCTAssertFalse(progress.isComplete)
    }

    func testOnlyDistinctAwayAndReturnVisitsCompleteRoundtrip() {
        var progress = WorkspaceFirstRunProgress()
        progress.recordSuccessfulVisit(contextID: "work")
        progress.recordSuccessfulVisit(contextID: "work")
        XCTAssertNil(progress.awayContextID)
        XCTAssertFalse(progress.isComplete)
        progress.recordSuccessfulVisit(contextID: "research")
        XCTAssertEqual(progress.awayContextID, "research")
        XCTAssertFalse(progress.isComplete)
        progress.recordSuccessfulVisit(contextID: "research")
        XCTAssertFalse(progress.isComplete)
        progress.recordSuccessfulVisit(contextID: "work")
        XCTAssertTrue(progress.isComplete)
    }

    func testThirdWorkspaceDoesNotCompleteRoundtripBeforeReturnToOrigin() {
        var progress = WorkspaceFirstRunProgress()
        progress.recordSuccessfulVisit(contextID: "work")
        progress.recordSuccessfulVisit(contextID: "research")
        progress.recordSuccessfulVisit(contextID: "writing")
        XCTAssertEqual(progress.originContextID, "work")
        XCTAssertEqual(progress.awayContextID, "research")
        XCTAssertFalse(progress.isComplete)
        progress.recordSuccessfulVisit(contextID: "work")
        XCTAssertTrue(progress.isComplete)
    }

    func testCompletedGuideStaysCompleteAcrossFurtherVisits() {
        var progress = WorkspaceFirstRunProgress()
        for id in ["work", "research", "work", "writing"] {
            progress.recordSuccessfulVisit(contextID: id)
        }
        XCTAssertTrue(progress.isComplete)
        XCTAssertEqual(progress.originContextID, "work")
        XCTAssertEqual(progress.awayContextID, "research")
    }

    func testProgressResumesRoundtripAfterPersistence() throws {
        var progress = WorkspaceFirstRunProgress()
        progress.recordSuccessfulVisit(contextID: "work")
        progress.recordSuccessfulVisit(contextID: "research")
        let data = try JSONEncoder().encode(progress)
        var restored = try JSONDecoder().decode(WorkspaceFirstRunProgress.self, from: data)
        XCTAssertFalse(restored.isComplete)
        restored.recordSuccessfulVisit(contextID: "work")
        XCTAssertTrue(restored.isComplete)
    }

    func testReconcileResetsRoundtripWhenAReferencedWorkspaceDisappears() {
        for validIDs: Set<String> in [["work"], ["research"], []] {
            var progress = WorkspaceFirstRunProgress()
            progress.recordSuccessfulVisit(contextID: "work")
            progress.recordSuccessfulVisit(contextID: "research")
            progress.reconcile(validContextIDs: validIDs)
            XCTAssertNil(progress.originContextID)
            XCTAssertNil(progress.awayContextID)
            XCTAssertFalse(progress.isComplete)
            progress.recordSuccessfulVisit(contextID: "writing")
            XCTAssertEqual(progress.originContextID, "writing")
        }
    }

    func testReconcileKeepsValidProgress() {
        var progress = WorkspaceFirstRunProgress()
        progress.recordSuccessfulVisit(contextID: "work")
        progress.recordSuccessfulVisit(contextID: "research")
        progress.reconcile(validContextIDs: ["work", "research", "writing"])
        progress.recordSuccessfulVisit(contextID: "work")
        XCTAssertTrue(progress.isComplete)
    }

    func testEmptyVisitCannotStartOrAdvanceGuide() {
        var progress = WorkspaceFirstRunProgress()
        progress.recordSuccessfulVisit(contextID: "")
        XCTAssertNil(progress.originContextID)
        progress.recordSuccessfulVisit(contextID: "work")
        progress.recordSuccessfulVisit(contextID: "")
        XCTAssertNil(progress.awayContextID)
        XCTAssertFalse(progress.isComplete)
    }
}
