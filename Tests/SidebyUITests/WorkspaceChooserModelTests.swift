import XCTest
import SidebyCore
@testable import SidebyUI

final class WorkspaceChooserModelTests: XCTestCase {
    func testOfflineWorkspacesDoNotConsumeVisibleShortcutNumbers() {
        let plan = ContextPlan(contexts: [
            .init(id: "offline", order: 1, name: "Desk", displayIDs: ["offline"]),
            .init(id: "a", order: 2, name: "Build", displaySpaceIndexes: ["main": 0]),
            .init(id: "b", order: 3, name: "Review", displaySpaceIndexes: ["main": 1])
        ], currentContextID: "a")
        let rows = WorkspaceChooserModel.rows(plan: plan, connectedDisplayIDs: ["main"], selectedDisplayIDs: ["main"], verifiedCurrentContextID: "a")
        XCTAssertEqual(rows.map(\.shortcut), ["⌥⇧1", "⌥⇧2"])
        let visible = WorkspaceContextVisibility.plan(plan, connectedDisplayIDs: ["main"])
        XCTAssertEqual(ContextKeyboardShortcutPolicy.action(command: .activate(position: 2), contextPlan: visible,
            isSidebyEnabled: true, isSwitching: false, isCapturing: false), .activate(contextID: "b"))
        XCTAssertEqual(visible.switchIntent(for: .next).targetContext?.id, "b")
    }
    func testRowsKeepShortcutOrderAndExposeOnlyVerifiedCurrentWorkspace() {
        let plan = ContextPlan(contexts: [
            .init(id: "development", order: 1, name: "Development", displayIDs: ["main", "external"]),
            .init(id: "review", order: 2, name: "Review", displayIDs: ["external"])
        ], currentContextID: "development")
        let rows = WorkspaceChooserModel.rows(plan: plan, connectedDisplayIDs: ["main"], selectedDisplayIDs: ["main"], verifiedCurrentContextID: nil, failedCommands: [.activate(position: 1)])
        XCTAssertEqual(rows.map(\.id), ["development"])
        XCTAssertFalse(rows[0].isCurrent)
        XCTAssertEqual(rows[0].connectedDisplayCount, 1)
        XCTAssertEqual(rows[0].totalDisplayCount, 2)
        XCTAssertTrue(rows[0].hasMoveTargets)
        XCTAssertNil(rows[0].shortcut)
        let reconnected = WorkspaceChooserModel.rows(plan: plan, connectedDisplayIDs: ["main", "external"], selectedDisplayIDs: ["main", "external"], verifiedCurrentContextID: nil)
        XCTAssertEqual(reconnected.map(\.id), ["development", "review"])
        XCTAssertEqual(reconnected[1].shortcut, "⌥⇧2")
    }

    func testUnselectedConnectedDisplaysAreNotReportedAsMoving() {
        let plan = ContextPlan(contexts: [.init(id: "work", order: 1, name: "Work", displayIDs: ["main"])], currentContextID: "work")
        let rows = WorkspaceChooserModel.rows(plan: plan, connectedDisplayIDs: ["main"], selectedDisplayIDs: [], verifiedCurrentContextID: nil)
        XCTAssertEqual(rows[0].connectedDisplayCount, 1)
        XCTAssertFalse(rows[0].hasMoveTargets)
        XCTAssertEqual(rows[0].movingDisplayCount, 0)
    }

    func testEmptyDraftsStayInEditorWithoutRenumberingRealShortcuts() {
        let plan = ContextPlan(contexts: [
            .init(id: "draft", order: 1, name: "Draft"),
            .init(id: "work", order: 2, name: "Work", displayIDs: ["main"])
        ], currentContextID: "work")
        let rows = WorkspaceChooserModel.rows(plan: plan, connectedDisplayIDs: ["main"], selectedDisplayIDs: ["main"], verifiedCurrentContextID: "work")
        XCTAssertEqual(rows.map(\.id), ["work"])
        XCTAssertEqual(rows[0].shortcut, "⌥⇧2")
    }
}
