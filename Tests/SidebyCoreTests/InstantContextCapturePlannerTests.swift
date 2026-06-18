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
        XCTAssertEqual(plan?.captureLimit, 5)
    }

    func testAsymmetricCurrentIndexesCanLeaveMiddleContextEmptyForDisplay() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 4, currentSpaceIndex: 3),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 2)
        ])

        XCTAssertEqual(plan?.contexts.count, 4)
        XCTAssertEqual(plan?.currentContextID, "context-4")
        XCTAssertEqual(plan?.isSynchronized, true)
        XCTAssertEqual(plan?.contexts.map(\.displayIDs), [
            ["builtin", "ext"],
            ["builtin", "ext"],
            ["ext"],
            ["builtin", "ext"]
        ])
        XCTAssertEqual(plan?.contexts[0].displaySpaceIndexes, ["builtin": 0, "ext": 0])
        XCTAssertEqual(plan?.contexts[1].displaySpaceIndexes, ["builtin": 1, "ext": 1])
        XCTAssertEqual(plan?.contexts[2].displaySpaceIndexes, ["ext": 2])
        XCTAssertEqual(plan?.contexts[3].displaySpaceIndexes, ["builtin": 2, "ext": 3])
    }

    func testRenamingCurrentContextPreservesCapturedSpaceIndexes() throws {
        let plan = try XCTUnwrap(InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 4, currentSpaceIndex: 3),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 2)
        ]))

        let contexts = plan.contextsRenamingCurrentContext(to: "Codex / Finder")

        XCTAssertEqual(contexts[3].name, "Codex / Finder")
        XCTAssertEqual(contexts[3].displaySpaceIndexes, ["builtin": 2, "ext": 3])
        XCTAssertEqual(contexts.compactMap { $0.spaceIndex(for: "builtin") }, [0, 1, 2])
    }

    func testAgreedCurrentIndexIsSynchronizedCurrentContext() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 5, currentSpaceIndex: 2),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 2)
        ])

        XCTAssertEqual(plan?.currentContextID, "context-3")
        XCTAssertEqual(plan?.isSynchronized, true)
    }

    func testDisagreeingCurrentIndexesAlignToHighestVisibleContext() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 5, currentSpaceIndex: 4),
            InstantCaptureDisplay(displayID: "builtin", spaceCount: 3, currentSpaceIndex: 1)
        ])

        XCTAssertEqual(plan?.currentContextID, "context-5")
        XCTAssertEqual(plan?.isSynchronized, true)
        XCTAssertEqual(plan?.contexts[1].displayIDs, ["ext"])
        XCTAssertEqual(plan?.contexts[4].displaySpaceIndexes, ["builtin": 1, "ext": 4])
    }

    func testContextCountIsCappedAtTwelve() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 30, currentSpaceIndex: 0)
        ])

        XCTAssertEqual(plan?.contexts.count, 12)
        XCTAssertEqual(plan?.captureLimit, 12)
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

    func testCurrentIndexBeyondCapIsNotSynchronized() {
        let plan = InstantContextCapturePlanner.plan(for: [
            InstantCaptureDisplay(displayID: "ext", spaceCount: 30, currentSpaceIndex: 20)
        ])

        XCTAssertEqual(plan?.currentContextID, "context-12")
        XCTAssertEqual(plan?.isSynchronized, false)
    }
}
