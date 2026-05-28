import XCTest
@testable import SidebyCore

final class ContextCaptureSessionTests: XCTestCase {
    func testSessionStartsAtCurrentContextAndCapturesForwardOnly() {
        var plan = ContextPlan.default
        plan.setCurrentContext(id: "context-2")

        let session = ContextCaptureSession(plan: plan)!

        XCTAssertEqual(session.contextIDs, ["context-2", "context-3"])
        XCTAssertEqual(session.currentContextID, "context-2")
        XCTAssertEqual(session.currentStep, 1)
        XCTAssertEqual(session.totalSteps, 2)
        XCTAssertEqual(session.nextCommand(), .next)
    }

    func testSessionHonorsPlanCaptureLimit() {
        var plan = ContextPlan.default
        plan.setCaptureLimit(2)

        let session = ContextCaptureSession(plan: plan)!

        XCTAssertEqual(session.contextIDs, ["context-1", "context-2"])
        XCTAssertEqual(session.totalSteps, 2)
    }

    func testSessionAdvanceAndStopControlNextCommand() {
        let session = ContextCaptureSession(plan: .default)!
        var advanced = session

        XCTAssertEqual(advanced.currentContextID, "context-1")
        XCTAssertEqual(advanced.nextCommand(), .next)

        advanced.advanceAfterSuccessfulSwitch()
        XCTAssertEqual(advanced.currentContextID, "context-2")
        XCTAssertEqual(advanced.nextCommand(), .next)

        advanced.stop()
        XCTAssertTrue(advanced.isStopped)
        XCTAssertNil(advanced.nextCommand())
    }

    func testSessionEndsAtLastContext() {
        var session = ContextCaptureSession(plan: .default)!

        session.advanceAfterSuccessfulSwitch()
        session.advanceAfterSuccessfulSwitch()

        XCTAssertEqual(session.currentContextID, "context-3")
        XCTAssertNil(session.nextCommand())
        XCTAssertTrue(session.isComplete)
    }
}
