import XCTest
import SidebyCore
@testable import SidebyApp

@MainActor
final class WorkspaceLiveRefreshTests: XCTestCase {
    private func model(_ contexts: [ContextDefinition]) -> SidebyAppModel {
        var settings = AppSettings.default
        settings.language = .korean
        settings.contextPlan = .init(contexts: contexts, currentContextID: contexts[0].id)
        return SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["main"], selectedDisplaySpaces: { nil }, postEventAccessGranted: false)
    }

    private func observation(_ ids: [UInt64], index: Int = 0) -> WorkspaceLayoutObservation {
        .init(displays: [.init(displayID: "main", spaceCount: ids.count, currentSpaceIndex: index)], spaceIDsByDisplayID: ["main": ids])
    }

    func testRefreshDoesNotCreateTasksForNewDesktops() {
        let model = model([
            .init(id: "a", order: 1, name: "개발", displaySpaceIndexes: ["main": 1, "offline": 0]),
            .init(id: "b", order: 2, name: "리뷰", displaySpaceIndexes: ["main": 0])
        ])
        model.workspaceObservationOverride = { self.observation([11, 12]) }
        model.refreshWorkspaceStatus()
        model.workspaceObservationOverride = { self.observation([11, 12, 13], index: 2) }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 2)
        XCTAssertEqual(model.settings.contextPlan.contexts[0].name, "개발")
        XCTAssertEqual(model.settings.contextPlan.contexts[0].displaySpaceIndexes, ["main": 1, "offline": 0])
        XCTAssertEqual(model.settings.contextPlan.contexts[1].displaySpaceIndexes, ["main": 0])
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), ["a", "b"])
        XCTAssertNil(model.verifiedCurrentWorkspaceID)
        let saved = model.settings.contextPlan
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.contextPlan, saved)
    }

    func testRemovingMiddleDesktopKeepsRemainingWorkspaceAttachedToItsSpace() {
        let model = model([
            .init(id: "a", order: 1, name: "개발", displayIDs: ["main"]),
            .init(id: "b", order: 2, name: "종료한 작업", displayIDs: ["main"]),
            .init(id: "c", order: 3, name: "리뷰", displayIDs: ["main"])
        ])
        model.workspaceObservationOverride = { self.observation([11, 12, 13], index: 2) }
        model.refreshWorkspaceStatus()
        model.workspaceObservationOverride = { self.observation([11, 13], index: 1) }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(model.isWorkspaceAssignmentAvailable(contextID: "b"))
        XCTAssertEqual(model.settings.contextPlan.contexts.last?.spaceIndex(for: "main"), 1)
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, "c")
    }

    func testReorderingSpacesDoesNotRelabelWorkspaces() {
        let model = model([
            .init(id: "a", order: 1, name: "개발", displayIDs: ["main"]),
            .init(id: "b", order: 2, name: "리뷰", displayIDs: ["main"])
        ])
        model.workspaceObservationOverride = { self.observation([11, 12]) }
        model.refreshWorkspaceStatus()
        model.setContextName(contextID: "a", name: "결제 개발")
        model.workspaceObservationOverride = { self.observation([12, 11], index: 1) }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, "a")
        XCTAssertEqual(model.settings.contextPlan.contexts[0].name, "결제 개발")
        XCTAssertEqual(model.settings.contextPlan.contexts[0].spaceIndex(for: "main"), 1)
    }

    func testUnreadableOrBusyRefreshPreservesSavedAssignments() {
        let model = model([.init(id: "a", order: 1, name: "개발", displayIDs: ["main"])])
        let saved = model.settings.contextPlan.contexts
        model.workspaceObservationOverride = { nil }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.contextPlan.contexts, saved)
        model.isSwitching = true
        model.workspaceObservationOverride = { self.observation([11, 12]) }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.contextPlan.contexts, saved)
    }

    func testManualRefreshPreservesUnassignedLegacyTasks() {
        let model = model([.init(id: "placeholder", order: 1, name: "Context 1")])
        model.workspaceObservationOverride = { self.observation([11, 12]) }
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), ["Context 1"])
        let saved = model.settings.contextPlan.contexts
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts, saved)
        model.workspaceObservationOverride = { nil }
        XCTAssertFalse(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts, saved)
    }

    func testAdditionalDisplayDoesNotChangeExistingMemberships() {
        let model = model([
            .init(id: "a", order: 1, name: "개발", displaySpaceIndexes: ["main": 1]),
            .init(id: "b", order: 2, name: "리뷰", displaySpaceIndexes: ["main": 0])
        ])
        model.selectedDisplayIDs = ["main", "external"]
        model.workspaceObservationOverride = {
            .init(displays: [.init(displayID: "main", spaceCount: 2, currentSpaceIndex: 1),
                             .init(displayID: "external", spaceCount: 3, currentSpaceIndex: 1)],
                  spaceIDsByDisplayID: ["main": [11, 12], "external": [21, 22, 23]])
        }
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 2)
        XCTAssertEqual(model.settings.contextPlan.contexts[0].displaySpaceIndexes, ["main": 1])
        XCTAssertEqual(model.settings.contextPlan.contexts[1].displaySpaceIndexes, ["main": 0])
    }

    func testRefreshDoesNotRecreateAnIntentionallyUnusedDesktopAfterSharing() {
        let model = model([
            .init(id: "a", order: 1, name: "개발", displaySpaceIndexes: ["main": 0]),
            .init(id: "b", order: 2, name: "리뷰", displaySpaceIndexes: ["main": 0])
        ])
        model.workspaceLastObservedSpaceIDs = ["main": [11, 12]]
        model.workspaceObservationOverride = { self.observation([11, 12]) }
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), ["a", "b"])
    }
}
