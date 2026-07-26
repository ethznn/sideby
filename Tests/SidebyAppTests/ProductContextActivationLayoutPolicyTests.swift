import XCTest
import SidebyCore
@testable import SidebyApp

final class ProductContextActivationLayoutPolicyTests: XCTestCase {
    func testCompleteLayoutRequirementRejectsPartialReadWhileNormalActivationAcceptsIt() {
        let partialRead = [
            InstantCaptureDisplay(displayID: "main", spaceCount: 2, currentSpaceIndex: 0)
        ]
        let completeRead = [
            InstantCaptureDisplay(displayID: "main", spaceCount: 2, currentSpaceIndex: 0),
            InstantCaptureDisplay(displayID: "external", spaceCount: 3, currentSpaceIndex: 1)
        ]

        XCTAssertTrue(
            ProductContextActivationLayoutPolicy.isAdmitted(
                partialRead,
                selectedDisplayIDs: ["main", "external"],
                requiresCompleteSelectedLayout: false
            )
        )
        XCTAssertFalse(
            ProductContextActivationLayoutPolicy.isAdmitted(
                partialRead,
                selectedDisplayIDs: ["main", "external"],
                requiresCompleteSelectedLayout: true
            )
        )
        XCTAssertTrue(
            ProductContextActivationLayoutPolicy.isAdmitted(
                completeRead,
                selectedDisplayIDs: ["main", "external"],
                requiresCompleteSelectedLayout: true
            )
        )
    }

    func testCompleteLayoutRequirementRejectsMalformedRead() {
        XCTAssertFalse(
            ProductContextActivationLayoutPolicy.isAdmitted(
                [InstantCaptureDisplay(displayID: "main", spaceCount: 2, currentSpaceIndex: 2)],
                selectedDisplayIDs: ["main"],
                requiresCompleteSelectedLayout: true
            )
        )
    }
}
