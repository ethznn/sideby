import XCTest
@testable import SidebyCore

final class ContextSafetyTests: XCTestCase {
    func testContextListStoresNamesByIndex() {
        var list = ContextList()

        list.setName("Work", for: 1)
        list.setName("Research", for: 2)
        list.setName("Deep Work", for: 1)

        XCTAssertEqual(list.name(for: 1), "Deep Work")
        XCTAssertEqual(list.name(for: 2), "Research")
    }

    func testFocusModeCanLockSpecificDirection() {
        let policy = FocusModePolicy(
            settings: FocusModeSettings(isEnabled: true, lockedCommands: [.previous])
        )

        XCTAssertFalse(policy.allows(.previous))
        XCTAssertTrue(policy.allows(.next))
        XCTAssertEqual(policy.diagnostic(for: .previous)?.title, "Meeting Locked")
    }

    func testDisabledFocusModeAllowsAllCommands() {
        let policy = FocusModePolicy(settings: .disabled)

        XCTAssertTrue(policy.allows(.previous))
        XCTAssertTrue(policy.allows(.next))
    }

    func testAdvancedModeWarnsWhenSeparateDisplaysIsEnabled() {
        let settings = AdvancedModeSettings(
            isSeparateDisplaysEnabled: true,
            exposesExperimentalControls: true
        )

        let diagnostic = AdvancedModePolicy().diagnostic(for: settings)

        XCTAssertEqual(diagnostic?.title, "Advanced mode is experimental")
        XCTAssertEqual(diagnostic?.severity, .warning)
    }
}
