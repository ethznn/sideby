import AppKit
import SwiftUI
import XCTest
import SidebyCore
@testable import SidebyApp

@MainActor final class WorkspaceComposerNativeTests: XCTestCase {
    private func requireNative() throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else { throw XCTSkip("Opt-in composer native interaction") }
        let app = NSApplication.shared, policy = app.activationPolicy()
        let previous = NSWorkspace.shared.frontmostApplication
        let pointer = CGEvent(source: nil)?.location
        app.setActivationPolicy(.accessory)
        app.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: NSNumber(value: true), with: "AXEnhancedUserInterface")
        addTeardownBlock { await MainActor.run {
            app.setActivationPolicy(policy); previous?.activate(options: [])
            if let pointer { CGWarpMouseCursorPosition(pointer) }
            NSCursor.arrow.set()
        } }
    }
    private func fixture(displays: Int = 2, contexts: Int = 4) -> SidebyAppModel {
        let ids = (0..<displays).map { "display-\($0)" }
        let keys = Dictionary(uniqueKeysWithValues: ids.map { id in (id, (0..<7).map { "\(id)-space-\($0)" }) })
        let handles = Dictionary(uniqueKeysWithValues: ids.enumerated().map { offset, id in (id, (0..<7).map { UInt64(100 * (offset + 1) + $0) }) })
        let observation = WorkspaceLayoutObservation(displays: ids.map { .init(displayID: $0, spaceCount: 7, currentSpaceIndex: 0) },
            spaceIDsByDisplayID: handles, spaceKeysByDisplayID: keys)
        var settings = AppSettings.default
        settings.language = .korean
        settings.contextPlan = .init(contexts: (0..<contexts).map { i in
            .init(id: "setup-\(i)", order: i + 1, name: ["개발", "디자인 검토", "회의", "집중", "자료 조사", "문서 작성", "운영", "개인 작업"][i % 8],
                displaySpaceIndexes: Dictionary(uniqueKeysWithValues: ids.map { ($0, i % 7) }))
        }, currentContextID: "setup-0")
        settings.savedWorkspaces.initialized = true
        for context in settings.contextPlan.contexts {
            settings.savedWorkspaces.bookmarks[context.id] = Dictionary(uniqueKeysWithValues: ids.map { ($0, keys[$0]![context.order % 7 == 0 ? 6 : (context.order - 1) % 7]) })
            settings.savedWorkspaces.assignAvailableShortcut(to: context.id)
        }
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: Set(ids), selectedDisplaySpaces: { nil }, postEventAccessGranted: true)
        model.workspacePreferences = nil
        model.permissionState = .granted
        model.displayLayout = .init(displays: ids.enumerated().map { i, id in
            .init(id: id, name: ["MacBook Pro", "Studio Display", "세로 모니터", "보조 화면"][i % 4], isPrimary: i == 0, isBuiltin: i == 0)
        })
        model.workspaceObservationOverride = { observation }
        model.workspaceDesktopNameSpaceIDs = handles
        model.workspaceDesktopNames = Dictionary(uniqueKeysWithValues: ids.enumerated().map { i, id in
            (id, Dictionary(uniqueKeysWithValues: (0..<7).map { index in
                (index, (i == 0 ? ["Xcode", "Slack", "Notes", "Terminal", "Mail", "Safari", "Preview"] : ["Chrome", "Figma", "Calendar", "Safari", "Terminal", "Mail", "Preview"])[index])
            }))
        })
        model.refreshWorkspaceStatus()
        return model
    }
    private func makeWindow(_ model: SidebyAppModel, size: NSSize, dark: Bool) -> NSWindow {
        let navigation = ProductUINavigation(preferences: MemoryProductUIPreferences())
        navigation.openSettings(.init(pane: .workspaces))
        let host = NSHostingView(rootView: ProductSettingsView(model: model, navigation: navigation, canCheckForUpdates: false,
            actions: .init(checkForUpdates: {}, openOnboarding: {}, finishAssignmentReview: {})).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
    private func capture(_ window: NSWindow, name: String) throws {
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"] ?? "/tmp/sideby-composer-native")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let host = try XCTUnwrap(window.contentView)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
    }
    private func attribute(_ object: NSObject, _ key: String) -> Any? {
        let names = ["AXIdentifier": "accessibilityIdentifier", "AXChildren": "accessibilityChildren", "AXTitle": "accessibilityLabel", "AXRole": "accessibilityRole", "AXValue": "accessibilityValue"]
        if let name = names[key], object.responds(to: NSSelectorFromString(name)) {
            return object.perform(NSSelectorFromString(name))?.takeUnretainedValue()
        }
        return nil
    }
    private func element(_ id: String, in window: NSWindow) -> NSObject? {
        func find(_ object: NSObject) -> NSObject? {
            if attribute(object, "AXIdentifier") as? String == id { return object }
            for child in attribute(object, "AXChildren") as? [NSObject] ?? [] {
                if let found = find(child) { return found }
            }
            return nil
        }
        return window.contentView.flatMap(find)
    }
    private func frame(_ element: NSObject) throws -> NSRect {
        try XCTUnwrap(element as? any NSAccessibilityElementProtocol).accessibilityFrame()
    }
    private func click(_ element: NSObject, window: NSWindow) throws {
        let frame = try frame(element), point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)))
        }
    }
    func testRenderDisplayRowsAndClickToAssignThenSaveAndUndo() async throws {
        try requireNative()
        for dark in [false, true] {
            let model = fixture()
            let original = model.settings.savedWorkspaces.bookmarks
            let window = makeWindow(model, size: NSSize(width: 1040, height: 760), dark: dark)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(300))
            try capture(window, name: "composer-\(dark ? "dark" : "light")")
            let source = try XCTUnwrap(element("composer-source-display-1-1", in: window))
            let firstSource = try XCTUnwrap(element("composer-source-display-0-1", in: window))
            XCTAssertEqual(attribute(source, "AXTitle") as? String, "Studio Display · 데스크탑 2 · Figma")
            XCTAssertEqual(try frame(source).minX, try frame(firstSource).minX, accuracy: 1)
            XCTAssertLessThan(try frame(source).minY, try frame(firstSource).minY)
            try click(source, window: window)
            try await Task.sleep(for: .milliseconds(100))
            let target = try XCTUnwrap(element("composer-cell-setup-0-display-1", in: window))
            XCTAssertEqual(attribute(target, "AXValue") as? String, "연결 가능")
            try click(target, window: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].members["display-1"]?.key, "display-1-space-1")
            XCTAssertEqual(attribute(try XCTUnwrap(element("composer-cell-setup-0-display-1", in: window)), "AXTitle") as? String,
                           "개발 · Studio Display · Figma")
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, original)
            XCTAssertFalse(model.isSwitching)
            try capture(window, name: "composer-changed-\(dark ? "dark" : "light")")
            try click(try XCTUnwrap(element("composer-save", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-1"], "display-1-space-1")
            try click(try XCTUnwrap(element("composer-undo", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, original)
        }
        for (width, height, displays) in [(840, 620, 3), (700, 560, 4)] {
            let window = makeWindow(fixture(displays: displays, contexts: 8), size: NSSize(width: width, height: height), dark: true)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(250))
            try capture(window, name: "composer-\(width)x\(height)-\(displays)displays")
            let save = try XCTUnwrap(element("composer-save", in: window))
            XCTAssertTrue(window.frame.contains(try frame(save)), "Save must remain visible at minimum window size")
        }
    }
    private func moveMouse(from a: NSRect, to b: NSRect, dragging: Bool = true,
                           whileHeld: (@MainActor @Sendable () throws -> Void)? = nil,
                           cancel: Bool = false) async throws {
        try XCTSkipUnless(CGPreflightPostEventAccess(), "Native mouse tests require existing input-event permission")
        let screenTop = NSScreen.screens[0].frame.maxY
        let start = CGPoint(x: a.midX, y: screenTop - a.midY), end = CGPoint(x: b.midX, y: screenTop - b.midY)
        // Exercise the normal AppKit event loop, including nonactivating panels.
        // XCTest alone runs a RunLoop but does not dispatch NSApplication events.
        let feed = Task.detached {
            func post(_ type: CGEventType, point: CGPoint) {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
            try await Task.sleep(for: .milliseconds(150))
            post(.mouseMoved, point: start)
            if dragging { post(.leftMouseDown, point: start) }
            try await Task.sleep(for: .milliseconds(100))
            for step in 1...24 {
                let t = CGFloat(step) / 24
                post(dragging ? .leftMouseDragged : .mouseMoved, point: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
                try await Task.sleep(for: .milliseconds(35))
            }
            try await Task.sleep(for: .milliseconds(150))
            do { try await whileHeld?() } catch { await MainActor.run { XCTFail("Drag observation failed: \(error)") } }
            if cancel {
                CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
                CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
            }
            if dragging { post(.leftMouseUp, point: end) }
            // A rejected native drop animates back before the source accepts another drag.
            try await Task.sleep(for: .milliseconds(750))
            DispatchQueue.main.async {
                NSApp.stop(nil)
                if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                    timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(wake, atStart: true) }
            }
        }
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
            MainActor.assumeIsolated { NSApp.run() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        try await feed.value
        try await Task.sleep(for: .milliseconds(100))
    }
    func testNativeDesktopDrag() async throws {
        try requireNative()
        let model = fixture()
        let original = model.settings.savedWorkspaces.bookmarks
        let window = makeWindow(model, size: NSSize(width: 1040, height: 760), dark: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        try await moveMouse(from: frame(XCTUnwrap(element("composer-source-display-1-1", in: window))),
                           to: frame(XCTUnwrap(element("composer-cell-setup-0-display-1", in: window))))
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].members["display-1"]?.key, "display-1-space-1")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, original)
        try capture(window, name: "composer-native-drop")
        // A rejected drop must not change another display or poison the next drag.
        try await moveMouse(from: frame(XCTUnwrap(element("composer-source-display-1-2", in: window))),
                           to: frame(XCTUnwrap(element("composer-cell-setup-0-display-0", in: window))))
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].members["display-0"]?.key, "display-0-space-0")
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].members["display-1"]?.key, "display-1-space-1")
        try await moveMouse(from: frame(XCTUnwrap(element("composer-source-display-1-2", in: window))),
                           to: frame(XCTUnwrap(element("composer-cell-setup-0-display-1", in: window))))
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].members["display-1"]?.key, "display-1-space-2")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, original)
    }

    func testDragShowsDestinationsBeforeMouseUp() async throws {
        try requireNative()
        for dark in [false, true] {
            let model = fixture()
            let window = makeWindow(model, size: NSSize(width: 1040, height: 760), dark: dark)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(300))
            let source = try frame(XCTUnwrap(element("composer-source-display-1-1", in: window)))
            let target = try frame(XCTUnwrap(element("composer-cell-setup-0-display-1", in: window)))
            try await moveMouse(from: source, to: target, whileHeld: {
                XCTAssertFalse(model.hasWorkspaceComposerChanges, "Hovering must not assign a desktop before release")
                XCTAssertEqual(self.attribute(try XCTUnwrap(self.element("composer-cell-setup-0-display-1", in: window)), "AXValue") as? String, "놓으면 연결")
                XCTAssertEqual(self.attribute(try XCTUnwrap(self.element("composer-cell-setup-1-display-1", in: window)), "AXValue") as? String, "연결 가능")
                XCTAssertEqual(self.attribute(try XCTUnwrap(self.element("composer-cell-setup-0-display-0", in: window)), "AXValue") as? String ?? "", "")
                try self.capture(window, name: "composer-drag-hover-\(dark ? "dark" : "light")")
            })
            XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].members["display-1"]?.key, "display-1-space-1")
            XCTAssertEqual(attribute(try XCTUnwrap(element("composer-cell-setup-1-display-1", in: window)), "AXValue") as? String ?? "", "")
            model.discardWorkspaceComposer()
            try await moveMouse(from: source, to: target, whileHeld: {
                XCTAssertEqual(self.attribute(try XCTUnwrap(self.element("composer-cell-setup-0-display-1", in: window)), "AXValue") as? String, "놓으면 연결")
            }, cancel: true)
            XCTAssertFalse(model.hasWorkspaceComposerChanges, "Escape cancels the connection")
            XCTAssertEqual(attribute(try XCTUnwrap(element("composer-cell-setup-1-display-1", in: window)), "AXValue") as? String ?? "", "")
        }
    }
    func testNativeContextDrag() async throws {
        try requireNative()
        let model = fixture()
        let window = makeWindow(model, size: NSSize(width: 1040, height: 760), dark: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        let grip = try frame(XCTUnwrap(element("composer-reorder-setup-0", in: window)))
        try await moveMouse(from: grip, to: frame(XCTUnwrap(element("composer-header-setup-2", in: window))))
        XCTAssertNotEqual(model.workspaceComposerDraft?.state.entries.first?.id, "setup-0")
        XCTAssertEqual(model.workspaceComposerDraft?.state.slots["setup-0"], 1)
    }

    func testNativeQuickMatrixReorderKeepsPanelOpenAndPreservesSlots() async throws {
        try requireNative()
        let model = fixture()
        let slots = model.settings.savedWorkspaces.shortcutSlots
        let size = NSSize(width: 780, height: 280)
        let panel = HeldMatrixPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        var pinned = false
        panel.contentView = HeldMatrixHostingView(rootView: SavedWorkspaceMatrix(model: model, keepOpen: {
            pinned = true; panel.acceptsKeyboard = true; NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
        }).frame(width: size.width, height: size.height))
        panel.center(); panel.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(300))
        let grip = try frame(XCTUnwrap(element("workspace-reorder-setup-0", in: panel)))
        try await moveMouse(from: grip, to: frame(XCTUnwrap(element("workspace-header-setup-2", in: panel))))
        XCTAssertTrue(pinned)
        XCTAssertTrue(panel.isVisible)
        XCTAssertNotEqual(model.settings.contextPlan.contexts.first?.id, "setup-0")
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, slots)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan.contexts.first?.id, "setup-0")
        try capture(panel, name: "quick-matrix-reorder")
    }

    func testPointerChangesOnSettingsAndNonactivatingMatrix() async throws {
        try requireNative()
        let model = fixture()
        let window = makeWindow(model, size: NSSize(width: 1040, height: 760), dark: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        let outside = NSRect(x: window.frame.minX - 20, y: window.frame.midY, width: 1, height: 1)
        try await moveMouse(from: outside, to: frame(XCTUnwrap(element("composer-source-display-0-0", in: window))), dragging: false)
        XCTAssertEqual(NSCursor.current, .openHand)
        try await moveMouse(from: outside, to: frame(XCTUnwrap(element("composer-cell-setup-0-display-0", in: window))), dragging: false)
        XCTAssertEqual(NSCursor.current, .pointingHand)
        window.orderOut(nil)

        let size = NSSize(width: 780, height: 280)
        let panel = HeldMatrixPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        panel.contentView = HeldMatrixHostingView(rootView: SavedWorkspaceMatrix(model: model).frame(width: size.width, height: size.height))
        panel.center(); panel.orderFrontRegardless(); NSApp.deactivate()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(panel.isKeyWindow)
        let before = NSRect(x: panel.frame.minX - 20, y: panel.frame.midY, width: 1, height: 1)
        try await moveMouse(from: before, to: frame(XCTUnwrap(element("workspace-select-setup-0", in: panel))), dragging: false)
        XCTAssertEqual(NSCursor.current, .pointingHand)
        try await moveMouse(from: before, to: frame(XCTUnwrap(element("workspace-reorder-setup-0", in: panel))), dragging: false)
        XCTAssertEqual(NSCursor.current, .openHand)
    }

    func testHorizontalScrollKeepsTitlesAlignedWithTheirCells() async throws {
        try requireNative()
        let window = makeWindow(fixture(contexts: 8), size: NSSize(width: 840, height: 620), dark: true)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        var horizontal: [NSScrollView] = []
        func inspect(_ view: NSView) {
            if let scroll = view as? NSScrollView,
               (scroll.documentView?.bounds.width ?? 0) > scroll.contentView.bounds.width + 100 { horizontal.append(scroll) }
            view.subviews.forEach(inspect)
        }
        inspect(try XCTUnwrap(window.contentView))
        let scroll = try XCTUnwrap(horizontal.min { $0.convert($0.bounds, to: nil).midY < $1.convert($1.bounds, to: nil).midY })
        for (x, id) in [(900.0, "setup-6"), (0.0, "setup-0")] {
            scroll.contentView.scroll(to: NSPoint(x: x, y: 0)); scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(200))
            let header = try frame(XCTUnwrap(element("composer-header-" + id, in: window)))
            let cell = try frame(XCTUnwrap(element("composer-cell-" + id + "-display-0", in: window)))
            XCTAssertEqual(header.midX, cell.midX, accuracy: 1)
            XCTAssertTrue(window.frame.contains(NSPoint(x: header.midX, y: header.midY)))
            if x > 0 { try capture(window, name: "composer-scrolled-dark") }
        }
    }

}
