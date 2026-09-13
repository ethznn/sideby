import XCTest
import SidebyCore
@testable import SidebyApp

final class WorkspaceDailyPresentationTests: XCTestCase {
    func testDefaultEmptyMappingsSelectSetupEvenWhenSessionIsUnconfirmed() {
        XCTAssertEqual(WorkspaceDailyPresentation.preparedContextIDs(in: .default), [])
        let view = presentation(plan: .default)
        XCTAssertEqual(view.status, .empty)
        XCTAssertNil(view.currentContextID)
    }

    func testEmptyPlanStillPrioritizesBusyAndRequiredAccess() {
        XCTAssertEqual(presentation(plan: .default, isSwitching: true).status, .busy)
        XCTAssertEqual(presentation(plan: .default, hasPermissions: false).status, .permissions)
        XCTAssertEqual(presentation(plan: .default, isEnabled: false).status, .disabled)
    }

    func testSavedAssignmentsNeedSessionReviewWithoutClaimingPlanCurrentIsVerified() {
        let view = presentation(plan: savedPlan)
        XCTAssertEqual(view.status, .connection(.unconfirmed))
        XCTAssertNil(view.currentContextID)
        XCTAssertEqual(WorkspaceDailyPresentation.preparedContextIDs(in: savedPlan), ["build", "review"])
    }

    func testFailedTargetStaysDistinctFromVerifiedCurrentAndBusyTakesPriority() {
        let recovery = WorkspaceRecoveryState(targetContext: savedPlan.contexts[1], selectedDisplayIDs: ["desk"],
                                               displays: [.init(displayID: "desk", spaceCount: 2, currentSpaceIndex: 0)])
        let view = presentation(plan: savedPlan, status: .ready, recovery: recovery, current: "build", target: "review")
        XCTAssertEqual(view.status, .recovery)
        XCTAssertEqual(view.currentContextID, "build")
        XCTAssertEqual(view.failedTargetID, "review")
        XCTAssertEqual(presentation(plan: savedPlan, isSwitching: true, status: .ready,
                                    recovery: recovery, current: "build", target: "review").status, .busy)
    }

    private var savedPlan: ContextPlan {
        .init(contexts: [
            .init(id: "build", order: 1, name: "Build", displaySpaceIndexes: ["desk": 0]),
            .init(id: "review", order: 2, name: "Review", displaySpaceIndexes: ["desk": 1])
        ], currentContextID: "build")
    }

    private func presentation(plan: ContextPlan, isSwitching: Bool = false, isEnabled: Bool = true,
                              hasPermissions: Bool = true, status: WorkspaceConnectionStatus = .unconfirmed,
                              recovery: WorkspaceRecoveryState? = nil, current: String? = nil,
                              target: String? = nil) -> WorkspaceDailyPresentation {
        WorkspaceDailyPresentation(plan: plan, isSwitching: isSwitching, isCapturing: false,
            isEnabled: isEnabled, hasRequiredPermissions: hasPermissions,
            connectionStatus: status, recovery: recovery,
            verifiedCurrentContextID: current, failedTargetID: target)
    }
}
