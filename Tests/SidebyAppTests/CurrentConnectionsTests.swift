import XCTest
import SidebyCore
import SidebySystem
@testable import SidebyApp

@MainActor final class CurrentConnectionsTests: XCTestCase {
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
        return model
    }

    func testOpeningAndRefreshingPreservesExistingConnectionsNamesAndShortcuts() {
        let model = fixture()
        let before = model.settings
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, before.savedWorkspaces.shortcutSlots)
        XCTAssertFalse(model.connectCurrentDesktopOrder(), "Initialization must never replace existing work")
        XCTAssertNil(model.workspaceSaveDraft)
        XCTAssertNil(model.workspaceComposerDraft)
        XCTAssertFalse(model.isSwitching)
    }

    func testClearCreateEditRestartAndUndoAllTheWayBack() throws {
        let model = fixture()
        let original = model.settings
        XCTAssertTrue(model.removeConnections(try XCTUnwrap(model.prepareConnectionRemoval(.all))))
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: "mac-b", contextID: nil))
        let id = try XCTUnwrap(model.settings.contextPlan.contexts.first?.id)
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 1)
        XCTAssertTrue(model.setCurrentConnection(displayID: "studio", key: "studio-c", contextID: id))
        model.settings = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(model.settings))
        model.workspaceObservationOverride = { self.observation(keys: ["mac-c", "mac-b", "mac-a"]) }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.settings.savedWorkspaces.undoCount, 3)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[id], ["mac": "mac-b"])
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, original.savedWorkspaces.bookmarks)
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, original.savedWorkspaces.shortcutSlots)
        XCTAssertEqual(model.settings.contextPlan.contexts.first?.spaceIndex(for: "mac"), 2)
        XCTAssertEqual(model.settings.savedWorkspaces.undoCount, 0)
        XCTAssertFalse(model.undoSavedWorkspaceChange())
        XCTAssertFalse(model.isSwitching)
    }

    func testClearOneDisplayKeepsOtherMembersAndWorksOffline() throws {
        let model = fixture()
        let original = model.settings
        let selection = model.selectedDisplayIDs
        let proposal = try XCTUnwrap(model.prepareConnectionRemoval(.display("studio")))
        XCTAssertEqual(proposal.count, 3)
        XCTAssertTrue(model.removeConnections(proposal))
        XCTAssertTrue(model.settings.contextPlan.contexts.allSatisfy { !$0.displayIDs.contains("studio") })
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"], ["mac": "mac-a", "offline": "offline-key"])
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, original.savedWorkspaces.shortcutSlots)
        XCTAssertEqual(model.selectedDisplayIDs, selection)
        XCTAssertTrue(model.removeConnections(try XCTUnwrap(model.prepareConnectionRemoval(.display("offline")))))
        XCTAssertNil(model.settings.savedWorkspaces.bookmarks["dev"]?["offline"])
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, original.savedWorkspaces.bookmarks)
        XCTAssertFalse(model.isSwitching)
    }

    func testClearingLastDisplayRemovesColumnsAndRestoresTheirShortcuts() throws {
        let model = fixture()
        let original = model.settings
        for id in ["offline", "studio", "mac"] {
            XCTAssertTrue(model.removeConnections(try XCTUnwrap(model.prepareConnectionRemoval(.display(id)))))
        }
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        XCTAssertTrue(model.settings.savedWorkspaces.shortcutSlots.isEmpty)
        for _ in 0..<3 { XCTAssertTrue(model.undoSavedWorkspaceChange()) }
        XCTAssertEqual(model.settings.contextPlan.contexts, original.contextPlan.contexts)
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, original.savedWorkspaces.shortcutSlots)
    }

    func testOfflineCellCanBeClearedWithoutReadingOrMovingSpaces() {
        let model = fixture()
        let before = model.settings
        model.workspaceObservationOverride = { nil }
        XCTAssertTrue(model.setCurrentConnection(displayID: "offline", key: nil, contextID: "dev"))
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"], ["mac": "mac-a", "studio": "studio-a"])
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, before.savedWorkspaces.shortcutSlots)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        XCTAssertFalse(model.isSwitching)
    }

    func testRemovalConfirmationAndFailedWritesDoNotLoseEditsOrHistory() throws {
        let model = fixture()
        let stale = try XCTUnwrap(model.prepareConnectionRemoval(.display("studio")))
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: "mac-c", contextID: "dev"))
        let before = model.settings
        XCTAssertFalse(model.removeConnections(stale))
        XCTAssertEqual(model.settings, before)
        let proposal = try XCTUnwrap(model.prepareConnectionRemoval(.display("studio")))
        model.settingsStore = ConnectionRejectingStore()
        XCTAssertFalse(model.removeConnections(proposal))
        XCTAssertFalse(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings, before)
        XCTAssertEqual(model.workspaceSaveFeedbackKind, .failure)
        XCTAssertFalse(model.isSwitching)
    }

    func testSelectedConnectionsAreRemovedAndRestoredTogetherAfterReload() throws {
        let model = fixture()
        let original = model.settings
        let selectedDisplays = model.selectedDisplayIDs
        XCTAssertNil(model.prepareConnectionRemoval(.connections([])))
        XCTAssertNil(model.prepareConnectionRemoval(.connections(["unknown"])))
        let proposal = try XCTUnwrap(model.prepareConnectionRemoval(.connections(["dev", "meeting"])))
        XCTAssertEqual(proposal.count, 2)
        XCTAssertEqual(model.settings, original, "Preparing or cancelling a confirmation must not change settings")
        XCTAssertTrue(model.removeConnections(proposal))
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), ["review"])
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, ["review": 2])
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, ["review": original.savedWorkspaces.bookmarks["review"]!])
        XCTAssertEqual(model.settings.savedWorkspaces.undoCount, 1, "A batch must be one undo step")
        model.settings = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(model.settings))
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan.contexts, original.contextPlan.contexts)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, original.savedWorkspaces.bookmarks, "Offline connections must also return")
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, original.savedWorkspaces.shortcutSlots)
        XCTAssertEqual(model.selectedDisplayIDs, selectedDisplays)
        XCTAssertFalse(model.isSwitching)
    }

    func testSelectedRemovalRejectsStaleConfirmationAndFailedStorage() throws {
        let model = fixture()
        let scope = ConnectionRemovalScope.connections(["dev", "meeting"])
        let stale = try XCTUnwrap(model.prepareConnectionRemoval(scope))
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: "mac-b", contextID: "dev"))
        let before = model.settings
        XCTAssertFalse(model.removeConnections(stale))
        XCTAssertEqual(model.settings, before)
        let proposal = try XCTUnwrap(model.prepareConnectionRemoval(scope))
        model.settingsStore = ConnectionRejectingStore()
        XCTAssertFalse(model.removeConnections(proposal))
        XCTAssertEqual(model.settings, before)
        model.isSwitching = true
        XCTAssertFalse(model.removeConnections(proposal))
        XCTAssertEqual(model.settings, before)
    }

    func testSelectingAllCanReachEmptyAndCreateOneThenUndoTwice() throws {
        let model = fixture()
        let original = model.settings
        let proposal = try XCTUnwrap(model.prepareConnectionRemoval(.connections(Set(original.contextPlan.contexts.map(\.id)))))
        XCTAssertTrue(model.removeConnections(proposal))
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        XCTAssertTrue(model.settings.savedWorkspaces.bookmarks.isEmpty)
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: "mac-b", contextID: nil))
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 1)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, original.savedWorkspaces.bookmarks)
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, original.savedWorkspaces.shortcutSlots)
    }

    func testContentRefreshReadsCurrentTitlesEvenWithMissingConnectionsWithoutMutatingSettings() {
        let model = fixture()
        model.settings.savedWorkspaces.bookmarks["dev"]?["mac"] = "vanished"
        model.selectedDisplayIDs = ["mac"]
        model.workspaceDesktopNames = ["mac": [0: "Old title"]]
        model.workspaceNameSuggestionProvider = ConnectionNames()
        let before = model.settings
        model.refreshCurrentDesktopContents()
        XCTAssertEqual(model.workspaceDesktopNames["mac"]?[0], "Current document")
        XCTAssertEqual(model.workspaceDesktopNames["studio"]?[0], "Current browser")
        XCTAssertEqual(model.settings, before)
        XCTAssertFalse(model.isSwitching)
    }

    func testAutomaticRefreshUpdatesTitlesPreservesConnectionsAndThrottlesRepeatedReads() async {
        let model = fixture()
        let provider = ConnectionNameProbe()
        model.workspaceNameSuggestionProvider = provider
        let before = model.settings
        await model.refreshVisibleConnections()
        XCTAssertEqual(model.workspaceDesktopNames["mac"]?[0], "Updated document")
        XCTAssertEqual(provider.readCount, 1)
        await model.refreshVisibleConnections()
        XCTAssertEqual(provider.readCount, 1, "Two visible editors must not duplicate expensive title reads")
        XCTAssertEqual(model.settings, before)
        model.isSwitching = true
        await model.refreshVisibleConnections(force: true)
        XCTAssertEqual(provider.readCount, 1)
        model.isSwitching = false
        await model.refreshVisibleConnections(force: true)
        XCTAssertEqual(provider.readCount, 2, "An explicit retry bypasses only the time throttle")
    }

    func testAutomaticRefreshDiscardsTitlesIfSpacesChangeWhileReading() async throws {
        let model = fixture()
        let provider = ConnectionNameProbe(blocks: true)
        model.workspaceNameSuggestionProvider = provider
        model.workspaceDesktopNames = ["mac": [0: "Previous document"]]
        let refresh = Task { await model.refreshVisibleConnections() }
        defer { provider.resume.signal() }
        for _ in 0..<100 where provider.readCount == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(provider.readCount, 1)
        model.workspaceObservationOverride = { self.observation(keys: ["mac-c", "mac-a", "mac-b"]) }
        provider.resume.signal()
        await refresh.value
        XCTAssertEqual(model.workspaceDesktopNames["mac"]?[0], "Previous document")
        XCTAssertFalse(model.connectionContentRefreshInFlight)
    }

    func testClearedConnectionsStayEmptyDuringAutomaticRefreshAndCanBeUndone() async throws {
        let model = fixture()
        let before = model.settings
        let proposal = try XCTUnwrap(model.prepareDeleteAllSavedWorkspaces())
        XCTAssertTrue(model.deleteAllSavedWorkspaces(proposal, label: model.connectionCopy.clearedAll(proposal.contexts.count)))
        model.workspaceNameSuggestionProvider = ConnectionNames()
        await model.refreshVisibleConnections(force: true)
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
        XCTAssertTrue(model.settings.savedWorkspaces.bookmarks.isEmpty)
        XCTAssertEqual(model.workspaceSaveFeedbackKind, .success)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, before.savedWorkspaces.shortcutSlots)
    }

    func testOneCellEditImmediatelyPersistsKeepsOtherConnectionsAndUndoes() throws {
        let model = fixture()
        let before = model.settings
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: "mac-c", contextID: "dev"))
        XCTAssertEqual(model.workspaceSaveFeedbackKind, .success)
        XCTAssertEqual(model.workspaceSaveMessage, model.connectionCopy.updated(display: "MacBook", connection: "개발", cleared: false))
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"]?["mac"], "mac-c")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"]?["offline"], "offline-key")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["review"], before.savedWorkspaces.bookmarks["review"])
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), before.contextPlan.contexts.map(\.name))
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, before.savedWorkspaces.shortcutSlots)
        XCTAssertNil(model.workspaceComposerDraft)
        XCTAssertNil(model.workspaceSaveDraft)
        XCTAssertFalse(model.isSwitching)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
    }

    func testEmptyPlanCanConnectCurrentOrderOnceWithoutNamesOrMovingDesktops() {
        let model = fixture()
        model.settings.contextPlan = .empty
        model.settings.savedWorkspaces = .init()
        model.selectedDisplayIDs = ["mac"]
        XCTAssertTrue(model.connectCurrentDesktopOrder())
        XCTAssertEqual(model.settings.contextPlan.contexts.count, 3)
        XCTAssertEqual(model.settings.contextPlan.contexts.map { $0.spaceIndex(for: "mac") }, [0, 1, 2])
        XCTAssertTrue(model.settings.contextPlan.contexts.allSatisfy { $0.spaceIndex(for: "studio") == nil })
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks.count, 3)
        XCTAssertFalse(model.connectCurrentDesktopOrder())
        XCTAssertNil(model.workspaceSaveDraft)
        XCTAssertNil(model.workspaceComposerDraft)
        XCTAssertFalse(model.isSwitching)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertTrue(model.settings.contextPlan.contexts.isEmpty)
    }

    func testReorderedKeysResolveAtClickTimeAndMissingKeysNeverReuseAnIndex() {
        let model = fixture()
        model.workspaceObservationOverride = { self.observation(keys: ["mac-c", "mac-a", "mac-b"]) }
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: "mac-b", contextID: "dev"))
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "dev" }?.spaceIndex(for: "mac"), 2)
        let before = model.settings
        model.workspaceObservationOverride = { self.observation(keys: ["mac-c", "mac-a", "replacement"]) }
        XCTAssertFalse(model.setCurrentConnection(displayID: "mac", key: "mac-b", contextID: "dev"))
        XCTAssertEqual(model.settings, before)
        XCTAssertEqual(model.workspaceSaveMessage, model.connectionCopy.vanished)
        XCTAssertEqual(model.workspaceSaveFeedbackKind, .failure)
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: "replacement", contextID: "dev"))
        XCTAssertEqual(model.workspaceSaveFeedbackKind, .success, "A recovered edit must replace the previous warning")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"]?["mac"], "replacement")
    }

    func testNewConnectionAndClearLastMemberAreAtomicAndUndoable() throws {
        let model = fixture()
        let ids = Set(model.settings.contextPlan.contexts.map(\.id))
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: "mac-b", contextID: nil))
        let new = try XCTUnwrap(model.settings.contextPlan.contexts.first { !ids.contains($0.id) })
        XCTAssertEqual(new.displayIDs, ["mac"])
        XCTAssertTrue(model.setCurrentConnection(displayID: "studio", key: "studio-c", contextID: new.id))
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[new.id]?.count, 2)
        XCTAssertTrue(model.setCurrentConnection(displayID: "studio", key: nil, contextID: new.id))
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: nil, contextID: new.id))
        XCTAssertFalse(model.settings.contextPlan.contexts.contains { $0.id == new.id })
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[new.id]?["mac"], "mac-b")
        XCTAssertFalse(model.isSwitching)
    }

    func testReadFailureWriteFailureAndExistingDraftKeepUserWorkIntact() {
        let model = fixture()
        let before = model.settings
        model.workspaceObservationOverride = { nil }
        XCTAssertFalse(model.setCurrentConnection(displayID: "mac", key: "mac-b", contextID: "dev"))
        XCTAssertEqual(model.settings, before)
        model.workspaceObservationOverride = { self.observation() }
        model.settingsStore = ConnectionRejectingStore()
        XCTAssertFalse(model.setCurrentConnection(displayID: "mac", key: "mac-b", contextID: "dev"))
        XCTAssertEqual(model.settings, before)
        XCTAssertEqual(model.workspaceSaveMessage, model.saveCopy.saveFailed)
        XCTAssertEqual(model.workspaceSaveFeedbackKind, .failure)
        model.beginWorkspaceComposer()
        model.editWorkspaceComposer { $0.entries[0].name = "저장 전 편집" }
        let draft = model.workspaceComposerDraft?.state
        XCTAssertFalse(model.setCurrentConnection(displayID: "mac", key: "mac-b", contextID: "dev"))
        XCTAssertEqual(model.workspaceComposerDraft?.state, draft)
        XCTAssertEqual(model.settings, before)
    }

    func testDraggingOccupiedCellsSwapsOnlyThatDisplayAndUndoRestoresBoth() {
        let model = fixture()
        let before = model.settings
        XCTAssertTrue(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-a"),
            from: "dev", to: "review", expectedDestinationKey: "mac-b", copying: false))
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"]?["mac"], "mac-b")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["review"]?["mac"], "mac-a")
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "dev" }?.spaceIndex(for: "mac"), 1)
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "review" }?.spaceIndex(for: "mac"), 0)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"]?["studio"], "studio-a")
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"]?["offline"], "offline-key")
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, before.savedWorkspaces.shortcutSlots)
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), before.contextPlan.contexts.map(\.name))
        XCTAssertFalse(model.isSwitching)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
        XCTAssertNil(model.settings.savedWorkspaces.undo)
    }

    func testCopyKeepsSourceAndCanCreateANewConnection() throws {
        let model = fixture()
        let before = model.settings
        for destination in ["review", nil] as [String?] {
            XCTAssertTrue(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-a"),
                from: "dev", to: destination, expectedDestinationKey: destination == nil ? nil : "mac-b", copying: true))
            let target = try XCTUnwrap(destination ?? model.settings.contextPlan.contexts.last?.id)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[target]?["mac"], "mac-a")
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"], before.savedWorkspaces.bookmarks["dev"])
            XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots["dev"], 1)
            XCTAssertTrue(model.undoSavedWorkspaceChange())
            XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        }
    }

    func testMoveToEmptyOrNewCellClearsOnlyTheSourceMember() throws {
        let model = fixture()
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: nil, contextID: "review"))
        let before = model.settings
        for destination in ["review", nil] as [String?] {
            XCTAssertTrue(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-a"),
                from: "dev", to: destination, expectedDestinationKey: nil, copying: false))
            let target = try XCTUnwrap(destination ?? model.settings.contextPlan.contexts.last?.id)
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks[target]?["mac"], "mac-a")
            XCTAssertNil(model.settings.savedWorkspaces.bookmarks["dev"]?["mac"])
            XCTAssertNil(model.settings.contextPlan.contexts.first { $0.id == "dev" }?.spaceIndex(for: "mac"))
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"]?["studio"], "studio-a")
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks["dev"]?["offline"], "offline-key")
            XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots["dev"], 1)
            XCTAssertTrue(model.undoSavedWorkspaceChange())
            XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        }
    }

    func testMovingLastMemberRemovesEmptyConnectionAndUndoRestoresItsShortcut() throws {
        let model = fixture()
        XCTAssertTrue(model.setCurrentConnection(displayID: "mac", key: "mac-a", contextID: nil))
        let id = try XCTUnwrap(model.settings.contextPlan.contexts.last?.id)
        let before = model.settings
        XCTAssertTrue(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-a"),
            from: id, to: nil, expectedDestinationKey: nil, copying: false))
        XCTAssertFalse(model.settings.contextPlan.contexts.contains { $0.id == id })
        XCTAssertNil(model.settings.savedWorkspaces.bookmarks[id])
        XCTAssertNil(model.settings.savedWorkspaces.shortcutSlots[id])
        XCTAssertEqual(model.settings.contextPlan.contexts.count, before.contextPlan.contexts.count)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan.contexts, before.contextPlan.contexts)
        XCTAssertEqual(model.settings.savedWorkspaces.shortcutSlots, before.savedWorkspaces.shortcutSlots)
    }

    func testStaleSourceDestinationOrMissingSpaceCannotAlterEitherCell() {
        let model = fixture()
        let before = model.settings
        for copying in [false, true] {
            XCTAssertFalse(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-b"),
                from: "dev", to: "review", expectedDestinationKey: "mac-b", copying: copying))
            XCTAssertFalse(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-a"),
                from: "dev", to: "review", expectedDestinationKey: "mac-c", copying: copying))
            XCTAssertFalse(model.transferCurrentConnection(.init(displayID: "studio", key: "mac-a"),
                from: "dev", to: "review", expectedDestinationKey: "studio-b", copying: copying))
        }
        model.workspaceObservationOverride = { self.observation(keys: ["replacement", "mac-b", "mac-c"]) }
        XCTAssertFalse(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-a"),
            from: "dev", to: "review", expectedDestinationKey: "mac-b", copying: false))
        model.workspaceObservationOverride = { self.observation(keys: ["mac-a", "replacement", "mac-c"]) }
        XCTAssertFalse(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-a"),
            from: "dev", to: "review", expectedDestinationKey: "mac-b", copying: false))
        XCTAssertEqual(model.settings, before)
    }

    func testFailedTransferWriteAndSelfDropPreserveBothCellsAndUndoHistory() {
        let model = fixture()
        XCTAssertTrue(model.setCurrentConnection(displayID: "studio", key: "studio-b", contextID: "dev"))
        let before = model.settings
        XCTAssertTrue(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-a"),
            from: "dev", to: "dev", expectedDestinationKey: "mac-a", copying: false))
        XCTAssertEqual(model.settings, before)
        model.settingsStore = ConnectionRejectingStore()
        for copying in [false, true] {
            XCTAssertFalse(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-a"),
                from: "dev", to: "review", expectedDestinationKey: "mac-b", copying: copying))
            XCTAssertEqual(model.settings, before)
        }
        XCTAssertFalse(model.isSwitching)
    }

    func testSwapResolvesBothDurableKeysAfterReordering() {
        let model = fixture()
        model.workspaceObservationOverride = { self.observation(keys: ["mac-c", "mac-a", "mac-b"]) }
        XCTAssertTrue(model.transferCurrentConnection(.init(displayID: "mac", key: "mac-a"),
            from: "dev", to: "review", expectedDestinationKey: "mac-b", copying: false))
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "dev" }?.spaceIndex(for: "mac"), 2)
        XCTAssertEqual(model.settings.contextPlan.contexts.first { $0.id == "review" }?.spaceIndex(for: "mac"), 1)
    }

    func testExcludedAndDisconnectedDisplaysAreNotSilentlyEnabledOrLost() {
        let model = fixture()
        model.selectedDisplayIDs = ["mac"]
        XCTAssertTrue(model.setCurrentConnection(displayID: "studio", key: "studio-c", contextID: "dev"))
        XCTAssertEqual(model.selectedDisplayIDs, ["mac"])
        let before = model.settings
        XCTAssertFalse(model.setCurrentConnection(displayID: "offline", key: "anything", contextID: "dev"))
        XCTAssertFalse(model.setCurrentConnection(displayID: "mac", key: "mac-b", contextID: "deleted-context"))
        XCTAssertEqual(model.settings, before)
    }
}

private struct ConnectionRejectingStore: SettingsStoring {
    func load() -> AppSettings { .default }
    func save(_ settings: AppSettings) {}
    func saveChecked(_ settings: AppSettings) -> Bool { false }
}

private struct ConnectionNames: SpaceNameSuggestionProviding {
    func names(for layout: DisplayLayout, spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]] {
        ["mac": [0: "Current document"], "studio": [0: "Current browser"]]
    }
}

private final class ConnectionNameProbe: SpaceNameSuggestionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let blocks: Bool
    let resume = DispatchSemaphore(value: 0)
    init(blocks: Bool = false) { self.blocks = blocks }
    var readCount: Int { lock.withLock { count } }
    func names(for layout: DisplayLayout, spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]] {
        lock.withLock { count += 1 }
        if blocks { _ = resume.wait(timeout: .now() + 5) }
        return ["mac": [0: "Updated document"]]
    }
}
