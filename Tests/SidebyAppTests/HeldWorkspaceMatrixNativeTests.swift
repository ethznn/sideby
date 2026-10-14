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

    private func nativeClick(_ object: NSObject) async throws {
        try XCTSkipUnless(CGPreflightPostEventAccess(), "Native mouse input uses the existing permission")
        let rect = try frame(object)
        let point = CGPoint(x: rect.midX, y: NSScreen.screens[0].frame.maxY - rect.midY)
        let feed = Task.detached {
            for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                try await Task.sleep(for: .milliseconds(100))
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
            try await Task.sleep(for: .milliseconds(150))
            DispatchQueue.main.async {
                NSApp.stop(nil)
                if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                    timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                    NSApp.postEvent(wake, atStart: true)
                }
            }
        }
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated { NSApp.run() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        try await feed.value
    }

    func testCurrentSpacesCanBeAddedWithoutEditingAndUndoneInTheQuickPanel() async throws {
        try requireNative()
        for english in [false, true] {
            let model = heldMatrixFixture(count: 3, displayCount: 2)
            model.workspacePreferences = nil
            model.workspaceNameSuggestionProvider = nil
            model.settings.language = english ? .english : .korean
            model.workspaceDesktopNames = ["mac": [0: "Xcode", 1: "Safari", 2: "Notes"],
                                           "external-1": [0: "Safari", 1: "Figma", 2: "Calendar"]]
            let base = try XCTUnwrap(model.workspaceObservationOverride?())
            model.workspaceObservationOverride = {
                .init(displays: base.displays.map { .init(displayID: $0.displayID, spaceCount: $0.spaceCount,
                                                        currentSpaceIndex: $0.displayID == "mac" ? 0 : 1) },
                      spaceIDsByDisplayID: base.spaceIDsByDisplayID, spaceKeysByDisplayID: base.spaceKeysByDisplayID)
            }
            model.refreshWorkspaceStatus()
            let before = model.settings
            let controller = HeldWorkspaceMatrixController(model: model)
            controller.showPersistent()
            let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
            defer { controller.dismiss(); window.close() }
            try await Task.sleep(for: .milliseconds(250))
            let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"] ?? "/tmp/sideby-current-spaces")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            func capture(_ suffix: String) throws {
                let view = try XCTUnwrap(window.contentView)
                view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appendingPathComponent("current-spaces-\(english ? "en" : "ko")-\(suffix).png"))
            }
            let button = try XCTUnwrap(element("held-add-current-connection", in: window))
            XCTAssertTrue(window.frame.contains(try frame(button)))
            try capture("before")
            try click(button, window: window)
            try await Task.sleep(for: .milliseconds(250))
            let id = try XCTUnwrap(model.settings.contextPlan.contexts.last?.id)
            XCTAssertEqual(model.settings.contextPlan.contexts.count, before.contextPlan.contexts.count + 1)
            XCTAssertEqual(model.settings.contextPlan.contexts.last?.name, "Xcode / Figma")
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[id], ["mac": base.spaceKeysByDisplayID["mac"]![0],
                                                                         "external-1": base.spaceKeysByDisplayID["external-1"]![1]])
            XCTAssertNotNil(element("held-switch-table", in: window))
            XCTAssertNil(element("current-connections-table", in: window), "Stay in the switching view")
            XCTAssertTrue(window.frame.contains(try frame(XCTUnwrap(element("held-workspace-" + id, in: window)))))
            let undo = try XCTUnwrap(element("held-undo-connection", in: window))
            XCTAssertTrue(window.frame.contains(try frame(undo)))
            XCTAssertFalse(model.isSwitching)
            XCTAssertNil(model.workspaceSaveDraft)
            try capture("added")
            try click(button, window: window)
            XCTAssertEqual(model.settings.contextPlan.contexts.count, before.contextPlan.contexts.count + 1)
            try click(undo, window: window)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
            XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, before.savedWorkspaces.shortcutSlots)
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

    func testRenameInShortcutEditorCanCancelApplyAndUndoWithoutLeavingPanel() async throws {
        try requireNative()
        for english in [false, true] {
            let model = heldMatrixFixture(count: 3, displayCount: 2)
            model.workspacePreferences = nil; model.workspaceNameSuggestionProvider = nil
            model.settings.language = english ? .english : .korean
            let controller = HeldWorkspaceMatrixController(model: model)
            controller.showPersistent()
            let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
            defer { controller.dismiss(); window.close() }
            try await Task.sleep(for: .milliseconds(150))
            try click(XCTUnwrap(element("held-edit-connections", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(200))
            let before = model.settings
            let button = try XCTUnwrap(element("connection-rename-work-0", in: window))
            try click(button, window: window)
            try await Task.sleep(for: .milliseconds(200))
            var popup = try XCTUnwrap(NSApp.windows.first { $0.isVisible && element("connection-name-cancel", in: $0) != nil })
            let editor = try XCTUnwrap(popup.firstResponder as? NSTextView)
            editor.selectAll(nil); editor.insertText("미저장 입력", replacementRange: editor.selectedRange())
            try click(XCTUnwrap(element("connection-name-cancel", in: popup)), window: popup)
            XCTAssertEqual(model.settings, before)
            XCTAssertTrue(window.isVisible)
            try click(button, window: window)
            try await Task.sleep(for: .milliseconds(200))
            popup = try XCTUnwrap(NSApp.windows.first { $0.isVisible && element("connection-name-apply", in: $0) != nil })
            let input = try XCTUnwrap(popup.firstResponder as? NSTextView)
            let name = english ? "Focused work" : "집중 작업"
            input.selectAll(nil); input.insertText(name, replacementRange: input.selectedRange())
            try await Task.sleep(for: .milliseconds(100))
            let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"] ?? "/tmp/sideby-current-spaces")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let host = try XCTUnwrap(popup.contentView)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("connection-rename-\(english ? "en" : "ko").png"))
            try click(XCTUnwrap(element("connection-name-apply", in: popup)), window: popup)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(model.settings.contextPlan.contexts.first?.name, name)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
            XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, before.savedWorkspaces.shortcutSlots)
            XCTAssertTrue(window.isVisible)
            let undo = try XCTUnwrap(element("connections-undo", in: window))
            let undoFrame = try frame(undo)
            XCTAssertTrue(window.frame.contains(undoFrame), "Rename undo must remain visible: panel \(window.frame), undo \(undoFrame)")
            let panelHost = try XCTUnwrap(window.contentView)
            let panelBitmap = try XCTUnwrap(panelHost.bitmapImageRepForCachingDisplay(in: panelHost.bounds))
            panelHost.cacheDisplay(in: panelHost.bounds, to: panelBitmap)
            try XCTUnwrap(panelBitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("connection-renamed-\(english ? "en" : "ko").png"))
            try click(undo, window: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts.first?.name, before.contextPlan.contexts.first?.name)
            XCTAssertFalse(model.isSwitching)
        }
    }

    func testRenameDirectlyInQuickPanelCanCancelApplyAndUndo() async throws {
        try requireNative()
        for english in [false, true] {
            let model = heldMatrixFixture(count: 3, displayCount: 2)
            model.workspacePreferences = nil; model.workspaceNameSuggestionProvider = nil
            model.settings.language = english ? .english : .korean
            let controller = HeldWorkspaceMatrixController(model: model)
            controller.showPersistent()
            let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
            defer { controller.dismiss(); window.close() }
            try await Task.sleep(for: .milliseconds(150))
            try await Task.sleep(for: .milliseconds(200))
            let before = model.settings
            let button = try XCTUnwrap(element("held-rename-work-0", in: window))
            try click(button, window: window)
            try await Task.sleep(for: .milliseconds(200))
            var popup = try XCTUnwrap(NSApp.windows.first { $0.isVisible && element("connection-name-cancel", in: $0) != nil })
            let editor = try XCTUnwrap(popup.firstResponder as? NSTextView)
            editor.selectAll(nil); editor.insertText("미저장 입력", replacementRange: editor.selectedRange())
            try click(XCTUnwrap(element("connection-name-cancel", in: popup)), window: popup)
            XCTAssertEqual(model.settings, before)
            XCTAssertTrue(window.isVisible)
            try click(button, window: window)
            try await Task.sleep(for: .milliseconds(200))
            popup = try XCTUnwrap(NSApp.windows.first { $0.isVisible && element("connection-name-apply", in: $0) != nil })
            let input = try XCTUnwrap(popup.firstResponder as? NSTextView)
            let name = english ? "Focused work" : "집중 작업"
            input.selectAll(nil); input.insertText(name, replacementRange: input.selectedRange())
            try await Task.sleep(for: .milliseconds(100))
            let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"] ?? "/tmp/sideby-current-spaces")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let host = try XCTUnwrap(popup.contentView)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("quick-rename-\(english ? "en" : "ko").png"))
            try click(XCTUnwrap(element("connection-name-apply", in: popup)), window: popup)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(model.settings.contextPlan.contexts.first?.name, name)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
            XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, before.savedWorkspaces.shortcutSlots)
            XCTAssertTrue(window.isVisible)
            let undo = try XCTUnwrap(element("held-undo-connection", in: window))
            let undoFrame = try frame(undo)
            XCTAssertTrue(window.frame.contains(undoFrame), "Rename undo must remain visible: panel \(window.frame), undo \(undoFrame)")
            let panelHost = try XCTUnwrap(window.contentView)
            let panelBitmap = try XCTUnwrap(panelHost.bitmapImageRepForCachingDisplay(in: panelHost.bounds))
            panelHost.cacheDisplay(in: panelHost.bounds, to: panelBitmap)
            try XCTUnwrap(panelBitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("quick-renamed-\(english ? "en" : "ko").png"))
            try click(undo, window: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.contextPlan.contexts.first?.name, before.contextPlan.contexts.first?.name)
            XCTAssertFalse(model.isSwitching)
            XCTAssertNotNil(element("held-switch-table", in: window))
            XCTAssertNil(element("current-connections-table", in: window))
        }
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

    func testPanelFitsRenderedContentAndRemeasuresFeedbackAndEditorInBothLanguages() async throws {
        try requireNative()
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"]
            ?? "/tmp/sideby-content-height.noindex")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for english in [false, true] {
          for displays in [1, 2] {
            let model = heldMatrixFixture(count: 2, displayCount: displays)
            model.workspacePreferences = nil
            model.settings.language = english ? .english : .korean
            model.settings.contextPlan = .init(contexts: model.settings.contextPlan.contexts.map {
                .init(id: $0.id, order: $0.order, name: $0.name,
                      displaySpaceIndexes: $0.displaySpaceIndexes.filter { $0.key != "offline" })
            }, currentContextID: "work-0")
            let before = model.settings
            let controller = HeldWorkspaceMatrixController(model: model)
            controller.showPersistent(anchor: NSRect(x: screen.midX, y: screen.maxY - 100, width: 1, height: 1))
            let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
            defer { controller.dismiss(); window.close() }
            let openingHeight = window.frame.height
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(window.frame.height, openingHeight, accuracy: 1, "Measure before showing the window")
            let initial = window.frame
            func checkBottom(_ id: String, padding: CGFloat = 18) throws {
                let bottom = try frame(XCTUnwrap(element(id, in: window)))
                XCTAssertTrue(window.frame.contains(bottom), "The last control must remain visible")
                XCTAssertEqual(bottom.minY - window.frame.minY, padding, accuracy: 2, "Only the normal bottom padding should remain")
                XCTAssertTrue(screen.contains(window.frame))
            }
            func capture(_ state: String) throws {
                let host = try XCTUnwrap(window.contentView)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                    output.appendingPathComponent("height-\(english ? "en" : "ko")-\(displays)-\(state).png"))
            }
            try checkBottom("held-footer")
            try capture("switching")
            // This combination already exists: show feedback without changing connections.
            try click(XCTUnwrap(element("held-add-current-connection", in: window)), window: window)
            model.workspaceSaveMessage = String(repeating: english ? "This connection is already available. " : "이미 연결된 Space입니다. ", count: 5)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertGreaterThan(window.frame.height, initial.height)
            XCTAssertEqual(window.frame.maxY, initial.maxY, accuracy: 1)
            try checkBottom("held-footer")
            try capture("feedback")
            model.workspaceSaveMessage = nil
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(window.frame.size, initial.size)
            try checkBottom("held-footer")
            try click(XCTUnwrap(element("held-edit-connections", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(250))
            // AX reports the single-line scope text inside the two-line status
            // row; its 9pt inset and vertical centering add 17.5pt here.
            try checkBottom("connections-status", padding: 35.5)
            try capture("editing")
            let editingFrame = window.frame
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(window.frame, editingFrame, "Measured height must settle without a compact-layout feedback loop")
            try click(XCTUnwrap(element("held-finish-editing", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(window.frame.size, initial.size)
            try checkBottom("held-footer")
            XCTAssertEqual(model.settings, before)
            XCTAssertFalse(model.isSwitching)
          }
        }
    }

    func testQuickEditorStaysInPlaceWhenClearedAndConnectedAgain() async throws {
        try requireNative()
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"]
            ?? "/tmp/sideby-quick-editor-stability.noindex")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for english in [false, true] {
            let model = heldMatrixFixture(count: 2, displayCount: 2)
            model.workspacePreferences = nil; model.workspaceNameSuggestionProvider = nil
            model.settings.language = english ? .english : .korean
            model.displayLayout = .init(displays: model.displayLayout.displays.filter { $0.id != "excluded" })
            model.settings.contextPlan = .init(contexts: model.settings.contextPlan.contexts.map {
                .init(id: $0.id, order: $0.order, name: $0.name,
                      displaySpaceIndexes: $0.displaySpaceIndexes.filter { $0.key != "offline" })
            }, currentContextID: "work-0")
            let observation = try XCTUnwrap(model.workspaceObservationOverride?())
            let controller = HeldWorkspaceMatrixController(model: model)
            let screen = try XCTUnwrap(NSScreen.main).visibleFrame
            controller.showPersistent(anchor: NSRect(x: screen.midX, y: screen.minY + 100, width: 1, height: 1))
            let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
            defer { controller.dismiss(); window.close() }
            try await Task.sleep(for: .milliseconds(200))
            try click(XCTUnwrap(element("held-edit-connections", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(300))
            let stableIDs = ["connections-title", "connection-source-mac-0", "connection-desktop-sources", "current-connections-table"]
            let initialFrames = try stableIDs.map { try frame(XCTUnwrap(element($0, in: window))) }
            let initialPanel = window.frame
            func checkStable(_ state: String) throws {
                XCTAssertEqual(window.frame, initialPanel, "Panel moved at \(state), \(english)")
                for (id, initial) in zip(stableIDs, initialFrames) {
                    XCTAssertEqual(try frame(XCTUnwrap(element(id, in: window))), initial, "\(id) moved at \(state), \(english)")
                }
                let title = try XCTUnwrap(element("connections-title", in: window))
                let value = title.perform(NSSelectorFromString("accessibilityValue"))?.takeUnretainedValue() as? String
                XCTAssertEqual(value, model.connectionCopy.title)
                XCTAssertTrue(screen.contains(window.frame))
                XCTAssertFalse(model.isSwitching)
                XCTAssertEqual(model.workspaceObservationOverride?(), observation)
                let host = try XCTUnwrap(window.contentView)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                    output.appendingPathComponent("stable-\(english ? "en" : "ko")-\(state).png"))
            }
            try click(XCTUnwrap(element("connections-clear-all", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(150))
            let sheet = try XCTUnwrap(window.attachedSheet)
            func confirmation(in view: NSView) -> NSButton? {
                if let button = view as? NSButton, button.title == model.connectionCopy.clearAllAction { return button }
                return view.subviews.lazy.compactMap { confirmation(in: $0) }.first
            }
            try XCTUnwrap(confirmation(in: XCTUnwrap(sheet.contentView))).performClick(nil)
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
            try checkStable("cleared")
            // Use the same assignment action as a drop, without global mouse input.
            let emptyCell = try frame(XCTUnwrap(element("connection-cell-new-mac", in: window)))
            XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: observation.spaceKeysByDisplayID["mac"]![0], contextID: nil))
            try await Task.sleep(for: .milliseconds(250))
            let id = try XCTUnwrap(model.settings.contextPlan.contexts.first?.id)
            XCTAssertEqual(try frame(XCTUnwrap(element("connection-cell-\(id)-mac", in: window))), emptyCell)
            try checkStable("first-space")
            // Dismissing feedback must not shrink or scroll the editing surface.
            try click(XCTUnwrap(element("connections-dismiss-feedback", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(200))
            try checkStable("feedback-dismissed")
            XCTAssertTrue(model.setCurrentConnection(displayID: "external-1", key: observation.spaceKeysByDisplayID["external-1"]![0], contextID: id))
            try await Task.sleep(for: .milliseconds(200))
            try checkStable("second-space")
            XCTAssertTrue(model.undoSavedWorkspaceChange())
            XCTAssertTrue(model.undoSavedWorkspaceChange())
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
            try checkStable("undone")
            XCTAssertNil(model.workspacePreferences)
        }
    }

    func testTallPanelScrollsWithinScreenAndReopeningRemeasuresEmptyContent() async throws {
        try requireNative()
        let model = heldMatrixFixture(count: 2, displayCount: 40)
        model.workspacePreferences = nil
        let controller = HeldWorkspaceMatrixController(model: model)
        controller.showPersistent()
        let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
        defer { controller.dismiss(); window.close() }
        try await Task.sleep(for: .milliseconds(250))
        let screen = try XCTUnwrap(window.screen).visibleFrame
        XCTAssertEqual(window.frame.height, screen.height - 48, accuracy: 1)
        XCTAssertTrue(screen.contains(window.frame))
        func verticalScroll(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView,
               (scroll.documentView?.bounds.height ?? 0) > scroll.contentView.bounds.height + 100 { return scroll }
            return view.subviews.lazy.compactMap { verticalScroll(in: $0) }.first
        }
        let scroll = try XCTUnwrap(verticalScroll(in: XCTUnwrap(window.contentView)))
        let document = try XCTUnwrap(scroll.documentView)
        document.scroll(NSPoint(x: 0, y: document.bounds.height - scroll.contentView.bounds.height))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(window.frame.contains(try frame(XCTUnwrap(element("held-footer", in: window)))), "The bottom must be reachable by scrolling")
        let largeFrame = window.frame
        controller.dismiss()
        // Late observations must not reopen a dismissed panel.
        model.selectedDisplayIDs = []
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.frame, largeFrame)
        controller.showPersistent()
        let reopened = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
        defer { reopened.close() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertLessThan(reopened.frame.height, 360, "An empty view must not inherit the previous tall frame")
        let footer = try frame(XCTUnwrap(element("held-footer", in: reopened)))
        XCTAssertEqual(footer.minY - reopened.frame.minY, 18, accuracy: 2)
        XCTAssertNotNil(element("held-edit-connections", in: reopened))
        XCTAssertNil(element("held-switch-table", in: reopened))
    }

    func testMissingSpaceCanBeRepairedDirectlyFromQuickPanelWithoutSwitchingAndUndone() async throws {
        try requireNative()
        for english in [false, true] {
            let model = heldMatrixFixture(count: 3, displayCount: 2)
            model.workspacePreferences = nil
            model.settings.language = english ? .english : .korean
            model.settings.savedWorkspaces.bookmarks["work-0"]?["mac"] = "default-desktop"
            model.refreshWorkspaceStatus()
            let before = model.settings
            let controller = HeldWorkspaceMatrixController(model: model)
            controller.showPersistent()
            let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
            defer { controller.dismiss(); window.close() }
            try await Task.sleep(for: .milliseconds(200))
            // The warning cell is actionable; it must not silently ignore the click.
            try click(XCTUnwrap(element("held-cell-work-0-mac", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(200))
            var popup = try XCTUnwrap(NSApp.windows.first { $0.isVisible && element("connection-choice-mac-1", in: $0) != nil })
            XCTAssertEqual(model.settings, before, "Opening repair must preserve the saved identity")
            XCTAssertFalse(model.isSwitching)
            XCTAssertNotNil(element("connection-repair-hint", in: popup))
            XCTAssertTrue(popup.frame.contains(try frame(XCTUnwrap(element("connection-choice-mac-2", in: popup)))))
            let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"] ?? "/tmp/sideby-missing-space.noindex")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for (target, suffix) in [(window, "panel"), (popup, "picker")] {
                let host = try XCTUnwrap(target.contentView)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("repair-\(english ? "en" : "ko")-\(suffix).png"))
            }
            // Dismiss and reopen through the title: only the pencil should rename.
            popup.performClose(nil)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertFalse(popup.isVisible)
            try click(XCTUnwrap(element("held-title-work-0", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(200))
            popup = try XCTUnwrap(NSApp.windows.first { $0.isVisible && element("connection-choice-mac-1", in: $0) != nil })
            XCTAssertNil(element("connection-name-apply", in: popup))
            XCTAssertEqual(model.settings, before)
            try click(XCTUnwrap(element("connection-choice-mac-1", in: popup)), window: popup)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["work-0"]?["mac"], model.workspaceLastObservedSpaceKeys["mac"]?[1])
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["work-0"]?["external-1"], before.savedWorkspaces.bookmarks["work-0"]?["external-1"])
            XCTAssertTrue(model.unresolvedWorkspaceMembers(model.settings.contextPlan.contexts[0]).isEmpty)
            XCTAssertFalse(model.isSwitching)
            XCTAssertNotNil(element("held-switch-table", in: window))
            XCTAssertNil(element("current-connections-table", in: window), "Repair stays in the quick panel")
            let undo = try XCTUnwrap(element("held-undo-connection", in: window))
            XCTAssertTrue(window.frame.contains(try frame(undo)))
            try click(undo, window: window)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
            XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
            // The warning action beside the shortcut also offers repair.
            try click(XCTUnwrap(element("held-go-work-0", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(200))
            popup = try XCTUnwrap(NSApp.windows.first { $0.isVisible && element("connection-choice-mac-1", in: $0) != nil })
            let clear = try XCTUnwrap(element("connection-clear", in: popup))
            let clearFrame = try frame(clear)
            XCTAssertTrue(popup.frame.contains(clearFrame), "Disconnect must be visible: popup \(popup.frame), button \(clearFrame)")
            try await nativeClick(clear)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertNil(model.settings.savedWorkspaces.bookmarks["work-0"]?["mac"])
            XCTAssertNil(model.settings.contextPlan.contexts.first { $0.id == "work-0" }?.spaceIndex(for: "mac"))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["work-0"]?["external-1"], before.savedWorkspaces.bookmarks["work-0"]?["external-1"])
            try click(XCTUnwrap(element("held-undo-connection", in: window)), window: window)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
            XCTAssertFalse(model.isSwitching)
        }
    }

    func testSpacePickerStaysInsideItsDisplayAtEveryScreenCorner() async throws {
        try requireNative()
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            for point in [NSPoint(x: visible.minX, y: visible.minY), NSPoint(x: visible.maxX - 1, y: visible.minY),
                          NSPoint(x: visible.minX, y: visible.maxY - 1), NSPoint(x: visible.maxX - 1, y: visible.maxY - 1)] {
                let model = heldMatrixFixture(count: 8)
                model.workspacePreferences = nil
                model.settings.savedWorkspaces.bookmarks["work-0"]?["mac"] = "missing-space"
                model.refreshWorkspaceStatus()
                let controller = HeldWorkspaceMatrixController(model: model)
                controller.showPersistent(anchor: NSRect(x: point.x, y: point.y + 62, width: 1, height: 1))
                let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
                defer { controller.dismiss(); window.close() }
                try await Task.sleep(for: .milliseconds(180))
                try click(XCTUnwrap(element("held-cell-work-0-mac", in: window)), window: window)
                try await Task.sleep(for: .milliseconds(250))
                let popup = try XCTUnwrap(NSApp.windows.first { $0.isVisible && element("connection-choice-mac-1", in: $0) != nil })
                XCTAssertTrue(visible.contains(popup.frame), "Picker \(popup.frame) escaped display \(visible), anchor \(point)")
                XCTAssertGreaterThanOrEqual(popup.level.rawValue, window.level.rawValue, "The picker must not be behind its matrix")
                let clear = try frame(XCTUnwrap(element("connection-clear", in: popup)))
                XCTAssertTrue(visible.contains(clear), "Disconnect must remain on screen")
                XCTAssertTrue(popup.frame.contains(clear), "Disconnect must remain inside the picker")
                XCTAssertFalse(model.isSwitching)
                popup.performClose(nil)
            }
        }
    }

    func testSpacePickerCorrectsLateOverflowAndKeepsActionsReachableAfterContentGrows() async throws {
        try requireNative()
        let screen = try XCTUnwrap(NSScreen.screens.last)
        let visible = screen.visibleFrame
        let model = heldMatrixFixture(count: 8)
        model.workspacePreferences = nil
        model.settings.savedWorkspaces.bookmarks["work-0"]?["mac"] = "missing-space"
        model.refreshWorkspaceStatus()
        let before = model.settings.savedWorkspaces.bookmarks
        let controller = HeldWorkspaceMatrixController(model: model)
        controller.showPersistent(anchor: NSRect(x: visible.maxX - 2, y: visible.minY + 62, width: 1, height: 1))
        let window = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue == "sideby-held-workspace-matrix" })
        defer { controller.dismiss(); window.close() }
        try await Task.sleep(for: .milliseconds(180))
        try click(XCTUnwrap(element("held-cell-work-0-mac", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(250))
        let popup = try XCTUnwrap(NSApp.windows.first { $0.isVisible && element("connection-choice-mac-1", in: $0) != nil })
        // Simulate a late native placement outside the originating display.
        // This is a guard regression, not a reproduction of the user's cause.
        popup.setFrameOrigin(NSPoint(x: visible.maxX - 30, y: visible.minY - 100))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(visible.contains(popup.frame), "A late move must be corrected on the original display")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)

        // An unusually long display name forces the whole picker to scroll,
        // in addition to its normal Space list, without clipping the footer.
        model.displayLayout = .init(displays: [
            .init(id: "mac", name: String(repeating: "Long display name ", count: 400), isPrimary: true, isBuiltin: true)
        ])
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(visible.contains(popup.frame), "Content growth must not escape the screen")
        func overflowingScroll(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView,
               (scroll.documentView?.bounds.height ?? 0) > scroll.contentView.bounds.height + 400 { return scroll }
            return view.subviews.lazy.compactMap { overflowingScroll(in: $0) }.first
        }
        let scroll = try XCTUnwrap(overflowingScroll(in: XCTUnwrap(popup.contentView)))
        let document = try XCTUnwrap(scroll.documentView)
        document.scroll(NSPoint(x: 0, y: document.bounds.height - scroll.contentView.bounds.height))
        try await Task.sleep(for: .milliseconds(150))
        let clear = try XCTUnwrap(element("connection-clear", in: popup))
        XCTAssertTrue(popup.frame.contains(try frame(clear)), "Disconnect must be reachable by scrolling")
        try await nativeClick(clear)
        XCTAssertNil(model.settings.savedWorkspaces.bookmarks["work-0"]?["mac"])
        XCTAssertNil(model.settings.contextPlan.contexts.first { $0.id == "work-0" }?.spaceIndex(for: "mac"))
        XCTAssertFalse(model.isSwitching)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
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
