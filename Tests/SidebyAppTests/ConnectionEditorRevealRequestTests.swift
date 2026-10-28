import XCTest
import SidebyCore
@testable import SidebyApp

final class ConnectionEditorRevealRequestTests: XCTestCase {
    private let context = ContextDefinition(id: "work", order: 1, name: "Work", displaySpaceIndexes: ["a": 0])

    func testRequestNeverSubstitutesAnotherContextOrDisplay() {
        let request = ConnectionEditorRevealRequest(contextID: "work", displayID: "a")
        XCTAssertEqual(request.resolve(context: nil, connectedIDs: ["a"], readableIDs: ["a"], canEdit: true).kind, .missingContext)
        let removed = ContextDefinition(id: "work", order: 1, name: "Work", displaySpaceIndexes: ["b": 0])
        XCTAssertEqual(request.resolve(context: removed, connectedIDs: ["a", "b"], readableIDs: ["a", "b"], canEdit: true).kind, .connectionOnly)
        XCTAssertEqual(request.resolve(context: context, connectedIDs: [], readableIDs: [], canEdit: true).kind, .offlineDisplay)
        XCTAssertEqual(request.resolve(context: context, connectedIDs: ["a"], readableIDs: [], canEdit: true).kind, .unreadableDisplay)
    }

    func testReadableMemberEditingDependsOnEditPermissionNotSwitchParticipation() {
        let request = ConnectionEditorRevealRequest(contextID: "work", displayID: "a")
        let blocked = request.resolve(context: context, connectedIDs: ["a"], readableIDs: ["a"], canEdit: false)
        XCTAssertEqual(blocked.kind, .pickableDisplay); XCTAssertFalse(blocked.canOpenPicker)
        XCTAssertTrue(request.resolve(context: context, connectedIDs: ["a"], readableIDs: ["a"], canEdit: true).canOpenPicker)
    }

    func testLateCallbacksCannotOpenOrCloseNewerRequestsAndCancellationIsTerminal() {
        let a = ConnectionEditorRevealRequest(contextID: "work", displayID: "a")
        let b = ConnectionEditorRevealRequest(contextID: "work", displayID: "a")
        var state = ConnectionRepairSession()
        state.show(a); state.setPicker(true, for: a.id)
        state.show(b)
        XCTAssertNil(state.pickerID, "Repeated target still starts a fresh request")
        state.setPicker(true, for: b.id)
        state.setPicker(false, for: a.id); state.dismiss(a.id)
        XCTAssertEqual(state.target, b); XCTAssertEqual(state.pickerID, b.id)
        state.closePicker(); XCTAssertEqual(state.target, b)
        state.dismiss(b.id); state.setPicker(true, for: b.id)
        XCTAssertNil(state.target); XCTAssertNil(state.pickerID)
    }
}
