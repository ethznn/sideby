import XCTest
@testable import SidebyCore

final class GestureEngineTests: XCTestCase {
    func testNaturalScrollingReturnsPreviousForPositiveHorizontalDelta() {
        let engine = GestureEngine(settings: .default)
        let event = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: AppSettings.defaultGestureModifiers
        )

        XCTAssertEqual(engine.command(for: event), .previous)
    }

    func testNaturalScrollingReturnsNextForNegativeHorizontalDelta() {
        let engine = GestureEngine(settings: .default)
        let event = InputEventFactory.horizontalSwipe(
            deltaX: -120,
            modifiers: AppSettings.defaultGestureModifiers
        )

        XCTAssertEqual(engine.command(for: event), .next)
    }

    func testReturnsNilWhenRequiredModifierIsMissing() {
        let engine = GestureEngine(settings: .default)
        let event = InputEventFactory.horizontalSwipe(deltaX: 120)

        XCTAssertNil(engine.command(for: event))
    }

    func testReturnsNilWhenExtraGestureModifierIsHeld() {
        let engine = GestureEngine(settings: .default)
        let event = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: [.control, .option, .shift]
        )

        XCTAssertNil(engine.command(for: event))
    }

    func testReturnsNilWhenHorizontalThresholdIsNotMet() {
        let engine = GestureEngine(settings: .default)
        let event = InputEventFactory.horizontalSwipe(
            deltaX: 40,
            modifiers: AppSettings.defaultGestureModifiers
        )

        XCTAssertNil(engine.command(for: event))
    }

    func testReturnsNilWhenVerticalMovementDominates() {
        let engine = GestureEngine(settings: .default)
        let event = InputEvent(
            type: .scrollWheel,
            deltaX: 120,
            deltaY: 100,
            modifierFlags: AppSettings.defaultGestureModifiers,
            phase: .changed,
            timestamp: 0,
            isMomentum: false
        )

        XCTAssertNil(engine.command(for: event))
    }

    func testShiftModifiedVerticalScrollCanStandInForHorizontalSwipe() {
        let engine = GestureEngine(settings: .default)
        let event = InputEvent(
            type: .scrollWheel,
            deltaX: 4,
            deltaY: 120,
            modifierFlags: AppSettings.defaultGestureModifiers,
            phase: .changed,
            timestamp: 0,
            isMomentum: false
        )

        XCTAssertEqual(engine.command(for: event), .previous)
    }

    func testNaturalScrollingDisabledUsesRawScrollDirection() {
        let settings = GestureSettings(
            requiredModifiers: [.option],
            horizontalThreshold: 80,
            dominanceRatio: 1.4,
            ignoresMomentum: true,
            naturalScrollingEnabled: false
        )
        let engine = GestureEngine(settings: settings)
        let event = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: [.option]
        )

        XCTAssertEqual(engine.command(for: event), .next)
    }
}
