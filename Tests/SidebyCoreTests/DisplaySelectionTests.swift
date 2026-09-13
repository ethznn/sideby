import Foundation
import XCTest
@testable import SidebyCore

final class DisplaySelectionTests: XCTestCase {
    func testFirstNonemptyLayoutSelectsDisplaysAndRemembersNames() {
        var selection = DisplaySelection()
        selection.reconcile(with: layout([]))
        XCTAssertFalse(selection.hasInitialized)

        selection.reconcile(with: layout([("built-in", "Built-in"), ("desk", "Desk")]))

        XCTAssertTrue(selection.hasInitialized)
        XCTAssertEqual(selection.selectedDisplayIDs, ["built-in", "desk"])
        XCTAssertEqual(selection.knownDisplayNames, ["built-in": "Built-in", "desk": "Desk"])
    }

    func testRefreshKeepsDeselectionAndLeavesNewDisplayUnselected() {
        var selection = DisplaySelection()
        selection.reconcile(with: layout([("built-in", "Built-in"), ("desk", "Desk")]))
        selection.setSelected(false, displayID: "desk")

        selection.reconcile(with: layout([("built-in", "Built-in"), ("desk", "Desk renamed"), ("new", "New")]))

        XCTAssertEqual(selection.selectedDisplayIDs, ["built-in"])
        XCTAssertEqual(selection.knownDisplayNames["desk"], "Desk renamed")
        XCTAssertEqual(selection.knownDisplayNames["new"], "New")
    }

    func testOfflineSelectionAndNamesSurviveSettingsRelaunchAndReconnect() throws {
        var settings = AppSettings.default
        settings.displaySelection.reconcile(with: layout([("built-in", "Built-in"), ("desk", "Desk")]))
        settings.displaySelection.setSelected(false, displayID: "built-in")
        settings.displaySelection.reconcile(with: layout([("built-in", "Built-in")]))
        XCTAssertEqual(settings.displaySelection.connectedSelectedDisplayIDs(in: layout([("built-in", "Built-in")])), [])

        var reloaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        reloaded.displaySelection.reconcile(with: layout([("built-in", "Built-in"), ("desk", "Desk")]))

        XCTAssertEqual(reloaded.displaySelection.selectedDisplayIDs, ["desk"])
        XCTAssertEqual(reloaded.displaySelection.knownDisplayNames, ["built-in": "Built-in", "desk": "Desk"])
        XCTAssertEqual(reloaded.displaySelection.connectedSelectedDisplayIDs(in: layout([("desk", "Desk")])), ["desk"])
    }

    func testEmptyUserSelectionSurvivesRelaunchWithoutDefaultingAgain() throws {
        var settings = AppSettings.default
        settings.displaySelection.reconcile(with: layout([("desk", "Desk")]))
        settings.displaySelection.setSelected(false, displayID: "desk")

        var reloaded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        reloaded.displaySelection.reconcile(with: layout([("desk", "Desk")]))

        XCTAssertTrue(reloaded.displaySelection.hasInitialized)
        XCTAssertEqual(reloaded.displaySelection.selectedDisplayIDs, [])
    }

    func testSelectingAllConnectedDisplaysPreservesOfflineChoice() {
        var selection = DisplaySelection()
        selection.reconcile(with: layout([("offline", "Offline")]))
        selection.selectAllConnected(in: layout([("desk", "Desk")]))

        XCTAssertEqual(selection.selectedDisplayIDs, ["offline", "desk"])
        XCTAssertEqual(selection.knownDisplayNames, ["offline": "Offline", "desk": "Desk"])
    }

    func testLegacySettingsWithoutDisplaySelectionDecodeAsUninitialized() throws {
        let data = try JSONEncoder().encode(AppSettings.default)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "displaySelection")

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))

        XCTAssertFalse(decoded.displaySelection.hasInitialized)
        XCTAssertEqual(decoded.displaySelection.selectedDisplayIDs, [])
        XCTAssertEqual(decoded.displaySelection.knownDisplayNames, [:])
    }

    private func layout(_ displays: [(String, String)]) -> DisplayLayout {
        DisplayLayout(displays: displays.map { id, name in
            DisplayInfo(id: id, name: name, isPrimary: false, isBuiltin: false)
        })
    }
}
