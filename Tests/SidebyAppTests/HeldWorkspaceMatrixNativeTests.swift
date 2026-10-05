import AppKit
import SidebyCore
import SidebyUI
import SwiftUI
import XCTest
@testable import SidebyApp

@MainActor final class HeldWorkspaceMatrixNativeTests: XCTestCase {
    private func requireNative() throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else { throw XCTSkip("Opt-in quick switch interactions") }
        NSApplication.shared.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
            with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        let policy = NSApplication.shared.activationPolicy()
        NSApplication.shared.setActivationPolicy(.accessory)
        let previous = NSWorkspace.shared.frontmostApplication
        let pointer = CGEvent(source: nil)?.location
        addTeardownBlock { await MainActor.run {
            NSApplication.shared.setActivationPolicy(policy)
            _ = previous?.activate(options: [])
            if let pointer { CGWarpMouseCursorPosition(pointer) }
        } }
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

    private func frame(_ object: NSObject) throws -> NSRect {
        try XCTUnwrap(object as? any NSAccessibilityElementProtocol).accessibilityFrame()
    }

    private func click(_ object: NSObject, window: NSWindow, belowTop: CGFloat? = nil) throws {
        let rect = try frame(object)
        let point = window.convertPoint(fromScreen: NSPoint(x: rect.midX, y: belowTop.map { rect.maxY - $0 } ?? rect.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: [.option, .shift], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
    }

    func testEditingRequiresExplicitChoiceAndReturnsToSwitchingInTheSamePanel() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 4, displayCount: 1)
        let before = model.settings
        let size = NSSize(width: 850, height: 640)
        let window = HeldMatrixPanel(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var pinned = false
        var selections: [String] = []
        window.contentView = HeldMatrixHostingView(rootView: HeldWorkspaceMatrixView(model: model,
            snapshot: .init(model: model), select: { selections.append($0.id) }, keepOpen: {
                pinned = true; window.acceptsKeyboard = true
                NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
            }).frame(width: size.width, height: size.height))
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNil(element("connection-cell-work-0-mac", in: window))
        XCTAssertNil(element("connections-add", in: window))
        XCTAssertNil(element("connections-undo", in: window))
        try click(XCTUnwrap(element("held-workspace-work-1", in: window)), window: window, belowTop: 92)
        XCTAssertEqual(selections, ["work-1"])
        XCTAssertFalse(pinned)
        XCTAssertEqual(model.settings, before)
        try click(XCTUnwrap(element("held-edit-connections", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(pinned)
        XCTAssertNil(element("held-switch-table", in: window))
        try click(XCTUnwrap(element("connection-cell-work-0-mac", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(200))
        let popup = try XCTUnwrap(NSApp.windows.first { $0.isVisible && element("connection-choice-mac-1", in: $0) != nil })
        try click(XCTUnwrap(element("connection-choice-mac-1", in: popup)), window: popup)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.settings.contextPlan.contexts[0].spaceIndex(for: "mac"), 1)
        XCTAssertEqual(selections, ["work-1"], "Editing must not switch screens")
        XCTAssertFalse(model.isSwitching)
        try click(XCTUnwrap(element("held-finish-editing", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNotNil(element("held-switch-table", in: window))
        XCTAssertNil(element("connection-cell-work-0-mac", in: window))
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
    }

    func testOpeningManyConnectionsRevealsCurrentColumnAndTracksCurrentChange() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 16, displayCount: 1)
        let base = try XCTUnwrap(model.workspaceObservationOverride?())
        func observe(_ index: Int) {
            model.workspaceObservationOverride = {
                .init(displays: base.displays.map { .init(displayID: $0.displayID, spaceCount: $0.spaceCount, currentSpaceIndex: index) },
                    spaceIDsByDisplayID: base.spaceIDsByDisplayID, spaceKeysByDisplayID: base.spaceKeysByDisplayID)
            }
            model.refreshWorkspaceStatus()
        }
        observe(13)
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, "work-13")
        let size = HeldMatrixPanelLayout.size(columns: 16, displays: 1, visibleFrame: NSRect(x: 0, y: 0, width: 1100, height: 700))
        let window = HeldMatrixPanel(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = HeldMatrixHostingView(rootView: HeldWorkspaceMatrixView(model: model, snapshot: .init(model: model), select: { _ in })
            .frame(width: size.width, height: size.height))
        window.center(); window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(350))
        let table = try frame(XCTUnwrap(element("held-switch-table", in: window)))
        let current = try frame(XCTUnwrap(element("held-workspace-work-13", in: window)))
        XCTAssertGreaterThan(table.intersection(current).width, HeldMatrixPanelLayout.columnWidth - 2)
        XCTAssertEqual(table.intersection(try frame(XCTUnwrap(element("held-workspace-work-0", in: window)))).width, 0)
        observe(2)
        try await Task.sleep(for: .milliseconds(200))
        let updated = try frame(XCTUnwrap(element("held-workspace-work-2", in: window)))
        XCTAssertGreaterThan(table.intersection(updated).width, HeldMatrixPanelLayout.columnWidth - 2)
        XCTAssertFalse(model.isSwitching)
    }

    func testRealPanelResizesForEditingAndKeepsTheSameWindow() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 2, displayCount: 1)
        let before = model.settings
        let controller = HeldWorkspaceMatrixController(model: model)
        // No shortcut registration or screen-switch request. All data are fixtures.
        controller.showPersistent()
        defer { controller.dismiss() }
        try await Task.sleep(for: .milliseconds(250))
        let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
        let number = window.windowNumber
        let compact = window.frame.size
        try click(XCTUnwrap(element("held-edit-connections", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(window.windowNumber, number)
        XCTAssertGreaterThan(window.frame.height, compact.height)
        let sources = try frame(XCTUnwrap(element("connection-desktop-sources", in: window)))
        let table = try frame(XCTUnwrap(element("current-connections-table", in: window)))
        XCTAssertTrue(window.frame.contains(sources))
        XCTAssertTrue(window.frame.contains(table))
        XCTAssertNotNil(element("connection-cell-work-0-mac", in: window))
        try click(XCTUnwrap(element("held-finish-editing", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(window.windowNumber, number)
        XCTAssertEqual(window.frame.size, compact)
        XCTAssertEqual(model.settings, before)
        // Verify the panel's AppKit cancellation responder independently of
        // WindowServer focus. Background XCTest cannot reliably acquire key
        // focus on the user's secondary display; synthetic key events would
        // conflate that harness limitation with product cancellation behavior.
        try click(XCTUnwrap(element("held-edit-connections", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(150))
        window.cancelOperation(nil)
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(model.settings, before)

    }

    func testNativeLayoutAndColumnClickInBothAppearances() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else {
            throw XCTSkip("Opt-in quick matrix native rendering and click evidence")
        }
        NSApplication.shared.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"),
            with: NSNumber(value: true), with: "AXEnhancedUserInterface")
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
                // Any part of a column, including a desktop row, switches without editing.
                let button = try XCTUnwrap(element("held-workspace-work-0", in: window))
                try click(button, window: window, belowTop: HeldMatrixPanelLayout.headerHeight + HeldMatrixPanelLayout.rowHeight / 2)
                try await Task.sleep(for: .milliseconds(80))
                XCTAssertEqual(selections, ["work-0"])
                XCTAssertNil(element("current-connections-table", in: window))
                XCTAssertNil(element("connections-displays", in: window))
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
