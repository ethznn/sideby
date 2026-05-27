import XCTest
@testable import SidebyCore

final class DisplaySpacePlanTests: XCTestCase {
    func testReconcileCreatesOneSetPerConnectedDisplay() {
        var plan = DisplaySpacePlan.default

        plan.reconcile(with: Self.twoDisplayLayout)

        XCTAssertEqual(plan.displaySpaces.map(\.displayID), ["built-in", "external-lg"])
        XCTAssertEqual(plan.spaces(displayID: "built-in").map(\.order), [1])
        XCTAssertEqual(plan.spaces(displayID: "external-lg").map(\.order), [1])
    }

    func testUpdatesLabelsByDisplayAndSpaceOrder() {
        var plan = DisplaySpacePlan.default

        plan.updateLabel(displayID: "built-in", spaceOrder: 4, label: "Code")

        XCTAssertEqual(plan.label(displayID: "built-in", spaceOrder: 4), "Code")
        XCTAssertEqual(plan.spaces(displayID: "built-in").map(\.order), [1, 2, 3, 4])
    }

    func testVisibleSpaceCountIncludesCaptureCountLabelsAndSuggestions() {
        var plan = DisplaySpacePlan.default
        plan.updateLabel(displayID: "built-in", spaceOrder: 4, label: "Code")

        XCTAssertEqual(
            plan.visibleSpaceCount(
                displayID: "built-in",
                captureCount: 3,
                suggestionOrders: [2, 5]
            ),
            5
        )
    }

    private static let twoDisplayLayout = DisplayLayout(
        displays: [
            DisplayInfo(id: "built-in", name: "Built-in Display", isPrimary: true, isBuiltin: true),
            DisplayInfo(id: "external-lg", name: "LG Display", isPrimary: false, isBuiltin: false)
        ]
    )
}
