import XCTest
@testable import SidebyCore

final class SettingsAccessRouteTests: XCTestCase {
    func testOpenSettingsUsesMenuPanelEvenWhenOnboardingIsIncomplete() {
        XCTAssertEqual(
            SettingsAccessRoute.route(for: .openSettings, didCompleteOnboarding: false),
            .menuPanel(.overview)
        )
    }

    func testCustomizeShortcutsUsesMenuPanelInputSectionEvenWhenOnboardingIsIncomplete() {
        XCTAssertEqual(
            SettingsAccessRoute.route(for: .customizeShortcuts, didCompleteOnboarding: false),
            .menuPanel(.input)
        )
    }

    func testReplayOnboardingReentersOnboarding() {
        XCTAssertEqual(
            SettingsAccessRoute.route(for: .replayOnboarding, didCompleteOnboarding: true),
            .onboarding
        )
    }
}
