import XCTest
import Combine
import SidebyCore
@testable import SidebyApp

final class ProductOnboardingStateTests: XCTestCase {
    private func readyFacts() -> ProductOnboardingFacts {
        ProductOnboardingFacts(
            hasAccessibilityPermission: true, hasSwitchingAccess: true,
            selectedDisplayCount: 1, participatingContextIDs: ["a", "b"],
            connectionStatus: .ready, isBusy: false, isEnabled: true,
            progress: WorkspaceFirstRunProgress())
    }

    func testDisplaysActionPrioritizesRevokedAccessBeforeConnectedScreens() {
        for (accessibility, switching) in [(false, true), (true, false), (false, false)] {
            var facts = readyFacts()
            facts.hasAccessibilityPermission = accessibility
            facts.hasSwitchingAccess = switching
            for count in [0, 2] {
                XCTAssertEqual(ProductOnboardingDisplayAction.resolve(
                    hasRequiredPermissions: facts.hasAccessibilityPermission && facts.hasSwitchingAccess,
                    connectedDisplayCount: count), .permissions)
            }
        }
        XCTAssertEqual(ProductOnboardingDisplayAction.resolve(hasRequiredPermissions: true,
                                                              connectedDisplayCount: 0), .refresh)
        XCTAssertEqual(ProductOnboardingDisplayAction.resolve(hasRequiredPermissions: true,
                                                              connectedDisplayCount: 2), .advance)
        var facts = readyFacts()
        facts.selectedDisplayCount = 0
        XCTAssertFalse(ProductOnboardingState(stage: .displays).canContinue(using: facts))
    }

    func testPermissionGrantDoesNotAdvanceUntilContinue() {
        var state = ProductOnboardingState()
        var facts = readyFacts()
        facts.hasAccessibilityPermission = false
        facts.hasSwitchingAccess = false
        XCTAssertFalse(state.continueIfAllowed(using: facts))
        facts.hasAccessibilityPermission = true
        XCTAssertFalse(state.continueIfAllowed(using: facts))
        facts.hasSwitchingAccess = true
        XCTAssertEqual(state.stage, .preparation)
        XCTAssertTrue(state.continueIfAllowed(using: facts))
        XCTAssertEqual(state.stage, .displays)
    }

    func testDisplayContinueRequiresOneSelectedConnectedDisplay() {
        var state = ProductOnboardingState(stage: .displays)
        var facts = readyFacts()
        facts.selectedDisplayCount = 0
        XCTAssertFalse(state.continueIfAllowed(using: facts))
        XCTAssertEqual(state.stage, .displays)
        facts.selectedDisplayCount = 1
        XCTAssertTrue(state.continueIfAllowed(using: facts))
        XCTAssertEqual(state.stage, .workspaces)
    }

    func testWorkspaceContinueRequiresTwoDistinctParticipatingContextsAndConfirmation() {
        var state = ProductOnboardingState(stage: .workspaces)
        var facts = readyFacts()
        for ids in [[], ["a"], ["a", "a"]] as [[String]] {
            facts.participatingContextIDs = ids
            XCTAssertFalse(state.continueIfAllowed(using: facts))
        }
        facts.participatingContextIDs = ["a", "b"]
        for status in [WorkspaceConnectionStatus.unconfirmed, .changed(["desk"]), .unavailable(["desk"])] {
            facts.connectionStatus = status
            XCTAssertFalse(state.continueIfAllowed(using: facts))
            XCTAssertEqual(state.stage, .workspaces)
        }
        facts.connectionStatus = .ready
        XCTAssertTrue(state.continueIfAllowed(using: facts))
        XCTAssertEqual(state.stage, .roundTrip)
    }

    func testBusyNeverAdvancesAndRevokedPrerequisitesBlockLaterStages() {
        var facts = readyFacts()
        facts.isBusy = true
        for stage in ProductOnboardingStage.allCases {
            var state = ProductOnboardingState(stage: stage)
            XCTAssertFalse(state.continueIfAllowed(using: facts))
            XCTAssertEqual(state.stage, stage)
        }
        facts.isBusy = false
        facts.hasSwitchingAccess = false
        XCTAssertFalse(ProductOnboardingState(stage: .workspaces).canContinue(using: facts))
        facts.hasSwitchingAccess = true
        facts.selectedDisplayCount = 0
        XCTAssertFalse(ProductOnboardingState(stage: .workspaces).canContinue(using: facts))
    }

    func testCompletionRequiresVerifiedRoundTripAndStaysInFourthStage() {
        var state = ProductOnboardingState(stage: .roundTrip)
        var facts = readyFacts()
        XCTAssertFalse(state.continueIfAllowed(using: facts))
        facts.progress.recordSuccessfulVisit(contextID: "a")
        facts.progress.recordSuccessfulVisit(contextID: "b")
        XCTAssertFalse(state.continueIfAllowed(using: facts))
        facts.progress.recordSuccessfulVisit(contextID: "a")
        XCTAssertTrue(state.continueIfAllowed(using: facts))
        XCTAssertEqual(state.stage, .roundTrip)
    }

    func testRelaunchResolvesEarliestInvalidPrerequisite() {
        var facts = readyFacts()
        for status in [WorkspaceConnectionStatus.unconfirmed, .changed(["desk"]), .unavailable(["desk"])] {
            var state = ProductOnboardingState(stage: .roundTrip)
            facts.connectionStatus = status
            state.reconcileAfterRelaunch(using: facts)
            XCTAssertEqual(state.stage, .workspaces)
        }
        facts.connectionStatus = .ready
        facts.participatingContextIDs = ["a"]
        var state = ProductOnboardingState(stage: .roundTrip)
        state.reconcileAfterRelaunch(using: facts)
        XCTAssertEqual(state.stage, .workspaces)
        facts.selectedDisplayCount = 0
        state.reconcileAfterRelaunch(using: facts)
        XCTAssertEqual(state.stage, .displays)
        facts.hasAccessibilityPermission = false
        state.reconcileAfterRelaunch(using: facts)
        XCTAssertEqual(state.stage, .preparation)
    }

    func testResumePreservesEligibleEarlierStageAndCurrentSessionPartialProgress() {
        var facts = readyFacts()
        facts.progress.recordSuccessfulVisit(contextID: "a")
        for stage in ProductOnboardingStage.allCases {
            var state = ProductOnboardingState(stage: stage)
            state.reconcileAfterRelaunch(using: facts)
            XCTAssertEqual(state.stage, stage)
        }
        XCTAssertEqual(facts.progress.originContextID, "a")
        XCTAssertFalse(facts.progress.isComplete)
    }

    @MainActor
    func testPresentationPersistsExplicitContinueBackAndResumeWithoutCompletingSetup() {
        let preferences = MemoryProductUIPreferences()
        let presentation = ProductOnboardingPresentation(preferences: preferences)
        XCTAssertTrue(presentation.continueIfAllowed(using: readyFacts()))
        XCTAssertEqual(preferences.onboardingStage, .displays)
        XCTAssertTrue(presentation.continueIfAllowed(using: readyFacts()))
        XCTAssertEqual(preferences.onboardingStage, .workspaces)
        presentation.goBack()
        XCTAssertEqual(preferences.onboardingStage, .displays)
        let reopened = ProductOnboardingPresentation(preferences: preferences)
        reopened.open(replay: false, facts: readyFacts())
        XCTAssertEqual(reopened.state.stage, .displays)
        XCTAssertFalse(preferences.didCompletePermissionSetup)
    }

    @MainActor
    func testReplayWhileOffPreservesCompletionAndDismissalFlags() {
        let preferences = MemoryProductUIPreferences()
        preferences.onboardingStage = .roundTrip
        preferences.didCompletePermissionSetup = true
        preferences.didDismissOnboarding = true
        let presentation = ProductOnboardingPresentation(preferences: preferences)
        var facts = readyFacts()
        facts.isEnabled = false
        for id in ["a", "b", "a"] { facts.progress.recordSuccessfulVisit(contextID: id) }
        presentation.open(replay: true, facts: facts)
        XCTAssertEqual(presentation.state.stage, .preparation)
        XCTAssertEqual(preferences.onboardingStage, .preparation)
        XCTAssertTrue(preferences.didCompletePermissionSetup)
        XCTAssertTrue(preferences.didDismissOnboarding)
        XCTAssertTrue(facts.progress.isComplete)
        XCTAssertFalse(facts.isEnabled)
    }

    @MainActor
    func testDismissedIncompletePreparationSurvivesExplicitResume() {
        let preferences = MemoryProductUIPreferences()
        preferences.didDismissOnboarding = true
        var facts = readyFacts()
        facts.hasAccessibilityPermission = false
        let presentation = ProductOnboardingPresentation(preferences: preferences)
        presentation.open(replay: false, facts: facts)
        XCTAssertEqual(presentation.state.stage, .preparation)
        XCTAssertFalse(presentation.continueIfAllowed(using: facts))
        XCTAssertTrue(preferences.didDismissOnboarding)
        XCTAssertFalse(preferences.didCompletePermissionSetup)
    }

    func testBusyObservationInvalidatesOldCountWithoutReadingUntilCompletion() {
        var observation = ProductOnboardingObservationState()
        observation.refresh(isBusy: false) { 2 }
        XCTAssertEqual(observation.contextCount, 2)
        var readsWhileBusy = 0
        observation.refresh(isBusy: true) { readsWhileBusy += 1; return 1 }
        XCTAssertEqual(readsWhileBusy, 0)
        XCTAssertNil(observation.contextCount)
        XCTAssertFalse(observation.didCheckObservation)
        XCTAssertFalse(observation.hasShortage(hasReadOrSavedAssignments: true))
        observation.refresh(isBusy: false) { 1 }
        XCTAssertEqual(observation.contextCount, 1)
        XCTAssertTrue(observation.hasShortage(hasReadOrSavedAssignments: true))
    }

    func testMissingObservationClearsPriorShortageRatherThanInventingZeroContexts() {
        var observation = ProductOnboardingObservationState()
        observation.refresh(isBusy: false) { 1 }
        XCTAssertTrue(observation.hasShortage(hasReadOrSavedAssignments: true))
        observation.refresh(isBusy: false) { nil }
        XCTAssertNil(observation.contextCount)
        XCTAssertTrue(observation.isUnavailable)
        XCTAssertFalse(observation.hasShortage(hasReadOrSavedAssignments: true))
        observation.refresh(isBusy: false) { 2 }
        XCTAssertFalse(observation.isUnavailable)
        XCTAssertFalse(observation.hasShortage(hasReadOrSavedAssignments: true))
    }

    func testReadingBeforeCaptureDoesNotPresentAnInventedPreparedWorkspaceShortage() {
        var observation = ProductOnboardingObservationState()
        observation.refresh(isBusy: false) { 1 }
        XCTAssertFalse(observation.hasShortage(hasReadOrSavedAssignments: false))
        XCTAssertTrue(observation.hasShortage(hasReadOrSavedAssignments: true))
        observation.invalidate()
        XCTAssertNil(observation.contextCount)
        XCTAssertFalse(observation.hasShortage(hasReadOrSavedAssignments: true))
    }

    @MainActor
    func testFreshSingleContextShowsShortageEvenWhenTwoNamedWorkspacesAreSaved() {
        var settings = AppSettings.default
        settings.contextPlan = .init(contexts: [
            .init(id: "build", order: 1, name: "Payment development", displaySpaceIndexes: ["desk": 0]),
            .init(id: "review", order: 2, name: "PR review", displaySpaceIndexes: ["desk": 1])
        ], currentContextID: "build")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["desk"],
            selectedDisplaySpaces: { [.init(displayID: "desk", spaceCount: 1, currentSpaceIndex: 0)] },
            postEventAccessGranted: false)
        var observation = ProductOnboardingObservationState()
        observation.refresh(isBusy: false) {
            ProductInstantContextCaptureStartPolicy.plan(
                for: model.workspaceObservation()?.displays,
                selectedDisplayIDs: model.selectedDisplayIDs)?.contexts.count
        }

        XCTAssertEqual(observation.contextCount, 1)
        XCTAssertTrue(observation.hasShortage(hasReadOrSavedAssignments: true))
        XCTAssertEqual(model.settings.contextPlan, settings.contextPlan)
        XCTAssertEqual(model.selectedDisplayIDs, ["desk"])
        XCTAssertNil(model.contextCaptureSession)
        XCTAssertFalse(model.firstWorkProgress.isComplete)
    }

    @MainActor
    func testEqualConnectionStatusPublicationRereadsChangedLayoutWithoutMutatingSavedWork() {
        var count = 1
        var reads = 0
        var settings = AppSettings.default
        settings.contextPlan = .init(contexts: [
            .init(id: "a", order: 1, name: "Keep this name", displayIDs: ["desk"])
        ], currentContextID: "a")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["desk"],
            selectedDisplaySpaces: {
                reads += 1
                return [.init(displayID: "desk", spaceCount: count, currentSpaceIndex: 0)]
            }, postEventAccessGranted: false)
        model.workspacePreferences = nil
        let originalProgress = model.firstWorkProgress
        var observation = ProductOnboardingObservationState()
        let subscription = model.$workspaceConnectionStatus.sink { _ in
            observation.refresh(isBusy: model.isSwitching || model.contextCaptureSession != nil) {
                ProductInstantContextCaptureStartPolicy.plan(
                    for: model.workspaceObservation()?.displays,
                    selectedDisplayIDs: model.selectedDisplayIDs)?.contexts.count
            }
        }
        XCTAssertEqual(observation.contextCount, 1)
        XCTAssertEqual(reads, 1)
        count = 2
        // T2's key/return refresh can publish the same status with a different observation.
        model.workspaceConnectionStatus = .unconfirmed
        XCTAssertEqual(observation.contextCount, 2)
        XCTAssertEqual(reads, 2, "Read-only observation must not publish recursively")
        XCTAssertFalse(observation.hasShortage(hasReadOrSavedAssignments: true))
        XCTAssertEqual(model.settings, settings)
        XCTAssertEqual(model.selectedDisplayIDs, ["desk"])
        XCTAssertEqual(model.firstWorkProgress, originalProgress)
        XCTAssertNil(model.contextCaptureSession)
        XCTAssertNil(model.workspacePreferences)
        subscription.cancel()
    }

}
