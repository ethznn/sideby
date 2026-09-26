import AppKit
import SidebyCore
import XCTest
@testable import SidebyApp

@MainActor final class HeldWorkspaceMatrixTests: XCTestCase {
    func testSnapshotKeepsOrderUsesAliasesAndOmitsOfflineAndExcludedDisplays() throws {
        let model = heldMatrixFixture()
        let target = try XCTUnwrap(model.prepareDesktopNameEdit(displayID: "mac", spaceIndex: 0))
        XCTAssertEqual(model.saveDesktopName("내 코드", target: target), .saved)
        let snapshot = HeldWorkspaceSnapshot(model: model)
        XCTAssertEqual(snapshot.displayIDs, ["mac"])
        XCTAssertEqual(snapshot.columns.map(\.id), ["work-0", "work-1", "work-2", "work-3"])
        XCTAssertEqual(snapshot.columns[0].cells["mac"], "내 코드")
        XCTAssertTrue(model.heldMatrixCanActivate(snapshot.columns[1], displayIDs: snapshot.displayIDs))
        model.setContextName(contextID: "work-1", name: "Changed header")
        XCTAssertEqual(snapshot.columns[1].name, "Review")
        XCTAssertTrue(snapshot.columns[1].stillMatches(model: model, displayIDs: snapshot.displayIDs))
    }

    func testReorderKeepsBookmarkButReassignmentInvalidatesTarget() {
        let model = heldMatrixFixture()
        let snapshot = HeldWorkspaceSnapshot(model: model)
        let observed = heldMatrixObservation(order: [2, 0, 3, 1])
        model.workspaceObservationOverride = { observed }
        model.refreshWorkspaceStatus()
        XCTAssertTrue(snapshot.columns[1].stillMatches(model: model, displayIDs: snapshot.displayIDs))
        XCTAssertTrue(model.assignWorkspaceDesktop(displayID: "mac", spaceIndex: 0, toContextID: "work-1"))
        XCTAssertFalse(snapshot.columns[1].stillMatches(model: model, displayIDs: snapshot.displayIDs))
    }

    func testUnavailableOrChangedSelectionDoesNotActivateAndOneDesktopIsValid() {
        let model = heldMatrixFixture(count: 1)
        let snapshot = HeldWorkspaceSnapshot(model: model)
        XCTAssertEqual(snapshot.columns.count, 1)
        XCTAssertTrue(model.heldMatrixCanActivate(snapshot.columns[0], displayIDs: snapshot.displayIDs))
        model.selectedDisplayIDs = []
        XCTAssertFalse(model.heldMatrixCanActivate(snapshot.columns[0], displayIDs: snapshot.displayIDs))
        XCTAssertTrue(HeldWorkspaceSnapshot(model: model).columns.isEmpty)
    }

    func testConfigurationPersistenceAndInvalidShortcutPreservesPreviousChoice() throws {
        let suite = "sideby-held-test-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = heldMatrixFixture()
        model.workspacePreferences = preferences
        let value = HeldMatrixConfiguration(shortcut: .init(keyCode: 40, modifiers: [.control, .option]))
        XCTAssertTrue(model.updateHeldMatrixConfiguration(value))
        XCTAssertFalse(model.updateHeldMatrixConfiguration(.init(shortcut: .init(keyCode: 49, modifiers: .command))))
        XCTAssertEqual(model.heldMatrixConfiguration, value)
        let restarted = heldMatrixFixture()
        restarted.workspacePreferences = preferences
        restarted.loadHeldMatrixConfiguration()
        XCTAssertEqual(restarted.heldMatrixConfiguration, value)
    }

    func testPanelStaysInsideScreensWithDifferentOriginsAndTinyVisibleFrames() {
        for frame in [NSRect(x: -1920, y: -300, width: 1920, height: 1080), NSRect(x: 0, y: 0, width: 800, height: 600)] {
            let size = HeldMatrixPanelLayout.size(columns: 20, displays: 8, visibleFrame: frame)
            for pointer in [NSPoint(x: frame.minX, y: frame.minY), NSPoint(x: frame.maxX, y: frame.maxY)] {
                let rect = NSRect(origin: HeldMatrixPanelLayout.origin(size: size, pointer: pointer, visibleFrame: frame), size: size)
                XCTAssertTrue(frame.contains(rect))
            }
        }
    }
}

@MainActor func heldMatrixFixture(count: Int = 4, displayCount: Int = 1) -> SidebyAppModel {
    let displayIDs = (0..<displayCount).map { $0 == 0 ? "mac" : "external-\($0)" }
    var settings = AppSettings.default
    settings.language = .korean
    settings.contextPlan = .init(contexts: (0..<count).map { index in
        .init(id: "work-\(index)", order: index + 1, name: ["Payments", "Review", "Operations", "Notes"][index % 4],
              displaySpaceIndexes: Dictionary(uniqueKeysWithValues: (displayIDs + ["offline"]).map { ($0, index) }))
    }, currentContextID: "work-0")
    let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: Set(displayIDs), selectedDisplaySpaces: { nil }, postEventAccessGranted: true)
    model.permissionState = .granted
    model.displayLayout = .init(displays: displayIDs.map {
        .init(id: $0, name: $0 == "mac" ? "MacBook Pro" : "Studio Display " + $0, isPrimary: $0 == "mac", isBuiltin: $0 == "mac")
    } + [.init(id: "excluded", name: "Not selected", isPrimary: false, isBuiltin: false)])
    let base = heldMatrixObservation(order: Array(0..<count))
    let observation = WorkspaceLayoutObservation(displays: displayIDs.map { .init(displayID: $0, spaceCount: count, currentSpaceIndex: 0) },
        spaceIDsByDisplayID: Dictionary(uniqueKeysWithValues: displayIDs.enumerated().map { offset, id in
            (id, base.spaceIDsByDisplayID["mac"]!.map { $0 + UInt64(offset * 100) })
        }),
        spaceKeysByDisplayID: Dictionary(uniqueKeysWithValues: displayIDs.map { ($0, base.spaceKeysByDisplayID["mac"]!) }))
    model.workspaceObservationOverride = { observation }
    model.refreshWorkspaceStatus()
    model.workspaceDesktopNames = ["mac": Dictionary(uniqueKeysWithValues: (0..<count).map { ($0, ["결제 API 구현 🧑‍💻", "변경 사항 검토", "운영 대시보드", "참고 자료"][$0 % 4]) })]
    model.workspaceDesktopNameSpaceIDs = observation.spaceIDsByDisplayID
    return model
}

func heldMatrixObservation(order: [Int]) -> WorkspaceLayoutObservation {
    .init(displays: [.init(displayID: "mac", spaceCount: order.count, currentSpaceIndex: 0)],
          spaceIDsByDisplayID: ["mac": order.map { UInt64($0 + 10) }],
          spaceKeysByDisplayID: ["mac": order.map { "uuid:11111111-1111-1111-1111-" + String(format: "%012d", $0) }])
}
