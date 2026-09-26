import XCTest
@testable import SidebyCore

final class HeldMatrixSessionTests: XCTestCase {
    func testReleaseClosesWithoutCommittingAndRepeatDoesNotReopen() {
        var session = HeldMatrixSession()
        XCTAssertNotNil(session.press())
        XCTAssertNil(session.press())
        session.release()
        XCTAssertFalse(session.isVisible)
        XCTAssertFalse(session.isTransitioning)
    }

    func testAcceptedClickOutlivesReleaseButLateCompletionCannotReopen() throws {
        var session = HeldMatrixSession()
        let generation = try XCTUnwrap(session.press())
        XCTAssertTrue(session.beginTransition(session: generation))
        XCTAssertFalse(session.beginTransition(session: generation))
        session.release()
        XCTAssertTrue(session.isTransitioning)
        session.finishTransition()
        XCTAssertFalse(session.isVisible)
        XCTAssertFalse(session.isHeld)
    }

    func testReleaseBeforeMouseUpAndStaleSessionCannotActivate() throws {
        var session = HeldMatrixSession()
        let old = try XCTUnwrap(session.press())
        session.release()
        XCTAssertFalse(session.beginTransition(session: old))
        let new = try XCTUnwrap(session.press())
        XCTAssertFalse(session.beginTransition(session: old))
        XCTAssertTrue(session.beginTransition(session: new))
    }

    func testEscapeSuppressesRepeatUntilFreshPressAndCompletionAllowsNextClick() throws {
        var session = HeldMatrixSession()
        let id = try XCTUnwrap(session.press())
        XCTAssertTrue(session.beginTransition(session: id))
        session.finishTransition()
        XCTAssertTrue(session.isVisible)
        XCTAssertTrue(session.beginTransition(session: id))
        session.finishTransition()
        session.dismiss()
        XCTAssertNil(session.press())
        XCTAssertFalse(session.beginTransition(session: id))
        session.release()
        XCTAssertNotNil(session.press())
        XCTAssertTrue(session.isVisible)
    }

    func testShortcutValidationProtectsExistingBindingsAndSupportedModifiers() {
        XCTAssertTrue(HeldMatrixConfiguration.isValid(HeldMatrixConfiguration().shortcut))
        for binding in ContextKeyboardShortcutCatalog.bindings { XCTAssertFalse(HeldMatrixConfiguration.isValid(binding.shortcut)) }
        for shortcut in [KeyboardShortcut(keyCode: 49, modifiers: .command),
                         .init(keyCode: 49, modifiers: []), .init(keyCode: 53, modifiers: .option),
                         .init(keyCode: 58, modifiers: .option), .init(keyCode: 49, modifiers: [.option, .function])] {
            XCTAssertFalse(HeldMatrixConfiguration.isValid(shortcut))
        }
        XCTAssertTrue(HeldMatrixConfiguration.isValid(.init(keyCode: 40, modifiers: [.control, .option])))
    }
}
