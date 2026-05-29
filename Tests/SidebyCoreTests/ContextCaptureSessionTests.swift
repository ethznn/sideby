import XCTest
@testable import SidebyCore

final class ContextCaptureSessionTests: XCTestCase {
    func testSessionStartsAligningWithCaptureLimit() {
        let session = ContextCaptureSession(captureLimit: 4)

        XCTAssertEqual(session.phase, .aligning(attempt: 1))
        XCTAssertEqual(session.captureLimit, 4)
        XCTAssertEqual(session.draftContexts, [])
    }

    func testAlignmentContinuesWhenPreviousChangedSpace() {
        var session = ContextCaptureSession(captureLimit: 4)

        session.recordAlignment(previousDidChange: true)

        XCTAssertEqual(session.phase, .aligning(attempt: 2))
    }

    func testAlignmentCompletesWhenPreviousDoesNotChangeSpace() {
        var session = ContextCaptureSession(captureLimit: 4)

        session.recordAlignment(previousDidChange: false)

        XCTAssertEqual(session.phase, .capturing(order: 1))
    }

    func testCaptureStoresDraftNamesAndAdvancesOnObservedMovement() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)

        session.recordCurrentSpace(name: "Code")
        session.recordForwardSwitch(didObserveMovement: true)

        XCTAssertEqual(session.draftContexts.map(\.name), ["Code"])
        XCTAssertEqual(session.phase, .capturing(order: 2))
    }

    func testCaptureCompletesWhenNextDoesNotMove() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)

        session.recordCurrentSpace(name: "Code")
        session.recordForwardSwitch(didObserveMovement: false)

        XCTAssertEqual(session.phase, .completed(currentContextID: "context-1"))
        XCTAssertEqual(session.draftContexts.map(\.name), ["Code"])
    }

    func testStopDiscardsDraftsForCommitPurposes() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)
        session.recordCurrentSpace(name: "Code")

        session.stop()

        XCTAssertEqual(session.phase, .stopped)
        XCTAssertFalse(session.shouldCommitDrafts)
    }

    func testCaptureLimitClampsToSupportedRange() {
        XCTAssertEqual(ContextCaptureSession(captureLimit: 0).captureLimit, 1)
        XCTAssertEqual(ContextCaptureSession(captureLimit: 13).captureLimit, 12)
    }

    func testMaxAlignmentAttemptsClampsToSupportedRange() {
        XCTAssertEqual(ContextCaptureSession(captureLimit: 3, maxAlignmentAttempts: 0).maxAlignmentAttempts, 1)
        XCTAssertEqual(ContextCaptureSession(captureLimit: 3, maxAlignmentAttempts: 25).maxAlignmentAttempts, 24)
    }

    func testAlignmentFailsWhenPreviousStillChangesAtMaxAttempt() {
        var session = ContextCaptureSession(captureLimit: 3, maxAlignmentAttempts: 2)

        session.recordAlignment(previousDidChange: true)
        XCTAssertEqual(session.phase, .aligning(attempt: 2))

        session.recordAlignment(previousDidChange: true)
        XCTAssertEqual(session.phase, .failed(reason: "Could not align to first Space"))
    }

    func testForwardSwitchWithoutCurrentDraftFailsOnObservedMovement() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)

        session.recordForwardSwitch(didObserveMovement: true)

        XCTAssertEqual(session.phase, .failed(reason: "Missing captured Context"))
        XCTAssertFalse(session.shouldCommitDrafts)
    }

    func testForwardSwitchWithoutCurrentDraftFailsWithoutMovement() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)

        session.recordForwardSwitch(didObserveMovement: false)

        XCTAssertEqual(session.phase, .failed(reason: "Missing captured Context"))
        XCTAssertFalse(session.shouldCommitDrafts)
    }

    func testRecordCurrentSpaceReplacesDuplicateRecordsForSameOrder() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)

        session.recordCurrentSpace(name: "Old")
        session.recordCurrentSpace(name: "New")

        XCTAssertEqual(session.draftContexts.map(\.name), ["New"])
    }

    func testCompletedSessionCannotBeStopped() {
        var session = ContextCaptureSession(captureLimit: 1)
        session.recordAlignment(previousDidChange: false)
        session.recordCurrentSpace(name: "Code")
        session.recordForwardSwitch(didObserveMovement: true)

        session.stop()

        XCTAssertEqual(session.phase, .completed(currentContextID: "context-1"))
        XCTAssertTrue(session.shouldCommitDrafts)
    }

    func testFailedSessionCannotBeStopped() {
        var session = ContextCaptureSession(captureLimit: 3)

        session.fail(reason: "Switch failed")
        session.stop()

        XCTAssertEqual(session.phase, .failed(reason: "Switch failed"))
        XCTAssertFalse(session.shouldCommitDrafts)
    }

    func testCompletedContextDefinitionsReturnSortedDraftPayload() {
        var session = ContextCaptureSession(captureLimit: 2)
        session.recordAlignment(previousDidChange: false)
        session.recordCurrentSpace(name: "Code")
        session.recordForwardSwitch(didObserveMovement: true)
        session.recordCurrentSpace(name: "Review")
        session.recordForwardSwitch(didObserveMovement: true)

        XCTAssertEqual(
            session.completedContextDefinitions,
            [
                ContextDefinition(id: "context-1", order: 1, name: "Code"),
                ContextDefinition(id: "context-2", order: 2, name: "Review")
            ]
        )
    }

    func testCompletedContextDefinitionsRequiresCurrentDraft() {
        let session = ContextCaptureSession(
            captureLimit: 2,
            phase: .completed(currentContextID: "context-2"),
            draftContexts: [ContextCaptureDraft(order: 1, name: "Code")]
        )

        XCTAssertNil(session.completedContextDefinitions)
    }

    func testCompletedContextDefinitionsRejectsSkippedOrders() {
        let session = ContextCaptureSession(
            captureLimit: 3,
            phase: .completed(currentContextID: "context-3"),
            draftContexts: [
                ContextCaptureDraft(order: 1, name: "Code"),
                ContextCaptureDraft(order: 3, name: "Chat")
            ]
        )

        XCTAssertNil(session.completedContextDefinitions)
    }

    func testCompletedContextDefinitionsDropsDraftsBeyondCompletedOrder() {
        let session = ContextCaptureSession(
            captureLimit: 3,
            phase: .completed(currentContextID: "context-2"),
            draftContexts: [
                ContextCaptureDraft(order: 1, name: "Code"),
                ContextCaptureDraft(order: 2, name: "Review"),
                ContextCaptureDraft(order: 3, name: "Chat")
            ]
        )

        XCTAssertEqual(
            session.completedContextDefinitions,
            [
                ContextDefinition(id: "context-1", order: 1, name: "Code"),
                ContextDefinition(id: "context-2", order: 2, name: "Review")
            ]
        )
    }

    func testCompletedContextDefinitionsRejectsDuplicateOrders() {
        let session = ContextCaptureSession(
            captureLimit: 3,
            phase: .completed(currentContextID: "context-2"),
            draftContexts: [
                ContextCaptureDraft(order: 1, name: "Code"),
                ContextCaptureDraft(order: 2, name: "Review"),
                ContextCaptureDraft(order: 2, name: "Duplicate")
            ]
        )

        XCTAssertNil(session.completedContextDefinitions)
    }

    func testFailDiscardsDraftsForCommitPurposes() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)
        session.recordCurrentSpace(name: "Code")

        session.fail(reason: "Switch failed")

        XCTAssertEqual(session.phase, .failed(reason: "Switch failed"))
        XCTAssertFalse(session.shouldCommitDrafts)
    }
}
