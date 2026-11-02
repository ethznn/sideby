import XCTest
import Combine
import SidebyCore
import SidebySystem
@testable import SidebyApp

@MainActor final class ConnectionDisplayRefreshTests: XCTestCase {
    private let main = DisplaySnapshot(displayID: 1, name: "MacBook", isPrimary: true,
        isBuiltin: true, vendorNumber: 1, modelNumber: 1, serialNumber: 1, displayUUID: "MAIN")
    private let external = DisplaySnapshot(displayID: 2, name: "Studio", isPrimary: false,
        isBuiltin: false, vendorNumber: 2, modelNumber: 2, serialNumber: 2, displayUUID: "EXTERNAL")

    private func fixture() -> SidebyAppModel {
        var settings = AppSettings.default
        settings.displaySelection = .init(hasInitialized: true,
            selectedDisplayIDs: ["uuid:MAIN", "uuid:EXTERNAL", "uuid:OFFLINE"])
        settings.contextPlan = .init(contexts: [.init(id: "work", order: 1, name: "Work",
            displaySpaceIndexes: ["uuid:MAIN": 0, "uuid:EXTERNAL": 0, "uuid:OFFLINE": 0])], currentContextID: "work")
        settings.savedWorkspaces.initialized = true
        settings.savedWorkspaces.bookmarks = ["work": ["uuid:MAIN": "main-a", "uuid:EXTERNAL": "external-a", "uuid:OFFLINE": "offline-a"]]
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: [],
            selectedDisplaySpaces: { nil }, postEventAccessGranted: true)
        model.workspaceObservationOverride = { [weak model] in
            guard let model, !model.displayLayout.displays.isEmpty else { return nil }
            let ids = model.displayLayout.displays.map(\.id)
            return .init(displays: ids.map { .init(displayID: $0, spaceCount: 1, currentSpaceIndex: 0) },
                spaceIDsByDisplayID: Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, [UInt64($0.offset + 1)]) }),
                spaceKeysByDisplayID: Dictionary(uniqueKeysWithValues: ids.map { ($0, [$0 == "uuid:MAIN" ? "main-a" : "external-a"]) }))
        }
        return model
    }

    func testVisibleEditorRecoversAnEmptyStartupDisplayListBeforeReadingSpaces() async {
        let model = fixture()
        model.displaySnapshotsProvider = { [self.main, self.external] }
        let saved = model.settings

        let observation = await model.refreshVisibleConnections(force: true)

        XCTAssertEqual(model.displayLayout.displayCount, 2)
        XCTAssertEqual(model.selectedDisplayIDs, ["uuid:MAIN", "uuid:EXTERNAL"])
        XCTAssertEqual(observation?.displays.count, 2)
        XCTAssertEqual(model.settings.displaySelection.selectedDisplayIDs, saved.displaySelection.selectedDisplayIDs)
        XCTAssertEqual(model.settings.contextPlan.contexts, saved.contextPlan.contexts)
        XCTAssertEqual(model.settings.savedWorkspaces, saved.savedWorkspaces)
        XCTAssertFalse(model.isSwitching)
    }

    func testVisibleRefreshRecoversMissedDisconnectAndReconnectWithoutSelectingExcludedDisplays() async {
        let model = fixture()
        model.settings.displaySelection.setSelected(false, displayID: "uuid:EXTERNAL")
        let saved = model.settings
        var snapshots = [main, external]
        model.displaySnapshotsProvider = { snapshots }
        _ = await model.refreshVisibleConnections(force: true)
        XCTAssertEqual(model.displayLayout.displayCount, 2)
        XCTAssertEqual(model.selectedDisplayIDs, ["uuid:MAIN"])

        snapshots = []
        _ = await model.refreshVisibleConnections(force: true)
        XCTAssertTrue(model.displayLayout.displays.isEmpty)
        XCTAssertTrue(model.selectedDisplayIDs.isEmpty)

        snapshots = [main, external]
        _ = await model.refreshVisibleConnections(force: true)
        XCTAssertEqual(model.displayLayout.displayCount, 2)
        XCTAssertEqual(model.selectedDisplayIDs, ["uuid:MAIN"])
        XCTAssertEqual(model.settings.displaySelection.selectedDisplayIDs, saved.displaySelection.selectedDisplayIDs)
        XCTAssertEqual(model.settings.contextPlan.contexts, saved.contextPlan.contexts)
        XCTAssertEqual(model.settings.savedWorkspaces, saved.savedWorkspaces)
        XCTAssertFalse(model.isSwitching)
    }

    func testDisplayReadsRespectRefreshThrottleAndInFlightSwitch() async {
        let model = fixture()
        var reads = 0
        model.displaySnapshotsProvider = { reads += 1; return [self.main] }
        _ = await model.refreshVisibleConnections()
        _ = await model.refreshVisibleConnections()
        XCTAssertEqual(reads, 1)
        model.isSwitching = true
        _ = await model.refreshVisibleConnections(force: true)
        XCTAssertEqual(reads, 1)
        model.isSwitching = false
        _ = await model.refreshVisibleConnections(force: true)
        XCTAssertEqual(reads, 2)
    }

    func testUnchangedDisplayRefreshDoesNotRepublishOrInvalidateConnections() {
        let model = fixture()
        model.displaySnapshotsProvider = { [self.main, self.external] }
        model.refreshDisplayLayout()
        let revision = model.workspaceConfigurationRevision
        var changes = 0
        let subscriptions = [
            model.$displayLayout.dropFirst().sink { _ in changes += 1 },
            model.$selectedDisplayIDs.dropFirst().sink { _ in changes += 1 },
            model.$settings.dropFirst().sink { _ in changes += 1 }
        ]
        model.refreshDisplayLayout()
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(model.workspaceConfigurationRevision, revision)
        withExtendedLifetime(subscriptions) {}
    }
}
