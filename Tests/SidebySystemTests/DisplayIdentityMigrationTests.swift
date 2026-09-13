import Foundation
import XCTest
@testable import SidebyCore
@testable import SidebySystem

final class DisplayIdentityMigrationTests: XCTestCase {
    func testDisplayUUIDRetainsSelectionWhenRuntimeIDChanges() throws {
        var settings = AppSettings.default
        settings.displaySelection.reconcile(with: DisplayLayoutMapper.layout(from: [snapshot(runtimeID: 1, uuid: "DISPLAY-A")]))
        settings.displaySelection.setSelected(false, displayID: "uuid:DISPLAY-A")
        var reloaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        let layout = DisplayLayoutMapper.layout(from: [snapshot(runtimeID: 9, uuid: "display-a")])
        reloaded.displaySelection.reconcile(with: layout)

        XCTAssertEqual(layout.displays.map(\.id), ["uuid:DISPLAY-A"])
        XCTAssertEqual(reloaded.displaySelection.selectedDisplayIDs, [])
        XCTAssertEqual(reloaded.displaySelection.knownDisplayNames.count, 1)
    }

    func testIdenticalHardwareWithoutUUIDRemainsDistinctAndDoesNotGuessReconnection() {
        let layout = DisplayLayoutMapper.layout(from: [snapshot(runtimeID: 1), snapshot(runtimeID: 2)])
        var selection = DisplaySelection()
        selection.reconcile(with: layout)
        selection.setSelected(false, displayID: "10-20-0-2")

        let changed = DisplayLayoutMapper.layout(from: [snapshot(runtimeID: 3), snapshot(runtimeID: 4)])
        selection.reconcile(with: changed)

        XCTAssertEqual(layout.displays.map(\.id), ["10-20-0-1", "10-20-0-2"])
        XCTAssertEqual(selection.selectedDisplayIDs, ["10-20-0-1"])
        XCTAssertEqual(selection.connectedSelectedDisplayIDs(in: changed), [])
        XCTAssertEqual(selection.knownDisplayNames.count, 4)
    }

    func testCapturedUUIDIsUsedForSpaceLayoutMapping() {
        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: [snapshot(runtimeID: 1, uuid: "DISPLAY-A")],
            uuidForDisplayID: { _ in nil }
        )

        XCTAssertEqual(mapping, ["DISPLAY-A": "uuid:DISPLAY-A"])
    }

    func testExactLegacySnapshotMigratesPlanOrderSelectionAndNamesWithoutChangingPlanState() {
        var settings = legacySettings(ids: ["10-20-0-1", "offline"], selected: ["10-20-0-1"])

        let remapped = DisplayIdentityMigration.migrate(settings: &settings, snapshots: [snapshot(runtimeID: 1, uuid: "DISPLAY-A")])

        XCTAssertEqual(remapped, ["10-20-0-1": "uuid:DISPLAY-A"])
        XCTAssertEqual(settings.contextPlan.contexts.map(\.name), ["Focus", "Review"])
        XCTAssertEqual(settings.contextPlan.contexts.map(\.order), [1, 2])
        XCTAssertEqual(settings.contextPlan.contexts[0].displaySpaceIndexes, ["uuid:DISPLAY-A": 2, "offline": 2])
        XCTAssertEqual(settings.contextPlan.contexts[1].displaySpaceIndexes, ["uuid:DISPLAY-A": 0, "offline": 0])
        XCTAssertEqual(settings.contextPlan.currentContextID, "review")
        XCTAssertEqual(settings.contextPlan.syncState, .needsSync)
        XCTAssertFalse(settings.contextPlan.isPinned)
        XCTAssertEqual(settings.displayRowOrder, ["uuid:DISPLAY-A", "offline"])
        XCTAssertEqual(settings.displaySelection.selectedDisplayIDs, ["uuid:DISPLAY-A"])
        XCTAssertEqual(settings.displaySelection.knownDisplayNames, ["uuid:DISPLAY-A": "Saved 10-20-0-1", "offline": "Saved offline"])
    }

    func testUniqueNonzeroSerialMigratesAfterRuntimeIDChanges() {
        var settings = legacySettings(ids: ["10-20-30-1"])

        let remapped = DisplayIdentityMigration.migrate(settings: &settings, snapshots: [snapshot(runtimeID: 9, serial: 30, uuid: "DISPLAY-A")])

        XCTAssertEqual(remapped, ["10-20-30-1": "uuid:DISPLAY-A"])
        XCTAssertEqual(settings.contextPlan.contexts[0].displayIDs, ["uuid:DISPLAY-A"])
    }

    func testZeroSerialDoesNotMigrateAfterRuntimeIDChanges() {
        var settings = legacySettings(ids: ["10-20-0-1"])
        let original = settings

        let remapped = DisplayIdentityMigration.migrate(settings: &settings, snapshots: [snapshot(runtimeID: 9, uuid: "DISPLAY-A")])

        XCTAssertEqual(remapped, [:])
        XCTAssertEqual(settings, original)
    }

    func testDuplicateConnectedSerialDoesNotGuessLegacyMatch() {
        var settings = legacySettings(ids: ["10-20-30-1"])
        let original = settings

        let remapped = DisplayIdentityMigration.migrate(settings: &settings, snapshots: [
            snapshot(runtimeID: 8, serial: 30, uuid: "DISPLAY-A"),
            snapshot(runtimeID: 9, serial: 30, uuid: "DISPLAY-B")
        ])

        XCTAssertEqual(remapped, [:])
        XCTAssertEqual(settings, original)
    }

    func testDuplicateStoredSerialDoesNotCollapseAbsentDisplays() {
        var settings = legacySettings(ids: ["10-20-30-1", "10-20-30-2"])
        let original = settings

        let remapped = DisplayIdentityMigration.migrate(settings: &settings, snapshots: [snapshot(runtimeID: 9, serial: 30, uuid: "DISPLAY-A")])

        XCTAssertEqual(remapped, [:])
        XCTAssertEqual(settings, original)
    }

    func testExistingStableEntryPreventsDestructiveCollisionWithLegacyEntry() {
        var settings = legacySettings(ids: ["10-20-30-1", "uuid:DISPLAY-A"])
        let original = settings

        let remapped = DisplayIdentityMigration.migrate(settings: &settings, snapshots: [snapshot(runtimeID: 1, serial: 30, uuid: "DISPLAY-A")])

        XCTAssertEqual(remapped, [:])
        XCTAssertEqual(settings, original)
    }

    private func snapshot(runtimeID: UInt32, serial: UInt32 = 0, uuid: String? = nil) -> DisplaySnapshot {
        DisplaySnapshot(
            displayID: runtimeID,
            name: "Desk",
            isPrimary: false,
            isBuiltin: false,
            vendorNumber: 10,
            modelNumber: 20,
            serialNumber: serial,
            displayUUID: uuid
        )
    }

    private func legacySettings(ids: [String], selected: Set<String> = []) -> AppSettings {
        var settings = AppSettings.default
        settings.contextPlan = ContextPlan(contexts: [
            ContextDefinition(id: "focus", order: 1, name: "Focus", displaySpaceIndexes: Dictionary(uniqueKeysWithValues: ids.map { ($0, 2) })),
            ContextDefinition(id: "review", order: 2, name: "Review", displaySpaceIndexes: Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) }))
        ], currentContextID: "review", syncState: .needsSync, isPinned: false)
        settings.displayRowOrder = ids
        settings.displaySelection = DisplaySelection(
            hasInitialized: true,
            selectedDisplayIDs: selected,
            knownDisplayNames: Dictionary(uniqueKeysWithValues: ids.map { ($0, "Saved \($0)") })
        )
        return settings
    }
}
