import XCTest
@testable import SidebyApp

final class ProductUINavigationTests: XCTestCase {
    @MainActor func testGenericOpenDoesNotReuseRecoveryIntent() {
        let preferences = MemoryProductUIPreferences()
        preferences.lastSettingsPane = .general
        let navigation = ProductUINavigation(preferences: preferences)
        navigation.openSettings(nil)
        XCTAssertEqual(navigation.settingsRoute.pane, .general)

        navigation.openSettings(.init(pane: .workspaces, contextID: "review", displayID: "desk", returnTo: .daily))
        XCTAssertEqual(navigation.settingsRoute.contextID, "review")
        XCTAssertEqual(navigation.settingsRoute.displayID, "desk")
        XCTAssertEqual(navigation.consumeReturnDestination(), .daily)
        XCTAssertNil(navigation.consumeReturnDestination())
        navigation.openSettings(nil)
        XCTAssertEqual(navigation.settingsRoute.pane, .workspaces)
        XCTAssertNil(navigation.settingsRoute.contextID)
        XCTAssertNil(navigation.settingsRoute.displayID)
        XCTAssertNil(navigation.settingsRoute.returnTo)
    }

    @MainActor func testGenericOpenDiscardsUnconsumedReturnAndRestoresMostRecentPane() {
        let preferences = MemoryProductUIPreferences()
        let navigation = ProductUINavigation(preferences: preferences)
        navigation.openSettings(.init(pane: .workspaces, contextID: "a", returnTo: .onboarding))
        navigation.openSettings(nil)
        XCTAssertNil(navigation.consumeReturnDestination())
        navigation.selectPane(.input)
        let reopened = ProductUINavigation(preferences: preferences)
        XCTAssertEqual(reopened.settingsRoute, .init(pane: .input))
    }

    @MainActor func testReplacingAnExplicitRouteCannotKeepOldTarget() {
        let navigation = ProductUINavigation(preferences: MemoryProductUIPreferences())
        navigation.openSettings(.init(pane: .workspaces, contextID: "a", displayID: "desk", returnTo: .daily))
        navigation.openSettings(.init(pane: .permissions))
        XCTAssertEqual(navigation.settingsRoute, .init(pane: .permissions))
        XCTAssertNil(navigation.consumeReturnDestination())
    }

    @MainActor func testNavigationDoesNotChangePreparationOrDismissalState() {
        let preferences = MemoryProductUIPreferences()
        preferences.onboardingStage = .roundTrip
        preferences.didCompletePermissionSetup = true
        preferences.didDismissOnboarding = true
        let navigation = ProductUINavigation(preferences: preferences)
        navigation.openSettings(.init(pane: .general))
        navigation.selectPane(.workspaces)
        XCTAssertEqual(preferences.onboardingStage, .roundTrip)
        XCTAssertTrue(preferences.didCompletePermissionSetup)
        XCTAssertTrue(preferences.didDismissOnboarding)
    }
}
