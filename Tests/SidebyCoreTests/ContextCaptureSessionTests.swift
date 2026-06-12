import XCTest
@testable import SidebyCore

final class ContextCaptureSessionTests: XCTestCase {
    func testMovementPolicyTreatsFingerprintChangeAsMovementWhenSpaceNotificationIsMissing() {
        let observation = ContextCaptureDisplayMovementObservation(
            displayID: "built-in",
            didObserveActiveSpaceChange: false,
            visibleFingerprintBefore: "Xcode - SidebyApp.swift",
            visibleFingerprintAfter: "Arc - Docs"
        )

        XCTAssertEqual(
            ContextCaptureMovementPolicy.movedDisplayIDs(from: [observation]),
            ["built-in"]
        )
    }

    func testMovementPolicyRequiresNotificationOrFingerprintChange() {
        let observation = ContextCaptureDisplayMovementObservation(
            displayID: "built-in",
            didObserveActiveSpaceChange: false,
            visibleFingerprintBefore: "Xcode - SidebyApp.swift",
            visibleFingerprintAfter: "Xcode - SidebyApp.swift"
        )

        XCTAssertEqual(
            ContextCaptureMovementPolicy.movedDisplayIDs(from: [observation]),
            []
        )
    }

    func testMovementPolicyTreatsSpaceNotificationAsMovement() {
        let observation = ContextCaptureDisplayMovementObservation(
            displayID: "external-lg",
            didObserveActiveSpaceChange: true,
            visibleFingerprintBefore: "Xcode - SidebyApp.swift",
            visibleFingerprintAfter: "Xcode - SidebyApp.swift"
        )

        XCTAssertEqual(
            ContextCaptureMovementPolicy.movedDisplayIDs(from: [observation]),
            ["external-lg"]
        )
    }

    func testAnyMovementPolicyTreatsGlobalSpaceNotificationAsMovement() {
        XCTAssertTrue(
            ContextCaptureMovementPolicy.didObserveAnyMovement(
                didObserveActiveSpaceChange: true,
                observations: []
            )
        )
    }

    func testAnyMovementPolicyTreatsFingerprintChangeAsMovementWhenNotificationIsMissing() {
        let observation = ContextCaptureDisplayMovementObservation(
            displayID: "external-lg",
            didObserveActiveSpaceChange: false,
            visibleFingerprintBefore: "Xcode - SidebyApp.swift",
            visibleFingerprintAfter: "Arc - Docs"
        )

        XCTAssertTrue(
            ContextCaptureMovementPolicy.didObserveAnyMovement(
                didObserveActiveSpaceChange: false,
                observations: [observation]
            )
        )
    }

    func testAnyMovementPolicyReportsNoMovementWithoutNotificationOrFingerprintChange() {
        let observation = ContextCaptureDisplayMovementObservation(
            displayID: "external-lg",
            didObserveActiveSpaceChange: false,
            visibleFingerprintBefore: "Xcode - SidebyApp.swift",
            visibleFingerprintAfter: "Xcode - SidebyApp.swift"
        )

        XCTAssertFalse(
            ContextCaptureMovementPolicy.didObserveAnyMovement(
                didObserveActiveSpaceChange: false,
                observations: [observation]
            )
        )
    }

    func testForwardDecisionRetainsMovedDisplaysAndResetsStreaks() {
        let decision = ContextCaptureMovementPolicy.forwardDecision(
            activeDisplayIDs: ["built-in", "external-lg"],
            movedDisplayIDs: ["built-in", "external-lg"],
            noMoveStreaks: ["external-lg": 1]
        )

        XCTAssertEqual(decision.activeDisplayIDs, ["built-in", "external-lg"])
        XCTAssertEqual(decision.noMoveStreaks, ["built-in": 0, "external-lg": 0])
    }

    func testForwardDecisionConfirmsOnlyMovedDisplaysWhileRetainingGraceTargets() {
        let decision = ContextCaptureMovementPolicy.forwardDecision(
            activeDisplayIDs: ["built-in", "external-lg"],
            movedDisplayIDs: ["external-lg"],
            noMoveStreaks: [:]
        )

        XCTAssertEqual(decision.confirmedDisplayIDs, ["external-lg"])
        XCTAssertEqual(decision.activeDisplayIDs, ["built-in", "external-lg"])
    }

    func testForwardDecisionGivesGraceToFirstMissedObservation() {
        let decision = ContextCaptureMovementPolicy.forwardDecision(
            activeDisplayIDs: ["built-in", "external-lg"],
            movedDisplayIDs: ["built-in"],
            noMoveStreaks: [:]
        )

        XCTAssertEqual(decision.activeDisplayIDs, ["built-in", "external-lg"])
        XCTAssertEqual(decision.noMoveStreaks, ["built-in": 0, "external-lg": 1])
    }

    func testForwardDecisionDropsDisplayAfterConsecutiveMissedObservations() {
        let decision = ContextCaptureMovementPolicy.forwardDecision(
            activeDisplayIDs: ["built-in", "external-lg"],
            movedDisplayIDs: ["built-in"],
            noMoveStreaks: ["external-lg": 1]
        )

        XCTAssertEqual(decision.activeDisplayIDs, ["built-in"])
        XCTAssertEqual(decision.noMoveStreaks, ["built-in": 0, "external-lg": 2])
    }

    func testForwardDecisionPrunesStreaksForInactiveDisplays() {
        let decision = ContextCaptureMovementPolicy.forwardDecision(
            activeDisplayIDs: ["built-in"],
            movedDisplayIDs: ["built-in"],
            noMoveStreaks: ["external-lg": 2]
        )

        XCTAssertEqual(decision.noMoveStreaks, ["built-in": 0])
    }

    func testSessionStartsAligningWithCaptureLimit() {
        let session = ContextCaptureSession(captureLimit: 4)

        XCTAssertEqual(session.phase, .aligning(attempt: 1))
        XCTAssertEqual(session.captureLimit, 4)
        XCTAssertEqual(session.draftContexts, [])
    }

    func testAutomaticCaptureConfigurationUsesResponsiveTiming() {
        let configuration = ContextCaptureConfiguration.automatic

        XCTAssertEqual(configuration.maxAlignmentAttempts, 12)
        XCTAssertEqual(configuration.observerWait, 0.90, accuracy: 0.0001)
        XCTAssertEqual(configuration.alignmentRetryDelay, 0.12, accuracy: 0.0001)
        XCTAssertEqual(configuration.forwardRetryDelay, 0.12, accuracy: 0.0001)
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

    func testCaptureStoresDraftDisplayMembershipAndAdvances() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)

        session.recordCurrentSpace(name: "Code", displayIDs: ["external-lg", "built-in"])
        session.recordForwardSwitch(movedDisplayIDs: ["built-in"])

        XCTAssertEqual(session.draftContexts.map(\.name), ["Code"])
        XCTAssertEqual(session.draftContexts.map(\.displayIDs), [["built-in", "external-lg"]])
        XCTAssertEqual(session.phase, .capturing(order: 2))
    }

    func testCaptureCompletesWhenNoDisplaysMoveBeforeLimit() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)

        session.recordCurrentSpace(name: "Code", displayIDs: ["built-in"])
        session.recordForwardSwitch(movedDisplayIDs: [])

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

        session.recordForwardSwitch(movedDisplayIDs: ["built-in"])

        XCTAssertEqual(session.phase, .failed(reason: "Missing captured Context"))
        XCTAssertFalse(session.shouldCommitDrafts)
    }

    func testForwardSwitchWithoutCurrentDraftFailsWithoutMovement() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)

        session.recordForwardSwitch(movedDisplayIDs: [])

        XCTAssertEqual(session.phase, .failed(reason: "Missing captured Context"))
        XCTAssertFalse(session.shouldCommitDrafts)
    }

    func testRecordCurrentSpaceReplacesDuplicateRecordsForSameOrder() {
        var session = ContextCaptureSession(captureLimit: 3)
        session.recordAlignment(previousDidChange: false)

        session.recordCurrentSpace(name: "Old", displayIDs: ["built-in"])
        session.recordCurrentSpace(name: "New", displayIDs: ["external-lg"])

        XCTAssertEqual(session.draftContexts.map(\.name), ["New"])
        XCTAssertEqual(session.draftContexts.map(\.displayIDs), [["external-lg"]])
    }

    func testCompletedSessionCannotBeStopped() {
        var session = ContextCaptureSession(captureLimit: 1)
        session.recordAlignment(previousDidChange: false)
        session.recordCurrentSpace(name: "Code", displayIDs: ["built-in"])
        session.recordForwardSwitch(movedDisplayIDs: ["built-in"])

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
        session.recordCurrentSpace(name: "Code", displayIDs: ["built-in", "external-lg"])
        session.recordForwardSwitch(movedDisplayIDs: ["built-in"])
        session.recordCurrentSpace(name: "Review", displayIDs: ["built-in"])
        session.recordForwardSwitch(movedDisplayIDs: [])

        XCTAssertEqual(
            session.completedContextDefinitions,
            [
                ContextDefinition(id: "context-1", order: 1, name: "Code", displayIDs: ["built-in", "external-lg"]),
                ContextDefinition(id: "context-2", order: 2, name: "Review", displayIDs: ["built-in"])
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
