import XCTest
@testable import SidebySystem

final class SpaceLayoutReaderTests: XCTestCase {
    func testParsesManagedDisplaySpacesPayload() {
        let payload: [[String: Any]] = [
            [
                "Display Identifier": "29047B54-6562-49DE-AA42-F7A696BE4F6B",
                "Current Space": ["ManagedSpaceID": NSNumber(value: 959)],
                "Spaces": [
                    ["ManagedSpaceID": NSNumber(value: 1)],
                    ["ManagedSpaceID": NSNumber(value: 928)],
                    ["ManagedSpaceID": NSNumber(value: 959)]
                ]
            ],
            [
                "Display Identifier": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
                "Current Space": ["ManagedSpaceID": NSNumber(value: 932)],
                "Spaces": [
                    ["ManagedSpaceID": NSNumber(value: 941)],
                    ["ManagedSpaceID": NSNumber(value: 932)]
                ]
            ]
        ]

        let layouts = DisplaySpaceLayout.displays(fromManagedDisplaySpaces: payload)

        XCTAssertEqual(layouts, [
            DisplaySpaceLayout(
                displayUUID: "29047B54-6562-49DE-AA42-F7A696BE4F6B",
                spaceIDs: [1, 928, 959],
                currentSpaceID: 959
            ),
            DisplaySpaceLayout(
                displayUUID: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
                spaceIDs: [941, 932],
                currentSpaceID: 932
            )
        ])
    }

    func testParsingFailsWhenAnyEntryIsMalformed() {
        let missingCurrent: [[String: Any]] = [
            [
                "Display Identifier": "A",
                "Spaces": [["ManagedSpaceID": NSNumber(value: 1)]]
            ]
        ]
        let emptySpaces: [[String: Any]] = [
            [
                "Display Identifier": "A",
                "Current Space": ["ManagedSpaceID": NSNumber(value: 1)],
                "Spaces": [[String: Any]]()
            ]
        ]

        XCTAssertNil(DisplaySpaceLayout.displays(fromManagedDisplaySpaces: missingCurrent))
        XCTAssertNil(DisplaySpaceLayout.displays(fromManagedDisplaySpaces: emptySpaces))
    }
}
