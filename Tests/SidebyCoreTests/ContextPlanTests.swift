import Foundation
import XCTest
@testable import SidebyCore

final class ContextPlanTests: XCTestCase {
    func testDefaultPlanCreatesThreeSynchronizedContexts() {
        let plan = ContextPlan.default

        XCTAssertEqual(plan.contexts.map(\.name), ["Context 1", "Context 2", "Context 3"])
        XCTAssertEqual(plan.currentContext?.name, "Context 1")
        XCTAssertEqual(plan.captureLimit, 3)
        XCTAssertEqual(plan.syncState, .synchronized)
    }

    func testRenamesContextWithoutDisplayLabels() {
        var plan = ContextPlan.default

        plan.renameContext(id: "context-2", name: "Research")

        XCTAssertEqual(plan.contexts[1].name, "Research")
    }

    func testContextDefinitionStoresTrimmedName() {
        let context = ContextDefinition(id: "context-1", order: 1, name: "  Research \n")

        XCTAssertEqual(context.name, "Research")
    }

    func testContextDefinitionDecodeUsesModelNormalization() throws {
        let data = Data("""
        {
            "id": "context-1",
            "order": 0,
            "name": "  Research  ",
            "displaySlots": [
                { "displayID": "built-in", "label": "Legacy Label" }
            ]
        }
        """.utf8)

        let context = try JSONDecoder().decode(ContextDefinition.self, from: data)

        XCTAssertEqual(context.order, 1)
        XCTAssertEqual(context.name, "Research")
    }

    func testReplaceContextsKeepsValidCurrentPointerAndCaptureLimit() {
        var plan = ContextPlan.default
        let contexts = [
            ContextDefinition(id: "context-1", order: 1, name: "Code"),
            ContextDefinition(id: "context-2", order: 2, name: "Review")
        ]

        plan.replaceContexts(contexts, currentContextID: "context-2", captureLimit: 5)

        XCTAssertEqual(plan.contexts.map(\.name), ["Code", "Review"])
        XCTAssertEqual(plan.currentContext?.name, "Review")
        XCTAssertEqual(plan.captureLimit, 5)
        XCTAssertEqual(plan.syncState, .synchronized)
    }

    func testDuplicateContextIDsNormalizeToUniqueIDs() {
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(id: "shared", order: 1, name: "Code"),
                ContextDefinition(id: "shared", order: 2, name: "Review"),
                ContextDefinition(id: "notes", order: 3, name: "Notes")
            ],
            currentContextID: "shared"
        )

        XCTAssertEqual(plan.contexts.map(\.id), ["shared", "context-1", "notes"])
        XCTAssertEqual(Set(plan.contexts.map(\.id)).count, plan.contexts.count)
        XCTAssertEqual(plan.contexts.map(\.order), [1, 2, 3])
    }

    func testEmptyContextIDsMintUniqueIDsWithoutCollidingWithExistingContextIDs() {
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(id: "context-1", order: 1, name: "Code"),
                ContextDefinition(id: "", order: 2, name: "Review"),
                ContextDefinition(id: "context-2", order: 3, name: "Notes"),
                ContextDefinition(id: "", order: 4, name: "Chat")
            ],
            currentContextID: "context-1"
        )

        XCTAssertEqual(plan.contexts.map(\.id), ["context-1", "context-3", "context-2", "context-4"])
        XCTAssertEqual(Set(plan.contexts.map(\.id)).count, plan.contexts.count)
    }

    func testNavigationAndCurrentContextAreUnambiguousAfterIDNormalization() {
        var plan = ContextPlan(
            contexts: [
                ContextDefinition(id: "shared", order: 1, name: "Code"),
                ContextDefinition(id: "shared", order: 2, name: "Review"),
                ContextDefinition(id: "context-1", order: 3, name: "Notes")
            ],
            currentContextID: "shared"
        )
        let reviewID = plan.contexts[1].id

        XCTAssertNotEqual(reviewID, "shared")
        XCTAssertTrue(plan.setCurrentContext(id: reviewID))
        XCTAssertEqual(plan.currentContext?.name, "Review")
        XCTAssertTrue(plan.navigation(for: .previous).isAllowed)
        XCTAssertEqual(plan.navigation(for: .previous).targetContext?.name, "Code")
        XCTAssertTrue(plan.navigation(for: .next).isAllowed)
        XCTAssertEqual(plan.navigation(for: .next).targetContext?.name, "Notes")

        plan.applySuccessfulNavigation(.next)

        XCTAssertEqual(plan.currentContext?.name, "Notes")
    }

    func testInitializerNormalizesCaptureLimitBelowMinimum() {
        let plan = ContextPlan(
            contexts: ContextPlan.default.contexts,
            currentContextID: "context-1",
            captureLimit: 0
        )

        XCTAssertEqual(plan.captureLimit, 1)
    }

    func testSetCaptureLimitNormalizesAboveMaximum() {
        var plan = ContextPlan.default

        plan.setCaptureLimit(13)

        XCTAssertEqual(plan.captureLimit, 12)
    }

    func testReplaceContextsNormalizesCaptureLimitBelowMinimum() {
        var plan = ContextPlan.default

        plan.replaceContexts(
            [ContextDefinition(id: "context-1", order: 1, name: "Code")],
            currentContextID: "context-1",
            captureLimit: -5
        )

        XCTAssertEqual(plan.captureLimit, 1)
    }

    func testDecodesLegacyPlanMissingSyncStateAndCaptureLimitIgnoringDisplaySlots() throws {
        let data = Data("""
        {
            "contexts": [
                {
                    "id": "context-1",
                    "order": 1,
                    "name": "  Code  ",
                    "displaySlots": [
                        { "displayID": "built-in", "label": "Legacy Label" }
                    ]
                },
                {
                    "id": "context-2",
                    "order": 2,
                    "name": "Review",
                    "displaySlots": []
                }
            ],
            "currentContextID": "context-2"
        }
        """.utf8)

        let plan = try JSONDecoder().decode(ContextPlan.self, from: data)

        XCTAssertEqual(plan.contexts.map(\.name), ["Code", "Review"])
        XCTAssertEqual(plan.currentContext?.name, "Review")
        XCTAssertEqual(plan.syncState, .synchronized)
        XCTAssertEqual(plan.captureLimit, 2)
    }

    func testDecodedCaptureLimitNormalizesAboveMaximum() throws {
        let data = Data("""
        {
            "contexts": [
                { "id": "context-1", "order": 1, "name": "Context 1" }
            ],
            "currentContextID": "context-1",
            "syncState": "synchronized",
            "captureLimit": 99
        }
        """.utf8)

        let plan = try JSONDecoder().decode(ContextPlan.self, from: data)

        XCTAssertEqual(plan.captureLimit, 12)
    }

    func testDecodedInvalidCurrentIDFallsBackToFirstContext() throws {
        let data = Data("""
        {
            "contexts": [
                { "id": "context-1", "order": 1, "name": "Code" },
                { "id": "context-2", "order": 2, "name": "Review" }
            ],
            "currentContextID": "missing",
            "syncState": "needsSync",
            "captureLimit": 2
        }
        """.utf8)

        let plan = try JSONDecoder().decode(ContextPlan.self, from: data)

        XCTAssertEqual(plan.currentContext?.name, "Code")
        XCTAssertEqual(plan.syncState, .needsSync)
    }

    func testDecodedUnknownSyncStateDefaultsToSynchronized() throws {
        let data = Data("""
        {
            "contexts": [
                { "id": "context-1", "order": 1, "name": "Code" }
            ],
            "currentContextID": "context-1",
            "syncState": "futureSyncState",
            "captureLimit": 1
        }
        """.utf8)

        let plan = try JSONDecoder().decode(ContextPlan.self, from: data)

        XCTAssertEqual(plan.syncState, .synchronized)
    }

    func testEncodedDefaultPlanDoesNotPersistDisplaySlots() throws {
        let data = try JSONEncoder().encode(ContextPlan.default)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("displaySlots"))
    }

    func testMarkNeedsSyncBlocksNavigation() {
        var plan = ContextPlan.default

        plan.markNeedsSync()
        let navigation = plan.navigation(for: .next)

        XCTAssertEqual(plan.syncState, .needsSync)
        XCTAssertFalse(navigation.isAllowed)
        XCTAssertEqual(navigation.diagnostic?.title, "Context needs sync")
    }

    func testSetCurrentRestoresSynchronizedState() {
        var plan = ContextPlan.default
        plan.markNeedsSync()

        XCTAssertTrue(plan.setCurrentContext(id: "context-3"))

        XCTAssertEqual(plan.currentContext?.name, "Context 3")
        XCTAssertEqual(plan.syncState, .synchronized)
    }

    func testNavigationBlocksAtEdgesAndAllowsAdjacentContextsWhenSynchronized() {
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

    func testSuccessfulNavigationUpdatesPointerButFailedNavigationDoesNot() {
        var plan = ContextPlan.default

        plan.applyFailedNavigation(.next)
        XCTAssertEqual(plan.currentContext?.name, "Context 1")

        plan.applySuccessfulNavigation(.next)
        XCTAssertEqual(plan.currentContext?.name, "Context 2")
    }
}
