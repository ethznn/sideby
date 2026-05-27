import XCTest
@testable import SidebyCore
@testable import SidebySystem

final class ShortcutInputSourceTests: XCTestCase {
    func testReturnsNextForMatchingNextShortcut() {
        let source = ShortcutInputSource(
            previousShortcut: .init(keyCode: 123, modifiers: [.shift, .command]),
            nextShortcut: .init(keyCode: 124, modifiers: [.shift, .command])
        )

        let command = source.command(for: KeyboardEvent(keyCode: 124, modifiers: [.shift, .command]))

        XCTAssertEqual(command, .next)
    }

    func testReturnsPreviousForMatchingPreviousShortcut() {
        let source = ShortcutInputSource(
            previousShortcut: .init(keyCode: 123, modifiers: [.shift, .command]),
            nextShortcut: .init(keyCode: 124, modifiers: [.shift, .command])
        )

        let command = source.command(for: KeyboardEvent(keyCode: 123, modifiers: [.shift, .command]))

        XCTAssertEqual(command, .previous)
    }

    func testReturnsNilForUnmatchedShortcut() {
        let source = ShortcutInputSource(
            previousShortcut: .init(keyCode: 123, modifiers: [.shift, .command]),
            nextShortcut: .init(keyCode: 124, modifiers: [.shift, .command])
        )

        let command = source.command(for: KeyboardEvent(keyCode: 36, modifiers: [.option]))

        XCTAssertNil(command)
    }

    func testRequiresExactModifierMatch() {
        let source = ShortcutInputSource(
            previousShortcut: .init(keyCode: 123, modifiers: [.shift, .command]),
            nextShortcut: .init(keyCode: 124, modifiers: [.shift, .command])
        )

        let command = source.command(for: KeyboardEvent(keyCode: 124, modifiers: [.control, .shift, .command]))

        XCTAssertNil(command)
    }
}
