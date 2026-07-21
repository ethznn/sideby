import XCTest
@testable import SidebyCore

final class ContextKeyboardShortcutTests: XCTestCase {
    func testCatalogMapsNumberRowAndArrowsToTwelveCommands() {
        XCTAssertEqual(ContextKeyboardShortcutCatalog.bindings.count, 12)
        XCTAssertEqual(
            Array(ContextKeyboardShortcutCatalog.bindings.prefix(10).map(\.command)),
            (1...10).map { .activate(position: $0) }
        )
        XCTAssertEqual(ContextKeyboardShortcutCatalog.bindings[10].command, .move(.previous))
        XCTAssertEqual(ContextKeyboardShortcutCatalog.bindings[11].command, .move(.next))
        XCTAssertEqual(
            ContextKeyboardShortcutCatalog.bindings.map(\.shortcut.keyCode),
            [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 123, 124]
        )
        XCTAssertTrue(
            ContextKeyboardShortcutCatalog.bindings.allSatisfy {
                $0.shortcut.modifiers == [.option, .shift]
            }
        )
    }

    func testZeroKeyBindingActivatesContextTen() {
        XCTAssertEqual(
            ContextKeyboardShortcutCatalog.bindings.first {
                $0.shortcut.keyCode == 29
            }?.command,
            .activate(position: 10)
        )
    }

    func testCatalogLooksUpBindingsForSupportedCommands() {
        XCTAssertEqual(
            ContextKeyboardShortcutCatalog.binding(for: .activate(position: 1)),
            ContextKeyboardShortcutBinding(
                shortcut: KeyboardShortcut(keyCode: 18, modifiers: [.option, .shift]),
                command: .activate(position: 1)
            )
        )
        XCTAssertEqual(
            ContextKeyboardShortcutCatalog.binding(for: .activate(position: 10)),
            ContextKeyboardShortcutBinding(
                shortcut: KeyboardShortcut(keyCode: 29, modifiers: [.option, .shift]),
                command: .activate(position: 10)
            )
        )
        XCTAssertEqual(
            ContextKeyboardShortcutCatalog.binding(for: .move(.previous)),
            ContextKeyboardShortcutBinding(
                shortcut: KeyboardShortcut(keyCode: 123, modifiers: [.option, .shift]),
                command: .move(.previous)
            )
        )
        XCTAssertEqual(
            ContextKeyboardShortcutCatalog.binding(for: .move(.next)),
            ContextKeyboardShortcutBinding(
                shortcut: KeyboardShortcut(keyCode: 124, modifiers: [.option, .shift]),
                command: .move(.next)
            )
        )
        XCTAssertNil(ContextKeyboardShortcutCatalog.binding(for: .activate(position: 11)))
    }

    func testPolicyActivatesContextAtLatestDisplayPosition() {
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(id: "review", order: 2, name: "Review"),
                ContextDefinition(id: "code", order: 1, name: "Code"),
                ContextDefinition(id: "chat", order: 3, name: "Chat")
            ],
            currentContextID: "code"
        )

        XCTAssertEqual(
            ContextKeyboardShortcutPolicy.action(
                command: .activate(position: 2),
                contextPlan: plan,
                isSidebyEnabled: true,
                isSwitching: false,
                isCapturing: false
            ),
            .activate(contextID: "review")
        )
    }

    func testPolicyReturnsPreviousAndNextMoveActions() {
        for command in [SwitchCommand.previous, .next] {
            XCTAssertEqual(
                ContextKeyboardShortcutPolicy.action(
                    command: .move(command),
                    contextPlan: .default,
                    isSidebyEnabled: true,
                    isSwitching: false,
                    isCapturing: false
                ),
                .move(command)
            )
        }
    }

    func testBusyTakesPriorityOverOffAndMissing() {
        XCTAssertEqual(
            ContextKeyboardShortcutPolicy.action(
                command: .activate(position: 10),
                contextPlan: .default,
                isSidebyEnabled: false,
                isSwitching: true,
                isCapturing: false
            ),
            .ignore
        )
        XCTAssertEqual(
            ContextKeyboardShortcutPolicy.action(
                command: .move(.next),
                contextPlan: .default,
                isSidebyEnabled: false,
                isSwitching: false,
                isCapturing: true
            ),
            .ignore
        )
    }

    func testOffTakesPriorityOverMissingAndMove() {
        XCTAssertEqual(
            ContextKeyboardShortcutPolicy.action(
                command: .activate(position: 10),
                contextPlan: .default,
                isSidebyEnabled: false,
                isSwitching: false,
                isCapturing: false
            ),
            .showSidebyOff
        )
        XCTAssertEqual(
            ContextKeyboardShortcutPolicy.action(
                command: .move(.previous),
                contextPlan: .default,
                isSidebyEnabled: false,
                isSwitching: false,
                isCapturing: false
            ),
            .showSidebyOff
        )
    }

    func testEnabledMissingAndInvalidPositionsAreHandledSafely() {
        XCTAssertEqual(
            ContextKeyboardShortcutPolicy.action(
                command: .activate(position: 7),
                contextPlan: .default,
                isSidebyEnabled: true,
                isSwitching: false,
                isCapturing: false
            ),
            .showMissingContext(position: 7)
        )
        XCTAssertEqual(
            ContextKeyboardShortcutPolicy.action(
                command: .activate(position: 11),
                contextPlan: .default,
                isSidebyEnabled: true,
                isSwitching: false,
                isCapturing: false
            ),
            .ignore
        )
    }
}
