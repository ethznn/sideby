import AppKit
import XCTest
@testable import SidebyApp

@MainActor final class HeldSwitcherInteractionTests: XCTestCase {
    func testViewPreferenceRoundTripsAndInvalidValueUsesCircle() throws {
        let name = "sideby-view-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserDefaultsProductUIPreferences(defaults: defaults)
        XCTAssertEqual(preferences.quickSwitcherView, .wheel)
        preferences.quickSwitcherView = .table
        XCTAssertEqual(UserDefaultsProductUIPreferences(defaults: defaults).quickSwitcherView, .table)
        defaults.set("editor", forKey: "sideby.ui.quick-switcher-view")
        XCTAssertEqual(preferences.quickSwitcherView, .wheel)
    }

    func testToolbarAnchorStaysFixedAcrossModeSizesAndClampsAtDisplayEdges() {
        let screen = NSRect(x: -1800, y: -200, width: 1800, height: 1100)
        let top = NSPoint(x: -900, y: 850)
        for size in [NSSize(width: 472, height: 608), NSSize(width: 882, height: 420), NSSize(width: 1040, height: 800)] {
            let origin = HeldSwitcherPanelAnchor.origin(size: size, topCenter: top, visibleFrame: screen)
            XCTAssertEqual(origin.x + size.width / 2, top.x)
            XCTAssertEqual(origin.y + size.height, top.y)
            for edge in [screen.origin, NSPoint(x: screen.maxX, y: screen.maxY)] {
                XCTAssertTrue(screen.contains(NSRect(origin: HeldSwitcherPanelAnchor.origin(size: size, topCenter: edge, visibleFrame: screen), size: size)))
            }
        }
        let pointer = NSPoint(x: -900, y: 300), toolbar = HeldSwitcherViewControl.height
        let size = HeldWorkspaceWheelLayout.size(in: screen, toolbarHeight: toolbar)
        let origin = HeldWorkspaceWheelLayout.origin(size: size, pointer: pointer, visibleFrame: screen, toolbarHeight: toolbar)
        XCTAssertEqual(origin.y + size.height - toolbar - 8 - (size.width - 32) / 2, pointer.y)
        XCTAssertFalse(HeldWorkspaceWheelLayout.fits(in: NSRect(x: 0, y: 0, width: 500, height: 470), toolbarHeight: toolbar))
    }

    func testReorderOnlyAcceptsCurrentInternalConnectionAndPreservesAssignmentsWithUndo() throws {
        let model = heldMatrixFixture(count: 10, displayCount: 3)
        model.workspacePreferences = nil
        let before = model.settings, session = UUID()
        let ids = before.contextPlan.contexts.sorted { $0.order < $1.order }.map(\.id)
        let payload = WorkspaceComposerDrag(session: session, contextID: ids[0])
        let target = try XCTUnwrap(HeldWheelReorderTarget.resolve(raw: payload.rawValue, active: payload, session: session, orderedIDs: ids, targetID: ids[9]))
        XCTAssertTrue(target.after, "Forward and cross-page drags move into the target position")
        XCTAssertTrue(model.reorderSavedWorkspace(target.sourceID, relativeTo: target.targetID, after: target.after))
        XCTAssertEqual(model.settings.contextPlan.contexts.sorted { $0.order < $1.order }.map(\.id), Array(ids.dropFirst()) + [ids[0]])
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        XCTAssertEqual(model.settings.contextPlan.currentContextID, before.contextPlan.currentContextID)
        XCTAssertFalse(model.isSwitching)
        XCTAssertTrue(model.undoSavedWorkspaceChange())
        XCTAssertEqual(model.settings.contextPlan, before.contextPlan)
        XCTAssertEqual(model.settings.savedWorkspaces.bookmarks, before.savedWorkspaces.bookmarks)
        let back = WorkspaceComposerDrag(session: session, contextID: ids[8])
        XCTAssertFalse(try XCTUnwrap(HeldWheelReorderTarget.resolve(raw: back.rawValue, active: back, session: session, orderedIDs: ids, targetID: ids[1])).after)
        for raw in [nil, "external text", WorkspaceComposerDrag(session: session, contextID: ids[1]).rawValue] {
            XCTAssertNil(HeldWheelReorderTarget.resolve(raw: raw, active: payload, session: session, orderedIDs: ids, targetID: ids[2]))
        }
        XCTAssertNil(HeldWheelReorderTarget.resolve(raw: payload.rawValue, active: payload, session: UUID(), orderedIDs: ids, targetID: ids[2]))
        XCTAssertNil(HeldWheelReorderTarget.resolve(raw: payload.rawValue, active: nil, session: session, orderedIDs: ids, targetID: ids[2]))
        XCTAssertNil(HeldWheelReorderTarget.resolve(raw: payload.rawValue, active: payload, session: session, orderedIDs: ids, targetID: ids[0]))
        XCTAssertNil(HeldWheelReorderTarget.resolve(raw: payload.rawValue, active: payload, session: session, orderedIDs: Array(ids.dropFirst()), targetID: ids[2]))
    }

    func testNativeSectorDragThresholdSuppressesSwitchAndTransparentAreasPassThrough() throws {
        let surface = DragProbe(frame: NSRect(x: 0, y: 0, width: 440, height: 440))
        surface.count = 4; surface.enabled = [0, 1, 2, 3]; surface.canReorder = true
        var clicks = 0, starts = 0
        surface.click = { _ in clicks += 1 }
        surface.beginDrag = { _ in starts += 1; return .init(session: surface.session, contextID: "first") }
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        // Unattached flipped view conversion is stable and never uses system input.
        let point = surface.convert(NSPoint(x: 220, y: 40), to: nil)
        surface.mouseDown(with: try event(.leftMouseDown, point.x, point.y))
        surface.mouseDragged(with: try event(.leftMouseDragged, point.x + 2, point.y))
        surface.mouseUp(with: try event(.leftMouseUp, point.x + 2, point.y))
        XCTAssertEqual(clicks, 1); XCTAssertEqual(starts, 0)
        surface.mouseDown(with: try event(.leftMouseDown, point.x, point.y))
        surface.mouseDragged(with: try event(.leftMouseDragged, point.x + 5, point.y))
        surface.mouseUp(with: try event(.leftMouseUp, point.x + 5, point.y))
        XCTAssertEqual(clicks, 1, "A drag must never also switch Spaces on release")
        XCTAssertEqual(starts, 1); XCTAssertEqual(surface.nativeStarts, 1)
        XCTAssertNil(surface.hitTest(surface.convert(NSPoint(x: 220, y: 220), to: nil)))
        XCTAssertNil(surface.hitTest(surface.convert(.zero, to: nil)))
        surface.toolsIndex = 0
        XCTAssertNil(surface.hitTest(surface.convert(NSPoint(x: 220, y: 98), to: nil)), "Rename/delete receive their own clicks")
        surface.isEnabled = false
        XCTAssertNil(surface.hitTest(point))
    }
}

@MainActor private final class DragProbe: WheelInteractionSurface.CursorView {
    var nativeStarts = 0
    override func startDragging(payload: WorkspaceComposerDrag, name: String, event: NSEvent) { nativeStarts += 1 }
}
