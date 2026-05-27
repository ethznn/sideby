import XCTest
@testable import SidebyCore

final class ModePolicyTests: XCTestCase {
    func testShortcutModeAllowsShortcutWhenSpacesAreAvailable() {
        let decision = ModePolicy().decision(
            for: .shortcut,
            inputMethod: .shortcut,
            runtimeState: .policyDualDisplay
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertNil(decision.blockReason)
        XCTAssertFalse(decision.isExperimental)
    }

    func testSwipeModeRequiresAccessibilityPermission() {
        var state = RuntimeState.policyDualDisplay
        state.accessibilityPermission = .denied

        let decision = ModePolicy().decision(
            for: .swipe,
            inputMethod: .swipe,
            runtimeState: state
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.blockReason, .accessibilityPermissionMissing)
    }

    func testAnyModeBlocksWhenOnlyOneSpaceExists() {
        var state = RuntimeState.policyDualDisplay
        state.availableSpaceCount = 1

        let decision = ModePolicy().decision(
            for: .shortcut,
            inputMethod: .shortcut,
            runtimeState: state
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.blockReason, .noAvailableSpace)
    }

    func testSingleDisplayAddsWarningWithoutBlockingShortcut() {
        let decision = ModePolicy().decision(
            for: .together,
            inputMethod: .shortcut,
            runtimeState: .singleDisplay
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertTrue(decision.warnings.contains(.singleDisplayMode))
    }

    func testSeparateDisplaysModeIsExperimental() {
        let decision = ModePolicy().decision(
            for: .separateDisplays,
            inputMethod: .shortcut,
            runtimeState: .policyDualDisplay
        )

        XCTAssertTrue(decision.isAllowed)
        XCTAssertTrue(decision.isExperimental)
        XCTAssertTrue(decision.warnings.contains(.experimentalMode))
    }
}

private extension RuntimeState {
    static let policyDualDisplay = RuntimeState(
        accessibilityPermission: .granted,
        displayLayout: DisplayLayout(
            displays: [
                DisplayInfo(id: "built-in", name: "Built-in Display", isPrimary: true, isBuiltin: true),
                DisplayInfo(id: "external-lg", name: "LG Display", isPrimary: false, isBuiltin: false)
            ]
        ),
        availableSpaceCount: 3
    )

    static let singleDisplay = RuntimeState(
        accessibilityPermission: .granted,
        displayLayout: DisplayLayout(
            displays: [
                DisplayInfo(id: "built-in", name: "Built-in Display", isPrimary: true, isBuiltin: true)
            ]
        ),
        availableSpaceCount: 3
    )
}
