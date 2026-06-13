import XCTest
@testable import SidebyCore

final class ContextCurrentMatcherTests: XCTestCase {
    private let contexts = [
        ContextDefinition(id: "context-1", order: 1, name: "C1", displayIDs: ["builtin", "ext"]),
        ContextDefinition(id: "context-2", order: 2, name: "C2", displayIDs: ["builtin", "ext"]),
        ContextDefinition(id: "context-3", order: 3, name: "C3", displayIDs: ["builtin", "ext"]),
        ContextDefinition(id: "context-4", order: 4, name: "C4", displayIDs: ["ext"]),
        ContextDefinition(id: "context-5", order: 5, name: "C5", displayIDs: ["ext"])
    ]

    func testMatchesWhenAllConnectedMembersAgree() {
        XCTAssertEqual(
            ContextCurrentMatcher.currentContextID(
                contexts: contexts,
                displayIndexes: ["ext": 1, "builtin": 1]
            ),
            "context-2"
        )
    }

    func testNonMemberDisplayIsUnconstrained() {
        XCTAssertEqual(
            ContextCurrentMatcher.currentContextID(
                contexts: contexts,
                displayIndexes: ["ext": 3, "builtin": 2]
            ),
            "context-4"
        )
    }

    func testMismatchedCombinationReturnsNil() {
        XCTAssertNil(
            ContextCurrentMatcher.currentContextID(
                contexts: contexts,
                displayIndexes: ["ext": 2, "builtin": 1]
            )
        )
    }

    func testDisconnectedMembersAreIgnored() {
        XCTAssertEqual(
            ContextCurrentMatcher.currentContextID(
                contexts: contexts,
                displayIndexes: ["builtin": 0]
            ),
            "context-1"
        )
    }

    func testNoConnectedMemberMeansNoMatch() {
        XCTAssertNil(
            ContextCurrentMatcher.currentContextID(
                contexts: contexts,
                displayIndexes: ["other": 0]
            )
        )
    }

    func testEmptyInputsReturnNil() {
        XCTAssertNil(ContextCurrentMatcher.currentContextID(contexts: [], displayIndexes: ["ext": 0]))
        XCTAssertNil(ContextCurrentMatcher.currentContextID(contexts: contexts, displayIndexes: [:]))
    }
}
