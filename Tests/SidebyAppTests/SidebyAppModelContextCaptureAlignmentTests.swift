import XCTest
import SidebyCore
@testable import SidebyApp

@MainActor
final class SidebyAppModelContextCaptureAlignmentTests: XCTestCase {
    func testCandidateChoiceRejectsActivationTimePartialLayoutWithoutChangingCurrentContext() throws {
        var settings = AppSettings.default
        settings.mode = .shortcut
        var reads = [
            [
                InstantCaptureDisplay(displayID: "main", spaceCount: 3, currentSpaceIndex: 2),
                InstantCaptureDisplay(displayID: "external", spaceCount: 2, currentSpaceIndex: 1)
            ],
            [
                InstantCaptureDisplay(displayID: "main", spaceCount: 3, currentSpaceIndex: 2)
            ]
        ]
        let model = SidebyAppModel(
            testSettings: settings,
            selectedDisplayIDs: ["main", "external"],
            selectedDisplaySpaces: { reads.removeFirst() },
            postEventAccessGranted: true
        )

        XCTAssertTrue(model.startInstantContextCapture())
        let request = try XCTUnwrap(model.pendingContextCaptureAlignment)
        let candidate = try XCTUnwrap(request.candidates.first)
        let capturedCurrentContextID = model.settings.contextPlan.currentContextID

        model.chooseContextCaptureAlignment(contextID: candidate.id)

        XCTAssertEqual(model.settings.contextPlan.syncState, .needsSync)
        XCTAssertFalse(model.isSwitching)
        XCTAssertNil(model.pendingContextCaptureAlignment)
        XCTAssertEqual(model.settings.contextPlan.currentContextID, capturedCurrentContextID)
        XCTAssertNotEqual(model.settings.contextPlan.currentContextID, candidate.id)
    }
}
