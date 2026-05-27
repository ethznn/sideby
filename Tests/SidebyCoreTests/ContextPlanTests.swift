import XCTest
@testable import SidebyCore

final class ContextPlanTests: XCTestCase {
    func testDefaultPlanCreatesThreeSequentialContexts() {
        let plan = ContextPlan.default

        XCTAssertEqual(plan.contexts.map(\.name), ["Context 1", "Context 2", "Context 3"])
        XCTAssertEqual(plan.currentContext?.name, "Context 1")
    }

    func testReconcileAddsSlotsForConnectedDisplaysAndPreservesDisconnectedLabels() {
        var plan = ContextPlan.default

        plan.updateLabel(contextID: "context-1", displayID: "old-display", label: "Docs")
        plan.reconcile(with: Self.twoDisplayLayout)

        XCTAssertEqual(plan.label(contextID: "context-1", displayID: "built-in"), "")
        XCTAssertEqual(plan.label(contextID: "context-1", displayID: "external-lg"), "")
        XCTAssertEqual(plan.label(contextID: "context-1", displayID: "old-display"), "Docs")
    }

    func testUpdatesLabelsForDisplaySlots() {
        var plan = ContextPlan.default

        plan.reconcile(with: Self.twoDisplayLayout)
        plan.updateLabel(contextID: "context-1", displayID: "built-in", label: "Code")

        XCTAssertEqual(plan.label(contextID: "context-1", displayID: "built-in"), "Code")
    }

    func testAddContextUsesNextSequentialContextNameAndDisplaySlots() {
        var plan = ContextPlan.default

        plan.reconcile(with: Self.twoDisplayLayout)
        let added = plan.addContext(displayLayout: Self.twoDisplayLayout)

        XCTAssertEqual(added.name, "Context 4")
        XCTAssertEqual(plan.contexts.map(\.name), ["Context 1", "Context 2", "Context 3", "Context 4"])
        XCTAssertEqual(
            Set(added.displaySlots.map(\.displayID)),
            ["built-in", "external-lg"]
        )
    }

    func testDeleteContextPreservesAtLeastOneContextAndMovesCurrentPointer() {
        var plan = ContextPlan.default

        plan.setCurrentContext(id: "context-2")
        XCTAssertTrue(plan.deleteContext(id: "context-2"))
        XCTAssertEqual(plan.currentContext?.name, "Context 1")

        XCTAssertTrue(plan.deleteContext(id: "context-1"))
        XCTAssertFalse(plan.deleteContext(id: "context-3"))
        XCTAssertEqual(plan.contexts.count, 1)
    }

    func testSetCurrentChangesPointerWithoutNavigation() {
        var plan = ContextPlan.default

        XCTAssertTrue(plan.setCurrentContext(id: "context-3"))

        XCTAssertEqual(plan.currentContext?.name, "Context 3")
    }

    func testNavigationBlocksAtEdgesAndAllowsAdjacentContexts() {
        var plan = ContextPlan.default

        XCTAssertFalse(plan.navigation(for: .previous).isAllowed)
        XCTAssertEqual(plan.navigation(for: .previous).diagnostic?.title, "No previous Context")
        XCTAssertTrue(plan.navigation(for: .next).isAllowed)
        XCTAssertEqual(plan.navigation(for: .next).targetContext?.name, "Context 2")

        plan.setCurrentContext(id: "context-3")

        XCTAssertFalse(plan.navigation(for: .next).isAllowed)
        XCTAssertEqual(plan.navigation(for: .next).diagnostic?.title, "No next Context")
        XCTAssertTrue(plan.navigation(for: .previous).isAllowed)
        XCTAssertEqual(plan.navigation(for: .previous).targetContext?.name, "Context 2")
    }

    func testSuccessfulNavigationUpdatesPointerButFailureDoesNot() {
        var plan = ContextPlan.default

        plan.applyFailedNavigation(.next)
        XCTAssertEqual(plan.currentContext?.name, "Context 1")

        plan.applySuccessfulNavigation(.next)
        XCTAssertEqual(plan.currentContext?.name, "Context 2")
    }

    private static let twoDisplayLayout = DisplayLayout(
        displays: [
            DisplayInfo(id: "built-in", name: "Built-in Display", isPrimary: true, isBuiltin: true),
            DisplayInfo(id: "external-lg", name: "LG Display", isPrimary: false, isBuiltin: false)
        ]
    )
}
