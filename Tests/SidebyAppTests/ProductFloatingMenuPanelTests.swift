import AppKit
import SidebyCore
import XCTest
@testable import SidebyApp

@MainActor final class ProductFloatingMenuPanelTests: XCTestCase {
    func testSwitchRetainsVisibleWindowContentFrameAndScrollWithoutOpeningSettings() async throws {
        try requireNativeSession()
        let model = heldMatrixFixture(count: 12)
        let controller = ProductFloatingMenuPanelController(refreshModel: { _ in })
        var routes = 0
        controller.present(from: nil, model: model, actions: .init(route: { _ in routes += 1 }, quit: {}))
        let panel = try XCTUnwrap(controller.panel)
        defer { controller.close(); panel.close() }
        try await Task.sleep(for: .milliseconds(250))
        let content = try XCTUnwrap(panel.contentViewController)
        let frame = panel.frame
        let expectedWidth = min(680, (panel.screen?.visibleFrame.width ?? 680))
        XCTAssertEqual(frame.width, expectedWidth, accuracy: 1, "First open must not retain the hosting controller's narrow minimum")
        let windows = Set(NSApplication.shared.windows.map(\.windowNumber))
        let horizontal = try XCTUnwrap(scrollViews(content.view).first { $0.documentView!.bounds.width > $0.contentSize.width + 100 })
        horizontal.contentView.scroll(to: NSPoint(x: 160, y: 0))
        horizontal.reflectScrolledClipView(horizontal.contentView)
        let offset = horizontal.contentView.bounds.origin
        XCTAssertGreaterThan(offset.x, 0)

        for succeeded in [true, false] {
            model.workspaceSwitchTargetName = "Review"
            model.isSwitching = true
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(panel.isVisible, "Switching must never order the menu out")
            XCTAssertEqual(panel.frame, frame)
            model.lastWorkspaceSwitchSucceeded = succeeded
            model.workspaceHistory.recordSuccessfulVisit(contextID: "work-0")
            model.workspaceHistory.recordSuccessfulVisit(contextID: "work-1")
            model.verifiedCurrentWorkspaceID = succeeded ? "work-1" : nil
            model.isSwitching = false
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertTrue(panel.isVisible, "Both success and failure leave the same menu visible")
            XCTAssertTrue(panel.contentViewController === content)
            XCTAssertEqual(panel.frame, frame)
            XCTAssertEqual(horizontal.contentView.bounds.origin, offset)
            XCTAssertEqual(Set(NSApplication.shared.windows.map(\.windowNumber)), windows)
            XCTAssertEqual(routes, 0, "A transition must not route to Settings or onboarding")
        }
    }

    func testExplicitCloseDuringSwitchIsNotUndoneByCompletion() async throws {
        try requireNativeSession()
        let model = heldMatrixFixture()
        let controller = ProductFloatingMenuPanelController(refreshModel: { _ in })
        controller.present(from: nil, model: model, actions: .init(route: { _ in XCTFail("Unexpected navigation") }, quit: {}))
        let panel = try XCTUnwrap(controller.panel)
        defer { controller.close(); panel.close() }
        try await Task.sleep(for: .milliseconds(150))
        model.isSwitching = true
        try await Task.sleep(for: .milliseconds(50))
        panel.cancelOperation(nil)
        XCTAssertFalse(panel.isVisible)
        model.lastWorkspaceSwitchSucceeded = false
        model.isSwitching = false
        // The former fallback would reopen the menu after 1.15 seconds.
        try await Task.sleep(for: .milliseconds(1300))
        XCTAssertFalse(panel.isVisible)
    }

    private func requireNativeSession() throws {
        guard ProcessInfo.processInfo.environment["SIDEBY_NATIVE_EVIDENCE"] == "1" else {
            throw XCTSkip("Opt-in menu window lifecycle verification")
        }
    }

    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
    }
}
