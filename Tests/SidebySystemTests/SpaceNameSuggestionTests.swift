import XCTest
import SidebyCore
@testable import SidebySystem

final class SpaceNameSuggestionTests: XCTestCase {
    func testNamesEverySpaceFromItsOwnWindowsAndIgnoresStickyWindows() {
        let layout = DisplayLayout(displays: [.init(id: "main", name: "Main", isPrimary: true, isBuiltin: true,
            frame: .init(x: 0, y: 0, width: 1000, height: 800))])
        func candidate(_ spaces: Set<UInt64>, _ app: String, _ title: String?, width: CGFloat = 900) -> SpaceWindowNameCandidate {
            .init(spaceIDs: spaces, window: .init(ownerName: app, windowTitle: title,
                bounds: CGRect(x: 0, y: 0, width: width, height: 700), processIdentifier: 42, layer: 0))
        }
        let names = SpaceNameSuggestionResolver.names(windows: [
            candidate([11, 12], "Sticky", "Everywhere", width: 1000),
            candidate([11], "Editor", "Payment.swift"),
            candidate([12], "Safari", nil),
            candidate([12], "Small", "Small utility", width: 100)
        ], layout: layout, spaceIDsByDisplayID: ["main": [11, 12, 13]])
        XCTAssertEqual(names["main"], [0: "Payment.swift", 1: "Safari"])
    }
}
