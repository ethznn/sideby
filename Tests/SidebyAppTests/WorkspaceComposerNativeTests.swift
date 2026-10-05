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
    private func makeWindow(_ model: SidebyAppModel, size: NSSize, dark: Bool, contextID: String? = nil) -> NSWindow {
        let navigation = ProductUINavigation(preferences: MemoryProductUIPreferences())
        navigation.openWorkspaces(.init(pane: .workspaces, contextID: contextID))
        let host = NSHostingView(rootView: WorkspaceLibraryView(model: model, navigation: navigation, startsInOverview: true, finish: {}).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless() // Match ProductWindowCoordinator's explicit open behavior.
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
                           cancel: Bool = false, stepMilliseconds: Int = 35, hoverMilliseconds: Int = 150,
                           optionAtStart: Bool = false, optionAtDrop: Bool? = nil) async throws {
        try XCTSkipUnless(CGPreflightPostEventAccess(), "Native mouse tests require existing input-event permission")
        let screenTop = NSScreen.screens[0].frame.maxY
        let start = CGPoint(x: a.midX, y: screenTop - a.midY), end = CGPoint(x: b.midX, y: screenTop - b.midY)
        // Exercise the normal AppKit event loop, including nonactivating panels.
        // XCTest alone runs a RunLoop but does not dispatch NSApplication events.
        let feed = Task.detached {
            var optionHeld = false
            func setOption(_ down: Bool) {
                guard down != optionHeld else { return }
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 58, keyDown: down)
                event?.flags = down ? .maskAlternate : []
                event?.post(tap: .cghidEventTap)
                optionHeld = down
            }
            defer { setOption(false) }
            func post(_ type: CGEventType, point: CGPoint) {
                let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
                if optionAtStart || optionAtDrop != nil { event?.flags = optionHeld ? .maskAlternate : [] }
                event?.post(tap: .cghidEventTap)
            }
            try await Task.sleep(for: .milliseconds(150))
            setOption(optionAtStart)
            post(.mouseMoved, point: start)
            if dragging { post(.leftMouseDown, point: start) }
            try await Task.sleep(for: .milliseconds(100))
            for step in 1...24 {
                if step == 12, let optionAtDrop { setOption(optionAtDrop) }
                let t = CGFloat(step) / 24
                post(dragging ? .leftMouseDragged : .mouseMoved, point: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
                try await Task.sleep(for: .milliseconds(stepMilliseconds))
            }
            try await Task.sleep(for: .milliseconds(hoverMilliseconds))
            do { try await whileHeld?() } catch { await MainActor.run { XCTFail("Drag observation failed: \(error)") } }
            if cancel {
                CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
                CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
            }
            if dragging { post(.leftMouseUp, point: end) }
            if optionHeld {
                try await Task.sleep(for: .milliseconds(100))
                setOption(false)
            }
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

    func testDesktopDragInProductionWindow() async throws {
        try requireNative()
        let model = fixture()
        let saved = model.settings
        let navigation = ProductUINavigation(preferences: MemoryProductUIPreferences())
        let coordinator = ProductWindowCoordinator(navigation: navigation,
            settingsContent: { _ in AnyView(EmptyView()) }, onboardingContent: { _ in AnyView(EmptyView()) },
            workspaceContent: { _ in AnyView(WorkspaceLibraryView(model: model, navigation: navigation, startsInOverview: true, finish: {})) },
            closeDaily: {}, refreshState: { model.refreshWorkspaceStatus() }, onboardingWillShow: { _ in }, onboardingWillClose: {})
        coordinator.showWorkspaces()
        let window = coordinator.makeWindow(for: .workspaces)
        defer { window.close(); withExtendedLifetime(coordinator) {} }
        try await Task.sleep(for: .milliseconds(300))
        try capture(window, name: "production-drag-before")
        for (index, speed) in [(1, 35), (2, 5)] {
            try await moveMouse(from: frame(XCTUnwrap(element("composer-source-display-0-\(index)", in: window))),
                               to: frame(XCTUnwrap(element("composer-cell-setup-0-display-0", in: window))),
                               stepMilliseconds: speed, hoverMilliseconds: 0)
            XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].members["display-0"]?.key, "display-0-space-\(index)")
            XCTAssertEqual(model.settings, saved)
            XCTAssertFalse(model.isSwitching)
        }
        NSApp.deactivate()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(window.isKeyWindow)
        try await moveMouse(from: frame(XCTUnwrap(element("composer-source-display-0-3", in: window))),
                           to: frame(XCTUnwrap(element("composer-cell-setup-0-display-0", in: window))))
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].members["display-0"]?.key, "display-0-space-3",
                       "The first drag into an inactive editor must connect")
        try await moveMouse(from: frame(XCTUnwrap(element("composer-source-display-1-4", in: window))),
                           to: frame(XCTUnwrap(element("composer-header-setup-0", in: window))), whileHeld: {
            XCTAssertEqual(self.attribute(try XCTUnwrap(self.element("composer-cell-setup-0-display-1", in: window)), "AXValue") as? String, "놓으면 연결")
        })
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].members["display-1"]?.key, "display-1-space-4",
                       "Dropping on a setup title must use the desktop's own display")
        for (index, fromTitle) in [(4, true), (5, false)] {
            let card = try frame(XCTUnwrap(element("composer-source-display-0-\(index)", in: window)))
            let start = NSRect(x: card.minX + 18, y: fromTitle ? card.maxY - 13 : card.minY + 12, width: 1, height: 1)
            try await moveMouse(from: start, to: frame(XCTUnwrap(element("composer-cell-setup-0-display-0", in: window))))
            XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].members["display-0"]?.key, "display-0-space-\(index)",
                           "Dragging must start over both the card title and its desktop subtitle")
        }
        XCTAssertEqual(model.settings, saved)
        try capture(window, name: "production-drag-after")
    }

    func testSelectingASetupNeverAssignsADesktopAndViewChangesPreserveTheDraft() async throws {
        try requireNative()
        let model = fixture()
        let saved = model.settings
        let window = makeWindow(model, size: NSSize(width: 1040, height: 740), dark: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        try click(XCTUnwrap(element("composer-source-display-1-1", in: window)), window: window)
        try click(XCTUnwrap(element("composer-open-setup-0", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(model.hasWorkspaceComposerChanges, "Opening a setup after selecting a source must not connect it")
        XCTAssertNotNil(element("library-setup-setup-0", in: window))
        XCTAssertNotNil(element("composer-cell-setup-0-display-1", in: window))
        try capture(window, name: "library-focused")
        XCTAssertTrue(model.assignWorkspaceComposer(.init(displayID: "display-1", key: "display-1-space-2"), to: "setup-0"))
        let draft = model.workspaceComposerDraft?.state
        try click(XCTUnwrap(element("library-setup-setup-1", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(element("composer-cell-setup-1-display-1", in: window))
        try click(XCTUnwrap(element("library-overview", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.workspaceComposerDraft?.state, draft)
        XCTAssertEqual(model.settings, saved)
        XCTAssertFalse(model.isSwitching)
    }

    func testCreateEmptySetupStaysInMatrixAndAcceptsDesktopDrag() async throws {
        try requireNative()
        let model = fixture(contexts: 8)
        let saved = model.settings
        let window = makeWindow(model, size: NSSize(width: 840, height: 740), dark: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        try click(XCTUnwrap(element("composer-add", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(200))
        let entry = try XCTUnwrap(model.workspaceComposerDraft?.state.entries.last)
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries.count, 9)
        XCTAssertEqual(entry.name, model.saveCopy.defaultName(1))
        XCTAssertTrue(entry.members.isEmpty)
        XCTAssertNil(window.attachedSheet, "An empty column should appear without a naming dialog")
        XCTAssertNotNil(element("composer-desktop-sources", in: window))
        XCTAssertNil(element("library-setup-" + entry.id, in: window), "Keep the matrix open")
        let target = try XCTUnwrap(element("composer-cell-\(entry.id)-display-0", in: window))
        let header = try XCTUnwrap(element("composer-header-" + entry.id, in: window))
        XCTAssertTrue(window.frame.contains(try frame(target)), "Reveal an added column beyond the viewport")
        XCTAssertEqual(try frame(target).midX, try frame(header).midX, accuracy: 1)
        XCTAssertTrue((attribute(target, "AXTitle") as? String ?? "").contains("데스크탑 연결"))
        try capture(window, name: "composer-new-empty-column")
        try await moveMouse(from: frame(XCTUnwrap(element("composer-source-display-0-1", in: window))),
                           to: frame(target), whileHeld: {
            XCTAssertEqual(self.attribute(try XCTUnwrap(self.element("composer-cell-\(entry.id)-display-0", in: window)), "AXValue") as? String, "놓으면 연결")
        })
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries.last?.members["display-0"]?.key, "display-0-space-1")
        XCTAssertEqual(model.settings, saved)
        XCTAssertFalse(model.isSwitching)
        try click(XCTUnwrap(element("library-overview", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(element("composer-cell-\(entry.id)-display-0", in: window), "Switching to one setup should open the column just added")
    }

    func testFirstEmptySetupSupportsClickAssignmentAndUndoWithoutLeavingMatrix() async throws {
        try requireNative()
        let model = fixture(contexts: 0)
        let saved = model.settings
        let window = makeWindow(model, size: NSSize(width: 840, height: 740), dark: true)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        try click(XCTUnwrap(element("composer-source-display-0-1", in: window)), window: window)
        try click(XCTUnwrap(element("composer-add", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(150))
        let firstID = try XCTUnwrap(model.workspaceComposerDraft?.state.entries.first?.id)
        let target = try XCTUnwrap(element("composer-cell-\(firstID)-display-0", in: window))
        XCTAssertEqual(attribute(target, "AXValue") as? String, "연결 가능", "Adding must retain the selected source")
        try click(target, window: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries.first?.members["display-0"]?.key, "display-0-space-1")
        try click(XCTUnwrap(element("composer-add", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries.map(\.name), [model.saveCopy.defaultName(1), model.saveCopy.defaultName(2)])
        try click(XCTUnwrap(element("composer-undo", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries.map(\.id), [firstID])
        XCTAssertNotNil(element("composer-desktop-sources", in: window))
        XCTAssertNil(element("library-missing-target", in: window))
        XCTAssertEqual(model.settings, saved)
        XCTAssertFalse(model.isSwitching)
    }

    func testSavingCurrentSetupPreservesOverviewAndRevealsItsColumn() async throws {
        try requireNative()
        let model = fixture(contexts: 7)
        let window = makeWindow(model, size: NSSize(width: 840, height: 620), dark: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        var draft = try XCTUnwrap(model.prepareWorkspaceSave())
        draft.name = "새로 저장한 구성"
        model.workspaceSaveDraft = draft
        model.setWorkspaceDraftDisplay("display-0", included: false)
        XCTAssertTrue(model.commitWorkspaceSave(), model.workspaceSaveMessage ?? "")
        model.workspaceSaveDraft = nil
        try await Task.sleep(for: .milliseconds(200))
        let id = try XCTUnwrap(model.workspaceSavedFocusID)
        XCTAssertNotNil(element("composer-desktop-sources", in: window))
        XCTAssertTrue(window.frame.contains(try frame(XCTUnwrap(element("composer-header-" + id, in: window)))))
        XCTAssertFalse(model.isSwitching)
    }

    func testReturningToMatrixRevealsSelectionAndDeletingKeepsNearestSetup() async throws {
        try requireNative()
        let model = fixture(contexts: 8)
        let window = makeWindow(model, size: NSSize(width: 840, height: 620), dark: true, contextID: "setup-6")
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNotNil(element("composer-cell-setup-6-display-1", in: window))
        try click(XCTUnwrap(element("library-overview", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(150))
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try capture(window, name: "composer-return-to-selected-column")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(window.frame.contains(try frame(XCTUnwrap(element("composer-header-setup-6", in: window)))))
        XCTAssertEqual(try frame(XCTUnwrap(element("composer-header-setup-6", in: window))).midX,
                       try frame(XCTUnwrap(element("composer-cell-setup-6-display-0", in: window))).midX, accuracy: 1)
        try click(XCTUnwrap(element("library-overview", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(100))
        model.editWorkspaceComposer { state in state.entries.removeAll { $0.id == "setup-6" }; state.slots.removeValue(forKey: "setup-6") }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(element("composer-cell-setup-7-display-1", in: window))
        XCTAssertNil(element("library-missing-target", in: window))
        model.editWorkspaceComposer { state in state.entries.removeAll { $0.id == "setup-7" }; state.slots.removeValue(forKey: "setup-7") }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(element("composer-cell-setup-5-display-1", in: window))
        XCTAssertNil(element("library-missing-target", in: window))
        XCTAssertFalse(model.isSwitching)
    }

    func testOnboardingCanFinishWithOneSetupWithoutClaimingACompletedRoundTrip() async throws {
        try requireNative()
        let model = fixture(contexts: 1)
        let preferences = MemoryProductUIPreferences()
        preferences.onboardingStage = .workspaces
        let presentation = ProductOnboardingPresentation(preferences: preferences)
        var finished = 0
        let size = NSSize(width: 680, height: 600)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ProductOnboardingView(model: model, presentation: presentation,
            preferences: preferences, actions: .init(close: {}, finishToDaily: { finished += 1 },
            openInputSettings: {}, openWorkspaceSettings: { _, _ in })).frame(width: size.width, height: size.height))
        window.center(); window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        try click(XCTUnwrap(element("guide-continue", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(presentation.state.stage, .workspaces)
        XCTAssertNotNil(element("current-connections-table", in: window))
        try capture(window, name: "guide-one-connection-ready")
        XCTAssertEqual(finished, 1)
        XCTAssertTrue(preferences.didDismissOnboarding)
        XCTAssertFalse(model.firstWorkProgress.isComplete)
        XCTAssertNil(model.firstWorkProgress.originContextID)
        XCTAssertFalse(model.isSwitching)
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

    func testNativeContextTitleDragKeepsMatrixOpen() async throws {
        try requireNative()
        let model = fixture()
        let saved = model.settings
        let window = makeWindow(model, size: NSSize(width: 1040, height: 760), dark: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        try await moveMouse(from: frame(XCTUnwrap(element("composer-open-setup-0", in: window))),
                           to: frame(XCTUnwrap(element("composer-header-setup-2", in: window))))
        XCTAssertNotEqual(model.workspaceComposerDraft?.state.entries.first?.id, "setup-0")
        XCTAssertNotNil(element("composer-desktop-sources", in: window))
        XCTAssertEqual(model.workspaceComposerDraft?.state.slots["setup-0"], 1)
        XCTAssertEqual(model.settings, saved)
        XCTAssertFalse(model.isSwitching)
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

    private func connectionsWindow(_ model: SidebyAppModel, size: NSSize = .init(width: 680, height: 620), dark: Bool = false) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = NSHostingView(rootView: ProductFloatingMenuPanelView(model: model,
            actions: .init(route: { _ in XCTFail("Editing a connection must stay in this menu") }, quit: {}))
            .frame(width: size.width, height: size.height))
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true); window.orderFrontRegardless()
        return window
    }

    private func popupElement(_ id: String) throws -> (NSObject, NSWindow) {
        for window in NSApp.windows where window.isVisible {
            if let item = element(id, in: window) { return (item, window) }
        }
        XCTFail("Missing popup element: " + id)
        throw NSError(domain: "Sideby.NativeEvidence.MissingPopup", code: 1)
    }

    func testHeldEditorMovesSwapsAndOptionCopiesAtDropTime() async throws {
        try requireNative()
        let model = fixture(contexts: 2)
        let before = model.settings.savedWorkspaces.bookmarks
        let size = NSSize(width: 820, height: 680)
        let window = HeldMatrixPanel(contentRect: .init(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.acceptsKeyboard = true
        window.appearance = NSAppearance(named: .darkAqua)
        defer { window.close() }
        var switches = 0
        window.contentView = HeldMatrixHostingView(rootView: HeldWorkspaceMatrixView(model: model,
            snapshot: .init(model: model), select: { _ in switches += 1 },
            keepOpen: { window.makeKeyAndOrderFront(nil) }).frame(width: size.width, height: size.height))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(250))
        try click(XCTUnwrap(element("held-edit-connections", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(200))
        let hint = try XCTUnwrap(element("connections-drag-hint", in: window))
        XCTAssertTrue(window.frame.contains(try frame(hint)))
        try capture(window, name: "move-copy-editor-ko")
        func cell(_ context: String, _ display: String = "display-0") throws -> NSRect {
            try frame(XCTUnwrap(element("connection-cell-" + context + "-" + display, in: window)))
        }
        for (optionStart, optionEnd) in [(false, false), (true, true), (false, true), (true, false)] {
            try await moveMouse(from: cell("setup-0"), to: cell("setup-1"), whileHeld: {
                XCTAssertEqual(NSEvent.modifierFlags.contains(.option), optionEnd)
            }, optionAtStart: optionStart, optionAtDrop: optionEnd)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-1"]?["display-0"], "display-0-space-0")
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-0"],
                optionEnd ? "display-0-space-0" : "display-0-space-1", "The modifier at drop time decides copy vs swap")
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-1"], "display-1-space-0")
            try click(XCTUnwrap(element("connections-undo", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
        }
        for copying in [false, true] {
            try await moveMouse(from: cell("setup-0"), to: cell("new"), optionAtStart: copying)
            let added = try XCTUnwrap(model.settings.contextPlan.contexts.last)
            XCTAssertEqual(model.settings.contextPlan.contexts.count, 3)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[added.id], ["display-0": "display-0-space-0"])
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-0"], copying ? "display-0-space-0" : nil)
            try click(XCTUnwrap(element("connections-undo", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
        }
        for copying in [false, true] {
            try await moveMouse(from: cell("setup-0"), to: cell("setup-1", "display-1"), optionAtStart: copying)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
        }
        try await moveMouse(from: cell("setup-0"), to: cell("setup-1"), cancel: true)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
        XCTAssertEqual(switches, 0)
        XCTAssertFalse(model.isSwitching)
        XCTAssertFalse(NSEvent.modifierFlags.contains(.option))
    }

    func testHeldEditorShowsSpaceCardsAndSupportsDragClickAndUndoWithoutSwitching() async throws {
        try requireNative()
        for (english, small) in [(false, false), (true, false), (false, true)] {
            let model = fixture(displays: small ? 4 : 2, contexts: 2)
            model.settings.language = english ? .english : .korean
            let before = model.settings.savedWorkspaces.bookmarks
            let size = small ? NSSize(width: 680, height: 560) : NSSize(width: 820, height: 680)
            let window = HeldMatrixPanel(contentRect: .init(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.acceptsKeyboard = true
            window.appearance = NSAppearance(named: english ? .aqua : .darkAqua)
            defer { window.close() }
            var switches = 0
            window.contentView = HeldMatrixHostingView(rootView: HeldWorkspaceMatrixView(model: model,
                snapshot: .init(model: model), select: { _ in switches += 1 },
                keepOpen: { window.makeKeyAndOrderFront(nil) }).frame(width: size.width, height: size.height))
            window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertNil(element("connection-desktop-sources", in: window))
            try click(XCTUnwrap(element("held-edit-connections", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(250))
            let sources = try frame(XCTUnwrap(element("connection-desktop-sources", in: window)))
            let table = try frame(XCTUnwrap(element("current-connections-table", in: window)))
            XCTAssertTrue(window.frame.contains(sources), "Space cards must be visible alongside the table")
            XCTAssertTrue(window.frame.contains(table), "The table must remain visible in a small editor")
            XCTAssertGreaterThanOrEqual(sources.height, 90)
            XCTAssertGreaterThanOrEqual(table.height, 140)
            let card = try XCTUnwrap(element("connection-source-display-0-1", in: window))
            let label = try XCTUnwrap(attribute(card, "AXTitle") as? String)
            XCTAssertTrue(label.contains("Slack"))
            XCTAssertTrue(label.contains(english ? "Space · position 2" : "2번째 Space"))
            XCTAssertFalse(label.contains("데스크탑 2"))
            XCTAssertNotNil(element("connection-new-hint", in: window))
            let newCell = try XCTUnwrap(element("connection-cell-new-display-0", in: window))
            XCTAssertTrue((attribute(newCell, "AXTitle") as? String)?.contains(english ? "Drop a Space here" : "여기로 끌어 놓기") == true)
            try capture(window, name: "space-editor-\(small ? "small" : english ? "en" : "ko")")
            // Click placement rejects another display, then accepts the matching row.
            try click(card, window: window)
            if !small {
                try click(XCTUnwrap(element("connection-cell-setup-0-display-1", in: window)), window: window)
                XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
            }
            try click(XCTUnwrap(element("connection-cell-setup-0-display-0", in: window)), window: window)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-0"], "display-0-space-1")
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-1"], before["setup-0"]?["display-1"])
            try await Task.sleep(for: .milliseconds(150))
            try click(XCTUnwrap(element("connections-undo", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
            if !small {
                let source = try frame(XCTUnwrap(element("connection-source-display-1-1", in: window)))
                try await moveMouse(from: source, to: frame(XCTUnwrap(element("connection-cell-setup-0-display-0", in: window))))
                XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
                try await moveMouse(from: source, to: frame(XCTUnwrap(element("connection-cell-setup-0-display-1", in: window))))
                XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-1"], "display-1-space-1")
                XCTAssertTrue(model.undoSavedWorkspaceChange())
                try await Task.sleep(for: .milliseconds(150))
                // Dropping directly into the visible blank column creates a connection.
                // No Add button, name prompt, save dialog, or Space switch is needed.
                try await moveMouse(from: frame(card), to: frame(newCell))
                XCTAssertEqual(model.settings.contextPlan.contexts.count, 3)
                let added = try XCTUnwrap(model.settings.contextPlan.contexts.last)
                XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[added.id], ["display-0": "display-0-space-1"])
                XCTAssertTrue(model.undoSavedWorkspaceChange())
            }
            XCTAssertEqual(switches, 0)
            XCTAssertFalse(model.isSwitching)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
            try click(XCTUnwrap(element("held-finish-editing", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertNotNil(element("held-switch-table", in: window))
            XCTAssertNil(element("connection-desktop-sources", in: window))
        }
    }

    func testSettingsShowsDesktopContentsAndConnectionsTogetherAndEditsWithoutLeaving() async throws {
        try requireNative()
        for (english, small) in [(false, false), (true, false), (false, true)] {
            let model = fixture(displays: small ? 4 : 2)
            if english {
                model.settings.language = .english
                model.settings.contextPlan.replaceContexts(model.settings.contextPlan.contexts.enumerated().map { i, context in
                    .init(id: context.id, order: context.order, name: ["Development", "Design review", "Meeting", "Focus"][i], displaySpaceIndexes: context.displaySpaceIndexes)
                }, currentContextID: "setup-0")
            }
            let navigation = ProductUINavigation(preferences: MemoryProductUIPreferences())
            let size = small ? NSSize(width: 760, height: 560) : NSSize(width: 1040, height: 740)
            let window = NSWindow(contentRect: .init(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.appearance = NSAppearance(named: english ? .aqua : .darkAqua)
            window.contentView = NSHostingView(rootView: ProductSettingsView(model: model, navigation: navigation,
                canCheckForUpdates: false, actions: .init(checkForUpdates: {}, openOnboarding: {}, finishAssignmentReview: {}))
                .frame(width: size.width, height: size.height))
            window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(300))
            let sources = try frame(XCTUnwrap(element("connection-desktop-sources", in: window)))
            let table = try frame(XCTUnwrap(element("current-connections-table", in: window)))
            XCTAssertTrue(window.frame.contains(sources))
            XCTAssertTrue(window.frame.contains(table))
            XCTAssertGreaterThanOrEqual(sources.height, 90)
            XCTAssertGreaterThanOrEqual(table.height, 140)
            let current = try XCTUnwrap(element("connection-source-display-0-0", in: window))
            XCTAssertTrue((attribute(current, "AXTitle") as? String)?.contains(english ? "On screen" : "지금 보고 있음") == true)
            try capture(window, name: "connections-settings-\(small ? "small" : english ? "en" : "ko")")
            try click(XCTUnwrap(element("connection-source-display-0-2", in: window)), window: window)
            try click(XCTUnwrap(element("connection-cell-setup-0-display-0", in: window)), window: window)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-0"], "display-0-space-2")
            XCTAssertNil(model.workspaceComposerDraft)
            XCTAssertFalse(model.isSwitching)
            XCTAssertEqual(navigation.settingsRoute.pane, .workspaces)
            XCTAssertTrue(model.undoSavedWorkspaceChange())
            if !small {
                let source = try frame(XCTUnwrap(element("connection-source-display-1-1", in: window)))
                let target = try frame(XCTUnwrap(element("connection-cell-setup-0-display-1", in: window)))
                try await moveMouse(from: source, to: target)
                XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-1"], "display-1-space-1")
                XCTAssertTrue(model.undoSavedWorkspaceChange())
            }
        }
    }

    func testCurrentConnectionsMenuEditsInlineAndRemembersWithoutSaveOrNavigation() async throws {
        try requireNative()
        for english in [false, true] {
            let model = fixture()
            if english { model.settings.language = .english }
            let before = model.settings.savedWorkspaces.bookmarks
            let window = connectionsWindow(model, dark: !english)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertNotNil(element("current-connections-table", in: window))
            XCTAssertNil(element("save-current-workspace", in: window))
            XCTAssertNil(element("library-overview", in: window))
            XCTAssertNil(element("composer-save", in: window))
            try capture(window, name: "connections-menu-\(english ? "en" : "ko")")
            try click(XCTUnwrap(element("connection-cell-setup-0-display-1", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(200))
            let (choice, popup) = try popupElement("connection-choice-display-1-2")
            try capture(popup, name: "connections-choice-\(english ? "en" : "ko")")
            try click(choice, window: popup)
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-1"], "display-1-space-2")
            XCTAssertNil(model.workspaceComposerDraft)
            XCTAssertNil(model.workspaceSaveDraft)
            XCTAssertFalse(model.isSwitching)
            XCTAssertTrue(window.isVisible)
            try click(XCTUnwrap(element("connections-undo", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
        }
    }

    func testCurrentConnectionsEmptyStartAndNewColumnNeedNoNamesOrSaveDialog() async throws {
        try requireNative()
        let model = fixture(contexts: 0)
        let window = connectionsWindow(model)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        try capture(window, name: "connections-first-use")
        try click(XCTUnwrap(element("connections-start", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 7)
        XCTAssertNil(model.workspaceSaveDraft)
        XCTAssertNil(model.workspaceComposerDraft)
        try click(XCTUnwrap(element("connections-add", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(200))
        let target = try XCTUnwrap(element("connection-cell-new-display-0", in: window))
        XCTAssertTrue(window.frame.contains(try frame(target)))
        try click(target, window: window)
        try await Task.sleep(for: .milliseconds(150))
        let (choice, popup) = try popupElement("connection-choice-display-0-2")
        try click(choice, window: popup)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 8)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[model.settings.contextPlan.contexts.last!.id]?["display-0"], "display-0-space-2")
        XCTAssertNil(model.workspaceSaveDraft)
        XCTAssertFalse(model.isSwitching)
    }

    func testCurrentConnectionsDragChangesOnlyMatchingDisplayAndCanUndo() async throws {
        try requireNative()
        let model = fixture()
        let before = model.settings.savedWorkspaces.bookmarks
        let window = connectionsWindow(model)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        let source = try frame(XCTUnwrap(element("connection-cell-setup-1-display-0", in: window)))
        let target = try frame(XCTUnwrap(element("connection-cell-setup-0-display-0", in: window)))
        try await moveMouse(from: source, to: target)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["setup-0"]?["display-0"], "display-0-space-1")
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
        let wrong = try frame(XCTUnwrap(element("connection-cell-setup-0-display-1", in: window)))
        try await moveMouse(from: source, to: wrong)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
        XCTAssertFalse(model.isSwitching)
    }

    func testCurrentConnectionsShowChangedCellsAndPreserveOtherAssignments() async throws {
        try requireNative()
        let model = fixture(displays: 4, contexts: 8)
        model.selectedDisplayIDs.remove("display-3")
        let before = model.settings.savedWorkspaces.bookmarks
        let window = connectionsWindow(model, size: .init(width: 560, height: 600), dark: true)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        let original = try XCTUnwrap(model.workspaceObservationOverride?())
        model.workspaceObservationOverride = {
            var keys = original.spaceKeysByDisplayID
            keys["display-1"]?[0] = "replacement"
            return .init(displays: original.displays, spaceIDsByDisplayID: original.spaceIDsByDisplayID, spaceKeysByDisplayID: keys)
        }
        model.refreshWorkspaceStatus()
        try await Task.sleep(for: .milliseconds(200))
        let broken = try XCTUnwrap(element("connection-cell-setup-0-display-1", in: window))
        XCTAssertTrue((attribute(broken, "AXTitle") as? String)?.contains(model.connectionCopy.repair) == true)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before)
        XCTAssertEqual(model.selectedDisplayIDs.count, 3)
        try capture(window, name: "connections-changed-small")
    }

    func testMinimumWindowShowsMoreThanOneDisplayAndKeepsSaveVisible() async throws {
        try requireNative()
        for english in [false, true] {
            let model = fixture(displays: 4, contexts: 8)
            if english { model.settings.language = .english }
            let window = makeWindow(model, size: NSSize(width: 760, height: 560), dark: !english)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(300))
            let sources = try frame(XCTUnwrap(element("composer-desktop-sources", in: window)))
            let secondSource = try frame(XCTUnwrap(element("composer-source-display-1-0", in: window)))
            XCTAssertGreaterThan(sources.intersection(secondSource).height, 16, "Reveal the next display, not only a count")
            let matrix = try frame(XCTUnwrap(element("workspace-assignment-table", in: window)))
            let secondCell = try frame(XCTUnwrap(element("composer-cell-setup-0-display-1", in: window)))
            XCTAssertGreaterThan(matrix.intersection(secondCell).height, 16)
            XCTAssertTrue(window.frame.contains(try frame(XCTUnwrap(element("composer-save", in: window)))))
            try capture(window, name: "director-minimum-\(english ? "en" : "ko")")
            model.displayLayout = .init(displays: model.displayLayout.displays.enumerated().map { i, display in
                .init(id: display.id, name: display.name, isPrimary: display.isPrimary, isBuiltin: display.isBuiltin,
                      frame: .init(x: Double(i * 1920), y: 0, width: 1920, height: 1080))
            })
            model.selectedDisplayIDs.remove("display-3")
            try await Task.sleep(for: .milliseconds(150))
            try click(XCTUnwrap(element("composer-show-display-participation", in: window)), window: window)
            try await Task.sleep(for: .milliseconds(150))
            let save = try frame(XCTUnwrap(element("composer-save", in: window)))
            let table = try frame(XCTUnwrap(element("workspace-assignment-table", in: window)))
            let participation = try frame(XCTUnwrap(element("composer-display-participation", in: window)))
            XCTAssertTrue(window.frame.contains(save))
            XCTAssertTrue(table.intersection(save).isEmpty, "Expanded display settings must not overlap Save")
            XCTAssertTrue(window.frame.contains(participation))
            XCTAssertGreaterThan(participation.minY, save.maxY, "The display controls must stay above the fixed footer")
            let firstDisplay = try frame(XCTUnwrap(element("display-selection-display-0", in: window)))
            XCTAssertGreaterThan(participation.intersection(firstDisplay).height, 10, "Show actionable checkboxes immediately in a compact window")
            try capture(window, name: "director-minimum-participation-\(english ? "en" : "ko")")
        }
    }

    func testExcludedDisplayWarningAndEmptySetupActionAreVisible() async throws {
        try requireNative()
        let model = fixture(contexts: 0)
        model.beginWorkspaceComposer()
        let id = try XCTUnwrap(model.addWorkspaceComposer(name: "외부 모니터용 구성", useCurrent: false))
        let window = makeWindow(model, size: NSSize(width: 840, height: 620), dark: false, contextID: id)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(model.canUseCurrentDesktopsInWorkspaceComposer(id))
        XCTAssertNotNil(element("composer-use-current", in: window))
        let unchanged = model.workspaceComposerDraft?.state
        try click(XCTUnwrap(element("composer-use-current", in: window)), window: window)
        XCTAssertEqual(model.workspaceComposerDraft?.state, unchanged)
        try capture(window, name: "director-empty-setup")
        model.selectedDisplayIDs = ["display-0"]
        XCTAssertTrue(model.assignWorkspaceComposer(.init(displayID: "display-1", key: "display-1-space-1"), to: id))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNotNil(element("composer-excluded-notice", in: window))
        try click(XCTUnwrap(element("composer-save", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(model.hasWorkspaceComposerChanges)
        XCTAssertNotNil(element("composer-excluded-notice", in: window))
        try capture(window, name: "director-excluded-display-saved")
        try click(XCTUnwrap(element("composer-show-display-participation", in: window)), window: window)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.selectedDisplayIDs, ["display-0"], "Opening settings must not change participation")
        try capture(window, name: "director-excluded-display-settings")
    }

    func testMenuProtectsDraftAndDoesNotAdvertiseDisabledChooserShortcut() async throws {
        try requireNative()
        let model = fixture()
        XCTAssertTrue(model.reorderSavedWorkspace("setup-0", relativeTo: "setup-2", after: true))
        model.beginWorkspaceComposer()
        model.editWorkspaceComposer { $0.entries[0].name = "저장 전 이름 변경" }
        model.heldMatrixConfiguration.isEnabled = false
        let saved = model.settings.contextPlan.contexts
        let draft = model.workspaceComposerDraft?.state
        var routes = 0
        model.openWorkspaceEditor = { _ in routes += 1 }
        let controller = ProductFloatingMenuPanelController(refreshModel: { _ in })
        controller.present(from: nil, model: model, actions: .init(route: { _ in routes += 1 }, quit: {}))
        let panel = try XCTUnwrap(controller.panel)
        defer { controller.close(); panel.close() }
        try await Task.sleep(for: .milliseconds(300))
        let notice = try XCTUnwrap(element("workspace-unsaved-edit-notice", in: panel))
        let resume = try XCTUnwrap(element("workspace-resume-editing", in: panel))
        XCTAssertTrue(panel.frame.contains(try frame(notice)))
        XCTAssertTrue(panel.frame.contains(try frame(resume)))
        XCTAssertNil(element("workspace-chooser-shortcut", in: panel))
        try click(XCTUnwrap(element("connections-undo", in: panel)), window: panel)
        XCTAssertNil(element("workspace-delete-all", in: panel))
        XCTAssertEqual(model.settings.contextPlan.contexts, saved)
        XCTAssertEqual(model.workspaceComposerDraft?.state, draft)
        try click(resume, window: panel)
        XCTAssertEqual(routes, 1)
        try capture(panel, name: "director-menu-draft-protection")
    }

    func testLibraryKeyboardSaveAndUndoStayInTheEditorAndRespectTextEditing() async throws {
        try requireNative()
        let model = fixture()
        let saved = model.settings.savedWorkspaces.bookmarks
        let window = makeWindow(model, size: NSSize(width: 1040, height: 740), dark: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        // XCTest does not dispatch NSApplication activation events by itself.
        // Pump the test app's event loop before checking window-local commands.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let activation = Task.detached {
            try await Task.sleep(for: .milliseconds(250))
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
        try await activation.value
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(window.isKeyWindow)
        guard window.isKeyWindow else { return }
        func key(_ character: String, flags: NSEvent.ModifierFlags = [.command]) throws -> Bool {
            window.performKeyEquivalent(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false,
                keyCode: character == "s" ? 1 : 6)))
        }
        XCTAssertTrue(model.assignWorkspaceComposer(.init(displayID: "display-0", key: "display-0-space-2"), to: "setup-0"))
        XCTAssertTrue(try key("z"))
        XCTAssertFalse(model.hasWorkspaceComposerChanges)
        XCTAssertTrue(model.assignWorkspaceComposer(.init(displayID: "display-0", key: "display-0-space-2"), to: "setup-0"))
        XCTAssertTrue(try key("s"))
        XCTAssertFalse(model.hasWorkspaceComposerChanges)
        XCTAssertNotEqual(model.settings.savedWorkspaces.bookmarks, saved)
        XCTAssertTrue(try key("z"))
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, saved)

        XCTAssertTrue(model.assignWorkspaceComposer(.init(displayID: "display-0", key: "display-0-space-2"), to: "setup-0"))
        let draft = model.workspaceComposerDraft?.state
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        let host = try XCTUnwrap(window.contentView)
        let container = NSView(frame: host.frame)
        window.contentView = container
        container.addSubview(host)
        container.addSubview(text)
        window.makeFirstResponder(text)
        XCTAssertTrue(window.firstResponder === text)
        _ = try key("z")
        XCTAssertEqual(model.workspaceComposerDraft?.state, draft, "Text undo must not undo desktop assignments")
        window.makeFirstResponder(nil); text.removeFromSuperview()
        window.contentView = host
        _ = try key("z", flags: [.command, .shift])
        XCTAssertEqual(model.workspaceComposerDraft?.state, draft, "Redo must not trigger undo")
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet, completionHandler: nil)
        _ = try key("s")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, saved, "An attached sheet owns its keyboard input")
        window.endSheet(sheet); sheet.orderOut(nil)
        XCTAssertFalse(model.isSwitching)
    }

}
