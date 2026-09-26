import AppKit
import SidebyCore
import SidebyUI
import SwiftUI
import XCTest
@testable import SidebyApp

@MainActor final class DesktopNameEditorTests: XCTestCase {
    func testReturnAndEscapeWaitForNativeMarkedTextToFinish() {
        var text = "코드"
        var submissions = 0
        var cancellations = 0
        let field = DesktopNameTextField(text: Binding(get: { text }, set: { text = $0 }), label: "Name",
                                        submit: { submissions += 1 }, cancel: { cancellations += 1 })
        let coordinator = field.makeCoordinator()
        let control = NSTextField(string: text)
        let editor = NSTextView()
        editor.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertFalse(coordinator.control(control, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertFalse(coordinator.control(control, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(submissions, 0)
        XCTAssertEqual(cancellations, 0)
        editor.unmarkText()
        control.stringValue = "한글 이름"
        XCTAssertTrue(coordinator.control(control, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(submissions, 1)
        XCTAssertEqual(text, "한글 이름")
        XCTAssertTrue(coordinator.control(control, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(cancellations, 1)
    }

    func testRenderDesktopNamesAndEditorInBothAppearances() async throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else {
            throw XCTSkip("Opt-in desktop name editor evidence")
        }
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE_OUTPUT"]
            ?? "/tmp/sideby-desktop-names.noindex/evidence")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for korean in [false, true] {
            let model = fixture(korean: korean)
            let first = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: "main", spaceIndex: 0))
            XCTAssertEqual(model.saveDesktopName(korean ? "결제 API 구현과 테스트 🧑‍💻" : "Payment API development 🧑‍💻", target: first), .saved)
            let target = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: "main", spaceIndex: 0))
            for dark in [false, true] {
                let name = "\(korean ? "ko" : "en")-\(dark ? "dark" : "light")"
                try await render(DesktopNameEditor(model: model, target: target, dismiss: {}),
                                 name: "desktop-name-editor-" + name, size: NSSize(width: 372, height: 260),
                                 dark: dark, output: output, checksField: true)
                try await render(WorkspaceMatrixView(model: model, compact: true).padding(16),
                                 name: "desktop-name-matrix-" + name, size: NSSize(width: 800, height: 245),
                                 dark: dark, output: output)
            }
        }
    }

    private func fixture(korean: Bool) -> SidebyAppModel {
        var settings = AppSettings.default
        settings.language = korean ? .korean : .english
        settings.contextPlan = .init(contexts: [
            .init(id: "code", order: 1, name: korean ? "결제 개발" : "Payments", displaySpaceIndexes: ["main": 0]),
            .init(id: "review", order: 2, name: korean ? "PR 리뷰" : "PR review", displaySpaceIndexes: ["main": 1]),
            .init(id: "shared", order: 3, name: korean ? "고객 요청" : "Customer request", displaySpaceIndexes: ["main": 0])
        ], currentContextID: "code")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["main"], selectedDisplaySpaces: { nil }, postEventAccessGranted: false)
        model.displayLayout = .init(displays: [.init(id: "main", name: "MacBook Pro", isPrimary: true, isBuiltin: true)])
        let observation = WorkspaceLayoutObservation(displays: [.init(displayID: "main", spaceCount: 2, currentSpaceIndex: 0)],
            spaceIDsByDisplayID: ["main": [1, 2]], spaceKeysByDisplayID: ["main": [
                "uuid:11111111-1111-1111-1111-111111111111", "uuid:22222222-2222-2222-2222-222222222222"]])
        model.workspaceObservationOverride = { observation }
        model.refreshWorkspaceStatus()
        model.workspaceDesktopNames = ["main": [0: "Xcode · PaymentService.swift", 1: "GitHub · Pull requests"]]
        model.workspaceDesktopNameSpaceIDs = observation.spaceIDsByDisplayID
        return model
    }

    private func render<V: View>(_ view: V, name: String, size: NSSize, dark: Bool, output: URL, checksField: Bool = false) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(NativeSurfaceStyle.windowBackground).environment(\.colorScheme, dark ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.setFrameSize(size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        if checksField {
            func fields(_ view: NSView) -> [NSTextField] {
                (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
            }
            let input = try XCTUnwrap(fields(host).first { $0.isEditable && $0.accessibilityIdentifier() == "desktop-name-field" })
            XCTAssertFalse(input.stringValue.isEmpty)
            XCTAssertTrue(input.isSelectable)
            XCTAssertFalse(input.isHidden)
            XCTAssertGreaterThan(input.bounds.height, 18)
            XCTAssertTrue(host.bounds.contains(input.convert(input.bounds, to: host)))
            XCTAssertTrue(window.makeFirstResponder(input))
            input.selectText(nil)
            let editor = try XCTUnwrap(input.currentEditor() as? NSTextView)
            XCTAssertEqual(editor.selectedRange().length, (input.stringValue as NSString).length)
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
    }
}
