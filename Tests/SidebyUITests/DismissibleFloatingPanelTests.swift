import AppKit
import XCTest
@testable import SidebyUI

@MainActor
final class DismissibleFloatingPanelTests: XCTestCase {
    func testPanelCanBecomeKeyForShortcutHandling() {
        let panel = DismissibleFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(panel.canBecomeKey)
    }

    func testCommandWInvokesDismissHandler() {
        var didDismiss = false
        let panel = DismissibleFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.onDismissShortcut = {
            didDismiss = true
        }

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )!

        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertTrue(didDismiss)
    }

    func testCancelOperationInvokesDismissHandler() {
        var didDismiss = false
        let panel = DismissibleFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.onDismissShortcut = {
            didDismiss = true
        }

        panel.cancelOperation(nil)

        XCTAssertTrue(didDismiss)
    }

    func testEscapeKeyInvokesDismissHandler() {
        var didDismiss = false
        let panel = DismissibleFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.onDismissShortcut = {
            didDismiss = true
        }

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )!

        panel.keyDown(with: event)

        XCTAssertTrue(didDismiss)
    }
}
