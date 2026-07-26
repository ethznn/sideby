import XCTest
@testable import SidebyCore

final class InstantContextCapturePlannerTests: XCTestCase {
    func testAsymmetricDisplaysGetExactMembership() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 5, currentSpaceIndex: 2),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 2)
        ])

        XCTAssertEqual(plan?.contexts.count, 5)
        XCTAssertEqual(plan?.contexts[2].displayIDs.sorted(), ["builtin", "ext"])
        XCTAssertEqual(plan?.contexts[3].displayIDs, ["ext"])
        XCTAssertEqual(plan?.contexts[4].displayIDs, ["ext"])
    }

    func testAsymmetricDisplaysPreserveRawSpaceIndexesWhenCurrentIndexesDiffer() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 4, currentSpaceIndex: 3),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 2)
        ])

        XCTAssertEqual(plan?.contexts.count, 4)
        XCTAssertEqual(plan?.currentContextID, "context-4")
        XCTAssertFalse(plan?.isSynchronized ?? true)
        XCTAssertEqual(plan?.contexts.map(\.displaySpaceIndexes), [
            ["builtin": 0, "ext": 0],
            ["builtin": 1, "ext": 1],
            ["builtin": 2, "ext": 2],
            ["ext": 3]
        ])
    }

    func testSuggestedCurrentNameChangesOnlySynchronizedCurrentContext() throws {
        let plan = try XCTUnwrap(InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 4, currentSpaceIndex: 2),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 2)
        ]))

        XCTAssertEqual(
            plan.contextsApplyingSuggestedCurrentName("Codex / Finder").map(\.name),
            ["Context 1", "Context 2", "Codex / Finder", "Context 4"]
        )
    }

    func testAgreedCurrentIndexIsSynchronizedCurrentContext() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 5, currentSpaceIndex: 2),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 2)
        ])

        XCTAssertEqual(plan?.currentContextID, "context-3")
        XCTAssertEqual(plan?.isSynchronized, true)
    }

    func testFirstDisplayCurrentIndexSelectsCurrentContextWithoutShiftingMembership() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 5, currentSpaceIndex: 4),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 1)
        ])

        XCTAssertEqual(plan?.currentContextID, "context-5")
        XCTAssertFalse(plan?.isSynchronized ?? true)
        XCTAssertEqual(plan?.contexts.map(\.displayIDs), [
            ["builtin", "ext"],
            ["builtin", "ext"],
            ["builtin", "ext"],
            ["ext"],
            ["ext"]
        ])
    }

    func testSuggestedCurrentNameLeavesUnsynchronizedPlanNamesUntouched() throws {
        let plan = try XCTUnwrap(InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 4, currentSpaceIndex: 3),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 2)
        ]))

        XCTAssertEqual(
            plan.contextsApplyingSuggestedCurrentName("Codex / Finder").map(\.name),
            ["Context 1", "Context 2", "Context 3", "Context 4"]
        )
    }

    func testContextCountIncludesEveryDiscoveredSpace() throws {
        let plan = try XCTUnwrap(InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 30, currentSpaceIndex: 20)
        ]))

        XCTAssertEqual(plan.contexts.count, 30)
        XCTAssertEqual(plan.currentContextID, "context-21")
        XCTAssertTrue(plan.isSynchronized)
        XCTAssertEqual(plan.contexts.last?.spaceIndex(for: "ext"), 29)
    }

    func testDefaultNamesAndIdentifiersFollowOrder() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "only", spaceCount: 2, currentSpaceIndex: 0)
        ])

        XCTAssertEqual(plan?.contexts.map(\.id), ["context-1", "context-2"])
        XCTAssertEqual(plan?.contexts.map(\.name), ["Context 1", "Context 2"])
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(InstantContextCapturePlanner.plan(for: []))
        XCTAssertNil(InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "x", spaceCount: 0, currentSpaceIndex: 0)
        ]))
    }

}
