import AppKit
import SidebyCore
import SidebyUI
import SwiftUI
import XCTest
@testable import SidebyApp

@MainActor final class HeldWorkspaceMatrixNativeTests: XCTestCase {
    func testDeleteAllConfirmationCancelAndUndoInQuickMatrix() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else {
            throw XCTSkip("Opt-in quick matrix deletion interaction")
        }
        let model = heldMatrixFixture(count: 4, displayCount: 1)
        model.settings.language = .korean
        let original = model.settings.contextPlan.contexts
        let size = NSSize(width: 784, height: 470)
        let window = HeldMatrixPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var keptOpen = false
        let view = HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model), select: { _ in },
            keepOpen: { keptOpen = true; window.acceptsKeyboard = true; window.makeKeyAndOrderFront(nil) })
        let host = HeldMatrixHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = host
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(200))
        func click(_ point: NSPoint) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                    modifierFlags: [.option, .shift], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
            }
        }
        func button(_ title: String) -> NSButton? {
            func find(_ view: NSView) -> NSButton? {
                if let button = view as? NSButton, button.title == title { return button }
                return view.subviews.lazy.compactMap(find).first
            }
            return NSApp.windows.lazy.compactMap { $0.contentView.flatMap(find) }.first
        }
        try click(NSPoint(x: size.width - 105, y: size.height - 171))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(keptOpen, "Opening confirmation pins the chooser before key release")
        try XCTUnwrap(button(model.saveCopy.cancel)).performClick(nil)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.settings.contextPlan.contexts, original)
        try click(NSPoint(x: size.width - 105, y: size.height - 171))
        try await Task.sleep(for: .milliseconds(150))
        try XCTUnwrap(button(model.saveCopy.deleteAllAction)).performClick(nil)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        XCTAssertTrue(window.isVisible)
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"] ?? "/tmp/sideby-delete-all-native")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("quick-matrix-deleted-all.png"))
        try click(NSPoint(x: size.width - 100, y: 26))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.settings.contextPlan.contexts, original)
    }

    func testNativeLayoutAndColumnClickInBothAppearances() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else {
            throw XCTSkip("Opt-in quick matrix native rendering and click evidence")
        }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"]
            ?? "/tmp/sideby-held-matrix.noindex/evidence")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for korean in [false, true] {
            for (dark, highContrast) in [(false, false), (true, false), (false, true), (true, true)] {
              for (count, displays) in [(1, 1), (4, 1), (12, 3), (12, 8)] {
                let model = heldMatrixFixture(count: count, displayCount: displays)
                model.settings.language = korean ? .korean : .english
                if count == 12 {
                    model.setContextName(contextID: "work-1", name: korean ? "배포 전 결제 흐름 검토" : "Review checkout before release")
                }
                XCTAssertEqual(model.verifiedCurrentWorkspaceID, "work-0")
                let snapshot = HeldWorkspaceSnapshot(model: model)
                let size = HeldMatrixPanelLayout.size(columns: count, displays: displays,
                    visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
                var selections: [String] = []
                let view = HeldWorkspaceMatrixView(model: model, snapshot: snapshot, select: { selections.append($0.id) })
                let host = HeldMatrixHostingView(rootView: view.frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, dark ? .dark : .light))
                let window = HeldMatrixPanel(contentRect: NSRect(origin: .zero, size: size),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.animationBehavior = .none
                defer { window.close() }
                window.appearance = NSAppearance(named: highContrast
                    ? (dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
                    : (dark ? .darkAqua : .aqua))
                window.contentView = host
                window.orderFrontRegardless()
                host.setFrameSize(size)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(180))
                host.layoutSubtreeIfNeeded()
                XCTAssertTrue(host.acceptsFirstMouse(for: nil))
                // A click in the first desktop row must activate the whole column,
                // including when Option and Shift are down; no cell editor is opened.
                let point = NSPoint(x: 18 + 132 + 80, y: size.height - 325)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                        modifierFlags: [.option, .shift], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                    window.sendEvent(event)
                }
                try await Task.sleep(for: .milliseconds(80))
                XCTAssertEqual(selections, ["work-0"])
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let name = "quick-matrix-\(korean ? "ko" : "en")-\(dark ? "dark" : "light")\(highContrast ? "-highcontrast" : "")-\(count)x\(displays).png"
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name))
                if count == 1, !korean, !dark {
                    var session = HeldMatrixSession()
                    session.press()
                    let frame = window.frame
                    let number = window.windowNumber
                    XCTAssertTrue(window.refreshOrderIfVisible(session: session, chordIsDown: true))
                    XCTAssertEqual(window.windowNumber, number)
                    XCTAssertEqual(window.frame, frame)
                    XCTAssertTrue(window.contentView === host)
                    XCTAssertFalse(window.isKeyWindow)
                    session.release()
                    XCTAssertFalse(window.refreshOrderIfVisible(session: session, chordIsDown: true))
                    session.press()
                    XCTAssertFalse(window.refreshOrderIfVisible(session: session, chordIsDown: false))
                    window.orderOut(nil)
                    XCTAssertFalse(window.refreshOrderIfVisible(session: session, chordIsDown: true))
                    XCTAssertFalse(window.isVisible)
                }
              }
            }
        }
    }
}
