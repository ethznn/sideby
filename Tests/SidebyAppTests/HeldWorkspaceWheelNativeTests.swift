import AppKit
import SidebyCore
import SwiftUI
import XCTest
@testable import SidebyApp

@MainActor final class HeldWorkspaceWheelNativeTests: XCTestCase {
    private func requireNative() throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else { throw XCTSkip("Opt-in isolated wheel UI") }
        NSApplication.shared.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        let policy = NSApp.activationPolicy(), previous = NSWorkspace.shared.frontmostApplication
        let pointer = CGEvent(source: nil)?.location
        NSApp.setActivationPolicy(.accessory)
        addTeardownBlock { await MainActor.run {
            NSApp.setActivationPolicy(policy); _ = previous?.activate(options: [])
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

    private func click(_ point: NSPoint, in window: NSWindow) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
    }

    private func click(_ id: String, in window: NSWindow) throws {
        let object = try XCTUnwrap(element(id, in: window), id)
        let rect = try XCTUnwrap(object as? any NSAccessibilityElementProtocol).accessibilityFrame()
        try click(window.convertPoint(fromScreen: NSPoint(x: rect.midX, y: rect.midY)), in: window)
    }

    private func key(_ code: UInt16, text: String, in window: NSWindow) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)))
        }
    }

    private func hover(_ point: NSPoint, in window: NSWindow) async throws {
        try XCTSkipUnless(CGPreflightPostEventAccess(), "Native hover requires existing input permission")
        let screenPoint = window.convertPoint(toScreen: point)
        let cgPoint = CGPoint(x: screenPoint.x, y: NSScreen.screens[0].frame.maxY - screenPoint.y)
        let feed = Task.detached {
            try await Task.sleep(for: .milliseconds(80))
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: cgPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(180))
            DispatchQueue.main.async {
                NSApp.stop(nil)
                if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(event, atStart: true) }
            }
        }
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { MainActor.assumeIsolated { NSApp.run() } }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        try await feed.value
    }

    private func capture(_ name: String, window: NSWindow) throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"] ?? "/tmp/sideby-wheel-native.noindex")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let host = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if name == "wheel-count-8" {
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
                bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? 1
            }
            XCTAssertEqual(alpha(0, 0), 0, accuracy: 0.01, "Outside HUD is transparent")
            XCTAssertEqual(alpha(325, 228), 0, accuracy: 0.01, "Center-to-sector gap is transparent")
            XCTAssertEqual(alpha(290, 99), 0, accuracy: 0.01, "Sector gap is transparent")
            XCTAssertGreaterThan(alpha(236, 228), 0.99, "Center control remains legible")
        }
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name + ".png"))
    }

    private func window<Content: View>(_ view: Content, size: NSSize = NSSize(width: 472, height: 568)) -> HeldMatrixPanel {
        let screen = NSScreen.main!.visibleFrame
        let window = HeldMatrixPanel(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
            width: size.width, height: size.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.acceptsKeyboard = true; window.level = .popUpMenu
        window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
        window.contentView = HeldMatrixHostingView(rootView: view)
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        return window
    }

    func testHoverRenameImmediateDeleteUndoAndCenterCaptureNeverSwitch() async throws {
        try requireNative()
        for language in [AppLanguage.korean, .english] {
            let model = heldMatrixFixture(count: 4, displayCount: 2)
            model.settings.language = language; model.workspacePreferences = nil
            let before = model.settings, observed = model.workspaceLastObservedSpaceKeys
            var switches = 0, pins = 0
            let window = window(HeldWorkspaceWheelView(model: model, select: { _ in switches += 1 }, keepOpen: { pins += 1 }))
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(600))
            let point = HeldWorkspaceWheelLayout.labelPoint(index: 1, count: 4)
            let hoverPoint = NSPoint(x: 16 + point.x, y: 568 - 8 - point.y)
            try await hover(hoverPoint, in: window)
            try capture("wheel-\(language)-hover", window: window)
            try click("wheel-rename-work-1", in: window)
            try await Task.sleep(for: .milliseconds(120))
            XCTAssertNotNil(element("connection-name-field", in: window)); XCTAssertGreaterThan(pins, 0)
            XCTAssertEqual(switches, 0)
            try click("connection-name-cancel", in: window)
            try await Task.sleep(for: .milliseconds(100))
            try await hover(hoverPoint, in: window)
            try click("wheel-delete-work-1", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNil(element("wheel-delete-confirmation", in: window))
            XCTAssertNil(window.attachedSheet)
            try capture("wheel-\(language)-deleted-undo", window: window)
            XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), ["work-0", "work-2", "work-3"])
            XCTAssertEqual(model.workspaceLastObservedSpaceKeys, observed); XCTAssertEqual(switches, 0)
            try click("held-undo-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
            let bounds = window.frame
            try click("held-add-current-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts.last?.displayIDs.sorted(), ["external-1", "mac"])
            XCTAssertEqual(model.workspaceLastObservedSpaceKeys, observed)
            XCTAssertEqual(window.frame, bounds); XCTAssertEqual(switches, 0)
            XCTAssertNotNil(element("held-add-feedback", in: window))
        }
    }

    func testSectorBodySwitchesAndDoesNotRenameOrDelete() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 4)
        var selected: [String] = []
        let before = model.settings
        let window = window(HeldWorkspaceWheelView(model: model, select: { selected.append($0.id) }))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let point = HeldWorkspaceWheelLayout.labelPoint(index: 1, count: 4)
        try click(NSPoint(x: 16 + point.x, y: 568 - 8 - point.y + 10), in: window)
        XCTAssertEqual(selected, ["work-1"])
        XCTAssertEqual(model.settings, before)
        XCTAssertNil(element("connection-name-field", in: window))
        try click(NSPoint(x: 325, y: 568 - 228), in: window)
        XCTAssertEqual(selected, ["work-1"], "Transparent gaps do not select or capture")
        XCTAssertEqual(model.settings, before)
    }

    func testCurrentPartialConnectionExplainsCoverageAndClickClosesWithoutSwitching() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 3, displayCount: 2)
        model.workspacePreferences = nil
        var contexts = model.settings.contextPlan.contexts
        contexts[0] = .init(id: "work-0", order: 1, name: "연결 1", displaySpaceIndexes: ["mac": 0])
        model.settings.contextPlan.replaceContexts(contexts, currentContextID: "work-0")
        model.settings.savedWorkspaces.bookmarks["work-0"] = ["mac": model.workspaceLastObservedSpaceKeys["mac"]![0]]
        model.refreshWorkspaceStatus()
        let before = model.settings
        var closes = 0, edits = 0
        let window = window(HeldWorkspaceWheelView(model: model,
            select: { _ in XCTFail("The current partial connection never switches") },
            close: { closes += 1 }, edit: { edits += 1 }))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let button = try XCTUnwrap(element("wheel-go-work-0", in: window))
        let label = button.perform(NSSelectorFromString("accessibilityLabel"))?.takeUnretainedValue() as? String ?? ""
        XCTAssertTrue(label.contains("이미 현재 Space"))
        XCTAssertTrue(label.contains("MacBook Pro만 연결"))
        XCTAssertTrue(label.contains("다른 모니터는 유지"))
        let point = HeldWorkspaceWheelLayout.labelPoint(index: 0, count: 3)
        try await hover(NSPoint(x: 16 + point.x, y: 568 - 8 - point.y), in: window)
        let summary = try XCTUnwrap(element("wheel-connection-summary", in: window) as? any NSAccessibilityElementProtocol)
        XCTAssertGreaterThan(summary.accessibilityFrame().height, 24, "Both status and display coverage must be visible")
        try capture("wheel-current-partial", window: window)
        try click(NSPoint(x: 16 + point.x, y: 568 - 8 - point.y + 10), in: window)
        XCTAssertEqual(closes, 1); XCTAssertEqual(edits, 0)
        XCTAssertEqual(model.settings, before)

        // A genuinely empty connection must offer setup, not an inert sector.
        contexts[0] = .init(id: "work-0", order: 1, name: "Empty", displaySpaceIndexes: [:])
        model.settings.contextPlan.replaceContexts(contexts, currentContextID: "work-1")
        model.settings.savedWorkspaces.bookmarks["work-0"] = [:]
        model.refreshWorkspaceStatus()
        try await Task.sleep(for: .milliseconds(100))
        try click(NSPoint(x: 16 + point.x, y: 568 - 8 - point.y + 10), in: window)
        XCTAssertEqual(edits, 1)
        XCTAssertEqual(closes, 1)
    }

    func testKeyboardCancelsClearAllAndRenameAppliesWithUndo() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 2, displayCount: 2)
        model.workspacePreferences = nil
        let before = model.settings
        var closes = 0
        let window = window(HeldWorkspaceWheelView(model: model, select: { _ in XCTFail("Editing must not switch") }, close: { closes += 1 }))
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let point = HeldWorkspaceWheelLayout.labelPoint(index: 0, count: 2)
        let hoverPoint = NSPoint(x: point.x + 16, y: 568 - 8 - point.y)
        for (code, character) in [(UInt16(36), "\r"), (UInt16(53), "\u{1b}")] {
            try click("wheel-clear-all", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNotNil(element("wheel-clear-all-confirmation", in: window))
            try key(code, text: character, in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNil(element("wheel-clear-all-confirmation", in: window), "Cancel key \(code), handler installed: \(window.cancelContent != nil)")
            XCTAssertEqual(model.settings, before); XCTAssertEqual(closes, 0)
        }
        try await hover(hoverPoint, in: window)
        try click("wheel-rename-work-0", in: window)
        try await Task.sleep(for: .milliseconds(100))
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.selectAll(nil); editor.insertText("집중 작업", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(80))
        try click("connection-name-apply", in: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.settings.contextPlan.contexts.first?.name, "집중 작업")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        try click("held-undo-connection", in: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
    }

    func testEmptyOneTwoThreeEightAndPagingRenderAndKeepEveryConnection() async throws {
        try requireNative()
        for count in [0, 1, 2, 3, 8, 9] {
            let model = heldMatrixFixture(count: max(1, count), displayCount: 2)
            if count == 0 { model.settings.contextPlan = .init(contexts: [], currentContextID: ""); model.settings.savedWorkspaces.bookmarks = [:] }
            model.workspacePreferences = nil
            let window = window(HeldWorkspaceWheelView(model: model, select: { _ in XCTFail("Rendering never switches") }))
            window.appearance = NSAppearance(named: count % 2 == 0 ? .darkAqua : .aqua)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(500))
            try capture("wheel-count-\(count)", window: window)
            XCTAssertNotNil(element("held-add-current-connection", in: window))
            XCTAssertNotNil(element("held-undo-connection", in: window))
            XCTAssertNotNil(element("wheel-clear-all", in: window))
            if count == 0 {
                XCTAssertNotNil(element("wheel-empty-guidance", in: window))
                XCTAssertNotNil(element("wheel-empty-space-mac", in: window))
                XCTAssertNil(element("wheel-go-work-0", in: window), "Empty guidance must not create a saved connection")
            }
            if count == 9 {
                try click("wheel-next-page", in: window)
                try await Task.sleep(for: .milliseconds(100))
                XCTAssertNotNil(element("wheel-go-work-8", in: window))
                try capture("wheel-page-2", window: window)
            }
        }
    }

    func testClearAllEmptyStateFirstCaptureAndUndoRemainAvailableAfterReopening() async throws {
        try requireNative()
        for language in [AppLanguage.korean, .english] {
            let model = heldMatrixFixture(count: 3, displayCount: 2)
            model.settings.language = language; model.workspacePreferences = nil
            let before = model.settings, observed = model.workspaceLastObservedSpaceKeys
            var pins = 0
            let window = window(HeldWorkspaceWheelView(model: model,
                select: { _ in XCTFail("Managing connections never switches Spaces") }, keepOpen: { pins += 1 }))
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(500))
            let originalFrame = window.frame
            try click("wheel-clear-all", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings, before)
            try capture("wheel-\(language)-clear-all-confirm", window: window)
            try click("wheel-confirm-clear-all", in: window)
            try await Task.sleep(for: .milliseconds(120))
            XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
            XCTAssertNotNil(element("wheel-empty-guidance", in: window))
            XCTAssertNotNil(element("wheel-empty-space-mac", in: window))
            XCTAssertEqual(window.frame, originalFrame)
            XCTAssertGreaterThan(pins, 0, "Deletion must keep the held menu open for recovery")
            try capture("wheel-\(language)-empty-after-clear", window: window)

            // Reopening discards local feedback flags; undo must still be discoverable.
            window.contentView = HeldMatrixHostingView(rootView: HeldWorkspaceWheelView(model: model,
                select: { _ in XCTFail("Undo never switches Spaces") }))
            try await Task.sleep(for: .milliseconds(500))
            try click("held-undo-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)

            try click("wheel-clear-all", in: window)
            try await Task.sleep(for: .milliseconds(100))
            try click("wheel-confirm-clear-all", in: window)
            try await Task.sleep(for: .milliseconds(100))
            try click("held-add-current-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts.count, 1)
            XCTAssertEqual(model.settings.contextPlan.contexts[0].displayIDs.sorted(), ["external-1", "mac"])
            XCTAssertNil(element("wheel-empty-guidance", in: window))
            XCTAssertEqual(window.frame, originalFrame)
            XCTAssertEqual(model.workspaceLastObservedSpaceKeys, observed)
            let onlyID = model.settings.contextPlan.contexts[0].id
            let point = HeldWorkspaceWheelLayout.labelPoint(index: 0, count: 1)
            try await hover(NSPoint(x: point.x + 16, y: 568 - 8 - point.y), in: window)
            try click("wheel-delete-" + onlyID, in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty, "The last connection is deleted without confirmation")
            XCTAssertNotNil(element("wheel-empty-guidance", in: window))
            try click("held-undo-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), [onlyID])
            try click("held-undo-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
            try click("held-undo-connection", in: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
        }
    }

    func testSmallWheelKeepsCleanupUndoAndFirstConnectionInsideWindow() async throws {
        try requireNative()
        for language in [AppLanguage.korean, .english] {
            for count in [0, 9] {
                let model = heldMatrixFixture(count: max(1, count), displayCount: 2)
                model.settings.language = language; model.workspacePreferences = nil
                if count == 0 {
                    model.settings.contextPlan = .empty
                    model.settings.savedWorkspaces.bookmarks = [:]
                }
                let window = window(HeldWorkspaceWheelView(model: model, select: { _ in }, diameter: 320),
                    size: NSSize(width: 352, height: 448))
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(500))
                for id in ["held-edit-connections", "wheel-show-table", "wheel-clear-all", "held-undo-connection", "held-add-current-connection"] {
                    let control = try XCTUnwrap(element(id, in: window) as? any NSAccessibilityElementProtocol)
                    XCTAssertTrue(window.frame.contains(control.accessibilityFrame()), "\(language), \(count), \(id) must fit")
                }
                try capture("wheel-small-\(language)-\(count)", window: window)
            }
        }
    }

    func testProductionControllerReturnsFromEditorToSamePointerAnchoredWheel() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 4, displayCount: 2)
        model.workspacePreferences = nil
        let controller = HeldWorkspaceMatrixController(model: model)
        controller.showPersistent()
        let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
        defer { controller.dismiss(); window.close() }
        try await Task.sleep(for: .milliseconds(500))
        let original = window.frame
        XCTAssertNotNil(element("held-workspace-wheel", in: window))
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor.alphaComponent, 0)
        XCTAssertFalse(window.hasShadow, "No rectangular window shadow around the HUD")
        try click("held-edit-connections", in: window)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(element("current-connections-table", in: window))
        XCTAssertNotNil(element("connection-space-count-mac", in: window))
        try capture("connections-native", window: window)
        try click("held-finish-editing", in: window)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(window.frame, original)
        XCTAssertNotNil(element("held-workspace-wheel", in: window))
        try click("wheel-show-table", in: window)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNotNil(element("held-switch-table", in: window))
        try click("held-show-wheel", in: window)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(window.frame, original)
    }
}
