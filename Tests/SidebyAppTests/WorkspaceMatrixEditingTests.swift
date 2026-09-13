import XCTest
import AppKit
import UniformTypeIdentifiers
import SidebyCore
@testable import SidebyApp

@MainActor final class WorkspaceMatrixEditingTests: XCTestCase {
    func testDragProviderUsesNativeTextTransportAndKeepsTheExactSource() async throws {
        let payload = WorkspaceSpaceDragPayload(sourceContextID: "shared|작업", displayID: "main", spaceIndex: 0)
        let provider = payload.itemProvider
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))
        let raw: String = try await withCheckedThrowingContinuation { continuation in
            provider.loadObject(ofClass: NSString.self) { object, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: object as? String ?? "") }
            }
        }
        XCTAssertEqual(WorkspaceSpaceDragPayload(rawValue: raw), payload)
        XCTAssertNil(WorkspaceSpaceDragPayload(rawValue: "display-row|main"))
        XCTAssertNil(WorkspaceSpaceDragPayload(rawValue: "Unrelated text"))
    }

    func testMoveIntoEmptyCellAndOptionCopyPreserveOtherSharedAssignments() {
        let model = model()
        XCTAssertTrue(model.assignWorkspaceDesktop(displayID: "main", spaceIndex: nil, toContextID: "c"))
        let payload = WorkspaceSpaceDragPayload(sourceContextID: "b", displayID: "main", spaceIndex: 0)
        XCTAssertTrue(model.dropWorkspaceDesktop(payload, targetDisplayID: "main", targetContextID: "c", copying: false))
        XCTAssertEqual(model.settings.contextPlan.contexts.prefix(3).map { $0.spaceIndex(for: "main") }, [0, nil, 0])
        let moved = WorkspaceSpaceDragPayload(sourceContextID: "c", displayID: "main", spaceIndex: 0)
        XCTAssertTrue(model.dropWorkspaceDesktop(moved, targetDisplayID: "main", targetContextID: "b", copying: true))
        XCTAssertEqual(model.settings.contextPlan.contexts.prefix(3).map { $0.spaceIndex(for: "main") }, [0, 0, 0])
    }

    private func model() -> SidebyAppModel {
        var settings = AppSettings.default
        settings.contextPlan = .init(contexts: [
            .init(id: "a", order: 1, name: "A", displaySpaceIndexes: ["main": 0]),
            .init(id: "b", order: 2, name: "B", displaySpaceIndexes: ["main": 0]),
            .init(id: "c", order: 3, name: "C", displaySpaceIndexes: ["main": 1])
        ], currentContextID: "a")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["main"], selectedDisplaySpaces: {
            [.init(displayID: "main", spaceCount: 3, currentSpaceIndex: 0)]
        }, postEventAccessGranted: false)
        model.workspaceSpaceIDsOverride = { ["main": [11, 12, 13]] }
        model.displayLayout = .init(displays: [.init(id: "main", name: "MacBook", isPrimary: true, isBuiltin: true)])
        model.refreshWorkspaceStatus()
        return model
    }

    func testMenuAssignmentSharesWithoutMovingTheOriginalAndSurvivesRefresh() {
        let model = model()
        let originalIDs = model.settings.contextPlan.contexts.map(\.id)
        XCTAssertTrue(model.assignWorkspaceDesktop(displayID: "main", spaceIndex: 0, toContextID: "c"))
        XCTAssertTrue(model.refreshWorkspaceList())
        XCTAssertEqual(model.settings.contextPlan.contexts.map(\.id), originalIDs)
        XCTAssertEqual(model.settings.contextPlan.contexts.prefix(3).map { $0.spaceIndex(for: "main") }, [0, 0, 0])
    }

    func testDragUsesTheActualSharedSourceAndRejectsWrongDisplayAndStalePayload() {
        let model = model()
        let payload = WorkspaceSpaceDragPayload(sourceContextID: "b", displayID: "main", spaceIndex: 0)
        XCTAssertFalse(model.dropWorkspaceDesktop(payload, targetDisplayID: "external", targetContextID: "c", copying: false))
        XCTAssertTrue(model.dropWorkspaceDesktop(payload, targetDisplayID: "main", targetContextID: "c", copying: false))
        XCTAssertEqual(model.settings.contextPlan.contexts.prefix(3).map { $0.spaceIndex(for: "main") }, [0, 1, 0])
        XCTAssertFalse(model.dropWorkspaceDesktop(payload, targetDisplayID: "main", targetContextID: "a", copying: false))
    }

    func testCopyDragPreservesSourceAndBusyEditingDoesNothing() {
        let model = model()
        let payload = WorkspaceSpaceDragPayload(sourceContextID: "b", displayID: "main", spaceIndex: 0)
        XCTAssertTrue(model.dropWorkspaceDesktop(payload, targetDisplayID: "main", targetContextID: "c", copying: true))
        let saved = model.settings.contextPlan.contexts
        model.isSwitching = true
        XCTAssertFalse(model.assignWorkspaceDesktop(displayID: "main", spaceIndex: 2, toContextID: "c"))
        XCTAssertFalse(model.dropWorkspaceDesktop(payload, targetDisplayID: "main", targetContextID: "c", copying: false))
        XCTAssertEqual(model.settings.contextPlan.contexts, saved)
    }

    func testRememberedDesktopCountPreservesGapsAfterRelaunchButFindsNewDesktops() throws {
        let existing: [ContextDefinition] = [
            .init(id: "a", order: 1, name: "A", displaySpaceIndexes: ["main": 0]),
            .init(id: "b", order: 2, name: "B", displaySpaceIndexes: ["main": 0])
        ]
        let observation = WorkspaceLayoutObservation(displays: [.init(displayID: "main", spaceCount: 3, currentSpaceIndex: 0)],
                                                     spaceIDsByDisplayID: ["main": [11, 12, 13]])
        let result = try XCTUnwrap(WorkspaceLiveRefreshPolicy.contexts(existing: existing, observation: observation,
            selectedDisplayIDs: ["main"], previousSpaceIDs: [:], previousSpaceCounts: ["main": 2], defaultName: { "Desktop \($0)" }))
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.last?.spaceIndex(for: "main"), 2)
        XCTAssertFalse(result.contains { $0.spaceIndex(for: "main") == 1 })
    }
}
