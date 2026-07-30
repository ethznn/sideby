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
        XCTAssertEqual(
            state.status,
            "Configured gestures are observed only while Sideby is on or during an explicitly active onboarding gesture test. While running, fixed ⌥⇧ number / < / > hot keys remain registered for off-state feedback. Other raw input is not inspected or stored."
        )
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

    func testDescribesFixedKeyboardControlsWhenSidebyIsEnabled() {
        let state = V1SetupFlow().viewState(
            for: V1SetupStatus(
                displayCount: 2,
                selectedTargetCount: 2,
                accessibilityPermission: .granted,
                isSidebyEnabled: true,
                didCompleteOnboarding: false
            )
        )

        XCTAssertEqual(
            state.status,
            "Use Option + Shift with horizontal scroll. For a Context number or < / >, release Option + Shift to switch."
        )
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

    func testPostEventDenialRoutesOnlyToAccessibilitySettings() {
        let feedback = PermissionRequestFeedbackResolver()
            .switchingAccessFeedback(postEventsGranted: false)

        XCTAssertEqual(feedback, PermissionRequestFeedback.postEventsDenied)
        XCTAssertEqual(feedback?.action, .openAccessibilitySettings)
    }

    func testSwitchingAccessGrantedClearsFeedback() {
        let feedback = PermissionRequestFeedbackResolver()
            .switchingAccessFeedback(postEventsGranted: true)

        XCTAssertNil(feedback)
    }

    func testPostEventGrantedRequestClearsFeedback() {
        let feedback = PermissionRequestFeedbackResolver().postEventFeedback(isGranted: true)

        XCTAssertNil(feedback)
    }
}
