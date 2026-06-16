import XCTest
@testable import SidebyCore

final class AlignFeedbackPolicyTests: XCTestCase {
    private func display(_ id: String, index: Int, count: Int = 4) -> InstantCaptureDisplay {
        InstantCaptureDisplay(displayID: id, spaceCount: count, currentSpaceIndex: index)
    }

    func testNonMemberDisplayReportsNotInContext() {
        // Main on space 2 -> target order 2 (context2). FA2440P moved to context4,
        // so it is not a member of context2 and must surface "not in this Context".
        let target = ContextDefinition(id: "context-2", order: 2, name: "Two", displayIDs: ["built-in"])
        let feedback = AlignFeedbackPolicy.feedback(
            displays: [display("built-in", index: 1), display("fa2440p", index: 3)],
            referenceDisplayID: "built-in",
            targetContext: target
        )

        XCTAssertEqual(feedback, [AlignDisplayFeedback(displayID: "fa2440p", reason: .notInContext)])
    }

    func testMemberAlreadyAtTargetIndexReportsAlreadyAligned() {
        let target = ContextDefinition(id: "context-2", order: 2, name: "Two", displayIDs: ["built-in", "fa2440p"])
        let feedback = AlignFeedbackPolicy.feedback(
            displays: [display("built-in", index: 1), display("fa2440p", index: 1)],
            referenceDisplayID: "built-in",
            targetContext: target
        )

        XCTAssertEqual(feedback, [AlignDisplayFeedback(displayID: "fa2440p", reason: .alreadyAligned)])
    }

    func testFeedbackUsesExplicitDisplaySpaceIndex() {
        let target = ContextDefinition(
            id: "context-4",
            order: 4,
            name: "Four",
            displayIDs: ["built-in", "fa2440p"],
            displaySpaceIndexes: ["built-in": 3, "fa2440p": 2]
        )
        let feedback = AlignFeedbackPolicy.feedback(
            displays: [display("built-in", index: 3), display("fa2440p", index: 2)],
            referenceDisplayID: "built-in",
            targetContext: target
        )

        XCTAssertEqual(feedback, [AlignDisplayFeedback(displayID: "fa2440p", reason: .alreadyAligned)])
    }

    func testMemberNeedingMoveProducesNoFeedback() {
        let target = ContextDefinition(id: "context-2", order: 2, name: "Two", displayIDs: ["built-in", "fa2440p"])
        let feedback = AlignFeedbackPolicy.feedback(
            displays: [display("built-in", index: 1), display("fa2440p", index: 3)],
            referenceDisplayID: "built-in",
            targetContext: target
        )

        XCTAssertEqual(feedback, [])
    }

    func testReferenceDisplayIsNeverIncluded() {
        let target = ContextDefinition(id: "context-2", order: 2, name: "Two", displayIDs: ["built-in"])
        let feedback = AlignFeedbackPolicy.feedback(
            displays: [display("built-in", index: 1)],
            referenceDisplayID: "built-in",
            targetContext: target
        )

        XCTAssertEqual(feedback, [])
    }

    func testFeedbackFollowsDisplayInputOrder() {
        let target = ContextDefinition(id: "context-2", order: 2, name: "Two", displayIDs: ["built-in", "lg"])
        let feedback = AlignFeedbackPolicy.feedback(
            displays: [
                display("built-in", index: 1),
                display("fa2440p", index: 3),
                display("lg", index: 1)
            ],
            referenceDisplayID: "built-in",
            targetContext: target
        )

        XCTAssertEqual(
            feedback,
            [
                AlignDisplayFeedback(displayID: "fa2440p", reason: .notInContext),
                AlignDisplayFeedback(displayID: "lg", reason: .alreadyAligned)
            ]
        )
    }
}
