import XCTest
@testable import SidebyCore

final class ContextEditActionTests: XCTestCase {
    func testRefreshMinimumContextCountReadsCurrentLiveLayout() {
        var readCount = 0

        let minimum = ContextEditAction.minimumContextCount(
            selectedDisplayIDs: ["built-in"],
            readLiveDisplays: {
                readCount += 1
                return [InstantCaptureDisplay(displayID: "built-in", spaceCount: 3, currentSpaceIndex: 0)]
            }
        )

        XCTAssertEqual(minimum, 3)
        XCTAssertEqual(readCount, 1)
    }

    func testDeleteContextRereadsLiveLayoutInsteadOfUsingStaleAvailabilitySnapshot() {
        var plan = contextPlan(count: 4)
        let staleMinimum = ContextEditAction.minimumContextCount(
            selectedDisplayIDs: ["built-in"],
            readLiveDisplays: {
                [InstantCaptureDisplay(displayID: "built-in", spaceCount: 3, currentSpaceIndex: 0)]
            }
        )
        var readCount = 0

        XCTAssertTrue(ContextEditPolicy.canDelete(
            contextCount: plan.contexts.count,
            minimumContextCount: staleMinimum
        ))
        XCTAssertFalse(ContextEditAction.deleteContext(
            id: "context-4",
            from: &plan,
            isEditingAllowed: true,
            selectedDisplayIDs: ["built-in"],
            readLiveDisplays: {
                readCount += 1
                return [InstantCaptureDisplay(displayID: "built-in", spaceCount: 4, currentSpaceIndex: 0)]
            }
        ))
        XCTAssertEqual(readCount, 1)
        XCTAssertEqual(plan.contexts.map(\.id), ["context-1", "context-2", "context-3", "context-4"])
    }

    func testDeleteContextFailsClosedWhenLiveLayoutIsUnavailable() {
        var plan = contextPlan(count: 4)
        var readCount = 0

        XCTAssertFalse(ContextEditAction.deleteContext(
            id: "context-4",
            from: &plan,
            isEditingAllowed: true,
            selectedDisplayIDs: ["built-in"],
            readLiveDisplays: {
                readCount += 1
                return nil
            }
        ))
        XCTAssertEqual(readCount, 1)
        XCTAssertEqual(plan.contexts.count, 4)
    }

    func testDeleteConfirmationUsesSelectedContextMappings() {
        let contexts = [
            ContextDefinition(id: "empty", order: 1, name: "Empty"),
            ContextDefinition(
                id: "mapped",
                order: 2,
                name: "Mapped",
                displayIDs: ["built-in"],
                displaySpaceIndexes: ["built-in": 1]
            )
        ]

        XCTAssertFalse(ContextEditAction.requiresDeleteConfirmation(
            contextID: "empty",
            contexts: contexts
        ))
        XCTAssertTrue(ContextEditAction.requiresDeleteConfirmation(
            contextID: "mapped",
            contexts: contexts
        ))
    }

    private func contextPlan(count: Int) -> ContextPlan {
        ContextPlan(
            contexts: (1...count).map { index in
                ContextDefinition(id: "context-\(index)", order: index, name: "Context \(index)")
            },
            currentContextID: "context-1",
            syncState: .synchronized,
            captureLimit: count,
            isPinned: false
        )
    }
}
