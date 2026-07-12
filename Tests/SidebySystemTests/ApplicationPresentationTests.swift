import AppKit
import XCTest
@testable import SidebySystem

final class ApplicationPresentationTests: XCTestCase {
    func testMenuBarOnlyPresentationUsesAccessoryActivationPolicy() {
        XCTAssertEqual(MenuBarOnlyApplicationPresentation.activationPolicy, .accessory)
    }

    @MainActor
    func testMenuBarOnlyPresentationAppliesAccessoryActivationPolicy() {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        defer { application.setActivationPolicy(originalPolicy) }

        XCTAssertTrue(MenuBarOnlyApplicationPresentation.apply(to: application))
        XCTAssertEqual(application.activationPolicy(), .accessory)
    }
}
