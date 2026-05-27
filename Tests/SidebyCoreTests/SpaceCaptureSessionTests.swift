import XCTest
@testable import SidebyCore

final class SpaceCaptureSessionTests: XCTestCase {
    func testSessionStartsAtSpaceOneAndMovesNextUntilCaptureCount() {
        var session = SpaceCaptureSession(spaceCount: 4)

        XCTAssertEqual(session.currentSpaceOrder, 1)
        XCTAssertEqual(session.currentStep, 1)
        XCTAssertEqual(session.totalSteps, 4)
        XCTAssertEqual(session.nextCommand(), .next)

        session.advanceAfterSuccessfulSwitch()
        XCTAssertEqual(session.currentSpaceOrder, 2)
        XCTAssertEqual(session.nextCommand(), .next)
    }

    func testSessionCompletesAtRequestedSpaceCount() {
        var session = SpaceCaptureSession(spaceCount: 2)

        session.advanceAfterSuccessfulSwitch()

        XCTAssertEqual(session.currentSpaceOrder, 2)
        XCTAssertNil(session.nextCommand())
        XCTAssertTrue(session.isComplete)
    }

    func testStopPreventsFurtherCommands() {
        var session = SpaceCaptureSession(spaceCount: 4)

        session.stop()

        XCTAssertTrue(session.isStopped)
        XCTAssertNil(session.nextCommand())
    }
}
