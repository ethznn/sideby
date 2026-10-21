import AppKit
import SidebyCore
import SwiftUI
import XCTest
@testable import SidebyApp

@MainActor final class SwitcherClickTargetTests: XCTestCase {
    func testViewChoiceHitRegionsCoverTheSegmentInBothLanguagesOffscreen() async throws {
        try requireOffscreen()
        for language in [AppLanguage.korean, .english] {
            for mode in [HeldSwitcherViewMode.wheel, .table] {
                let window = hiddenWindow(HeldSwitcherViewControl(mode: mode, language: language, select: { _ in }),
                                          size: NSSize(width: 472, height: 40))
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(150))
                for id in ["wheel-show-table", "held-show-wheel"] {
                    let target = try XCTUnwrap(element(id, in: window) as? any NSAccessibilityElementProtocol)
                    let frame = target.accessibilityFrame()
                    // Without a content shape, plain buttons expose only their
                    // glyph bounds (Korean Table was 31.5 x 14 points).
                    XCTAssertGreaterThanOrEqual(frame.width, 72, "\(language) \(mode) \(id): full segment, not only its text")
                    XCTAssertGreaterThanOrEqual(frame.height, 24)
                    XCTAssertTrue(window.frame.contains(frame))
                }
                XCTAssertFalse(window.isVisible); XCTAssertFalse(window.isKeyWindow)
            }
        }
    }

    func testRapidAlternatingViewActionsKeepEveryRequestOffscreen() async throws {
        try requireOffscreen()
        for startsWithCircle in [true, false] {
            let model = heldMatrixFixture(count: 8, displayCount: 3)
            let before = model.settings
            var changes: [HeldSwitcherPresentation] = []
            let window = hiddenWindow(HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model),
                select: { _ in XCTFail("Changing views must not switch Spaces") }, usesRadial: startsWithCircle,
                wheelDiameter: 440, presentationChanged: { changes.append($0) }), size: NSSize(width: 1040, height: 680))
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(200))
            let circle = try XCTUnwrap(element("held-show-wheel", in: window))
            let table = try XCTUnwrap(element("wheel-show-table", in: window))
            var expected: [HeldSwitcherPresentation] = []
            for _ in 0..<10 {
                for (button, mode) in startsWithCircle ? [(table, HeldSwitcherPresentation.table), (circle, .wheel)]
                                                       : [(circle, HeldSwitcherPresentation.wheel), (table, .table)] {
                    try press(button)
                    expected.append(mode)
                    XCTAssertEqual(changes, expected, "Do not ignore the next request until rendering settles")
                }
            }
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNotNil(element(startsWithCircle ? "held-workspace-wheel" : "held-switch-table", in: window))
            XCTAssertEqual(model.settings, before); XCTAssertFalse(model.isSwitching)
            XCTAssertFalse(window.isVisible); XCTAssertFalse(window.isKeyWindow)
        }
    }

    private func requireOffscreen() throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_OFFSCREEN_EVIDENCE"] == "1" else {
            throw XCTSkip("Opt-in hidden-window tests; no system events")
        }
        NSApplication.shared.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
                                     with: NSNumber(value: true), with: "AXEnhancedUserInterface")
    }
    private func hiddenWindow<Content: View>(_ content: Content, size: NSSize) -> NSWindow {
        let window = ClickProbePanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = HeldMatrixHostingView(rootView: content)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }
    private func press(_ object: NSObject) throws {
        if let button = object as? NSButton { button.performClick(nil); return }
        let selector = NSSelectorFromString("accessibilityPerformPress")
        XCTAssertTrue(object.responds(to: selector))
        let action = unsafeBitCast(try XCTUnwrap(object.method(for: selector)), to: (@convention(c) (AnyObject, Selector) -> Bool).self)
        XCTAssertTrue(action(object, selector))
    }

    private func element(_ id: String, in window: NSWindow) -> NSObject? {
        func find(_ object: NSObject) -> NSObject? {
            if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
               object.perform(NSSelectorFromString("accessibilityIdentifier"))?.takeUnretainedValue() as? String == id { return object }
            if object.responds(to: NSSelectorFromString("accessibilityChildren")),
               let children = object.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue() as? [NSObject] {
                return children.lazy.compactMap(find).first
            }
            return nil
        }
        return window.contentView.flatMap(find)
    }
}

/// Prevent any accidental presentation or activation while inspecting the
/// hidden hosting view and invoking its own accessibility actions.
@MainActor private final class ClickProbePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {}
    override func makeKeyAndOrderFront(_ sender: Any?) {}
}
