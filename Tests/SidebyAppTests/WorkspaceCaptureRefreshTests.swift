import XCTest
import SidebyCore
@testable import SidebyApp

final class WorkspaceCaptureRefreshTests: XCTestCase {
    func testRefreshPreservesNamesIDsAndOfflineMappingsForReview() {
        let old = [ContextDefinition(id: "custom-id", order: 1, name: "Payment", displayIDs: ["main", "offline"])]
        let discovered = [ContextDefinition(id: "context-1", order: 1, name: "Context 1", displayIDs: ["main"], displaySpaceIndexes: ["main": 1])]
        let refreshed = WorkspaceCaptureRefreshPolicy.contexts(discovered: discovered, existing: old, selectedDisplayIDs: ["main"])
        XCTAssertEqual(refreshed[0].id, "custom-id")
        XCTAssertEqual(refreshed[0].name, "Payment")
        XCTAssertEqual(refreshed[0].spaceIndex(for: "main"), 1)
        XCTAssertEqual(refreshed[0].spaceIndex(for: "offline"), 0)
    }

    func testRefreshRemovesWorkspacesWhoseOnlyDesktopNoLongerExists() {
        let old = [
            ContextDefinition(id: "a", order: 1, name: "Build", displayIDs: ["main"]),
            ContextDefinition(id: "b", order: 2, name: "Review", displayIDs: ["main"])
        ]
        let refreshed = WorkspaceCaptureRefreshPolicy.contexts(discovered: [old[0]], existing: old, selectedDisplayIDs: ["main"])
        XCTAssertEqual(refreshed.map(\.name), ["Build"])
    }

    func testNineSavedRowsBecomeTwoForTwoDesktopsAndRepeatedImportIsStable() throws {
        let old = (1...9).map { ContextDefinition(id: "saved-\($0)", order: $0, name: "Task \($0)", displayIDs: $0 == 9 ? [] : ["main"]) }
        let discovered = try XCTUnwrap(InstantContextCapturePlanner.plan(for: [.init(displayID: "main", spaceCount: 2, currentSpaceIndex: 1)])).contexts
        let refreshed = WorkspaceCaptureRefreshPolicy.contexts(discovered: discovered, existing: old, selectedDisplayIDs: ["main"])
        XCTAssertEqual(refreshed.map(\.id), ["saved-1", "saved-2"])
        XCTAssertEqual(refreshed.map(\.name), ["Task 1", "Task 2"])
        XCTAssertEqual(refreshed.map { $0.spaceIndex(for: "main") }, [0, 1])
        XCTAssertEqual(WorkspaceCaptureRefreshPolicy.contexts(discovered: discovered, existing: refreshed, selectedDisplayIDs: ["main"]), refreshed)
    }

    func testRefreshRetainsOtherDisplaysButRemovesTheirObsoleteSelectedDisplayMapping() {
        let old = [
            ContextDefinition(id: "a", order: 1, name: "Local", displayIDs: ["main"]),
            ContextDefinition(id: "b", order: 2, name: "Desk", displayIDs: ["main", "offline"])
        ]
        let refreshed = WorkspaceCaptureRefreshPolicy.contexts(discovered: [old[0]], existing: old, selectedDisplayIDs: ["main"])
        XCTAssertEqual(refreshed.map(\.name), ["Local", "Desk"])
        XCTAssertEqual(refreshed[1].displaySpaceIndexes, ["offline": 1])
    }

    @MainActor func testImportExistingSingleDisplayWorkspacesIsImmediatelyReady() throws {
        var settings = AppSettings.default
        settings.contextPlan = .init(contexts: (1...9).map {
            .init(id: "saved-\($0)", order: $0, name: "Task \($0)", displayIDs: ["main"])
        }, currentContextID: "saved-1")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["main"], selectedDisplaySpaces: {
            [.init(displayID: "main", spaceCount: 2, currentSpaceIndex: 1)]
        }, postEventAccessGranted: false)
        model.workspaceSpaceIDsOverride = { ["main": [11, 12]] }
        XCTAssertTrue(model.startInstantContextCapture())
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 2)
        XCTAssertEqual(model.workspaceConnectionStatus, .ready)
        XCTAssertEqual(model.settings.contextPlan.syncState, .synchronized)
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, "saved-2")
        XCTAssertNil(model.pendingContextCaptureAlignment)
        XCTAssertTrue(model.startInstantContextCapture())
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), ["saved-1", "saved-2"])
    }

    @MainActor func testReimportStillOffersAlignmentWhenTwoDisplaysAreOnDifferentDesktops() throws {
        var settings = AppSettings.default
        settings.contextPlan = .init(contexts: [
            .init(id: "a", order: 1, name: "Build", displayIDs: ["main", "external"]),
            .init(id: "b", order: 2, name: "Review", displayIDs: ["main", "external"])
        ], currentContextID: "a")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["main", "external"], selectedDisplaySpaces: {
            [.init(displayID: "main", spaceCount: 2, currentSpaceIndex: 1),
             .init(displayID: "external", spaceCount: 2, currentSpaceIndex: 0)]
        }, postEventAccessGranted: false)
        model.workspaceSpaceIDsOverride = { ["main": [11, 12], "external": [21, 22]] }
        XCTAssertTrue(model.startInstantContextCapture())
        let request = try XCTUnwrap(model.pendingContextCaptureAlignment)
        XCTAssertEqual(request.candidates.map(\.id), ["a", "b"])
        XCTAssertNil(model.verifiedCurrentWorkspaceID)
        XCTAssertEqual(model.settings.contextPlan.syncState, .needsSync)
        XCTAssertFalse(model.isSwitching)
    }
}
