import XCTest
import SidebyCore
@testable import SidebyApp

final class ConnectionGuidancePresentationTests: XCTestCase {
    private let partial = ContextDefinition(id: "work", order: 1, name: "Work", displaySpaceIndexes: ["a": 0])

    private func guidance(contexts: [ContextDefinition]? = nil, displays: [String] = ["a", "b"],
                          readable: Set<String> = ["a", "b"], available: Set<String> = ["work"],
                          resolved: Set<String> = ["work"], eligible: Bool = true, editable: Bool = true) -> ConnectionGuidancePresentation {
        .init(contexts: contexts ?? [partial], displayIDs: displays, readableIDs: readable,
              availableIDs: available, resolvedIDs: resolved, isEligible: eligible, canEdit: editable)
    }

    func testPartialCurrentConnectionCanExplainBothPairingAndItsExistingUse() {
        let value = guidance()
        XCTAssertEqual(value.pairing, .init(contextID: "work", displayIDs: ["b"]))
        XCTAssertEqual(value.usage, .rememberCurrent)
    }

    func testCountsSavedConnectionsInsteadOfOnlyAvailableConnections() {
        let second = ContextDefinition(id: "offline", order: 2, name: "Offline", displaySpaceIndexes: ["offline": 0])
        XCTAssertEqual(guidance(contexts: [partial, second]), ConnectionGuidancePresentation())
        XCTAssertEqual(guidance(contexts: []), ConnectionGuidancePresentation())
    }

    func testUnknownBlockedAndUnavailableStatesMakeNoDestinationClaim() {
        XCTAssertEqual(guidance(eligible: false), ConnectionGuidancePresentation())
        XCTAssertEqual(guidance(available: []), ConnectionGuidancePresentation())
        XCTAssertNil(guidance(editable: false).pairing)
        XCTAssertEqual(guidance(editable: false).usage, .rememberCurrent)
    }

    func testOnlyReadableParticipatingMissingDisplaysAreSuggestedInDisplayOrder() {
        let value = guidance(displays: ["c", "a", "b", "unreadable"], readable: ["a", "b", "c", "excluded"])
        XCTAssertEqual(value.pairing?.displayIDs, ["c", "b"])
        XCTAssertNil(guidance(displays: ["a"]).pairing)
        XCTAssertNil(guidance(readable: ["b"]).pairing)
        XCTAssertEqual(guidance(resolved: []).usage, .chooseDestination)
    }

    @MainActor func testModelAdapterDoesNotReadNativeStateOrMutateSettings() {
        let model = heldMatrixFixture(count: 1)
        let before = model.settings
        var reads = 0
        model.workspaceObservationOverride = { reads += 1; return nil }
        XCTAssertEqual(model.connectionGuidance.usage, .rememberCurrent)
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(model.settings, before)
        model.permissionState = .denied
        XCTAssertEqual(model.connectionGuidance, ConnectionGuidancePresentation())
    }
}
