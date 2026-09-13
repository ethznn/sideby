import XCTest
import SidebyCore
@testable import SidebyApp

final class OnboardingPreparationPolicyTests: XCTestCase {
    func testInitialDefaultsRequireBothAccessesAndUncompletedPreparation() {
        XCTAssertFalse(OnboardingPreparationPolicy.shouldApplyInitialDefaults(
            didCompletePermissionSetup: false, hasRequiredPermissions: false))
        XCTAssertTrue(OnboardingPreparationPolicy.shouldApplyInitialDefaults(
            didCompletePermissionSetup: false, hasRequiredPermissions: true))
    }

    func testReplayCannotReenableAnExistingUsersDisabledApp() {
        XCTAssertFalse(OnboardingPreparationPolicy.shouldApplyInitialDefaults(
            didCompletePermissionSetup: true, hasRequiredPermissions: true))
        XCTAssertFalse(OnboardingPreparationPolicy.shouldApplyInitialDefaults(
            didCompletePermissionSetup: true, hasRequiredPermissions: false))
    }

    @MainActor
    private func retryModel() -> SidebyAppModel {
        var settings = AppSettings.default
        settings.contextPlan = ContextPlan(contexts: [
            .init(id: "a", order: 1, name: "Build", displayIDs: ["desk"]),
            .init(id: "b", order: 2, name: "Review", displayIDs: ["desk"])
        ], currentContextID: "a")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["desk"],
            selectedDisplaySpaces: { [.init(displayID: "desk", spaceCount: 2, currentSpaceIndex: 0)] },
            postEventAccessGranted: false)
        model.workspacePreferences = nil
        model.workspaceSpaceIDsOverride = { ["desk": [11, 12]] }
        return model
    }

    @MainActor
    func testFirstFailedMoveCanResumeRecordingOnlyAfterExplicitRetryAndVerifiedSuccess() {
        let model = retryModel()
        XCTAssertTrue(model.confirmWorkspaceConnections())
        let target = model.settings.contextPlan.contexts[0]
        // Model the first command's recording state without invoking its system action.
        model.workspaceGuideIsRecording = true
        XCTAssertFalse(model.recordWorkspaceActivation(target, succeeded: false))
        XCTAssertNil(model.firstWorkProgress.originContextID)
        model.dismissFirstWorkGuide()
        let preferences = MemoryProductUIPreferences()
        preferences.onboardingStage = .roundTrip
        preferences.didDismissOnboarding = true
        let presentation = ProductOnboardingPresentation(preferences: preferences)
        presentation.open(replay: false, facts: .init(
            hasAccessibilityPermission: true, hasSwitchingAccess: true,
            selectedDisplayCount: 1, participatingContextIDs: ["a", "b"],
            connectionStatus: .ready, isBusy: false, isEnabled: true, progress: model.firstWorkProgress))
        XCTAssertFalse(model.workspaceGuideIsRecording, "Reopening alone must not authorize recording")
        let progress = model.firstWorkProgress
        let settings = model.settings
        let history = model.workspaceHistory
        let revision = model.workspaceConfigurationRevision
        let connectionStatus = model.workspaceConnectionStatus
        let baseline = model.workspaceConnectionSession.status(for: ["desk"], spaceIDsByDisplayID: ["desk": [11, 12]])

        model.prepareFirstWorkspaceGuideRetry()

        XCTAssertTrue(model.workspaceGuideIsRecording)
        XCTAssertTrue(model.isShowingFirstWorkGuide)
        XCTAssertEqual(model.firstWorkProgress, progress)
        XCTAssertEqual(model.settings, settings)
        XCTAssertEqual(model.selectedDisplayIDs, ["desk"])
        XCTAssertEqual(model.workspaceHistory, history)
        XCTAssertEqual(model.workspaceConfigurationRevision, revision)
        XCTAssertEqual(model.workspaceConnectionStatus, connectionStatus)
        XCTAssertEqual(model.workspaceConnectionSession.status(for: ["desk"], spaceIDsByDisplayID: ["desk": [11, 12]]), baseline)
        XCTAssertEqual(model.workspaceRecoveryTargetID, "a")
        XCTAssertTrue(preferences.didDismissOnboarding)
        XCTAssertFalse(preferences.didCompletePermissionSetup)
        XCTAssertNil(model.workspacePreferences)
        XCTAssertFalse(model.recordWorkspaceActivation(target, succeeded: false))
        XCTAssertEqual(model.firstWorkProgress, progress)
        XCTAssertTrue(model.recordWorkspaceActivation(target, succeeded: true))
        XCTAssertEqual(model.firstWorkProgress.originContextID, "a")
        XCTAssertNil(model.firstWorkProgress.awayContextID)
        XCTAssertFalse(model.firstWorkProgress.isComplete)
    }

    @MainActor
    func testLaterRetriesPreserveVerifiedAAndBAndCompleteOnlyOnVerifiedReturn() {
        let model = retryModel()
        let a = model.settings.contextPlan.contexts[0]
        let b = model.settings.contextPlan.contexts[1]
        model.workspaceGuideIsRecording = true
        XCTAssertTrue(model.recordWorkspaceActivation(a, succeeded: true))
        for target in [b, a] {
            XCTAssertFalse(model.recordWorkspaceActivation(target, succeeded: false))
            model.dismissFirstWorkGuide()
            let before = model.firstWorkProgress
            model.prepareFirstWorkspaceGuideRetry()
            XCTAssertEqual(model.firstWorkProgress, before)
            XCTAssertTrue(model.workspaceGuideIsRecording)
            XCTAssertFalse(model.recordWorkspaceActivation(target, succeeded: false))
            XCTAssertEqual(model.firstWorkProgress, before)
            XCTAssertTrue(model.recordWorkspaceActivation(target, succeeded: true))
        }
        XCTAssertEqual(model.firstWorkProgress.originContextID, "a")
        XCTAssertEqual(model.firstWorkProgress.awayContextID, "b")
        XCTAssertTrue(model.firstWorkProgress.isComplete)
    }

    @MainActor
    func testCompletedGuideRetryPreparationDisarmsWithoutResettingCompletion() {
        let model = retryModel()
        let a = model.settings.contextPlan.contexts[0]
        let b = model.settings.contextPlan.contexts[1]
        model.workspaceGuideIsRecording = true
        for target in [a, b, a] { XCTAssertTrue(model.recordWorkspaceActivation(target, succeeded: true)) }
        let completed = model.firstWorkProgress
        model.prepareFirstWorkspaceGuideRetry()
        XCTAssertTrue(model.firstWorkProgress.isComplete)
        XCTAssertEqual(model.firstWorkProgress, completed)
        XCTAssertFalse(model.workspaceGuideIsRecording)
        XCTAssertNil(model.workspacePreferences)
    }

}
