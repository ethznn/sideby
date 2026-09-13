import XCTest
import SidebyCore
import SidebySystem
@testable import SidebyApp

@MainActor final class WorkspaceNameRefreshTests: XCTestCase {
    private func model() -> SidebyAppModel {
        var settings = AppSettings.default
        settings.contextPlan = .init(contexts: [
            .init(id: "a", order: 1, name: "Context 1", displaySpaceIndexes: ["main": 0]),
            .init(id: "b", order: 2, name: "My review", displaySpaceIndexes: ["main": 1]),
            .init(id: "c", order: 3, name: "데스크탑 3", displaySpaceIndexes: ["main": 2])
        ], currentContextID: "a")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["main"], selectedDisplaySpaces: {
            [.init(displayID: "main", spaceCount: 3, currentSpaceIndex: 0)]
        }, postEventAccessGranted: false)
        model.workspaceSpaceIDsOverride = { ["main": [11, 12, 13]] }
        model.workspaceNameSuggestionProvider = Names(value: ["main": [0: "Code", 1: "GitHub", 2: "Docs"]])
        return model
    }

    func testRefreshNamesInactiveDesktopsAndPreservesCustomNameAndMapping() {
        let model = model()
        let mappings = model.settings.contextPlan.contexts.map(\.displaySpaceIndexes)
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), ["Code", "My review", "Docs"])
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.displaySpaceIndexes), mappings)
        XCTAssertEqual(model.workspaceDesktopNames["main"]?[1], "GitHub")
        XCTAssertEqual(model.workspaceNameRefreshCount, 2)
    }

    func testRefreshUpdatesAutomaticNamesButNeverReplacesExplicitDefaultLookingName() {
        let model = model()
        XCTAssertTrue(model.refreshWorkspaceList())
        model.setContextName(contextID: "c", name: "Context 3")
        model.workspaceNameSuggestionProvider = Names(value: ["main": [0: "New code", 2: "New docs"]])
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), ["New code", "My review", "Context 3"])
        model.workspaceNameSuggestionProvider = Names(value: [:])
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts.first?.name, "New code")
    }

    func testNamesBelongToDisplayAndDesktopAndFollowMatrixAssignment() {
        let model = model()
        model.displayLayout = .init(displays: [
            .init(id: "main", name: "Mac", isPrimary: true, isBuiltin: true),
            .init(id: "external", name: "Monitor", isPrimary: false, isBuiltin: false)
        ])
        model.selectedDisplayIDs = ["main", "external"]
        model.workspaceObservationOverride = {
            .init(displays: [.init(displayID: "main", spaceCount: 3, currentSpaceIndex: 0),
                             .init(displayID: "external", spaceCount: 2, currentSpaceIndex: 0)],
                  spaceIDsByDisplayID: ["main": [11, 12, 13], "external": [21, 22]])
        }
        model.workspaceNameSuggestionProvider = Names(value: ["main": [0: "Code", 1: "Review", 2: "Notes"],
                                                            "external": [0: "API docs", 1: "Preview"]])
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts[0].spaceIndex(for: "external"), 0)
        XCTAssertEqual(model.workspaceDesktopName(displayID: "main", spaceIndex: 0), "Code")
        XCTAssertEqual(model.workspaceDesktopName(displayID: "external", spaceIndex: 0), "API docs")
        XCTAssertEqual(model.settings.contextPlan.contexts[0].name, "Code / API docs")
        XCTAssertTrue(model.assignWorkspaceDesktop(displayID: "external", spaceIndex: 1, toContextID: "a"))
        XCTAssertEqual(model.settings.contextPlan.contexts[0].name, "Code / Preview")
        XCTAssertEqual(model.settings.contextPlan.contexts[1].name, "My review")
        XCTAssertTrue(model.assignWorkspaceDesktop(displayID: "main", spaceIndex: 0, toContextID: "c"))
        XCTAssertEqual(model.settings.contextPlan.contexts[2].name, "Code")
    }

    func testDragSwapsSpaceNamesAndUpdatesOnlyAutomaticWorkspaceNames() {
        let model = model()
        model.displayLayout = .init(displays: [.init(id: "main", name: "Mac", isPrimary: true, isBuiltin: true)])
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertTrue(model.dropWorkspaceDesktop(.init(sourceContextID: "a", displayID: "main", spaceIndex: 0),
            targetDisplayID: "main", targetContextID: "c", copying: false))
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), ["Docs", "My review", "Code"])
        XCTAssertEqual(model.workspaceDesktopName(displayID: "main", spaceIndex: 0), "Code")
        XCTAssertTrue(model.dropWorkspaceDesktop(.init(sourceContextID: "c", displayID: "main", spaceIndex: 0),
            targetDisplayID: "main", targetContextID: "b", copying: true))
        XCTAssertEqual(model.settings.contextPlan.contexts[1].name, "My review")
        XCTAssertEqual(model.settings.contextPlan.contexts[1].spaceIndex(for: "main"), 0)
    }

    func testCachedDesktopNamesFollowSpaceIdentityWhenOrderChanges() {
        let model = model()
        XCTAssertTrue(model.refreshWorkspaceList())
        model.workspaceSpaceIDsOverride = { ["main": [12, 11, 99]] }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.workspaceDesktopName(displayID: "main", spaceIndex: 0), "GitHub")
        XCTAssertEqual(model.workspaceDesktopName(displayID: "main", spaceIndex: 1), "Code")
        XCTAssertNil(model.workspaceDesktopName(displayID: "main", spaceIndex: 2))
        XCTAssertNil(model.workspaceDesktopName(displayID: "other", spaceIndex: 0))
    }

    func testUnchangedFieldCommitDoesNotDisableAutomaticNaming() {
        let model = model()
        model.setContextName(contextID: "a", name: "Context 1")
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts[0].name, "Code")
    }

    func testFirstSuccessfulMoveRemembersVerifiedOriginAndFailureDoesNotChangeHistory() {
        let model = model()
        let target = model.settings.contextPlan.contexts[1]
        XCTAssertTrue(model.recordWorkspaceActivation(target, succeeded: true, originContextID: "a"))
        XCTAssertEqual(model.workspaceHistory.previousContextID, "a")
        XCTAssertFalse(model.recordWorkspaceActivation(model.settings.contextPlan.contexts[2], succeeded: false, originContextID: "b"))
        XCTAssertEqual(model.workspaceHistory.currentContextID, "b")
        XCTAssertEqual(model.workspaceHistory.previousContextID, "a")
    }

    func testExplicitNameImportWorksForInactiveCustomWorkspace() {
        let model = model()
        XCTAssertTrue(model.useDesktopContentName(contextID: "b"))
        XCTAssertEqual(model.settings.contextPlan.contexts[1].name, "GitHub")
        model.isSwitching = true
        XCTAssertFalse(model.useDesktopContentName(contextID: "a"))
    }
}

private struct Names: SpaceNameSuggestionProviding {
    let value: [String: [Int: String]]
    func names(for layout: DisplayLayout, spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]] { value }
}
