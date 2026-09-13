import XCTest
import SidebyCore
import SidebySystem
@testable import SidebyApp

final class WorkspaceLayoutObservationTests: XCTestCase {
    private let snapshot = DisplaySnapshot(displayID: 1, name: "Main", isPrimary: true, isBuiltin: true, vendorNumber: 1, modelNumber: 1, serialNumber: 1, displayUUID: "SCREEN")

    func testCurrentIndexAndOrderedIdentitiesComeFromSameLayout() throws {
        let observation = try XCTUnwrap(WorkspaceLayoutObservation.make(
            layouts: [.init(displayUUID: "SCREEN", spaceIDs: [41, 12, 93], currentSpaceID: 12)],
            snapshots: [snapshot], selectedDisplayIDs: ["uuid:SCREEN"]
        ))
        XCTAssertEqual(observation.displays, [.init(displayID: "uuid:SCREEN", spaceCount: 3, currentSpaceIndex: 1)])
        XCTAssertEqual(observation.spaceIDsByDisplayID, ["uuid:SCREEN": [41, 12, 93]])
    }

    func testAmbiguousAndMalformedLayoutsCannotEstablishAnObservation() {
        let valid = DisplaySpaceLayout(displayUUID: "SCREEN", spaceIDs: [1, 2], currentSpaceID: 1)
        XCTAssertNil(WorkspaceLayoutObservation.make(layouts: [valid, valid], snapshots: [snapshot], selectedDisplayIDs: ["uuid:SCREEN"]))
        XCTAssertNil(WorkspaceLayoutObservation.make(layouts: [.init(displayUUID: "SCREEN", spaceIDs: [1, 1], currentSpaceID: 1)], snapshots: [snapshot], selectedDisplayIDs: ["uuid:SCREEN"]))
        XCTAssertNil(WorkspaceLayoutObservation.make(layouts: [.init(displayUUID: "SCREEN", spaceIDs: [1, 2], currentSpaceID: 3)], snapshots: [snapshot], selectedDisplayIDs: ["uuid:SCREEN"]))
    }

    func testLockedSessionCannotSupplyATruncatedDesktopLayout() {
        XCTAssertNil(WorkspaceLayoutObservation.make(
            layouts: [.init(displayUUID: "SCREEN", spaceIDs: [1], currentSpaceID: 1)],
            snapshots: [snapshot], selectedDisplayIDs: ["uuid:SCREEN"], isInteractiveSession: false
        ))
    }
}
