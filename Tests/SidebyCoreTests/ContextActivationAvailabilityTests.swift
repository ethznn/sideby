import XCTest
@testable import SidebyCore

final class ContextActivationAvailabilityTests: XCTestCase {
    func testContextActivationRequiresEnabledIdleState() {
        XCTAssertTrue(
            ContextActivationAvailability.canActivate(
                isSidebyEnabled: true,
                isSwitching: false,
                isCapturing: false
            )
        )
        XCTAssertFalse(
            ContextActivationAvailability.canActivate(
                isSidebyEnabled: false,
                isSwitching: false,
                isCapturing: false
            )
        )
        XCTAssertFalse(
            ContextActivationAvailability.canActivate(
                isSidebyEnabled: true,
                isSwitching: true,
                isCapturing: false
            )
        )
        XCTAssertFalse(
            ContextActivationAvailability.canActivate(
                isSidebyEnabled: true,
                isSwitching: false,
                isCapturing: true
            )
        )
    }
}
