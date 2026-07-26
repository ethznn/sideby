import XCTest
import SidebyCore
@testable import SidebyApp

final class ProductInstantContextCaptureStartPolicyTests: XCTestCase {
    func testPlanRejectsMissingCaptureDisplays() {
        XCTAssertNil(
            ProductInstantContextCaptureStartPolicy.plan(
                for: nil,
                selectedDisplayIDs: ["main"]
            )
        )
    }

    func testPlanRejectsPartialCaptureDisplayRead() {
        XCTAssertNil(
            ProductInstantContextCaptureStartPolicy.plan(
                for: [
                    InstantCaptureDisplay(displayID: "main", spaceCount: 2, currentSpaceIndex: 0)
                ],
                selectedDisplayIDs: ["main", "external"]
            )
        )
    }

    func testPlanRejectsMalformedCaptureDisplayRead() {
        XCTAssertNil(
            ProductInstantContextCaptureStartPolicy.plan(
                for: [
                    InstantCaptureDisplay(displayID: "main", spaceCount: 2, currentSpaceIndex: 2)
                ],
                selectedDisplayIDs: ["main"]
            )
        )
    }

    func testPlanAdmitsCompleteCaptureDisplayRead() throws {
        let plan = try XCTUnwrap(
            ProductInstantContextCaptureStartPolicy.plan(
                for: [
                    InstantCaptureDisplay(displayID: "main", spaceCount: 2, currentSpaceIndex: 0),
                    InstantCaptureDisplay(displayID: "external", spaceCount: 3, currentSpaceIndex: 0)
                ],
                selectedDisplayIDs: ["main", "external"]
            )
        )

        XCTAssertEqual(plan.currentContextID, "context-1")
        XCTAssertEqual(plan.contexts.count, 3)
    }
}
