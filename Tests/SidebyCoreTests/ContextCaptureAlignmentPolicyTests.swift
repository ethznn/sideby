import XCTest
@testable import SidebyCore

final class ContextCaptureAlignmentPolicyTests: XCTestCase {
    private let contexts = [
        ContextDefinition(id: "context-5", order: 5, name: "Context 5", displayIDs: ["ext"]),
        ContextDefinition(id: "context-3", order: 3, name: "Context 3", displayIDs: ["builtin", "ext"]),
        ContextDefinition(id: "context-1", order: 1, name: "Context 1", displayIDs: ["builtin", "ext"]),
        ContextDefinition(id: "context-4", order: 4, name: "Context 4", displayIDs: ["ext"]),
        ContextDefinition(id: "context-2", order: 2, name: "Context 2", displayIDs: ["builtin", "ext"])
    ]

    func testCandidatesIncludeOnlyContextsSharedByEverySelectedDisplayInOrder() {
        XCTAssertEqual(
            ContextCaptureAlignmentPolicy.candidates(
                contexts: contexts,
                selectedDisplayIDs: ["builtin", "ext"]
            ),
            [
                .init(id: "context-1", order: 1, name: "Context 1"),
                .init(id: "context-2", order: 2, name: "Context 2"),
                .init(id: "context-3", order: 3, name: "Context 3")
            ]
        )
    }

    func testCandidatesReturnsEmptyForEmptySelection() {
        XCTAssertEqual(
            ContextCaptureAlignmentPolicy.candidates(contexts: contexts, selectedDisplayIDs: []),
            []
        )
    }

    func testCandidatesReturnsEmptyWhenSelectedDisplaysNeverCooccur() {
        XCTAssertEqual(
            ContextCaptureAlignmentPolicy.candidates(
                contexts: contexts,
                selectedDisplayIDs: ["builtin", "other"]
            ),
            []
        )
    }
}
