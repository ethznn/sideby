import XCTest
import SidebyCore
@testable import SidebyApp

@MainActor final class HeldWorkspaceRecoveryPresentationTests: XCTestCase {
    private func observation(a: Int = 0, b: Int = 1) -> WorkspaceLayoutObservation {
        .init(displays: [.init(displayID: "a", spaceCount: 2, currentSpaceIndex: a),
                         .init(displayID: "b", spaceCount: 2, currentSpaceIndex: b)],
              spaceIDsByDisplayID: ["a": [1, 2], "b": [3, 4]])
    }
    private func presentation(observation: WorkspaceLayoutObservation?, configured: Set<String> = ["a", "b"],
        connected: Set<String> = ["a", "b"], selected: Set<String> = ["a", "b"],
        blocked: Set<String> = [], unresolved: Set<String> = [], status: WorkspaceConnectionStatus = .ready,
        members: [String: Int] = ["a": 1, "b": 1]) -> HeldWorkspaceRecoveryPresentation? {
        .init(target: .init(id: "target", order: 1, name: "Review", displaySpaceIndexes: members),
              configuredIDs: configured, connectedIDs: connected, selectedIDs: selected,
              displayOrder: ["b", "a"], observation: observation, blockedIDs: blocked,
              unresolvedIDs: unresolved, sessionStatus: status)
    }

    func testPendingDisplaysOfferRetryButMixedInvalidOrUnknownStateDoesNot() throws {
        let value = try XCTUnwrap(presentation(observation: observation()))
        XCTAssertEqual(value.action, .retry); XCTAssertEqual(value.displayIDs, ["a"])
        XCTAssertEqual(presentation(observation: observation(), blocked: ["b"])?.action, .review)
        XCTAssertEqual(presentation(observation: observation(), unresolved: ["b"])?.action, .review)
        XCTAssertEqual(presentation(observation: observation(), members: ["a": 1, "b": 9])?.action, .review)
        XCTAssertEqual(presentation(observation: nil)?.action, .refresh)
        XCTAssertEqual(presentation(observation: observation(), status: .unconfirmed)?.action, .review)
    }

    func testDisconnectedConfiguredDisplayIsNotReportedAsResolvedOrSilentlyDropped() {
        let aligned = observation(a: 1)
        let value = presentation(observation: aligned, connected: ["a"], selected: ["a"])
        XCTAssertEqual(value?.kind, .offline); XCTAssertEqual(value?.displayIDs, ["b"])
        XCTAssertEqual(value?.action, .review)
        XCTAssertNil(presentation(observation: aligned, configured: ["a"], selected: ["a"]),
                     "An explicitly excluded display is not an offline recovery requirement")
        XCTAssertEqual(presentation(observation: nil, connected: [], selected: [])?.kind, .offline)
    }

    func testUnreadableDisplayWinsOverPendingAndDuplicateHandlesCannotOfferRetry() {
        var value = observation()
        value = .init(displays: Array(value.displays.prefix(1)), spaceIDsByDisplayID: ["a": [1, 2]])
        XCTAssertEqual(presentation(observation: value)?.kind, .unreadable)
        let duplicate = WorkspaceLayoutObservation(displays: observation().displays,
                                                   spaceIDsByDisplayID: ["a": [1, 1], "b": [3, 4]])
        XCTAssertEqual(presentation(observation: duplicate)?.action, .refresh)
        XCTAssertNil(presentation(observation: observation(a: 1)))
        XCTAssertEqual(presentation(observation: observation(), configured: [], selected: [])?.kind, .noParticipants)
    }

    func testPresentationUsesCachedStateAndRetryRechecksChangedObservation() throws {
        let model = heldMatrixFixture(count: 3)
        model.workspaceRecoveryTargetID = "work-1"
        let expected = try XCTUnwrap(model.heldWorkspaceRecovery)
        XCTAssertEqual(expected.action, .retry)
        var reads = 0, selections = 0, edits = 0
        model.workspaceObservationOverride = { reads += 1; return nil }
        _ = model.heldWorkspaceRecovery
        XCTAssertEqual(reads, 0, "Rendering must not read native Space state")
        model.performHeldWorkspaceRecovery(expected, select: { _ in selections += 1 }, edit: { _ in edits += 1 })
        XCTAssertGreaterThan(reads, 0)
        XCTAssertEqual(selections, 0); XCTAssertEqual(edits, 0, "A changed retry must not silently become a repair action")
        XCTAssertEqual(model.heldWorkspaceRecovery?.action, .refresh)
        XCTAssertFalse(model.isSwitching)
    }

    func testExplicitRetryUsesFreshIdentityAndDoesNotMoveByItself() throws {
        let model = heldMatrixFixture(count: 3)
        model.workspaceRecoveryTargetID = "work-1"
        let expected = try XCTUnwrap(model.heldWorkspaceRecovery)
        let bookmarks = model.settings.savedWorkspaces.bookmarks
        let slots = model.settings.savedWorkspaces.shortcutSlots
        model.workspaceObservationOverride = { heldMatrixObservation(order: [0, 2, 1]) }
        var chosen: HeldWorkspaceColumn?
        model.performHeldWorkspaceRecovery(expected, select: { chosen = $0 }, edit: { _ in XCTFail("Retry is not edit") })
        XCTAssertEqual(chosen?.id, "work-1")
        XCTAssertEqual(chosen?.desktopLabels["mac"], model.connectionCopy.spacePosition(2))
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, bookmarks)
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, slots)
        XCTAssertFalse(model.isSwitching, "Only the existing select callback may initiate a move")
    }

    func testBusyDisabledPermissionLossAndDeletedTargetNeverOfferRecoveryAction() {
        let model = heldMatrixFixture(count: 3)
        model.workspaceRecoveryTargetID = "work-1"
        model.isSwitching = true; XCTAssertNil(model.heldWorkspaceRecovery)
        model.isSwitching = false
        model.permissionState = .denied; XCTAssertNil(model.heldWorkspaceRecovery)
        model.permissionState = .granted
        model.workspaceRecoveryTargetID = "deleted"; XCTAssertNil(model.heldWorkspaceRecovery)
    }
}
