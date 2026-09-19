import Foundation
import XCTest
import SidebyCore
import SidebySystem
@testable import SidebyApp

@MainActor final class WorkspaceRebuildTests: XCTestCase {
    private func observation(_ keys: [String], current: Int = 0, handles: [UInt64]? = nil) -> WorkspaceLayoutObservation {
        .init(displays: [.init(displayID: "main", spaceCount: keys.count, currentSpaceIndex: current)],
              spaceIDsByDisplayID: ["main": handles ?? keys.map { UInt64($0.utf8.first!) }],
              spaceKeysByDisplayID: ["main": keys])
    }

    private func model() -> SidebyAppModel {
        var settings = AppSettings.default
        settings.language = .korean
        settings.contextPlan = .init(contexts: [
            .init(id: "a", order: 1, name: "My build", displaySpaceIndexes: ["main": 1, "offline": 0]),
            .init(id: "offline", order: 2, name: "Desk", displaySpaceIndexes: ["offline": 1]),
            .init(id: "b", order: 3, name: "My review", displaySpaceIndexes: ["main": 1]),
            .init(id: "c", order: 4, name: "Notes", displaySpaceIndexes: ["main": 0])
        ], currentContextID: "c")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["main"],
                                   selectedDisplaySpaces: { nil }, postEventAccessGranted: false)
        model.workspaceObservationOverride = { self.observation(["A", "B", "C", "D"]) }
        model.workspaceNameSuggestionProvider = Names()
        return model
    }

    func testRebuildCreatesFourOrderedWorkspacesWithFreshNamesAndRetainsOfflineMappings() throws {
        let model = model()
        let proposal = try XCTUnwrap(model.prepareWorkspaceRebuild())
        let previous = model.settings.contextPlan
        XCTAssertEqual(proposal.count, 4)
        XCTAssertTrue(model.rebuildWorkspaces(proposal))
        let active = model.settings.contextPlan.contexts.filter { $0.displayIDs.contains("main") }
        XCTAssertEqual(active.count, 4)
        XCTAssertEqual(active.map { $0.spaceIndex(for: "main") }, [0, 1, 2, 3])
        XCTAssertEqual(active.map(\.name), ["Editor", "Browser", "데스크탑 3", "데스크탑 4"])
        XCTAssertTrue(Set(active.map(\.id)).isDisjoint(with: previous.contexts.map(\.id)))
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "a" }?.displaySpaceIndexes, ["offline": 0])
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "offline" }?.name, "Desk")
        XCTAssertEqual(model.workspaceKeyboardPlan.contexts.map(\.id), active.map(\.id))
        XCTAssertEqual(model.workspaceRebuildBackup?.plan, previous)
    }

    func testCancelPreparationDoesNotRebuildOrCreateBackup() throws {
        let model = model()
        model.refreshWorkspaceStatus()
        let saved = model.settings.contextPlan
        XCTAssertNotNil(model.prepareWorkspaceRebuild())
        XCTAssertEqual(model.settings.contextPlan, saved)
        XCTAssertNil(model.workspaceRebuildBackup)
    }

    func testRebuildRejectsChangedTopologyAndChangedAssignmentsAfterConfirmationWasOpened() throws {
        let model = model()
        let proposal = try XCTUnwrap(model.prepareWorkspaceRebuild())
        model.workspaceObservationOverride = { self.observation(["B", "A", "C", "D"]) }
        let saved = model.settings.contextPlan
        XCTAssertFalse(model.rebuildWorkspaces(proposal))
        XCTAssertEqual(model.settings.contextPlan, saved)
        XCTAssertNil(model.workspaceRebuildBackup)
        let fresh = try XCTUnwrap(model.prepareWorkspaceRebuild())
        model.updateContextPlan { _ = $0.assignDisplaySpace(displayID: "main", spaceIndex: 2, toContextID: "a") }
        XCTAssertFalse(model.rebuildWorkspaces(fresh))
    }

    func testUndoRestoresNamesAndSharedAssignmentsByIdentityAfterReorder() throws {
        let model = model()
        let proposal = try XCTUnwrap(model.prepareWorkspaceRebuild())
        let before = model.settings.contextPlan
        XCTAssertTrue(model.rebuildWorkspaces(proposal))
        model.workspaceObservationOverride = { self.observation(["B", "D", "A", "C"], current: 2) }
        XCTAssertTrue(model.restoreWorkspaceRebuildBackup())
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), before.contexts.map(\.id))
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), before.contexts.map(\.name))
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "a" }?.spaceIndex(for: "main"), 0)
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "b" }?.spaceIndex(for: "main"), 0)
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "c" }?.spaceIndex(for: "main"), 2)
        XCTAssertNil(model.workspaceRebuildBackup)
    }

    func testUndoKeepsBackupAndCurrentPlanWhenRequiredDesktopWasDeleted() throws {
        let model = model()
        XCTAssertTrue(model.rebuildWorkspaces(try XCTUnwrap(model.prepareWorkspaceRebuild())))
        let saved = model.settings.contextPlan
        model.workspaceObservationOverride = { self.observation(["A", "C", "D"]) }
        XCTAssertFalse(model.restoreWorkspaceRebuildBackup())
        XCTAssertEqual(model.settings.contextPlan, saved)
        XCTAssertNotNil(model.workspaceRebuildBackup)
    }

    func testRestartRemapsSameDesktopUUIDsEvenWhenRuntimeHandlesAndOrderChange() throws {
        let suite = "SidebyTests-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let first = model()
        first.workspacePreferences = preferences
        XCTAssertTrue(first.rebuildWorkspaces(try XCTUnwrap(first.prepareWorkspaceRebuild())))
        let saved = first.settings
        let next = SidebyAppModel(testSettings: saved, selectedDisplayIDs: ["main"],
                                 selectedDisplaySpaces: { nil }, postEventAccessGranted: false)
        next.workspacePreferences = preferences
        next.loadWorkspacePersistence()
        next.workspaceObservationOverride = { self.observation(["D", "B", "A", "C"], current: 2, handles: [901, 902, 903, 904]) }
        next.refreshWorkspaceStatus()
        let active = next.settings.contextPlan.contexts.filter { $0.displayIDs.contains("main") }
        XCTAssertEqual(active.map { $0.spaceIndex(for: "main") }, [2, 1, 3, 0])
        XCTAssertEqual(next.verifiedCurrentWorkspaceID, active[0].id)
        XCTAssertNotNil(next.workspaceRebuildBackup)
        XCTAssertTrue(next.restoreWorkspaceRebuildBackup())
        XCTAssertEqual(next.settings.contextPlan.contexts.first { $0.id == "c" }?.spaceIndex(for: "main"), 2)
    }

    func testUnavailableIdentityDoesNotRebindSavedWorkspaceByNumber() throws {
        let model = model()
        model.refreshWorkspaceStatus()
        let saved = model.settings.contextPlan.contexts
        model.workspaceObservationOverride = { .init(displays: [.init(displayID: "main", spaceCount: 4, currentSpaceIndex: 0)],
                                                     spaceIDsByDisplayID: ["main": [1, 2, 3, 4]]) }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.contextPlan.contexts, saved)
        XCTAssertFalse(model.isWorkspaceAssignmentAvailable(contextID: "a"))
        XCTAssertFalse(model.admitWorkspaceActivation(saved[0], snapshot: ["main": [1, 2, 3, 4]]))
    }

    func testRebuildRefusesBusyOrIncompleteSelectedDisplayLayout() {
        let model = model()
        model.isSwitching = true
        XCTAssertNil(model.prepareWorkspaceRebuild())
        model.isSwitching = false
        model.selectedDisplayIDs = ["main", "missing"]
        XCTAssertNil(model.prepareWorkspaceRebuild())
    }

    func testNamesReadCannotApplyARebuildAfterTopologyChanges() throws {
        let model = model()
        let proposal = try XCTUnwrap(model.prepareWorkspaceRebuild())
        let saved = model.settings.contextPlan
        var reads = 0
        model.workspaceObservationOverride = {
            reads += 1
            return self.observation(reads == 1 ? ["A", "B", "C", "D"] : ["B", "A", "C", "D"])
        }
        XCTAssertFalse(model.rebuildWorkspaces(proposal))
        XCTAssertEqual(model.settings.contextPlan, saved)
        XCTAssertNil(model.workspaceRebuildBackup)
    }

    func testStaleActivationTargetIsRejectedAfterIdentityReconciliation() throws {
        let model = model()
        model.refreshWorkspaceStatus()
        let stale = try XCTUnwrap(model.settings.contextPlan.contexts.first { $0.id == "a" })
        let changed = observation(["B", "A", "C", "D"])
        model.workspaceObservationOverride = { changed }
        XCTAssertTrue(model.reconcileWorkspaceLayout(changed))
        XCTAssertFalse(model.admitWorkspaceActivation(stale, snapshot: changed.spaceIDsByDisplayID))
        let fresh = try XCTUnwrap(model.settings.contextPlan.contexts.first { $0.id == "a" })
        XCTAssertEqual(fresh.spaceIndex(for: "main"), 0)
        XCTAssertTrue(model.admitWorkspaceActivation(fresh, snapshot: changed.spaceIDsByDisplayID))
    }

    func testDamagedIdentityCacheRequiresExplicitRebuildAndDoesNotReplaceNames() throws {
        let suite = "SidebyTests-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = model()
        model.workspacePreferences = preferences
        preferences.set(Data("broken".utf8), forKey: SidebyAppModel.identitySnapshotKey)
        model.loadWorkspacePersistence()
        let saved = model.settings.contextPlan.contexts
        model.refreshWorkspaceStatus()
        model.loadWorkspaceNamesIfNeeded()
        XCTAssertEqual(model.settings.contextPlan.contexts, saved)
        XCTAssertTrue(model.workspaceIdentityNeedsReview)
        XCTAssertFalse(model.confirmWorkspaceConnections())
        XCTAssertTrue(model.rebuildWorkspaces(try XCTUnwrap(model.prepareWorkspaceRebuild())))
        XCTAssertFalse(model.workspaceIdentityNeedsReview)
        XCTAssertEqual(model.settings.contextPlan.contexts.filter { $0.displayIDs.contains("main") }.count, 4)
    }

    func testNewRebuildReplacesOnlyTheSingleUndoSnapshot() throws {
        let model = model()
        XCTAssertTrue(model.rebuildWorkspaces(try XCTUnwrap(model.prepareWorkspaceRebuild())))
        let firstRebuild = model.settings.contextPlan.contexts
        XCTAssertTrue(model.rebuildWorkspaces(try XCTUnwrap(model.prepareWorkspaceRebuild())))
        XCTAssertEqual(model.workspaceRebuildBackup?.plan.contexts, firstRebuild)
        XCTAssertTrue(model.restoreWorkspaceRebuildBackup())
        XCTAssertEqual(model.settings.contextPlan.contexts, firstRebuild)
    }

    private struct Names: SpaceNameSuggestionProviding {
        func names(for layout: DisplayLayout, spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]] {
            ["main": [0: "Editor", 1: "Browser"]]
        }
    }
}
