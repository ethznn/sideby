import XCTest
@testable import SidebyCore

final class ContextDisplayMovePlannerTests: XCTestCase {
    func testPlansMovesToExactTargetIndexesAcrossDisplays() {
        let target = ContextDefinition(
            id: "context-4",
            order: 4,
            name: "Four",
            displayIDs: ["built-in", "external-lg"],
            displaySpaceIndexes: ["built-in": 2, "external-lg": 3]
        )
        let moves = ContextDisplayMovePlanner.moves(
            displays: [
                InstantCaptureDisplay(displayID: "built-in", spaceCount: 3, currentSpaceIndex: 0),
                InstantCaptureDisplay(displayID: "external-lg", spaceCount: 4, currentSpaceIndex: 1)
            ],
            targetContext: target
        )

        XCTAssertEqual(
            moves,
            [
                ContextDisplayMove(displayID: "built-in", currentIndex: 0, targetIndex: 2),
                ContextDisplayMove(displayID: "external-lg", currentIndex: 1, targetIndex: 3)
            ]
        )
    }

    func testSkipsDisplaysAlreadyAtTargetOrNotInContext() {
        let target = ContextDefinition(
            id: "context-2",
            order: 2,
            name: "Two",
            displayIDs: ["built-in"],
            displaySpaceIndexes: ["built-in": 1]
        )
        let moves = ContextDisplayMovePlanner.moves(
            displays: [
                InstantCaptureDisplay(displayID: "built-in", spaceCount: 3, currentSpaceIndex: 1),
                InstantCaptureDisplay(displayID: "external-lg", spaceCount: 4, currentSpaceIndex: 0)
            ],
            targetContext: target
        )

        XCTAssertEqual(moves, [])
    }
}
