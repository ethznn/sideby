import XCTest
@testable import SidebyCore

final class V1SetupFlowTests: XCTestCase {
    func testBlocksCompletionWhenNoMoveTargetsAreSelected() {
        let state = V1SetupFlow().viewState(
            for: V1SetupStatus(
                displayCount: 2,
                selectedTargetCount: 0,
                accessibilityPermission: .granted,
                isSidebyEnabled: false,
                didCompleteOnboarding: false
            )
        )

        XCTAssertEqual(state.primaryActionTitle, "Select Move Targets")
        XCTAssertFalse(state.canCompleteSetup)
    }

    func testRequestsAccessibilityBeforeCompletingSetup() {
        let state = V1SetupFlow().viewState(
            for: V1SetupStatus(
                displayCount: 2,
                selectedTargetCount: 2,
                accessibilityPermission: .denied,
                isSidebyEnabled: false,
                didCompleteOnboarding: false
            )
        )

        XCTAssertEqual(state.title, "Permission needed")
        XCTAssertEqual(state.primaryActionTitle, "Enable Accessibility")
        XCTAssertFalse(state.canCompleteSetup)
    }

    func testAllowsCompletionAfterTargetsAndPermissionAreReady() {
        let state = V1SetupFlow().viewState(
            for: V1SetupStatus(
                displayCount: 2,
                selectedTargetCount: 2,
                accessibilityPermission: .granted,
                isSidebyEnabled: false,
                didCompleteOnboarding: false
            )
        )

        XCTAssertEqual(state.title, "Ready to turn on")
        XCTAssertEqual(state.primaryActionTitle, "Turn On Sideby")
        XCTAssertTrue(state.canCompleteSetup)
    }

    func testOnboardingCompletionSelectsAllConnectedDisplaysAndEnablesSideby() {
        let layout = DisplayLayout(displays: [
            DisplayInfo(id: "built-in", name: "Built-in Display", isPrimary: true, isBuiltin: true),
            DisplayInfo(id: "external-lg", name: "LG Display", isPrimary: false, isBuiltin: false)
        ])

        let defaults = OnboardingCompletionPolicy().completionDefaults(for: layout)

        XCTAssertEqual(defaults.selectedDisplayIDs, ["built-in", "external-lg"])
        XCTAssertTrue(defaults.isSidebyEnabled)
    }

    func testPostEventDeniedRequestProvidesSettingsFeedback() {
        let feedback = PermissionRequestFeedbackResolver().postEventFeedback(isGranted: false)

        XCTAssertEqual(feedback, PermissionRequestFeedback.postEventsDenied)
        XCTAssertEqual(feedback?.action, .openAccessibilitySettings)
    }

    func testPostEventRequestStartedProvidesImmediateFeedback() {
        let feedback = PermissionRequestFeedback.postEventsRequesting

        XCTAssertEqual(feedback.kind, .postEventsRequesting)
        XCTAssertNil(feedback.action)
    }

    func testSwitchingAccessRequestStartedProvidesImmediateFeedback() {
        let feedback = PermissionRequestFeedback.switchingAccessRequesting

        XCTAssertEqual(feedback.kind, .switchingAccessRequesting)
        XCTAssertNil(feedback.action)
    }

    func testSwitchingAccessDeniedByAutomationProvidesAutomationSettingsFeedback() {
        let feedback = PermissionRequestFeedbackResolver()
            .switchingAccessFeedback(postEventsGranted: true, automationGranted: false)

        XCTAssertEqual(feedback, PermissionRequestFeedback.automationDenied)
        XCTAssertEqual(feedback?.action, .openAutomationSettings)
    }

    func testSwitchingAccessWhenSystemEventsIsNotRegisteredAvoidsDeadSettingsFallback() {
        let feedback = PermissionRequestFeedbackResolver()
            .switchingAccessFeedback(postEventsGranted: true, automationStatusCode: -600)

        XCTAssertEqual(feedback, PermissionRequestFeedback.automationNotRegistered)
        XCTAssertNil(feedback?.action)
    }

    func testSwitchingAccessGrantedClearsFeedback() {
        let feedback = PermissionRequestFeedbackResolver()
            .switchingAccessFeedback(postEventsGranted: true, automationGranted: true)

        XCTAssertNil(feedback)
    }

    func testPostEventGrantedRequestClearsFeedback() {
        let feedback = PermissionRequestFeedbackResolver().postEventFeedback(isGranted: true)

        XCTAssertNil(feedback)
    }
}
