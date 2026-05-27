import XCTest
@testable import SidebyCore

final class DebounceGateTests: XCTestCase {
    func testAcceptsFirstEvent() {
        var gate = DebounceGate(lockoutInterval: 0.6)
        let event = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: AppSettings.defaultGestureModifiers,
            timestamp: 1
        )

        XCTAssertTrue(gate.accepts(event, settings: .default))
    }

    func testRejectsEventInsideLockoutInterval() {
        var gate = DebounceGate(lockoutInterval: 0.6)
        let first = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: AppSettings.defaultGestureModifiers,
            timestamp: 1
        )
        let second = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: AppSettings.defaultGestureModifiers,
            timestamp: 1.4
        )

        XCTAssertTrue(gate.accepts(first, settings: .default))
        XCTAssertFalse(gate.accepts(second, settings: .default))
    }

    func testAcceptsEventAfterLockoutInterval() {
        var gate = DebounceGate(lockoutInterval: 0.6)
        let first = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: AppSettings.defaultGestureModifiers,
            timestamp: 1
        )
        let second = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: AppSettings.defaultGestureModifiers,
            timestamp: 1.7
        )

        XCTAssertTrue(gate.accepts(first, settings: .default))
        XCTAssertTrue(gate.accepts(second, settings: .default))
    }

    func testRejectsMomentumWhenSettingsIgnoreMomentum() {
        var gate = DebounceGate(lockoutInterval: 0.6)
        let event = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: AppSettings.defaultGestureModifiers,
            timestamp: 1,
            isMomentum: true
        )

        XCTAssertFalse(gate.accepts(event, settings: .default))
    }

    func testGestureEngineCanUseDebounceGate() {
        let engine = GestureEngine(settings: .default)
        var gate = DebounceGate(lockoutInterval: 0.6)
        let first = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: AppSettings.defaultGestureModifiers,
            timestamp: 1
        )
        let second = InputEventFactory.horizontalSwipe(
            deltaX: 120,
            modifiers: AppSettings.defaultGestureModifiers,
            timestamp: 1.2
        )

        XCTAssertEqual(engine.command(for: first, debounceGate: &gate), .previous)
        XCTAssertNil(engine.command(for: second, debounceGate: &gate))
    }
}
