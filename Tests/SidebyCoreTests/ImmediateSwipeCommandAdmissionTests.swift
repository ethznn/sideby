import XCTest
@testable import SidebyCore

final class ImmediateSwipeCommandAdmissionTests: XCTestCase {
    func testRecognizedSwipeBeginsSwitchWithoutModifierRelease() {
        var latch = InputCommandLatch()

        XCTAssertTrue(
            ImmediateSwipeCommandAdmission.admit(.next, latch: &latch, at: 1)
        )
        XCTAssertEqual(latch.state, .switching)
    }

    func testBusySwipeIsIgnoredWithoutQueueing() {
        var latch = InputCommandLatch()

        XCTAssertTrue(ImmediateSwipeCommandAdmission.admit(.next, latch: &latch, at: 1))
        XCTAssertFalse(ImmediateSwipeCommandAdmission.admit(.previous, latch: &latch, at: 1.1))
    }
}
