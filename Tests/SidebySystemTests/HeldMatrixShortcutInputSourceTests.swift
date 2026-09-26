import XCTest
import SidebyCore
@testable import SidebySystem

@MainActor final class HeldMatrixShortcutInputSourceTests: XCTestCase {
    func testEachRequiredKeyReleaseClosesAndExtraModifierDoesNot() {
        for released in [49, 56, 58] as [UInt16] {
            let fixture = HeldInputFixture()
            fixture.press()
            fixture.modifiers.insert(.command)
            fixture.registrar.emit(.released)
            XCTAssertEqual(fixture.events, [.pressed])
            if released == 49 { fixture.keys.remove(49) }
            else { fixture.modifiers.remove(released == 56 ? .shift : .option) }
            fixture.source.checkHeldKeys()
            XCTAssertEqual(fixture.events, [.pressed, .released])
            fixture.source.checkHeldKeys()
            XCTAssertEqual(fixture.events.count, 2)
            fixture.source.stop()
        }
    }

    func testRepeatEscapeAndLostReleaseAreBoundedToOneHold() {
        let fixture = HeldInputFixture()
        fixture.press()
        fixture.registrar.emit(.pressed)
        fixture.keys.insert(53)
        fixture.source.checkHeldKeys()
        fixture.source.checkHeldKeys()
        fixture.registrar.emit(.pressed)
        XCTAssertEqual(fixture.events, [.pressed, .cancelled])
        fixture.keys = []
        fixture.source.checkHeldKeys() // No Carbon release: watchdog still closes.
        XCTAssertEqual(fixture.events, [.pressed, .cancelled, .released])
        fixture.press()
        XCTAssertEqual(fixture.events.last, .pressed)
        fixture.source.stop()
    }

    func testStopAndNoninteractiveSessionEndHold() {
        let fixture = HeldInputFixture()
        fixture.press()
        fixture.interactive = false
        fixture.source.checkHeldKeys()
        XCTAssertEqual(fixture.events, [.pressed, .released])
        fixture.source.stop()
        XCTAssertEqual(fixture.events.count, 2)
    }

    func testRecordingAnAlreadyHeldShortcutWaitsForFreshPress() {
        let fixture = HeldInputFixture(start: false)
        fixture.keys = [49]
        fixture.modifiers = [.option, .shift]
        XCTAssertTrue(fixture.source.start(shortcut: HeldMatrixConfiguration().shortcut))
        fixture.registrar.emit(.pressed)
        XCTAssertTrue(fixture.events.isEmpty)
        fixture.keys = []
        fixture.source.checkHeldKeys()
        fixture.events = []
        fixture.press()
        XCTAssertEqual(fixture.events, [.pressed])
        fixture.source.stop()
    }

    func testFailedRegistrationCleansUpAndDoesNotReportHeld() {
        let fixture = HeldInputFixture(start: false)
        fixture.registrar.canRegister = false
        XCTAssertFalse(fixture.source.start(shortcut: HeldMatrixConfiguration().shortcut))
        XCTAssertTrue(fixture.registrar.didStop)
        XCTAssertFalse(fixture.source.isHeld)
        XCTAssertTrue(fixture.events.isEmpty)
    }
}

@MainActor private final class HeldInputFixture {
    let registrar = HeldTestRegistrar()
    var keys: Set<UInt16> = []
    var modifiers: ModifierFlags = []
    var interactive = true
    var events: [HeldMatrixShortcutInputSource.Event] = []
    lazy var source = HeldMatrixShortcutInputSource(registrar: registrar,
        keyIsDown: { [unowned self] in keys.contains($0) }, modifiers: { [unowned self] in modifiers },
        sessionIsInteractive: { [unowned self] in interactive }, handler: { [unowned self] in events.append($0) })
    init(start: Bool = true) { if start { XCTAssertTrue(source.start(shortcut: HeldMatrixConfiguration().shortcut)) } }
    func press() { keys = [49]; modifiers = [.option, .shift]; registrar.emit(.pressed) }
}

@MainActor private final class HeldTestRegistrar: ContextKeyboardHotKeyRegistering {
    var handler: ((UInt32, ContextKeyboardHotKeyEvent) -> Void)?
    var canRegister = true
    var didStop = false
    func installHandler(_ handler: @escaping (UInt32, ContextKeyboardHotKeyEvent) -> Void) -> Bool { self.handler = handler; return true }
    func register(id: UInt32, shortcut: KeyboardShortcut) -> Bool { canRegister }
    func stop() { didStop = true; handler = nil }
    func emit(_ event: ContextKeyboardHotKeyEvent) { handler?(1, event) }
}
