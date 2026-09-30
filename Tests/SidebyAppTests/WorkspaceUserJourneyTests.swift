import AppKit
import SwiftUI
import SidebyCore
import XCTest
@testable import SidebyApp

/// Native user journeys use isolated data and send input only to these test windows.
@MainActor final class WorkspaceUserJourneyTests: XCTestCase {
    private func requireNative() throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else {
            throw XCTSkip("Opt-in workspace user journeys")
        }
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        application.setActivationPolicy(.accessory)
        addTeardownBlock {
            await MainActor.run {
                NSApplication.shared.setActivationPolicy(previousPolicy)
                if let previousPID { NSRunningApplication(processIdentifier: previousPID)?.activate(options: []) }
            }
        }
    }
    private func observation(offline: Bool = false) -> WorkspaceLayoutObservation {
        .init(displays: [.init(displayID: "mac", spaceCount: 3, currentSpaceIndex: 1)]
            + (offline ? [] : [.init(displayID: "studio", spaceCount: 3, currentSpaceIndex: 2)]),
            spaceIDsByDisplayID: offline ? ["mac": [11, 12, 13]] : ["mac": [11, 12, 13], "studio": [21, 22, 23]],
            spaceKeysByDisplayID: offline ? ["mac": ["a", "b", "c"]] : ["mac": ["a", "b", "c"], "studio": ["d", "e", "f"]])
    }
    private func fixture() -> SidebyAppModel {
        var settings = AppSettings.default
        settings.language = .korean
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["mac", "studio"], selectedDisplaySpaces: { nil }, postEventAccessGranted: true)
        model.permissionState = .granted
        model.displayLayout = .init(displays: [
            .init(id: "mac", name: "MacBook Pro", isPrimary: true, isBuiltin: true),
            .init(id: "studio", name: "Studio Display", isPrimary: false, isBuiltin: false)])
        model.workspaceObservationOverride = { self.observation() }
        model.refreshWorkspaceStatus()
        return model
    }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(200)) }
    private func matrixWindow() throws -> NSWindow {
        try XCTUnwrap(NSApp.windows.first { $0.identifier?.rawValue == "sideby-held-workspace-matrix" && $0.isVisible })
    }
    private func click(_ window: NSWindow, x: CGFloat, fromTop y: CGFloat) throws {
        let height = try XCTUnwrap(window.contentView).bounds.height
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: height - y),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
    }
    private func key(_ window: NSWindow, code: UInt16, characters: String) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            NSApp.sendEvent(try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)))
        }
    }
    private func name(_ panel: NSWindow, _ value: String) throws {
        let editor = try XCTUnwrap(panel.firstResponder as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(value, replacementRange: editor.selectedRange())
    }
    private func scrollToTop(_ window: NSWindow) {
        func scrolls(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
        }
        guard let host = window.contentView else { return }
        for scroll in scrolls(host) {
            let y = scroll.documentView?.isFlipped == false
                ? max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height) : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    private func capture(_ window: NSWindow, _ filename: String) throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"] ?? "/tmp/sideby-user-journeys")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let host = try XCTUnwrap(window.contentView)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(filename + ".png"))
    }

    func testMatrixHidesDisconnectedDisplayAndRestoresItOnReconnectWithoutLosingSavedConnection() async throws {
        try requireNative()
        let model = fixture()
        model.workspaceSaveDraft = model.prepareWorkspaceSave()
        XCTAssertTrue(model.commitWorkspaceSave())
        model.workspaceSaveDraft = nil
        model.workspaceSaveMessage = nil
        model.settings.displaySelection = .init(hasInitialized: true, selectedDisplayIDs: ["mac", "studio"],
            knownDisplayNames: ["studio": "Studio Display"])
        let contexts = model.settings.contextPlan.contexts
        let bookmarks = model.settings.savedWorkspaces.bookmarks
        let connectedLayout = model.displayLayout
        model.displayLayout = .init(displays: connectedLayout.displays.filter { $0.id == "mac" })
        model.selectedDisplayIDs = ["mac"]
        model.workspaceObservationOverride = { self.observation(offline: true) }
        let chooser = HeldWorkspaceMatrixController(model: model)
        defer { model.workspaceSaveController?.finish(saved: false); chooser.dismiss() }
        chooser.showPersistent()
        try await settle()
        let disconnected = try matrixWindow()
        XCTAssertEqual(SavedWorkspaceMatrix(model: model).displayIDs, ["mac"], "Remembered monitors must not clutter the workspace chooser")
        XCTAssertLessThanOrEqual(disconnected.frame.height, 430, "An offline monitor must not enlarge the chooser")
        try capture(disconnected, "journey-connected-only-matrix")
        chooser.dismiss()
        model.workspaceSaveDraft = model.prepareWorkspaceSave(editingID: contexts[0].id)
        XCTAssertEqual(model.workspaceSaveDraft?.members["studio"], 2)
        XCTAssertEqual(model.workspaceSaveDraft?.bookmarks["studio"], "f")
        model.workspaceSaveDraft = nil

        model.displayLayout = connectedLayout
        model.selectedDisplayIDs = ["mac", "studio"]
        model.workspaceObservationOverride = { self.observation() }
        chooser.showPersistent()
        try await settle()
        let reconnected = try matrixWindow()
        XCTAssertEqual(SavedWorkspaceMatrix(model: model).displayIDs, ["mac", "studio"])
        XCTAssertEqual(model.settings.contextPlan.contexts, contexts)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, bookmarks)
        try capture(reconnected, "journey-reconnected-matrix")
    }

    func testFirstSaveDuplicateCancelEditAndUndoThroughNativeWindows() async throws {
        try requireNative()
        let model = fixture()
        let chooser = HeldWorkspaceMatrixController(model: model)
        defer { model.workspaceSaveController?.finish(saved: false); chooser.dismiss() }
        chooser.showPersistent()
        try await settle()
        var matrix = try matrixWindow()
        try capture(matrix, "journey-empty")
        try click(matrix, x: 120, fromTop: 130)
        try await settle()
        let save = try XCTUnwrap(model.workspaceSaveController?.panel)
        XCTAssertTrue(save.isVisible)
        XCTAssertFalse(matrix.isVisible)
        try name(save, "집중 개발")
        try key(save, code: 36, characters: "\r")
        try await settle()
        XCTAssertNil(model.workspaceSaveDraft)
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), ["집중 개발"])
        matrix = try matrixWindow()
        try capture(matrix, "journey-saved")
        try click(matrix, x: 120, fromTop: 130)
        try await settle()
        let duplicate = try XCTUnwrap(model.workspaceSaveController?.panel)
        try name(duplicate, "중복 구성")
        try key(duplicate, code: 36, characters: "\r")
        try await settle()
        XCTAssertNotNil(model.workspaceSaveDraft?.duplicateID)
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 1)
        XCTAssertTrue(duplicate.isVisible)
        try capture(duplicate, "journey-duplicate")
        try key(duplicate, code: 53, characters: "\u{1b}")
        try await settle()
        XCTAssertNil(model.workspaceSaveDraft)
        matrix = try matrixWindow()
        try click(matrix, x: 280, fromTop: 237)
        try await settle()
        let edit = try XCTUnwrap(model.workspaceSaveController?.panel)
        XCTAssertEqual(model.workspaceSaveDraft?.editingID, model.settings.contextPlan.contexts[0].id)
        try name(edit, "설계 검토")
        try key(edit, code: 36, characters: "\r")
        try await settle()
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), ["설계 검토"])
        matrix = try matrixWindow()
        try click(matrix, x: matrix.frame.width - 90, fromTop: matrix.contentView!.bounds.height - 26)
        try await settle()
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), ["집중 개발"])
        try key(matrix, code: 53, characters: "\u{1b}")
        try await settle()
        XCTAssertFalse(matrix.isVisible)
    }

    func testOfflineDisplayCanBeUncheckedAndRecheckedWithoutReopeningEditor() async throws {
        try requireNative()
        let model = fixture()
        model.workspaceSaveDraft = model.prepareWorkspaceSave()
        XCTAssertTrue(model.commitWorkspaceSave())
        model.workspaceSaveDraft = nil
        let id = model.settings.contextPlan.contexts[0].id
        model.displayLayout = .init(displays: [.init(id: "mac", name: "MacBook Pro", isPrimary: true, isBuiltin: true)])
        model.selectedDisplayIDs = ["mac"]
        model.workspaceObservationOverride = { self.observation(offline: true) }
        model.showWorkspaceSave(editingID: id)
        defer { model.workspaceSaveController?.finish(saved: false) }
        try await settle()
        let panel = try XCTUnwrap(model.workspaceSaveController?.panel)
        try click(panel, x: 48, fromTop: 291)
        try await settle()
        XCTAssertNil(model.workspaceSaveDraft?.members["studio"])
        try capture(panel, "journey-offline-unchecked")
        try click(panel, x: 48, fromTop: 291)
        try await settle()
        XCTAssertEqual(model.workspaceSaveDraft?.members["studio"], 2, "An offline display must stay available to re-include before saving")
        XCTAssertEqual(model.workspaceSaveDraft?.bookmarks["studio"], "f")
    }

    func testEmptyNameAndNoDisplaysCannotSaveAndEscapeCancels() async throws {
        try requireNative()
        let model = fixture()
        model.showWorkspaceSave()
        defer { model.workspaceSaveController?.finish(saved: false) }
        try await settle()
        let panel = try XCTUnwrap(model.workspaceSaveController?.panel)
        try name(panel, "   ")
        try key(panel, code: 36, characters: "\r")
        try await settle()
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        XCTAssertTrue(panel.isVisible)
        try name(panel, "첫 작업")
        try await settle()
        scrollToTop(panel)
        try await settle()
        try click(panel, x: 48, fromTop: 223)
        try await settle()
        try click(panel, x: 48, fromTop: 287)
        try await settle()
        XCTAssertEqual(model.workspaceSaveDraft?.members.count, 0)
        try key(panel, code: 36, characters: "\r")
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        try key(panel, code: 53, characters: "\u{1b}")
        try await settle()
        XCTAssertNil(model.workspaceSaveDraft)
        XCTAssertNil(model.settings.savedWorkspaces.undo)
    }

    func testComposingKoreanNameDoesNotSubmitOnCandidateConfirmation() async throws {
        try requireNative()
        let model = fixture()
        model.showWorkspaceSave()
        defer { model.workspaceSaveController?.finish(saved: false) }
        try await settle()
        let panel = try XCTUnwrap(model.workspaceSaveController?.panel)
        let editor = try XCTUnwrap(panel.firstResponder as? NSTextView)
        editor.selectAll(nil)
        editor.setMarkedText("한글 작업", selectedRange: NSRange(location: 5, length: 0), replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hasMarkedText())
        try key(panel, code: 36, characters: "\r")
        try await settle()
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty, "Return used to finish composition must not also save")
        XCTAssertTrue(panel.isVisible)
        editor.unmarkText()
        try key(panel, code: 36, characters: "\r")
        try await settle()
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), ["한글 작업"])
    }

    func testReadFailureRetryKeepsTypedNameAndSavesWithoutReopening() async throws {
        try requireNative()
        let model = fixture()
        model.workspaceObservationOverride = {
            let live = self.observation()
            return .init(displays: live.displays, spaceIDsByDisplayID: live.spaceIDsByDisplayID)
        }
        model.showWorkspaceSave()
        defer { model.workspaceSaveController?.finish(saved: false) }
        try await settle()
        let panel = try XCTUnwrap(model.workspaceSaveController?.panel)
        try name(panel, "읽기 복구 후 작업")
        try await settle()
        XCTAssertEqual(model.workspaceSaveDraft?.error, model.saveCopy.readUnavailable, "Typing a name cannot clear a desktop reading error")
        try capture(panel, "journey-read-failure")
        model.workspaceObservationOverride = { self.observation() }
        try click(panel, x: 100, fromTop: panel.contentView!.bounds.height - 90)
        try await settle()
        XCTAssertEqual(model.workspaceSaveDraft?.members.count, 2)
        XCTAssertEqual(model.workspaceSaveDraft?.name, "읽기 복구 후 작업")
        try key(panel, code: 36, characters: "\r")
        try await settle()
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), ["읽기 복구 후 작업"])
    }

    func testDeleteAllConfirmationDefaultsToCancelAndPreservesData() async throws {
        try requireNative()
        let model = fixture()
        model.workspaceSaveDraft = model.prepareWorkspaceSave()
        XCTAssertTrue(model.commitWorkspaceSave())
        model.workspaceSaveDraft = nil
        let original = model.settings.contextPlan.contexts
        let chooser = HeldWorkspaceMatrixController(model: model)
        defer { chooser.dismiss() }
        chooser.showPersistent()
        try await settle()
        let matrix = try matrixWindow()
        try click(matrix, x: matrix.frame.width - 100, fromTop: 171)
        try await settle()
        func findCancel(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.title == model.saveCopy.cancel { return button }
            return view.subviews.lazy.compactMap(findCancel).first
        }
        let cancel = try XCTUnwrap(NSApp.windows.filter(\.isVisible).lazy.compactMap { $0.contentView.flatMap(findCancel) }.first)
        let confirmation = try XCTUnwrap(cancel.window)
        XCTAssertEqual(confirmation.defaultButtonCell?.title, model.saveCopy.cancel)
        try capture(confirmation, "journey-delete-confirmation")
        // XCTest's alert has no WindowServer key window. Verify the actual
        // default button and its action; physical Enter needs a launched-app check.
        cancel.performClick(nil)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(model.settings.contextPlan.contexts, original)
        XCTAssertFalse(confirmation.isVisible)
        XCTAssertTrue(matrix.isVisible)
    }

    func testPersistentMatrixDismissesWhenClickingAnotherSidebyWindow() async throws {
        try requireNative()
        let model = fixture()
        let chooser = HeldWorkspaceMatrixController(model: model)
        defer { chooser.dismiss() }
        chooser.showPersistent()
        try await settle()
        let matrix = try matrixWindow()
        let settings = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 350, height: 250),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        defer { settings.close() }
        settings.makeKeyAndOrderFront(nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 100),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: settings.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.sendEvent(event)
        }
        try await settle()
        XCTAssertFalse(matrix.isVisible, "An outside click in Sideby's own settings also dismisses the transient chooser")
    }
}
