import XCTest
import SidebyCore
import SidebySystem
@testable import SidebyApp

@MainActor final class WorkspaceComposerTests: XCTestCase {
    private func observation(keys: [String] = ["mac-a", "mac-b", "mac-c"]) -> WorkspaceLayoutObservation {
        .init(displays: [.init(displayID: "mac", spaceCount: keys.count, currentSpaceIndex: 0),
                         .init(displayID: "studio", spaceCount: 3, currentSpaceIndex: 0)],
              spaceIDsByDisplayID: ["mac": keys.map { UInt64($0.utf8.last!) }, "studio": [201, 202, 203]],
              spaceKeysByDisplayID: ["mac": keys, "studio": ["studio-a", "studio-b", "studio-c"]])
    }
    private func fixture() -> SidebyAppModel {
        var settings = AppSettings.default
        settings.language = .korean
        settings.contextPlan = .init(contexts: [
            .init(id: "dev", order: 1, name: "개발", displaySpaceIndexes: ["mac": 0, "studio": 0, "offline": 4]),
            .init(id: "review", order: 2, name: "검토", displaySpaceIndexes: ["mac": 1, "studio": 1]),
            .init(id: "meeting", order: 3, name: "회의", displaySpaceIndexes: ["mac": 2, "studio": 2])
        ], currentContextID: "dev")
        settings.savedWorkspaces.initialized = true
        settings.savedWorkspaces.bookmarks = ["dev": ["mac": "mac-a", "studio": "studio-a", "offline": "offline-key"],
            "review": ["mac": "mac-b", "studio": "studio-b"], "meeting": ["mac": "mac-c", "studio": "studio-c"]]
        settings.savedWorkspaces.shortcutSlots = ["dev": 1, "review": 2, "meeting": 3]
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["mac", "studio"], selectedDisplaySpaces: { nil }, postEventAccessGranted: true)
        model.workspacePreferences = nil
        model.permissionState = .granted
        model.displayLayout = .init(displays: [.init(id: "mac", name: "MacBook", isPrimary: true, isBuiltin: true),
                                              .init(id: "studio", name: "Studio", isPrimary: false, isBuiltin: false)])
        model.workspaceObservationOverride = { self.observation() }
        model.refreshWorkspaceStatus()
        model.beginWorkspaceComposer()
        return model
    }
    func testDraftDoesNotWriteUntilSaveAndCancelRestoresEverything() throws {
        let model = fixture()
        let original = modelSnapshot(model)
        let before = model.settings
        XCTAssertTrue(model.assignWorkspaceComposer(.init(displayID: "studio", key: "studio-b"), to: "dev"))
        model.editWorkspaceComposer { $0.move("meeting", relativeTo: "dev", after: false) }
        XCTAssertTrue(model.hasWorkspaceComposerChanges)
        XCTAssertEqual(model.settings, before)
        XCTAssertFalse(model.isSwitching)
        model.undoWorkspaceComposer()
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries.map(\.id), ["dev", "review", "meeting"])
        XCTAssertTrue(model.hasWorkspaceComposerChanges)
        model.discardWorkspaceComposer()
        XCTAssertFalse(model.hasWorkspaceComposerChanges)
        XCTAssertEqual(modelSnapshot(model), original)
    }
    func testCommitFollowsIdentityThroughRenumberingAndKeepsOfflineAndShortcuts() throws {
        let model = fixture()
        XCTAssertTrue(model.assignWorkspaceComposer(.init(displayID: "mac", key: "mac-c"), to: "review"))
        model.editWorkspaceComposer { $0.move("review", relativeTo: "dev", after: false) }
        model.workspaceObservationOverride = { self.observation(keys: ["mac-c", "mac-a", "mac-b"]) }
        model.refreshWorkspaceStatus()
        XCTAssertTrue(model.commitWorkspaceComposer(), model.workspaceComposerDraft?.error ?? "")
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), ["review", "dev", "meeting"])
        XCTAssertEqual(model.settings.contextPlan.contexts[0].spaceIndex(for: "mac"), 0)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["review"]?["mac"], "mac-c")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"]?["offline"], "offline-key")
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, ["dev": 1, "review": 2, "meeting": 3])
        XCTAssertFalse(model.hasWorkspaceComposerChanges)
        model.undoWorkspaceComposer()
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), ["dev", "review", "meeting"])
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "review" }?.spaceIndex(for: "mac"), 2)
    }
    func testWrongDisplayMissingDesktopAndDisconnectedSourceAreRejected() {
        let model = fixture()
        let original = model.workspaceComposerDraft?.state
        XCTAssertFalse(model.assignWorkspaceComposer(.init(displayID: "mac", key: "mac-b"), to: "dev", displayID: "studio"))
        XCTAssertFalse(model.assignWorkspaceComposer(.init(displayID: "mac", key: "missing"), to: "dev"))
        XCTAssertFalse(model.assignWorkspaceComposer(.init(displayID: "offline", key: "offline-key"), to: "dev"))
        XCTAssertEqual(model.workspaceComposerDraft?.state, original)
        XCTAssertTrue(model.assignWorkspaceComposer(.init(displayID: "mac", key: "mac-c"), to: "review"))
        model.workspaceObservationOverride = { self.observation(keys: ["mac-a", "mac-b"]) }
        let before = model.settings
        XCTAssertFalse(model.commitWorkspaceComposer())
        XCTAssertEqual(model.settings, before)
        XCTAssertTrue(model.hasWorkspaceComposerChanges)
    }
    func testDesktopNamesUseComposerSpaceIdentityInsteadOfSavedAssignmentOrder() throws {
        let model = fixture()
        let first = "uuid:00000000-0000-0000-0000-000000000001"
        let second = "uuid:00000000-0000-0000-0000-000000000002"
        let identity = try XCTUnwrap(DesktopNameIdentity(spaceKey: first, displayID: "studio"))
        model.workspaceDesktopAliases[identity.storageKey] = "설계 자료"
        // Excluded displays can retain the old assignment order while the composer shows live Spaces.
        model.selectedDisplayIDs = ["mac"]
        model.workspaceLastObservedSpaceKeys["studio"] = [first, second]
        model.workspaceDesktopNameSpaceIDs["studio"] = [201, 202]
        model.workspaceDesktopNames["studio"] = [0: "Safari", 1: "Notes"]
        model.workspaceComposerDraft?.observation = .init(
            displays: [.init(displayID: "studio", spaceCount: 2, currentSpaceIndex: 0)],
            spaceIDsByDisplayID: ["studio": [202, 201]],
            spaceKeysByDisplayID: ["studio": [second, first]])
        XCTAssertEqual(model.workspaceComposerDesktopName(displayID: "studio", spaceIndex: 0), "Notes")
        XCTAssertEqual(model.workspaceComposerDesktopName(displayID: "studio", spaceIndex: 1), "설계 자료")
    }
    func testDesktopNameDoesNotTransferToReplacementSpaceAtSamePosition() {
        let model = fixture()
        model.workspaceDesktopNameSpaceIDs["mac"] = [97, 98, 99]
        model.workspaceDesktopNames["mac"] = [0: "이전 스페이스"]
        model.workspaceComposerDraft?.observation = observation(keys: ["mac-d", "mac-b", "mac-c"])
        XCTAssertNil(model.workspaceComposerDesktopName(displayID: "mac", spaceIndex: 0))
    }
    func testReopeningComposerRefreshesContentNamesWithoutDiscardingEdits() {
        let model = fixture()
        model.workspaceNameSuggestionProvider = ComposerNames(value: ["mac": [0: "Xcode"], "studio": [1: "Figma"]])
        model.beginWorkspaceComposer()
        XCTAssertEqual(model.workspaceComposerDesktopName(displayID: "mac", spaceIndex: 0), "Xcode")
        XCTAssertEqual(model.workspaceComposerDesktopName(displayID: "studio", spaceIndex: 1), "Figma")
        model.editWorkspaceComposer { $0.entries[0].name = "편집 중인 구성" }
        model.workspaceNameSuggestionProvider = ComposerNames(value: ["mac": [0: "Safari"], "studio": [1: "설계 문서"]])
        model.beginWorkspaceComposer()
        XCTAssertEqual(model.workspaceComposerDesktopName(displayID: "mac", spaceIndex: 0), "Safari")
        XCTAssertEqual(model.workspaceComposerDesktopName(displayID: "studio", spaceIndex: 1), "설계 문서")
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].name, "편집 중인 구성")
        XCTAssertTrue(model.hasWorkspaceComposerChanges)
    }
    func testConcurrentChangesRejectSaveButIndexRebasingDoesNotConflict() {
        let model = fixture()
        model.editWorkspaceComposer { $0.entries[0].name = "이름 초안" }
        XCTAssertTrue(model.deleteSavedWorkspace("meeting"))
        let externallyChanged = model.settings
        XCTAssertFalse(model.commitWorkspaceComposer())
        XCTAssertEqual(model.settings, externallyChanged)
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].name, "이름 초안")
    }
    func testEmptyAndDuplicateDraftsCannotSaveAndPersistedSlotsSurviveDeletion() throws {
        let model = fixture()
        let id = try XCTUnwrap(model.addWorkspaceComposer(name: "새 구성", useCurrent: false))
        XCTAssertFalse(model.commitWorkspaceComposer())
        XCTAssertTrue(model.assignWorkspaceComposer(.init(displayID: "mac", key: "mac-b"), to: id))
        XCTAssertTrue(model.assignWorkspaceComposer(.init(displayID: "studio", key: "studio-b"), to: id))
        XCTAssertFalse(model.commitWorkspaceComposer())
        model.editWorkspaceComposer { state in
            state.entries.removeAll { $0.id == "review" }; state.slots.removeValue(forKey: "review")
        }
        XCTAssertTrue(model.commitWorkspaceComposer(), model.workspaceComposerDraft?.error ?? "")
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots[id], 4)
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots["meeting"], 3)
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(model.settings))
        XCTAssertEqual(restored.savedWorkspaces.bookmarks[id], ["mac": "mac-b", "studio": "studio-b"])
    }
    func testStorageFailureRetainsDraftAndPreviousUndo() {
        let model = fixture()
        model.editWorkspaceComposer { $0.entries[0].name = "보존할 이름" }
        let before = model.settings
        model.settingsStore = ComposerRejectingStore()
        XCTAssertFalse(model.commitWorkspaceComposer())
        XCTAssertEqual(model.settings, before)
        XCTAssertEqual(model.workspaceComposerDraft?.state.entries[0].name, "보존할 이름")
    }
    func testQuickMatrixReorderIsUndoableAndDoesNotChangeShortcutOrConnections() {
        let model = fixture()
        let before = model.settings
        XCTAssertTrue(model.reorderSavedWorkspace("meeting", relativeTo: "dev", after: false))
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), ["meeting", "dev", "review"])
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, before.savedWorkspaces.shortcutSlots)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
        model.editWorkspaceComposer { $0.entries[0].name = "편집 중" }
        XCTAssertFalse(model.reorderSavedWorkspace("meeting", relativeTo: "dev", after: false))
    }
    func testReadFailureAllowsRenameOfRememberedConnectionsButCannotMakeNewConnections() {
        let model = fixture()
        model.workspaceObservationOverride = { nil }
        model.editWorkspaceComposer { $0.entries[0].name = "이름 변경" }
        XCTAssertTrue(model.commitWorkspaceComposer())
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"]?["offline"], "offline-key")
        XCTAssertFalse(model.assignWorkspaceComposer(.init(displayID: "mac", key: "mac-b"), to: "dev"))
    }
    func testRemovingLegacyMemberDoesNotReappearOnRefreshButUndoPreservesItsIdentity() {
        let model = fixture()
        model.settings.savedWorkspaces.bookmarks["dev"]?.removeValue(forKey: "studio")
        model.workspaceLegacyRuntimeBookmarks["dev"] = ["studio": 201]
        model.discardWorkspaceComposer()
        model.editWorkspaceComposer { $0.entries[0].members.removeValue(forKey: "studio") }
        XCTAssertTrue(model.commitWorkspaceComposer())
        model.refreshWorkspaceStatus()
        XCTAssertNil(model.settings.contextPlan.contexts.first { $0.id == "dev" }?.spaceIndex(for: "studio"))
        model.workspaceObservationOverride = {
            .init(displays: [.init(displayID: "mac", spaceCount: 3, currentSpaceIndex: 0),
                             .init(displayID: "studio", spaceCount: 3, currentSpaceIndex: 1)],
                  spaceIDsByDisplayID: ["mac": [97, 98, 99], "studio": [202, 201, 203]],
                  spaceKeysByDisplayID: ["mac": ["mac-a", "mac-b", "mac-c"], "studio": ["studio-b", "studio-a", "studio-c"]])
        }
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "dev" }?.spaceIndex(for: "studio"), 1)
        XCTAssertEqual(model.workspaceLegacyRuntimeBookmarks["dev"]?["studio"], 201)
    }
    func testDragPayloadRoundTripAndForeignTextRejection() {
        let value = WorkspaceComposerDrag(session: UUID(), desktop: .init(displayID: "studio", key: "space|한글"))
        XCTAssertEqual(WorkspaceComposerDrag(rawValue: value.rawValue), value)
        XCTAssertNil(WorkspaceComposerDrag(rawValue: "external text"))
        XCTAssertNil(WorkspaceComposerDrag(rawValue: WorkspaceComposerDrag(session: UUID()).rawValue))
        XCTAssertNil(WorkspaceComposerDrag(rawValue: WorkspaceComposerDrag(session: UUID(), desktop: value.desktop, contextID: "dev").rawValue))
    }
    private func modelSnapshot(_ model: SidebyAppModel) -> WorkspaceComposerState { .init(settings: model.settings) }
}
private struct ComposerRejectingStore: SettingsStoring {
    func load() -> AppSettings { .default }
    func save(_ settings: AppSettings) {}
    func saveChecked(_ settings: AppSettings) -> Bool { false }
}
private struct ComposerNames: SpaceNameSuggestionProviding {
    let value: [String: [Int: String]]
    func names(for layout: DisplayLayout, spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]] { value }
}
