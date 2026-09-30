import XCTest
import SidebyCore
@testable import SidebyApp

@MainActor
final class WorkspaceActivationGuardTests: XCTestCase {
    private func model(index: Int = 0, count: Int = 2) -> SidebyAppModel {
        var settings = AppSettings.default
        settings.contextPlan = ContextPlan(contexts: [
            .init(id: "a", order: 1, name: "Development", displayIDs: ["main"]),
            .init(id: "b", order: 2, name: "Review", displayIDs: ["main"])
        ], currentContextID: "a")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["main"], selectedDisplaySpaces: {
            [.init(displayID: "main", spaceCount: count, currentSpaceIndex: index)]
        }, postEventAccessGranted: false)
        model.workspaceSpaceIDsOverride = { ["main": [11, 12]] }
        return model
    }

    func testLaunchRestoresSingleDisplaySwitchingWithoutManualConfirmation() {
        let model = model()
        let target = model.settings.contextPlan.contexts[1]
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.workspaceConnectionStatus, .ready)
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, "a")
        XCTAssertTrue(model.settings.contextPlan.switchIntent(for: .next).shouldExecute)
        XCTAssertTrue(model.admitWorkspaceActivation(target, snapshot: ["main": [11, 12]]))
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), ["Development", "Review"])
        XCTAssertFalse(model.isSwitching)
    }

    func testDirectActivationReadsTheCurrentLayoutWithoutPriorSessionConfirmation() {
        let model = model()
        let target = model.settings.contextPlan.contexts[1]
        XCTAssertTrue(model.admitWorkspaceActivation(target, snapshot: ["main": [11, 12]]))
        XCTAssertTrue(model.admitWorkspaceActivation(target, snapshot: ["main": [12, 11]]))
        XCTAssertFalse(model.admitWorkspaceActivation(target, snapshot: ["main": [11]]))
        XCTAssertFalse(model.admitWorkspaceActivation(target, snapshot: nil))
        XCTAssertFalse(model.isSwitching)
    }

    func testFailedReconfirmationClearsPreviouslyVerifiedWorkspace() {
        let model = model()
        XCTAssertTrue(model.confirmWorkspaceConnections())
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, "a")
        model.workspaceSpaceIDsOverride = { nil }
        XCTAssertFalse(model.confirmWorkspaceConnections())
        XCTAssertNil(model.verifiedCurrentWorkspaceID)
        XCTAssertEqual(model.workspaceConnectionSession.status(for: ["main"], spaceIDsByDisplayID: ["main": [11, 12]]), .unconfirmed)
    }

    func testConfirmationUsesOneObservationForIdentityAndCurrentPosition() {
        let model = model()
        var reads = 0
        model.workspaceObservationOverride = {
            reads += 1
            return WorkspaceLayoutObservation(
                displays: [.init(displayID: "main", spaceCount: 2, currentSpaceIndex: reads == 1 ? 0 : 1)],
                spaceIDsByDisplayID: ["main": reads == 1 ? [11, 12] : [12, 11]]
            )
        }
        XCTAssertTrue(model.confirmWorkspaceConnections())
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, "a")
        model.refreshWorkspaceStatus()
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(model.workspaceConnectionStatus, .ready)
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, "a")
        XCTAssertEqual(model.settings.contextPlan.contexts[0].spaceIndex(for: "main"), 1)
    }

    func testMappingEditResetsPartialGuideButRenamePreservesIt() {
        let model = model()
        model.workspaceGuideIsRecording = true
        model.recordWorkspaceActivation(model.settings.contextPlan.contexts[0], succeeded: true)
        model.recordWorkspaceActivation(model.settings.contextPlan.contexts[1], succeeded: true)
        model.setContextName(contextID: "a", name: "Payment")
        XCTAssertEqual(model.firstWorkProgress.originContextID, "a")
        XCTAssertEqual(model.firstWorkProgress.awayContextID, "b")
        model.moveDisplaySpace(displayID: "main", spaceIndex: 0, toContextID: "b")
        XCTAssertNil(model.firstWorkProgress.originContextID)
        XCTAssertEqual(model.workspaceHistory.currentContextID, "b", "Editing assignments does not erase actual visit history")
        XCTAssertFalse(model.workspaceGuideIsRecording)
        XCTAssertEqual(model.workspaceConnectionStatus, .ready)
    }

    func testWholeSettingsUpdateReconcilesSelectedDisplays() {
        let model = model()
        model.displayLayout = .init(displays: [
            .init(id: "main", name: "Main", isPrimary: true, isBuiltin: true),
            .init(id: "external", name: "External", isPrimary: false, isBuiltin: false)
        ])
        XCTAssertTrue(model.confirmWorkspaceConnections())
        var incoming = model.settings
        incoming.displaySelection = .init(hasInitialized: true, selectedDisplayIDs: ["external"])
        model.updateSettings(incoming)
        XCTAssertEqual(model.selectedDisplayIDs, ["external"])
        XCTAssertNil(model.verifiedCurrentWorkspaceID)
    }

    func testAnOldActivationCannotPublishSuccessAfterWorkspaceReplacement() {
        let model = model()
        let target = model.settings.contextPlan.contexts[0]
        let revision = model.workspaceConfigurationRevision
        model.workspaceGuideIsRecording = true
        model.moveDisplaySpace(displayID: "main", spaceIndex: 0, toContextID: "b")
        XCTAssertFalse(model.recordWorkspaceActivation(target, succeeded: true, expectedConfigurationRevision: revision))
        XCTAssertFalse(model.lastWorkspaceSwitchSucceeded)
        XCTAssertNil(model.verifiedCurrentWorkspaceID)
        XCTAssertNil(model.workspaceHistory.currentContextID)
        XCTAssertNil(model.firstWorkProgress.originContextID)
    }

    func testMissingDesktopCannotBeConfirmedAsValidMapping() {
        let model = model(count: 1)
        model.settings.contextPlan = .init(contexts: [
            .init(id: "b", order: 1, name: "Review", displaySpaceIndexes: ["main": 1])
        ], currentContextID: "b")
        model.workspaceSpaceIDsOverride = { ["main": [11]] }
        XCTAssertFalse(model.confirmWorkspaceConnections())
        XCTAssertNil(model.verifiedCurrentWorkspaceID)
    }

    func testSingleDisplayKeepsValidWorkspaceUsableWhenAnotherSavedDesktopIsMissing() {
        let model = model(count: 1)
        model.workspaceSpaceIDsOverride = { ["main": [11]] }
        model.settings.contextPlan = .init(contexts: [
            .init(id: "a", order: 1, name: "Development", displaySpaceIndexes: ["main": 0, "external": 0]),
            .init(id: "b", order: 2, name: "Review", displaySpaceIndexes: ["main": 1, "external": 1])
        ], currentContextID: "a")
        let savedPlan = model.settings.contextPlan

        XCTAssertTrue(model.confirmWorkspaceConnections())
        XCTAssertEqual(model.workspaceConnectionStatus, .ready)
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, "a")
        XCTAssertTrue(model.isWorkspaceAssignmentAvailable(contextID: "a"))
        XCTAssertFalse(model.isWorkspaceAssignmentAvailable(contextID: "b"))
        XCTAssertFalse(model.admitWorkspaceActivation(savedPlan.contexts[1], snapshot: ["main": [11]]))
        XCTAssertTrue(model.admitWorkspaceActivation(savedPlan.contexts[0], snapshot: ["main": [11]]))
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.displaySpaceIndexes), savedPlan.contexts.map(\.displaySpaceIndexes))
        XCTAssertFalse(model.isSwitching)
    }

    func testRoundTripUsesOnlyWorkspacesAvailableOnTheSingleConnectedDisplay() {
        let model = model(count: 1)
        model.displayLayout = .init(displays: [.init(id: "main", name: "MacBook", isPrimary: true, isBuiltin: true)])
        model.workspaceSpaceIDsOverride = { ["main": [11]] }
        XCTAssertTrue(model.confirmWorkspaceConnections())
        XCTAssertEqual(ProductOnboardingFacts(model: model).participatingContextIDs, ["a"])
    }

    func testUnreadableDisplayDoesNotBlockAWorkspaceUsingOnlyTheAvailableDisplay() {
        let model = model(count: 1)
        model.selectedDisplayIDs = ["main", "external"]
        model.workspaceSpaceIDsOverride = { ["main": [11]] }
        model.settings.contextPlan = .init(contexts: [
            .init(id: "a", order: 1, name: "Local", displaySpaceIndexes: ["main": 0]),
            .init(id: "b", order: 2, name: "External", displaySpaceIndexes: ["external": 0])
        ], currentContextID: "a")
        XCTAssertFalse(model.confirmWorkspaceConnections())
        XCTAssertTrue(model.admitWorkspaceActivation(model.settings.contextPlan.contexts[0], snapshot: ["main": [11]]))
        XCTAssertFalse(model.admitWorkspaceActivation(model.settings.contextPlan.contexts[1], snapshot: ["main": [11]]))
    }

    func testFailedActivationAndCaptureAlignmentDoNotCompleteFirstRoundTrip() {
        let model = model()
        model.workspaceGuideIsRecording = true
        let a = model.settings.contextPlan.contexts[0]
        let b = model.settings.contextPlan.contexts[1]
        model.recordWorkspaceActivation(a, succeeded: true)
        model.recordWorkspaceActivation(b, succeeded: false)
        model.recordWorkspaceActivation(a, succeeded: true)
        XCTAssertFalse(model.firstWorkProgress.isComplete)
        XCTAssertNil(model.workspaceHistory.previousContextID)
        model.recordWorkspaceActivation(b, succeeded: true, recordsVisit: false)
        XCTAssertNil(model.firstWorkProgress.awayContextID)
    }

    func testSharedSingleDesktopKeepsTheChosenWorkspaceOnRefresh() {
        let model = model(count: 1)
        model.workspaceSpaceIDsOverride = { ["main": [11]] }
        model.settings.contextPlan = .init(contexts: [
            .init(id: "a", order: 1, name: "Development", displaySpaceIndexes: ["main": 0, "external": 0]),
            .init(id: "b", order: 2, name: "Review", displaySpaceIndexes: ["main": 0, "external": 1])
        ], currentContextID: "b")
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, "b")
        XCTAssertEqual(model.settings.contextPlan.syncState, .synchronized)
        XCTAssertTrue(model.isWorkspaceAssignmentAvailable(contextID: "a"))
        XCTAssertTrue(model.isWorkspaceAssignmentAvailable(contextID: "b"))
    }
}
