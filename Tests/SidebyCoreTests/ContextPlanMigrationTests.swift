import XCTest
@testable import SidebyCore

final class ContextPlanMigrationTests: XCTestCase {
    func testMigratesSpaceOrdersIntoSingleContextNames() {
        let legacy = DisplaySpacePlan(
            displaySpaces: [
                DisplaySpaceSet(displayID: "built-in", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Mail"),
                    DisplaySpaceSlot(order: 2, label: "Code")
                ]),
                DisplaySpaceSet(displayID: "external-lg", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Calendar"),
                    DisplaySpaceSlot(order: 2, label: "Preview")
                ])
            ],
            defaultCaptureCount: 4
        )

        let plan = ContextPlanMigration.migrate(from: legacy)

        XCTAssertEqual(plan.contexts.map(\.name), ["Mail / Calendar", "Code / Preview"])
        XCTAssertEqual(plan.contexts.map(\.id), ["context-1", "context-2"])
        XCTAssertEqual(plan.contexts.map(\.order), [1, 2])
        XCTAssertEqual(plan.currentContextID, "context-1")
        XCTAssertEqual(plan.captureLimit, 4)
        XCTAssertEqual(plan.syncState, .synchronized)
    }

    func testMigrationJoinsLabelsBySortedDisplayIDWhenInputIsUnsorted() {
        let legacy = DisplaySpacePlan(
            displaySpaces: [
                DisplaySpaceSet(displayID: "z-display", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Preview")
                ]),
                DisplaySpaceSet(displayID: "a-display", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Mail")
                ])
            ],
            defaultCaptureCount: 2
        )

        let plan = ContextPlanMigration.migrate(from: legacy)

        XCTAssertEqual(plan.contexts.map(\.name), ["Mail / Preview"])
        XCTAssertEqual(plan.contexts.map(\.id), ["context-1"])
        XCTAssertEqual(plan.contexts.map(\.order), [1])
    }

    func testMigrationDeduplicatesAndFallsBackToDefaultNames() {
        let legacy = DisplaySpacePlan(
            displaySpaces: [
                DisplaySpaceSet(displayID: "a", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Code"),
                    DisplaySpaceSlot(order: 2, label: "")
                ]),
                DisplaySpaceSet(displayID: "b", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Code"),
                    DisplaySpaceSlot(order: 3, label: "Docs")
                ])
            ],
            defaultCaptureCount: 3
        )

        let plan = ContextPlanMigration.migrate(from: legacy)

        XCTAssertEqual(plan.contexts.map(\.name), ["Code", "Context 2", "Docs"])
        XCTAssertEqual(plan.contexts.map(\.id), ["context-1", "context-2", "context-3"])
        XCTAssertEqual(plan.contexts.map(\.order), [1, 2, 3])
    }

    func testMigrationDeduplicatesWhitespaceTrimmedLabels() {
        let legacy = DisplaySpacePlan(
            displaySpaces: [
                DisplaySpaceSet(displayID: "a", spaces: [
                    DisplaySpaceSlot(order: 1, label: "  Code\n")
                ]),
                DisplaySpaceSet(displayID: "b", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Code")
                ])
            ],
            defaultCaptureCount: 2
        )

        let plan = ContextPlanMigration.migrate(from: legacy)

        XCTAssertEqual(plan.contexts.map(\.name), ["Code"])
    }

    func testMigrationFallsBackForWhitespaceOnlyLabels() {
        let legacy = DisplaySpacePlan(
            displaySpaces: [
                DisplaySpaceSet(displayID: "a", spaces: [
                    DisplaySpaceSlot(order: 1, label: " \n\t ")
                ])
            ],
            defaultCaptureCount: 2
        )

        let plan = ContextPlanMigration.migrate(from: legacy)

        XCTAssertEqual(plan.contexts.map(\.name), ["Context 1"])
    }

    func testMigrationOfEmptyLegacyPlanKeepsOneDefaultContextAndCaptureLimit() {
        let legacy = DisplaySpacePlan(displaySpaces: [], defaultCaptureCount: 4)

        let plan = ContextPlanMigration.migrate(from: legacy)

        XCTAssertEqual(plan.contexts.map(\.name), ["Context 1"])
        XCTAssertEqual(plan.contexts.map(\.id), ["context-1"])
        XCTAssertEqual(plan.contexts.map(\.order), [1])
        XCTAssertEqual(plan.captureLimit, 4)
    }

    func testMigrationCaptureLimitClampsThroughContextPlan() {
        let legacy = DisplaySpacePlan(
            displaySpaces: [
                DisplaySpaceSet(displayID: "a", spaces: [
                    DisplaySpaceSlot(order: 1, label: "Code")
                ])
            ],
            defaultCaptureCount: 99
        )

        let plan = ContextPlanMigration.migrate(from: legacy)

        XCTAssertEqual(plan.captureLimit, 12)
    }
}
