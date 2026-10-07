import XCTest
@testable import SidebyCore

final class SavedWorkspaceHistoryTests: XCTestCase {
    private func change(_ index: Int) -> SavedWorkspaceUndo {
        .init(contexts: [.init(id: "one", order: 1, name: "Name \(index)", displaySpaceIndexes: ["mac": index])],
            bookmarks: ["one": ["mac": "space-\(index)"]], shortcutSlots: ["one": 1], label: "Change \(index)",
            resultingContexts: [.init(id: "one", order: 1, name: "Name \(index + 1)", displaySpaceIndexes: ["mac": index + 1])],
            resultingBookmarks: ["one": ["mac": "space-\(index + 1)"]])
    }

    func testOldSettingsDecodeAndKeepTheirSingleUndo() throws {
        var library = SavedWorkspaceLibrary()
        library.undo = change(0)
        let data = try JSONEncoder().encode(library)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["previousUndos"])
        var decoded = try JSONDecoder().decode(SavedWorkspaceLibrary.self, from: data)
        XCTAssertEqual(decoded.undoCount, 1)
        decoded.recordUndo(change(1))
        decoded.popUndo()
        XCTAssertEqual(decoded.undo, library.undo)
        decoded.popUndo()
        XCTAssertEqual(decoded.undoCount, 0)
    }

    func testHistoryIsBoundedAndSurvivesSerialization() throws {
        var library = SavedWorkspaceLibrary()
        for index in 0..<25 { library.recordUndo(change(index)) }
        library = try JSONDecoder().decode(SavedWorkspaceLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(library.undoCount, 20)
        for index in stride(from: 24, through: 5, by: -1) {
            XCTAssertEqual(library.undo, change(index))
            library.popUndo()
        }
        XCTAssertNil(library.undo)
    }

    func testNewBranchAfterUndoKeepsOlderEditsButDropsUnrelatedHistory() {
        var library = SavedWorkspaceLibrary()
        for index in 0..<3 { library.recordUndo(change(index)) }
        library.popUndo()
        library.recordUndo(change(2))
        XCTAssertEqual(library.undoCount, 3)
        library.recordUndo(change(10))
        XCTAssertEqual(library.undoCount, 1, "Out-of-band edits cannot bridge unrelated undo histories")
    }
}
