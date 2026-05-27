import XCTest
@testable import SidebyCore

final class SettingsPanelPolicyTests: XCTestCase {
    func testProductSettingsExcludeAdvancedSection() {
        XCTAssertEqual(
            SettingsPanelPolicy.sections(for: .product),
            [.overview, .displays, .input, .permissions, .general]
        )
    }

    func testDevSettingsKeepAdvancedSection() {
        XCTAssertEqual(
            SettingsPanelPolicy.sections(for: .dev),
            [.overview, .displays, .input, .permissions, .general, .advanced]
        )
    }

    func testProductSettingsHideLastInputStatusWhileDevKeepsIt() {
        XCTAssertFalse(SettingsPanelPolicy.showsLastInputStatus(for: .product))
        XCTAssertTrue(SettingsPanelPolicy.showsLastInputStatus(for: .dev))
    }
}
