import XCTest
@testable import SidebyApp

final class ProductUINavigationTests: XCTestCase {
    @MainActor func testWorkspaceEditingDoesNotReplaceTheLastSettingsPane() {
        let preferences = MemoryProductUIPreferences()
        preferences.lastSettingsPane = .input
        let navigation = ProductUINavigation(preferences: preferences)
        navigation.openWorkspaces(.init(pane: .workspaces, contextID: "writing", displayID: "desk", returnTo: .onboarding))
        navigation.openSettings(nil)
        XCTAssertEqual(navigation.settingsRoute, .init(pane: .input))
        XCTAssertEqual(navigation.workspaceRoute.contextID, "writing")
        XCTAssertEqual(navigation.workspaceRoute.displayID, "desk")
        XCTAssertEqual(preferences.lastSettingsPane, .input)
        XCTAssertEqual(navigation.consumeReturnDestination(), .onboarding)
        XCTAssertNil(navigation.consumeReturnDestination())
    }

    @MainActor func testGenericWorkspaceOpenClearsEarlierRecoveryIntent() {
        let navigation = ProductUINavigation(preferences: MemoryProductUIPreferences())
        navigation.openWorkspaces(.init(pane: .workspaces, contextID: "a", returnTo: .onboarding))
        navigation.openWorkspaces()
        XCTAssertEqual(navigation.workspaceRoute, .init(pane: .workspaces))
        XCTAssertNil(navigation.consumeReturnDestination())
    }

    @MainActor func testConnectionsOpenInsideSettingsAndKeepLegacyDraftRouteSeparate() {
        let preferences = MemoryProductUIPreferences()
        preferences.lastSettingsPane = .workspaces
        let navigation = ProductUINavigation(preferences: preferences)
        XCTAssertEqual(navigation.settingsRoute.pane, .workspaces)
        navigation.openSettings(.init(pane: .workspaces, contextID: "a", returnTo: .daily))
        XCTAssertEqual(navigation.settingsRoute.contextID, "a")
        XCTAssertNil(navigation.workspaceRoute.contextID)
        XCTAssertEqual(navigation.settingsRoute.pane, .workspaces)
        navigation.selectPane(.permissions)
        XCTAssertEqual(navigation.settingsRoute.pane, .permissions)
        XCTAssertNil(navigation.consumeReturnDestination())
    }

    @MainActor func testNavigationDoesNotChangePreparationOrDismissalState() {
        let preferences = MemoryProductUIPreferences()
        preferences.onboardingStage = .roundTrip
        preferences.didCompletePermissionSetup = true
        preferences.didDismissOnboarding = true
        let navigation = ProductUINavigation(preferences: preferences)
        navigation.openSettings(.init(pane: .general))
        navigation.openWorkspaces()
        XCTAssertEqual(preferences.onboardingStage, .roundTrip)
        XCTAssertTrue(preferences.didCompletePermissionSetup)
        XCTAssertTrue(preferences.didDismissOnboarding)
    }
}
