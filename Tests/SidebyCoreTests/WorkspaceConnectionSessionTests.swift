import XCTest
@testable import SidebyCore

final class WorkspaceConnectionSessionTests: XCTestCase {
    private let baseline: [String: [UInt64]] = ["builtin": [11, 12], "external": [21, 22]]

    func testFreshSessionCannotTrustAStoredWorkspace() {
        let session = WorkspaceConnectionSession()
        XCTAssertEqual(session.status(for: ["builtin"], spaceIDsByDisplayID: baseline), .unconfirmed)
    }

    func testExplicitConfirmationAllowsMatchingRequiredLayouts() {
        var session = WorkspaceConnectionSession()
        XCTAssertTrue(session.confirm(spaceIDsByDisplayID: baseline))
        XCTAssertEqual(session.status(for: ["builtin", "external"], spaceIDsByDisplayID: baseline), .ready)
    }

    func testUnrelatedDisplayChangesDoNotBlockRequiredSubset() {
        var session = WorkspaceConnectionSession()
        session.confirm(spaceIDsByDisplayID: baseline)
        XCTAssertEqual(session.status(for: ["builtin"], spaceIDsByDisplayID: ["builtin": [11, 12]]), .ready)
        XCTAssertEqual(
            session.status(for: ["builtin"], spaceIDsByDisplayID: ["builtin": [11, 12], "external": [22, 21]]),
            .ready
        )
    }

    func testReorderReplacementDeletionAndAdditionRequireReviewWithoutRebasing() {
        var session = WorkspaceConnectionSession()
        session.confirm(spaceIDsByDisplayID: baseline)
        let changedLayouts: [[UInt64]] = [[12, 11], [11, 13], [11], [11, 12, 13]]
        for layout in changedLayouts {
            XCTAssertEqual(
                session.status(for: ["builtin"], spaceIDsByDisplayID: ["builtin": layout]),
                .changed(["builtin"])
            )
            XCTAssertEqual(
                session.status(for: ["builtin"], spaceIDsByDisplayID: ["builtin": layout]),
                .changed(["builtin"])
            )
        }
        XCTAssertEqual(session.status(for: ["builtin"], spaceIDsByDisplayID: baseline), .ready)
    }

    func testMissingEmptyAndDuplicateRequiredLayoutsAreUnavailable() {
        var session = WorkspaceConnectionSession()
        session.confirm(spaceIDsByDisplayID: baseline)
        let unavailableLayouts: [[String: [UInt64]]?] = [nil, [:], ["builtin": []], ["builtin": [11, 11]]]
        for layout in unavailableLayouts {
            XCTAssertEqual(session.status(for: ["builtin"], spaceIDsByDisplayID: layout), .unavailable(["builtin"]))
        }
    }

    func testUnavailableDisplaysTakePrecedenceOverChangedDisplays() {
        var session = WorkspaceConnectionSession()
        session.confirm(spaceIDsByDisplayID: baseline)
        XCTAssertEqual(
            session.status(for: ["builtin", "external"], spaceIDsByDisplayID: ["builtin": [12, 11]]),
            .unavailable(["external"])
        )
    }

    func testLiveLayoutsSharingSpaceIdentityAreUnavailable() {
        var session = WorkspaceConnectionSession()
        session.confirm(spaceIDsByDisplayID: baseline)
        XCTAssertEqual(
            session.status(for: ["builtin", "external"], spaceIDsByDisplayID: ["builtin": [11, 12], "external": [11, 22]]),
            .unavailable(["builtin", "external"])
        )
    }

    func testInvalidConfirmationClearsAnyPreviousTrust() {
        let invalidLayouts: [[String: [UInt64]]] = [
            [:], ["builtin": []], ["builtin": [11, 11]], ["": [11]],
            ["builtin": [11, 12], "external": [12, 22]]
        ]
        for layout in invalidLayouts {
            var session = WorkspaceConnectionSession()
            session.confirm(spaceIDsByDisplayID: baseline)
            XCTAssertFalse(session.confirm(spaceIDsByDisplayID: layout))
            XCTAssertEqual(session.status(for: ["builtin"], spaceIDsByDisplayID: baseline), .unconfirmed)
        }
    }

    func testNewRequiredDisplayNeedsExplicitConfirmation() {
        var session = WorkspaceConnectionSession()
        session.confirm(spaceIDsByDisplayID: ["builtin": [11, 12]])
        XCTAssertEqual(session.status(for: ["external"], spaceIDsByDisplayID: baseline), .unconfirmed)
        session.confirm(spaceIDsByDisplayID: baseline)
        XCTAssertEqual(session.status(for: ["external"], spaceIDsByDisplayID: baseline), .ready)
    }

    func testResetRequiresConfirmationAgain() {
        var session = WorkspaceConnectionSession()
        session.confirm(spaceIDsByDisplayID: baseline)
        session.reset()
        XCTAssertEqual(session.status(for: ["builtin"], spaceIDsByDisplayID: baseline), .unconfirmed)
    }

    func testNoRequiredDisplayCannotBeReportedReady() {
        var session = WorkspaceConnectionSession()
        session.confirm(spaceIDsByDisplayID: baseline)
        XCTAssertEqual(session.status(for: [], spaceIDsByDisplayID: baseline), .unavailable([]))
    }
}
