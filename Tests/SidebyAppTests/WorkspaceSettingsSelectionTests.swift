import XCTest
@testable import SidebyApp

final class WorkspaceSettingsSelectionTests: XCTestCase {
    func testDeletedSelectionFallsBackAndExplainsMissingTarget() {
        var selection = WorkspaceSettingsSelection(selectedContextID: "review")
        selection.reconcile(contextIDs: ["build", "support"], preferredID: nil)
        XCTAssertEqual(selection.selectedContextID, "build")
        XCTAssertEqual(selection.missingContextID, "review")
    }

    func testExplicitDeepLinkOverridesSelectionAndMissingLinkDoesNotMasqueradeAsTarget() {
        var selection = WorkspaceSettingsSelection(selectedContextID: "build")
        selection.reconcile(contextIDs: ["build", "review"], preferredID: "review")
        XCTAssertEqual(selection.selectedContextID, "review")
        selection.reconcile(contextIDs: ["build", "review"], preferredID: "deleted")
        XCTAssertEqual(selection.selectedContextID, "build")
        XCTAssertEqual(selection.missingContextID, "deleted")
        selection.reconcile(contextIDs: ["build", "review"], preferredID: "review")
        XCTAssertNil(selection.missingContextID)
    }

    func testEmptyAndUnchangedListsPreserveOnlyValidSelection() {
        var selection = WorkspaceSettingsSelection(selectedContextID: "review")
        selection.reconcile(contextIDs: ["build", "review"], preferredID: nil)
        XCTAssertEqual(selection.selectedContextID, "review")
        selection.reconcile(contextIDs: [], preferredID: nil)
        XCTAssertNil(selection.selectedContextID)
        selection.reconcile(contextIDs: ["new"], preferredID: nil)
        XCTAssertEqual(selection.selectedContextID, "new")
    }

    func testRestoredTargetClearsMissingMessageWithoutChangingCurrentEditorSelection() {
        var selection = WorkspaceSettingsSelection(selectedContextID: "build")
        selection.reconcile(contextIDs: ["build"], preferredID: "review")
        selection.reconcile(contextIDs: ["build", "review"], preferredID: nil)
        XCTAssertNil(selection.missingContextID)
        XCTAssertEqual(selection.selectedContextID, "build")
    }

    @MainActor func testRepeatedEqualRoutePublishesAnExplicitSelectionRequestAgain() {
        let navigation = ProductUINavigation(preferences: MemoryProductUIPreferences())
        var selection = WorkspaceSettingsSelection()
        let subscription = navigation.$workspaceRoute.sink { route in
            selection.reconcile(contextIDs: ["build", "review"], preferredID: route.contextID)
        }
        let route = ProductSettingsRoute(pane: .workspaces, contextID: "build", displayID: "desk")
        navigation.openWorkspaces(route)
        selection.reconcile(contextIDs: ["build", "review"], preferredID: "review")
        navigation.openWorkspaces(route)
        XCTAssertEqual(selection.selectedContextID, "build")
        withExtendedLifetime(subscription) {}
    }
}
