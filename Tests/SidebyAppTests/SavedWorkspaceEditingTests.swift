import XCTest
import SidebyCore
@testable import SidebyApp

@MainActor final class SavedWorkspaceEditingTests: XCTestCase {
    private func fixture() -> SidebyAppModel {
        var settings = AppSettings.default
        settings.language = .korean
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["mac", "studio"], selectedDisplaySpaces: { nil }, postEventAccessGranted: true)
        model.permissionState = .granted
        model.displayLayout = .init(displays: [
            .init(id: "mac", name: "MacBook", isPrimary: true, isBuiltin: true),
            .init(id: "studio", name: "Studio", isPrimary: false, isBuiltin: false)])
        model.workspaceObservationOverride = { self.observation() }
        model.refreshWorkspaceStatus()
        return model
    }
    private func observation(mac: Int = 1, studio: Int = 2, keys: [String] = ["mac-a", "mac-b", "mac-c"]) -> WorkspaceLayoutObservation {
        .init(displays: [.init(displayID: "mac", spaceCount: keys.count, currentSpaceIndex: mac),
                         .init(displayID: "studio", spaceCount: 3, currentSpaceIndex: studio)],
              spaceIDsByDisplayID: ["mac": keys.map { UInt64($0.utf8.last ?? 0) }, "studio": [201, 202, 203]],
              spaceKeysByDisplayID: ["mac": keys, "studio": ["studio-a", "studio-b", "studio-c"]])
    }
    private func save(_ model: SidebyAppModel, name: String) throws -> String {
        model.workspaceSaveDraft = try XCTUnwrap(model.prepareWorkspaceSave())
        model.workspaceSaveDraft?.name = name
        XCTAssertTrue(model.commitWorkspaceSave(), model.workspaceSaveDraft?.error ?? "")
        model.workspaceSaveDraft = nil
        return try XCTUnwrap(model.workspaceSavedFocusID)
    }

    func testEmptyLibraryDoesNotGenerateTasksAndSaveCapturesDifferentCurrentIndexes() throws {
        let model = fixture()
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        let id = try save(model, name: "개발")
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 1)
        XCTAssertEqual(model.settings.contextPlan.contexts[0].displaySpaceIndexes, ["mac": 1, "studio": 2])
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[id], ["mac": "mac-b", "studio": "studio-c"])
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots[id], 1)
        XCTAssertNil(model.workspaceHistory.previousContextID)
        XCTAssertEqual(model.verifiedCurrentWorkspaceID, id)
    }
    func testSecondSaveAndUndoPreserveFirstWorkspaceAndHistory() throws {
        let model = fixture()
        let first = try save(model, name: "개발")
        model.workspaceHistory.recordSuccessfulVisit(contextID: first)
        let original = model.settings.contextPlan.contexts
        model.workspaceObservationOverride = { self.observation(mac: 2, studio: 0) }
        let second = try save(model, name: "리뷰")
        XCTAssertEqual(model.settings.contextPlan.contexts.first, original.first)
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots[second], 2)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan.contexts, original)
        XCTAssertNotNil(model.settings.savedWorkspaces.bookmarks[first])
        XCTAssertNil(model.settings.savedWorkspaces.bookmarks[second])
    }
    func testDuplicateRejectedAndCancelDoesNotCreateUndo() throws {
        let model = fixture()
        _ = try save(model, name: "개발")
        let undo = model.settings.savedWorkspaces.undo
        model.workspaceSaveDraft = try XCTUnwrap(model.prepareWorkspaceSave())
        model.workspaceSaveDraft?.name = "다른 이름"
        XCTAssertFalse(model.commitWorkspaceSave())
        XCTAssertNotNil(model.workspaceSaveDraft?.duplicateID)
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 1)
        model.workspaceSaveDraft = nil
        XCTAssertEqual(model.settings.savedWorkspaces.undo, undo)
    }
    func testChangedCurrentDesktopBlocksSaveWithoutLosingDraft() throws {
        let model = fixture()
        model.workspaceSaveDraft = try XCTUnwrap(model.prepareWorkspaceSave())
        model.workspaceSaveDraft?.name = "진행 중 이름"
        model.workspaceObservationOverride = { self.observation(mac: 0) }
        XCTAssertFalse(model.commitWorkspaceSave())
        XCTAssertEqual(model.workspaceSaveDraft?.name, "진행 중 이름")
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        model.refreshWorkspaceSaveDraft()
        XCTAssertTrue(model.commitWorkspaceSave())
        XCTAssertEqual(model.settings.contextPlan.contexts[0].spaceIndex(for: "mac"), 0)
    }
    func testReorderMissingDesktopAndReplacementNeverDeleteOrRetargetSavedTask() throws {
        let model = fixture()
        let id = try save(model, name: "개발")
        model.workspaceObservationOverride = { self.observation(mac: 0, keys: ["mac-b", "mac-c", "mac-a"]) }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.contextPlan.contexts[0].spaceIndex(for: "mac"), 0)
        XCTAssertTrue(model.isWorkspaceAssignmentAvailable(contextID: id))
        model.workspaceObservationOverride = { self.observation(mac: 0, keys: ["new-space", "mac-c", "mac-a"]) }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 1)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[id]?["mac"], "mac-b")
        XCTAssertFalse(model.isWorkspaceAssignmentAvailable(contextID: id))
        XCTAssertNil(model.verifiedCurrentWorkspaceID)
    }
    func testEditOnlyOneTaskAndDeleteLastTaskToEmptyWithUndoAfterSerialization() throws {
        let model = fixture()
        let first = try save(model, name: "개발")
        model.workspaceObservationOverride = { self.observation(mac: 0, studio: 0) }
        let second = try save(model, name: "리뷰")
        let review = model.settings.contextPlan.contexts[1]
        model.workspaceSaveDraft = try XCTUnwrap(model.prepareWorkspaceSave(editingID: first))
        model.workspaceSaveDraft?.name = "집중 개발"
        model.setWorkspaceDraftDisplay("studio", included: false)
        XCTAssertTrue(model.commitWorkspaceSave())
        model.workspaceSaveDraft = nil
        XCTAssertEqual(model.settings.contextPlan.contexts[1], review)
        XCTAssertEqual(model.settings.contextPlan.contexts[0].displayIDs, ["mac"])
        XCTAssertTrue(model.deleteSavedWorkspace(second))
        XCTAssertTrue(model.deleteSavedWorkspace(first))
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        let data = try JSONEncoder().encode(model.settings)
        model.settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), [first])
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots[first], 1)
    }
    func testFailedStorageWritePreservesPlanUndoAndDraft() throws {
        let model = fixture()
        _ = try save(model, name: "개발")
        model.workspaceObservationOverride = { self.observation(mac: 0) }
        model.workspaceSaveDraft = try XCTUnwrap(model.prepareWorkspaceSave())
        model.workspaceSaveDraft?.name = "보존할 이름"
        let before = model.settings
        model.settingsStore = RejectingStore()
        XCTAssertFalse(model.commitWorkspaceSave())
        XCTAssertEqual(model.settings, before)
        XCTAssertEqual(model.workspaceSaveDraft?.name, "보존할 이름")
    }
    func testOfflineMemberSurvivesRenameAndShortcutSlotsDoNotShift() throws {
        let model = fixture()
        let first = try save(model, name: "개발")
        model.workspaceObservationOverride = { self.observation(mac: 0, studio: 0) }
        let second = try save(model, name: "리뷰")
        model.selectedDisplayIDs = ["mac"]
        model.displayLayout = .init(displays: [.init(id: "mac", name: "MacBook", isPrimary: true, isBuiltin: true)])
        model.workspaceObservationOverride = {
            let o = self.observation(mac: 0)
            return .init(displays: o.displays.filter { $0.displayID == "mac" }, spaceIDsByDisplayID: ["mac": o.spaceIDsByDisplayID["mac"]!], spaceKeysByDisplayID: ["mac": o.spaceKeysByDisplayID["mac"]!])
        }
        model.workspaceSaveDraft = try XCTUnwrap(model.prepareWorkspaceSave(editingID: first))
        model.workspaceSaveDraft?.name = "새 이름"
        XCTAssertTrue(model.commitWorkspaceSave())
        model.workspaceSaveDraft = nil
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[first]?["studio"], "studio-c")
        XCTAssertTrue(model.deleteSavedWorkspace(first))
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots[second], 2)
        XCTAssertEqual(ContextKeyboardShortcutPolicy.action(command: .activate(position: 2), contextPlan: model.settings.contextPlan,
            isSidebyEnabled: true, isSwitching: false, isCapturing: false, shortcutSlots: model.settings.savedWorkspaces.shortcutSlots), .activate(contextID: second))
    }
    func testMissingIdentityReadCannotReusePreviouslyCachedKeys() throws {
        let model = fixture()
        let id = try save(model, name: "개발")
        model.workspaceObservationOverride = {
            let o = self.observation()
            return .init(displays: o.displays, spaceIDsByDisplayID: o.spaceIDsByDisplayID)
        }
        model.refreshWorkspaceStatus()
        XCTAssertFalse(model.isWorkspaceAssignmentAvailable(contextID: id))
        XCTAssertNil(model.verifiedCurrentWorkspaceID)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[id]?["mac"], "mac-b")
    }

    func testRestartKeepsPinnedShortcutAndRebasesIdentityBeforeUndo() throws {
        let model = fixture()
        let first = try save(model, name: "개발")
        model.workspaceObservationOverride = { self.observation(mac: 0) }
        let second = try save(model, name: "리뷰")
        XCTAssertTrue(model.deleteSavedWorkspace(first))
        let restored = SidebyAppModel(testSettings: model.settings, selectedDisplayIDs: ["mac", "studio"],
            selectedDisplaySpaces: { nil }, postEventAccessGranted: true)
        restored.displayLayout = model.displayLayout
        restored.workspaceObservationOverride = { self.observation(mac: 1, keys: ["mac-c", "mac-a", "mac-b"]) }
        restored.refreshWorkspaceStatus()
        XCTAssertEqual(restored.settings.savedWorkspaces.shortcutSlots[second], 2)
        XCTAssertEqual(restored.settings.contextPlan.contexts[0].spaceIndex(for: "mac"), 1)
        XCTAssertTrue(restored.undoSavedWorkspaceChange())
        XCTAssertEqual(restored.settings.contextPlan.contexts.first { $0.id == first }?.spaceIndex(for: "mac"), 2)
        XCTAssertEqual(restored.settings.savedWorkspaces.shortcutSlots[first], 1)
    }

    func testRetryInitialIdentityReadFailureCapturesRecoveredDisplays() throws {
        let model = fixture()
        model.workspaceObservationOverride = {
            let original = self.observation()
            return .init(displays: original.displays, spaceIDsByDisplayID: original.spaceIDsByDisplayID)
        }
        model.workspaceSaveDraft = model.prepareWorkspaceSave()
        model.workspaceSaveDraft?.name = "복구할 작업"
        XCTAssertTrue(try XCTUnwrap(model.workspaceSaveDraft).members.isEmpty)
        XCTAssertNotNil(model.workspaceSaveDraft?.error)
        model.workspaceObservationOverride = { self.observation() }
        model.refreshWorkspaceSaveDraft()
        XCTAssertEqual(model.workspaceSaveDraft?.members, ["mac": 1, "studio": 2])
        XCTAssertEqual(model.workspaceSaveDraft?.name, "복구할 작업")
        XCTAssertTrue(model.commitWorkspaceSave())
    }

    func testDeleteAllIncludesOfflineWorkspacesAndRestoresEverythingAfterRestart() throws {
        let model = fixture()
        _ = try save(model, name: "개발")
        model.workspaceObservationOverride = { self.observation(mac: 0) }
        _ = try save(model, name: "리뷰")
        let contexts = model.settings.contextPlan.contexts
        let library = model.settings.savedWorkspaces
        let displaySelection = model.settings.displaySelection
        let enabled = model.isEnabled
        model.selectedDisplayIDs = []
        model.displayLayout = .init(displays: [])
        model.workspaceObservationOverride = { nil }
        let proposal = try XCTUnwrap(model.prepareDeleteAllSavedWorkspaces())
        XCTAssertTrue(model.deleteAllSavedWorkspaces(proposal))
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        XCTAssertTrue(model.settings.savedWorkspaces.bookmarks.isEmpty)
        XCTAssertTrue(model.settings.savedWorkspaces.shortcutSlots.isEmpty)
        XCTAssertEqual(model.settings.savedWorkspaces.lastIncludedDisplayIDs, library.lastIncludedDisplayIDs)
        XCTAssertEqual(model.settings.displaySelection, displaySelection)
        XCTAssertEqual(model.isEnabled, enabled)
        XCTAssertNil(model.verifiedCurrentWorkspaceID)
        XCTAssertNil(model.workspaceSavedFocusID)
        XCTAssertFalse(model.canDeleteAllSavedWorkspaces)
        XCTAssertFalse(model.deleteAllSavedWorkspaces(proposal))
        let persisted = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(model.settings))
        let restarted = SidebyAppModel(testSettings: persisted, selectedDisplayIDs: ["mac", "studio"],
            selectedDisplaySpaces: { nil }, postEventAccessGranted: true)
        restarted.workspaceObservationOverride = { self.observation(mac: 0) }
        restarted.refreshWorkspaceStatus()
        XCTAssertTrue(restarted.settings.contextPlan.contexts.isEmpty)
        XCTAssertTrue(restarted.undoSavedWorkspaceChange())
        XCTAssertEqual(restarted.settings.contextPlan.contexts, contexts)
        XCTAssertEqual(restarted.settings.savedWorkspaces.bookmarks, library.bookmarks)
        XCTAssertEqual(restarted.settings.savedWorkspaces.shortcutSlots, library.shortcutSlots)
    }

    func testDeleteAllConfirmationIsReadOnlyAndRejectsChangedList() throws {
        let model = fixture()
        _ = try save(model, name: "개발")
        let before = model.settings
        let proposal = try XCTUnwrap(model.prepareDeleteAllSavedWorkspaces())
        XCTAssertEqual(model.settings, before, "Opening or cancelling confirmation must not change settings or undo")
        model.workspaceObservationOverride = { self.observation(mac: 0) }
        _ = try save(model, name: "리뷰")
        let latest = model.settings
        XCTAssertFalse(model.deleteAllSavedWorkspaces(proposal))
        XCTAssertEqual(model.settings, latest)
        XCTAssertEqual(model.workspaceSaveMessage, model.saveCopy.deleteAllChanged)
    }

    func testDeleteAllWriteFailureAndBusyStatePreserveLibraryAndUndo() throws {
        let model = fixture()
        _ = try save(model, name: "개발")
        let proposal = try XCTUnwrap(model.prepareDeleteAllSavedWorkspaces())
        model.isSwitching = true
        XCTAssertNil(model.prepareDeleteAllSavedWorkspaces())
        XCTAssertFalse(model.deleteAllSavedWorkspaces(proposal))
        model.isSwitching = false
        model.workspaceSaveDraft = model.prepareWorkspaceSave(editingID: model.settings.contextPlan.contexts[0].id)
        XCTAssertFalse(model.canDeleteAllSavedWorkspaces)
        XCTAssertFalse(model.deleteAllSavedWorkspaces(proposal))
        model.workspaceSaveDraft = nil
        let before = model.settings
        model.settingsStore = RejectingStore()
        XCTAssertFalse(model.deleteAllSavedWorkspaces(proposal))
        XCTAssertEqual(model.settings, before)
        XCTAssertEqual(model.workspaceSaveMessage, model.saveCopy.saveFailed)
    }
}

private struct RejectingStore: SettingsStoring {
    func load() -> AppSettings { .default }
    func save(_ settings: AppSettings) {}
    func saveChecked(_ settings: AppSettings) -> Bool { false }
}
