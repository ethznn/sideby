import XCTest
import SidebyCore
import SidebyUI
@testable import SidebyApp

final class WorkspaceTablePresentationTests: XCTestCase {
    func testColumnsShowConnectedDisplaysInSavedOrderByDefault() {
        XCTAssertEqual(WorkspaceTablePresentation.displayIDs(connected: ["main", "desk"], remembered: ["offline", "unused"], assigned: ["legacy", "desk"], order: ["desk", "offline", "main"]), ["desk", "main"])
        XCTAssertEqual(WorkspaceTablePresentation.displayIDs(connected: ["main", "desk"], remembered: ["offline", "unused"], assigned: ["legacy", "desk"], order: ["desk", "offline", "main"], includeDisconnected: true), ["desk", "offline", "main", "legacy", "unused"])
    }

    func testTwoDisplaysFitSmallWindowAndSingleDisplayDoesNotStretch() {
        let small = WorkspaceTablePresentation(windowWidth: 700, displayCount: 2)
        XCTAssertLessThanOrEqual(small.nameWidth + small.displayWidth * 2, small.contentWidth)
        let single = WorkspaceTablePresentation(windowWidth: 840, displayCount: 1)
        XCTAssertEqual(single.displayWidth, 160)
        let many = WorkspaceTablePresentation(windowWidth: 700, displayCount: 4)
        XCTAssertGreaterThan(many.nameWidth + many.displayWidth * 4, many.contentWidth)
    }

    func testAssignmentStatesDoNotConfuseOfflineFailureInvalidAndUnassigned() {
        XCTAssertEqual(WorkspaceTablePresentation.state(index: 2, connected: false, selected: true, count: nil), .offline)
        XCTAssertEqual(WorkspaceTablePresentation.state(index: 2, connected: true, selected: true, count: nil), .unavailable)
        XCTAssertEqual(WorkspaceTablePresentation.state(index: 2, connected: true, selected: true, count: 2), .invalid)
        XCTAssertEqual(WorkspaceTablePresentation.state(index: nil, connected: true, selected: true, count: 2), .unassigned)
        XCTAssertEqual(WorkspaceTablePresentation.state(index: 2, connected: true, selected: false, count: nil), .excluded)
    }

    @MainActor func testMonitorHitRegionsKeepRealPortraitRatioAndDoNotOverlap() {
        let displays = [
            DisplayInfo(id: "left", name: "Left", isPrimary: true, isBuiltin: false, frame: .init(x: 0, y: 0, width: 1920, height: 1080)),
            DisplayInfo(id: "portrait", name: "Portrait", isPrimary: false, isBuiltin: false, frame: .init(x: 1920, y: 0, width: 1080, height: 1920)),
            DisplayInfo(id: "right", name: "Right", isPrimary: false, isBuiltin: false, frame: .init(x: 3000, y: 0, width: 1920, height: 1080))
        ]
        let placements = NativeDisplaySelector.placements(displays, size: .init(width: 531, height: 92))
        XCTAssertEqual(placements.count, 3)
        let portrait = placements[1].frame
        XCTAssertEqual(portrait.width / portrait.height, 1080.0 / 1920.0, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(portrait.width, 32)
        XCTAssertLessThanOrEqual(placements[0].frame.maxX, portrait.minX + 0.01)
        XCTAssertLessThanOrEqual(portrait.maxX, placements[2].frame.minX + 0.01)
    }

    func testUnknownOrInvalidGeometryUsesListInsteadOfInventedPositions() {
        let good = DisplayInfo(id: "a", name: "A", isPrimary: true, isBuiltin: true, frame: .init(x: -100, y: 20, width: 100, height: 200))
        let unknown = DisplayInfo(id: "b", name: "B", isPrimary: false, isBuiltin: false)
        XCTAssertTrue(WorkspaceTablePresentation.hasGeometry([good]))
        XCTAssertFalse(WorkspaceTablePresentation.hasGeometry([good, unknown]))
        XCTAssertFalse(WorkspaceTablePresentation.hasGeometry([]))
        XCTAssertFalse(WorkspaceTablePresentation.hasGeometry([.init(id: "bad", name: "Bad", isPrimary: false, isBuiltin: false, frame: .init(x: 0, y: 0, width: 0, height: 100))]))
    }
}
