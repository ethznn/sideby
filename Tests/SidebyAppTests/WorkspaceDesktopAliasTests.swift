import XCTest
import SidebyCore
import SidebySystem
@testable import SidebyApp

@MainActor final class WorkspaceDesktopAliasTests: XCTestCase {
    private let displayID = "uuid:AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    private let keys = (1...5).map { "uuid:00000000-0000-0000-0000-00000000000\($0)" }

    private func observation(_ order: [Int] = [0, 1, 2, 3], offset: UInt64 = 10) -> WorkspaceLayoutObservation {
        .init(displays: [.init(displayID: displayID, spaceCount: order.count, currentSpaceIndex: 0)],
              spaceIDsByDisplayID: [displayID: order.map { offset + UInt64($0) }],
              spaceKeysByDisplayID: [displayID: order.map { keys[$0] }])
    }

    private func model() -> SidebyAppModel {
        var settings = AppSettings.default
        settings.contextPlan = .init(contexts: (0..<4).map {
            .init(id: "c\($0)", order: $0 + 1, name: "Desktop \($0 + 1)", displaySpaceIndexes: [displayID: $0])
        }, currentContextID: "c0")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: [displayID], selectedDisplaySpaces: { nil }, postEventAccessGranted: false)
        model.displayLayout = .init(displays: [.init(id: displayID, name: "Mac", isPrimary: true, isBuiltin: true)])
        let initial = observation()
        model.workspaceObservationOverride = { initial }
        model.workspaceNameSuggestionProvider = AliasTestNames(value: [displayID: [0: "Editor", 1: "Browser", 2: "Docs", 3: "Chat"]])
        XCTAssertTrue(model.refreshWorkspaceList())
        return model
    }

    @discardableResult private func rename(_ name: String, index: Int, model: SidebyAppModel) throws -> DesktopNameEditTarget {
        let target = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: displayID, spaceIndex: index))
        XCTAssertEqual(model.saveDesktopName(name, target: target), .saved)
        return target
    }

    func testSharedDesktopChangesEveryReferenceButNotWorkspaceNames() throws {
        let model = model()
        XCTAssertTrue(model.assignWorkspaceDesktop(displayID: displayID, spaceIndex: 0, toContextID: "c1"))
        let names = model.settings.contextPlan.contexts.map(\.name)
        let target = try rename("결제 코드", index: 0, model: model)
        XCTAssertEqual(target.sharedCount, 2)
        XCTAssertEqual(model.workspaceDesktopName(displayID: displayID, spaceIndex: 0), "결제 코드")
        XCTAssertEqual(model.workspaceDesktopNames[displayID]?[0], "Editor")
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.name), names)
        XCTAssertEqual(model.workspaceDesktopName(displayID: displayID, spaceIndex: 0), "결제 코드")
        XCTAssertEqual(model.workspaceDesktopChoices(displayID: displayID).first?.spaceIndex, 0)
    }

    func testMoveSwapCopyAndRemoveDoNotChangeDesktopNames() throws {
        let model = model()
        try rename("개발", index: 0, model: model)
        try rename("리뷰", index: 1, model: model)
        XCTAssertTrue(model.dropWorkspaceDesktop(.init(sourceContextID: "c0", displayID: displayID, spaceIndex: 0),
            targetDisplayID: displayID, targetContextID: "c1", copying: false))
        XCTAssertEqual(model.settings.contextPlan.contexts[0].spaceIndex(for: displayID), 1)
        XCTAssertEqual(model.workspaceDesktopName(displayID: displayID, spaceIndex: 1), "리뷰")
        XCTAssertTrue(model.assignWorkspaceDesktop(displayID: displayID, spaceIndex: nil, toContextID: "c2"))
        XCTAssertTrue(model.dropWorkspaceDesktop(.init(sourceContextID: "c1", displayID: displayID, spaceIndex: 0),
            targetDisplayID: displayID, targetContextID: "c2", copying: true))
        XCTAssertEqual(model.settings.contextPlan.contexts[2].spaceIndex(for: displayID), 0)
        XCTAssertTrue(model.assignWorkspaceDesktop(displayID: displayID, spaceIndex: nil, toContextID: "c1"))
        XCTAssertTrue(model.assignWorkspaceDesktop(displayID: displayID, spaceIndex: nil, toContextID: "c2"))
        XCTAssertEqual(model.desktopAlias(displayID: displayID, spaceIndex: 0), "개발")
    }

    func testEditingTracksOriginalDesktopDuringReorderAndAfterRuntimeIDsChange() throws {
        let model = model()
        let target = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: displayID, spaceIndex: 0))
        let changed = observation([2, 1, 3, 0], offset: 200)
        model.workspaceObservationOverride = { changed }
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.saveDesktopName("코드", target: target), .saved)
        XCTAssertEqual(model.settings.contextPlan.contexts[0].spaceIndex(for: displayID), 3)
        XCTAssertEqual(model.workspaceDesktopName(displayID: displayID, spaceIndex: 3), "코드")
        XCTAssertNil(model.desktopAlias(displayID: displayID, spaceIndex: 0))
    }

    func testOpeningEditorAfterUnobservedReorderTargetsSavedCellIdentity() throws {
        let model = model()
        let changed = observation([1, 0, 2, 3])
        model.workspaceObservationOverride = { changed }
        let target = try rename("원래 첫 화면", index: 0, model: model)
        XCTAssertEqual(target.spaceIndex, 1)
        model.refreshWorkspaceStatus()
        XCTAssertEqual(model.desktopAlias(displayID: displayID, spaceIndex: 1), "원래 첫 화면")
    }

    func testDeletedDesktopCannotTransferNameToReplacementAtSameIndex() throws {
        let model = model()
        try rename("보관된 이름", index: 0, model: model)
        let target = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: displayID, spaceIndex: 0))
        let replacement = observation([4, 1, 2, 3])
        model.workspaceObservationOverride = { replacement }
        XCTAssertEqual(model.saveDesktopName("다른 이름", target: target), .unavailable)
        model.refreshWorkspaceStatus()
        XCTAssertNil(model.desktopAlias(displayID: displayID, spaceIndex: 0))
        XCTAssertEqual(model.workspaceDesktopAliases.count, 1)
    }

    func testMissingAndAmbiguousIdentityCannotWriteOrEraseAliases() throws {
        let model = model()
        let target = try rename("보존", index: 0, model: model)
        model.workspaceObservationOverride = { nil }
        XCTAssertEqual(model.saveDesktopName(nil, target: target), .unavailable)
        XCTAssertEqual(model.workspaceDesktopAliases[target.identity.storageKey], "보존")
        var missing = observation()
        missing.spaceKeysByDisplayID = [:]
        model.workspaceObservationOverride = { missing }
        XCTAssertNil(model.prepareDesktopNameEdit(displayID: displayID, spaceIndex: 0))
        var ambiguous = observation()
        ambiguous.spaceKeysByDisplayID[displayID] = [keys[0], keys[0], keys[2], keys[3]]
        model.workspaceObservationOverride = { ambiguous }
        XCTAssertEqual(model.saveDesktopName("오류", target: target), .unavailable)
        XCTAssertEqual(model.workspaceDesktopAliases[target.identity.storageKey], "보존")
    }

    func testTwoEditorsCannotSilentlyOverwriteOneAnother() throws {
        let model = model()
        let first = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: displayID, spaceIndex: 0))
        let second = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: displayID, spaceIndex: 0))
        XCTAssertEqual(model.saveDesktopName("최신 이름", target: first), .saved)
        XCTAssertEqual(model.saveDesktopName("오래된 편집", target: second), .conflict)
        XCTAssertEqual(model.saveDesktopName(nil, target: second), .conflict)
        XCTAssertEqual(model.workspaceDesktopName(displayID: displayID, spaceIndex: 0), "최신 이름")
    }

    func testInvalidNamesLeaveSavedValueAndOtherDesktopsUntouched() throws {
        let model = model()
        try rename("자료", index: 0, model: model)
        try rename("자료", index: 1, model: model) // Duplicate labels are valid.
        let target = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: displayID, spaceIndex: 0))
        XCTAssertEqual(model.saveDesktopName(" \n", target: target), .invalid(.empty))
        XCTAssertEqual(model.saveDesktopName(String(repeating: "가", count: 61), target: target), .invalid(.tooLong))
        XCTAssertEqual(model.saveDesktopName("가\n나", target: target), .invalid(.multipleLines))
        XCTAssertEqual(model.desktopAlias(displayID: displayID, spaceIndex: 0), "자료")
        XCTAssertEqual(model.desktopAlias(displayID: displayID, spaceIndex: 1), "자료")
    }

    func testExplicitWorkspaceNameImportStaysFixedAndResetAffectsOnlyDesktop() throws {
        let model = model()
        try rename("내 작업", index: 0, model: model)
        XCTAssertTrue(model.useDesktopContentName(contextID: "c0"))
        try rename("새 데스크탑 이름", index: 0, model: model)
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts[0].name, "내 작업")
        let target = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: displayID, spaceIndex: 0))
        XCTAssertEqual(model.saveDesktopName(nil, target: target), .saved)
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.workspaceDesktopName(displayID: displayID, spaceIndex: 0), "Editor")
        XCTAssertEqual(model.settings.contextPlan.contexts[0].name, "내 작업")
    }

    func testRebuildUsesAliasesAndRestoreKeepsLatestAlias() throws {
        let model = model()
        try rename("구현", index: 0, model: model)
        let originalPlan = model.settings.contextPlan.contexts
        let proposal = try XCTUnwrap(model.prepareWorkspaceRebuild())
        XCTAssertTrue(model.rebuildWorkspaces(proposal))
        XCTAssertEqual(model.settings.contextPlan.contexts[0].name, "구현")
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts[0].name, "구현")
        try rename("결제 구현", index: 0, model: model)
        XCTAssertTrue(model.restoreWorkspaceRebuildBackup())
        XCTAssertEqual(model.settings.contextPlan.contexts, originalPlan)
        XCTAssertEqual(model.workspaceDesktopName(displayID: displayID, spaceIndex: 0), "결제 구현")
    }

    func testRestartDisconnectAndReconnectPreserveDurableNames() throws {
        let suite = "sideby-alias-tests-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let original = model()
        original.workspacePreferences = preferences
        original.saveWorkspaceIdentitySnapshot()
        try rename("다음 날에도 코드", index: 0, model: original)
        let restarted = model()
        restarted.workspacePreferences = preferences
        restarted.loadWorkspacePersistence()
        let changed = observation([1, 2, 0, 3], offset: 1000)
        restarted.workspaceObservationOverride = { changed }
        restarted.refreshWorkspaceStatus()
        XCTAssertEqual(restarted.workspaceDesktopName(displayID: displayID, spaceIndex: 2), "다음 날에도 코드")
        restarted.workspaceObservationOverride = { nil }
        restarted.displayLayout = .init(displays: [])
        restarted.refreshWorkspaceStatus()
        XCTAssertEqual(restarted.workspaceDesktopAliases.count, 1)
        restarted.displayLayout = original.displayLayout
        restarted.workspaceObservationOverride = { changed }
        restarted.refreshWorkspaceStatus()
        XCTAssertEqual(restarted.workspaceDesktopName(displayID: displayID, spaceIndex: 2), "다음 날에도 코드")
    }

    func testConnectedExcludedDisplayCanBeNamedWithoutSelectingIt() throws {
        let model = model()
        model.selectedDisplayIDs = []
        try rename("제외된 화면", index: 1, model: model)
        XCTAssertTrue(model.selectedDisplayIDs.isEmpty)
        XCTAssertEqual(model.workspaceDesktopName(displayID: displayID, spaceIndex: 1), "제외된 화면")
    }

    func testNewlyDiscoveredWorkspaceUsesStoredAliasWithoutChangingExistingNames() throws {
        let model = model()
        let identity = try XCTUnwrap(DesktopNameIdentity(spaceKey: keys[4], displayID: displayID))
        model.workspaceDesktopAliases[identity.storageKey] = "다시 찾은 자료"
        let previousNames = model.settings.contextPlan.contexts.map(\.name)
        let expanded = observation([0, 1, 2, 3, 4])
        model.workspaceObservationOverride = { expanded }
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(Array(model.settings.contextPlan.contexts.prefix(4)).map(\.name), previousNames)
        XCTAssertEqual(model.settings.contextPlan.contexts.last?.name, "다시 찾은 자료")
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts.last?.name, "다시 찾은 자료")
    }

    func testUnreadableAliasStorageDoesNotBlockWorkspaceOperations() throws {
        let suite = "sideby-alias-tests-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(Data("invalid json".utf8), forKey: SidebyAppModel.desktopAliasesKey)
        let model = model()
        model.workspacePreferences = preferences
        model.loadWorkspacePersistence()
        XCTAssertTrue(model.workspaceDesktopAliases.isEmpty)
        XCTAssertFalse(model.workspaceIdentityNeedsReview)
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertTrue(model.isWorkspaceAssignmentAvailable(contextID: "c0"))
        XCTAssertTrue(model.assignWorkspaceDesktop(displayID: displayID, spaceIndex: 1, toContextID: "c0"))
    }

    func testTwoDisplaysWithDefaultDesktopHaveIndependentNames() throws {
        let model = model()
        let second = "uuid:BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        model.displayLayout = .init(displays: [.init(id: displayID, name: "Mac", isPrimary: true, isBuiltin: true),
                                              .init(id: second, name: "External", isPrimary: false, isBuiltin: false)])
        model.workspaceLastObservedSpaceIDs = [:]
        model.workspaceLastObservedSpaceKeys = [:]
        let layout = WorkspaceLayoutObservation(displays: [
            .init(displayID: displayID, spaceCount: 1, currentSpaceIndex: 0),
            .init(displayID: second, spaceCount: 1, currentSpaceIndex: 0)],
            spaceIDsByDisplayID: [displayID: [100], second: [200]],
            spaceKeysByDisplayID: [displayID: ["default-desktop"], second: ["default-desktop"]])
        model.workspaceObservationOverride = { layout }
        try rename("Mac 코드", index: 0, model: model)
        let target = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: second, spaceIndex: 0))
        XCTAssertEqual(model.saveDesktopName("참고 자료", target: target), .saved)
        XCTAssertEqual(model.desktopAlias(displayID: displayID, spaceIndex: 0), "Mac 코드")
        XCTAssertEqual(model.desktopAlias(displayID: second, spaceIndex: 0), "참고 자료")
    }
}

private struct AliasTestNames: SpaceNameSuggestionProviding {
    let value: [String: [Int: String]]
    func names(for layout: DisplayLayout, spaceIDsByDisplayID: [String: [UInt64]]) -> [String: [Int: String]] { value }
}
