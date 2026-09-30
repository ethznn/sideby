import AppKit
import SwiftUI
import SidebyCore
import XCTest
@testable import SidebyApp

@MainActor final class WorkspaceSaveNativeTests: XCTestCase {
    func testSaveEditorFocusCancelAndBothAppearances() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else {
            throw XCTSkip("Opt-in native workspace save interaction")
        }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"] ?? "/tmp/sideby-save-native")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let observation = WorkspaceLayoutObservation(displays: [
            .init(displayID: "mac", spaceCount: 3, currentSpaceIndex: 1),
            .init(displayID: "studio", spaceCount: 3, currentSpaceIndex: 2)],
            spaceIDsByDisplayID: ["mac": [11, 12, 13], "studio": [21, 22, 23]],
            spaceKeysByDisplayID: ["mac": ["a", "b", "c"], "studio": ["d", "e", "f"]])
        for dark in [false, true] {
            var settings = AppSettings.default
            settings.language = .korean
            let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["mac", "studio"],
                selectedDisplaySpaces: { nil }, postEventAccessGranted: true)
            model.displayLayout = .init(displays: [
                .init(id: "mac", name: "MacBook Pro", isPrimary: true, isBuiltin: true),
                .init(id: "studio", name: "Studio Display", isPrimary: false, isBuiltin: false)])
            model.workspaceObservationOverride = { observation }
            model.refreshWorkspaceStatus()
            model.workspaceSaveDraft = try XCTUnwrap(model.prepareWorkspaceSave())
            let controller = WorkspaceSaveWindowController(model: model)
            var returned = false
            controller.show(anchor: nil) { returned = true }
            let panel = try XCTUnwrap(controller.panel)
            defer { controller.finish(saved: false) }
            panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            try await Task.sleep(for: .milliseconds(250))
            let editor = try XCTUnwrap(panel.firstResponder as? NSTextView)
            XCTAssertEqual(editor.string, "구성 1")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 4))
            XCTAssertTrue(panel.isVisible)
            let host = try XCTUnwrap(panel.contentView)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("save-editor-\(dark ? "dark" : "light").png"))
            panel.performClose(nil)
            XCTAssertTrue(returned)
            XCTAssertNil(model.workspaceSaveDraft)
            XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
            XCTAssertNil(model.settings.savedWorkspaces.undo)
        }
    }
}
