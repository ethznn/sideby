import XCTest
@testable import SidebyCore

final class CoreModelsTests: XCTestCase {
    func testAppModeStableIdentifiers() {
        XCTAssertEqual(AppMode.together.id, "together")
        XCTAssertEqual(AppMode.shortcut.id, "shortcut")
        XCTAssertEqual(AppMode.swipe.id, "swipe")
        XCTAssertEqual(AppMode.separateDisplays.id, "separate-displays")
        XCTAssertEqual(AppMode.focus.id, "focus")
    }

    func testSwitchCommandDirections() {
        XCTAssertEqual(SwitchCommand.previous.direction, .left)
        XCTAssertEqual(SwitchCommand.next.direction, .right)
    }

    func testModifierFlagsCanBeCombined() {
        let modifiers: ModifierFlags = [.shift, .command]

        XCTAssertTrue(modifiers.contains(.shift))
        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertFalse(modifiers.contains(.control))
    }

    func testGestureSettingsDefaultsToOptionShiftHorizontalSwipe() {
        let settings = GestureSettings.default

        XCTAssertEqual(settings.requiredModifiers, [.option, .shift])
        XCTAssertEqual(settings.horizontalThreshold, 80)
        XCTAssertEqual(settings.dominanceRatio, 1.4)
        XCTAssertTrue(settings.ignoresMomentum)
        XCTAssertTrue(settings.naturalScrollingEnabled)
    }

    func testInputEventStoresNormalizedValues() {
        let event = InputEvent(
            type: .scrollWheel,
            deltaX: 120,
            deltaY: 12,
            modifierFlags: [.option],
            phase: .changed,
            timestamp: 42.5,
            isMomentum: false
        )

        XCTAssertEqual(event.type, .scrollWheel)
        XCTAssertEqual(event.deltaX, 120)
        XCTAssertEqual(event.deltaY, 12)
        XCTAssertEqual(event.modifierFlags, [.option])
        XCTAssertEqual(event.phase, .changed)
        XCTAssertEqual(event.timestamp, 42.5)
        XCTAssertFalse(event.isMomentum)
    }

    func testDisplayLayoutDetectsExternalDisplays() {
        let layout = DisplayLayout(
            displays: [
                DisplayInfo(id: "built-in", name: "Built-in Display", isPrimary: true, isBuiltin: true),
                DisplayInfo(id: "external-lg", name: "LG Display", isPrimary: false, isBuiltin: false)
            ]
        )

        XCTAssertEqual(layout.displayCount, 2)
        XCTAssertTrue(layout.hasExternalDisplay)
        XCTAssertEqual(layout.primaryDisplay?.id, "built-in")
        XCTAssertEqual(layout.stableKey, "built-in|external-lg")
    }
}
