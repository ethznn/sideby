import XCTest
@testable import SidebyCore

final class SettingsAccessRouteTests: XCTestCase {
    func testOpenSettingsUsesMainSettingsEvenWhenOnboardingIsIncomplete() {
        XCTAssertEqual(
            SettingsAccessRoute.route(for: .openSettings, didCompleteOnboarding: false),
            .mainSettings(.overview)
        )
    }

    func testCustomizeShortcutsUsesInputSectionEvenWhenOnboardingIsIncomplete() {
        XCTAssertEqual(
            SettingsAccessRoute.route(for: .customizeShortcuts, didCompleteOnboarding: false),
            .mainSettings(.input)
        )
    }

    func testReplayOnboardingReentersOnboarding() {
        XCTAssertEqual(
            SettingsAccessRoute.route(for: .replayOnboarding, didCompleteOnboarding: true),
            .onboarding
        )
    }
}
