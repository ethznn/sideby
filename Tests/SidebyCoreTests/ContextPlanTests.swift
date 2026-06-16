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
        XCTAssertTrue(plan.isPinned)
    }

    func testRenamesContextWithoutDisplayLabels() {
        var plan = ContextPlan.default

        plan.renameContext(id: "context-2", name: "Research")

        XCTAssertEqual(plan.contexts[1].name, "Research")
    }

    func testRenamingContextPreservesDisplayMembership() {
        var plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "Code",
                    displayIDs: ["external-lg", "built-in"]
                )
            ],
            currentContextID: "context-1"
        )

        plan.renameContext(id: "context-1", name: "Focus")

        XCTAssertEqual(plan.contexts[0].name, "Focus")
        XCTAssertEqual(plan.contexts[0].displayIDs, ["built-in", "external-lg"])
    }

    func testContextDefinitionStoresTrimmedName() {
        let context = ContextDefinition(id: "context-1", order: 1, name: "  Research \n")

        XCTAssertEqual(context.name, "Research")
    }

    func testContextDefinitionStoresSortedUniqueDisplayIDs() {
        let context = ContextDefinition(
            id: "context-1",
            order: 1,
            name: "Research",
            displayIDs: ["external-lg", "built-in", "built-in"]
        )

        XCTAssertEqual(context.displayIDs, ["built-in", "external-lg"])
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
        XCTAssertEqual(context.displayIDs, [])
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

    func testReplaceContextsPreservesDisplayMembership() {
        var plan = ContextPlan.default
        let contexts = [
            ContextDefinition(
                id: "context-1",
                order: 1,
                name: "Code",
                displayIDs: ["built-in", "external-lg"]
            ),
            ContextDefinition(
                id: "context-2",
                order: 2,
                name: "Review",
                displayIDs: ["built-in"]
            )
        ]

        plan.replaceContexts(contexts, currentContextID: "context-2", captureLimit: 2)

        XCTAssertEqual(plan.contexts[0].displayIDs, ["built-in", "external-lg"])
        XCTAssertEqual(plan.contexts[1].displayIDs, ["built-in"])
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

    func testReplaceContextsRearmsPinnedMatching() {
        var plan = ContextPlan.default
        plan.setPinned(false)

        plan.replaceContexts(
            [ContextDefinition(id: "context-1", order: 1, name: "Code")],
            currentContextID: "context-1",
            captureLimit: 1
        )

        XCTAssertTrue(plan.isPinned)
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

    func testEncodedPlanPersistsDisplayMembershipButNotLegacyDisplaySlots() throws {
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "Code",
                    displayIDs: ["built-in", "external-lg"]
                )
            ],
            currentContextID: "context-1"
        )
        let data = try JSONEncoder().encode(plan)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("displaySlots"))
        XCTAssertTrue(json.contains("displayIDs"))
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

    func testUnsynchronizedMovementPausesPinnedContextMatchingWithoutChangingCurrentContext() {
        var plan = ContextPlan.default

        plan.pauseContextMatchingForUnsynchronizedMovement()

        XCTAssertFalse(plan.isPinned)
        XCTAssertEqual(plan.syncState, .needsSync)
        XCTAssertEqual(plan.currentContextID, "context-1")
    }

    func testReenablingPinnedContextMatchingKeepsNeedsSyncUntilCurrentContextIsExplicitlySet() {
        var plan = ContextPlan.default
        plan.pauseContextMatchingForUnsynchronizedMovement()

        plan.setPinned(true)
        let intent = plan.switchIntent(for: .next)

        XCTAssertTrue(plan.isPinned)
        XCTAssertEqual(plan.syncState, .needsSync)
        XCTAssertEqual(plan.currentContextID, "context-1")
        XCTAssertFalse(intent.shouldExecute)
        XCTAssertEqual(intent.diagnostic?.title, "Context needs sync")
    }

    func testUnpinnedNeedsSyncSwitchIntentFallsBackToGeneralMovement() {
        var plan = ContextPlan.default
        plan.pauseContextMatchingForUnsynchronizedMovement()

        let intent = plan.switchIntent(for: .next)

        XCTAssertTrue(intent.shouldExecute)
        XCTAssertNil(intent.targetContext)
        XCTAssertEqual(intent.targetDisplayIDs, [])
        XCTAssertNil(intent.diagnostic)
    }

    func testDecodedLegacyPlanDefaultsToPinned() throws {
        let data = Data("""
        {
            "contexts": [
                { "id": "context-1", "order": 1, "name": "Code" }
            ],
            "currentContextID": "context-1",
            "syncState": "synchronized",
            "captureLimit": 1
        }
        """.utf8)

        let plan = try JSONDecoder().decode(ContextPlan.self, from: data)

        XCTAssertTrue(plan.isPinned)
    }

    func testExternalSpaceChangePausesOnlyEnabledPinnedSynchronizedContextMatching() {
        var synchronizedPinned = ContextPlan.default
        XCTAssertTrue(
            ExternalSpaceChangeContextPolicy.shouldPauseContextMatching(
                isSidebyEnabled: true,
                plan: synchronizedPinned
            )
        )

        XCTAssertFalse(
            ExternalSpaceChangeContextPolicy.shouldPauseContextMatching(
                isSidebyEnabled: false,
                plan: synchronizedPinned
            )
        )

        synchronizedPinned.setPinned(false)
        XCTAssertFalse(
            ExternalSpaceChangeContextPolicy.shouldPauseContextMatching(
                isSidebyEnabled: true,
                plan: synchronizedPinned
            )
        )

        var needsSync = ContextPlan.default
        needsSync.markNeedsSync()
        XCTAssertFalse(
            ExternalSpaceChangeContextPolicy.shouldPauseContextMatching(
                isSidebyEnabled: true,
                plan: needsSync
            )
        )
    }

    func testContextPinningPersistsThroughCoding() throws {
        var plan = ContextPlan.default

        plan.setPinned(false)
        let decoded = try JSONDecoder().decode(ContextPlan.self, from: JSONEncoder().encode(plan))

        XCTAssertFalse(decoded.isPinned)
    }

    func testContextDisplayMembershipPersistsThroughCoding() throws {
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "Code",
                    displayIDs: ["built-in", "external-lg"]
                ),
                ContextDefinition(
                    id: "context-2",
                    order: 2,
                    name: "Review",
                    displayIDs: ["built-in"]
                )
            ],
            currentContextID: "context-1"
        )
        let decoded = try JSONDecoder().decode(ContextPlan.self, from: JSONEncoder().encode(plan))

        XCTAssertEqual(decoded.contexts.map(\.displayIDs), [["built-in", "external-lg"], ["built-in"]])
    }

    func testContextDisplaySpaceIndexesPersistWhenNonDefault() throws {
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-4",
                    order: 4,
                    name: "Review",
                    displayIDs: ["built-in", "external-lg"],
                    displaySpaceIndexes: ["built-in": 2, "external-lg": 3]
                )
            ],
            currentContextID: "context-4"
        )

        let data = try JSONEncoder().encode(plan)
        let json = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(ContextPlan.self, from: data)

        XCTAssertTrue(json.contains("displaySpaceIndexes"))
        XCTAssertEqual(decoded.contexts[0].displayIDs, ["built-in", "external-lg"])
        XCTAssertEqual(decoded.contexts[0].displaySpaceIndexes, ["built-in": 2, "external-lg": 3])
    }

    func testMovingDisplaySpaceToEmptyNonCurrentContextCreatesGapAtSource() {
        var plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "One",
                    displayIDs: ["built-in", "external-lg"],
                    displaySpaceIndexes: ["built-in": 0, "external-lg": 0]
                ),
                ContextDefinition(
                    id: "context-2",
                    order: 2,
                    name: "Two",
                    displayIDs: ["external-lg"],
                    displaySpaceIndexes: ["external-lg": 1]
                ),
                ContextDefinition(
                    id: "context-3",
                    order: 3,
                    name: "Three",
                    displayIDs: ["built-in", "external-lg"],
                    displaySpaceIndexes: ["built-in": 1, "external-lg": 2]
                )
            ],
            currentContextID: "context-1"
        )

        XCTAssertTrue(plan.moveDisplaySpace(displayID: "built-in", spaceIndex: 1, toContextID: "context-2"))

        XCTAssertNil(plan.contexts[2].spaceIndex(for: "built-in"))
        XCTAssertEqual(plan.contexts[1].spaceIndex(for: "built-in"), 1)
        XCTAssertEqual(plan.contexts.map(\.displayIDs), [
            ["built-in", "external-lg"],
            ["built-in", "external-lg"],
            ["external-lg"]
        ])
        XCTAssertEqual(plan.syncState, .synchronized)
    }

    func testMovingDisplaySpaceToOccupiedContextSwapsIndexes() {
        var plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "One",
                    displayIDs: ["built-in"],
                    displaySpaceIndexes: ["built-in": 0]
                ),
                ContextDefinition(
                    id: "context-2",
                    order: 2,
                    name: "Two",
                    displayIDs: ["built-in"],
                    displaySpaceIndexes: ["built-in": 1]
                )
            ],
            currentContextID: "context-1"
        )

        XCTAssertTrue(plan.moveDisplaySpace(displayID: "built-in", spaceIndex: 0, toContextID: "context-2"))

        XCTAssertEqual(plan.contexts[0].spaceIndex(for: "built-in"), 1)
        XCTAssertEqual(plan.contexts[1].spaceIndex(for: "built-in"), 0)
        XCTAssertEqual(plan.syncState, .needsSync)
    }

    func testMovingMissingDisplaySpaceReturnsFalse() {
        var plan = ContextPlan.default

        XCTAssertFalse(plan.moveDisplaySpace(displayID: "missing", spaceIndex: 0, toContextID: "context-2"))
        XCTAssertEqual(plan, .default)
    }

    func testPinnedSwitchIntentBlocksAtContextEdges() {
        var plan = ContextPlan.default

        XCTAssertTrue(plan.setCurrentContext(id: "context-3"))
        let intent = plan.switchIntent(for: .next)

        XCTAssertFalse(intent.shouldExecute)
        XCTAssertNil(intent.targetContext)
        XCTAssertEqual(intent.targetDisplayIDs, [])
        XCTAssertEqual(intent.diagnostic?.title, "No next Context")
    }

    func testUnpinnedSwitchIntentAllowsMovementWithoutTargetContext() {
        var plan = ContextPlan.default

        XCTAssertTrue(plan.setCurrentContext(id: "context-3"))
        plan.setPinned(false)
        let intent = plan.switchIntent(for: .next)

        XCTAssertTrue(intent.shouldExecute)
        XCTAssertNil(intent.targetContext)
        XCTAssertEqual(intent.targetDisplayIDs, [])
        XCTAssertNil(intent.diagnostic)
    }

    func testPinnedNextSwitchIntentUsesTargetContextDisplayMembership() {
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "Code",
                    displayIDs: ["built-in", "external-lg"]
                ),
                ContextDefinition(
                    id: "context-2",
                    order: 2,
                    name: "Review",
                    displayIDs: ["built-in"]
                )
            ],
            currentContextID: "context-1"
        )

        let intent = plan.switchIntent(for: .next)

        XCTAssertTrue(intent.shouldExecute)
        XCTAssertEqual(intent.targetContext?.id, "context-2")
        XCTAssertEqual(intent.targetDisplayIDs, ["built-in"])
    }

    func testPinnedPreviousSwitchIntentUsesTargetContextDisplayMembership() {
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "Code",
                    displayIDs: ["built-in", "external-lg"]
                ),
                ContextDefinition(
                    id: "context-2",
                    order: 2,
                    name: "Review",
                    displayIDs: ["built-in"]
                )
            ],
            currentContextID: "context-2"
        )

        let intent = plan.switchIntent(for: .previous)

        XCTAssertTrue(intent.shouldExecute)
        XCTAssertEqual(intent.targetContext?.id, "context-1")
        XCTAssertEqual(intent.targetDisplayIDs, ["built-in", "external-lg"])
    }

    func testContextActivationIntentCanTargetNonAdjacentContext() {
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "Code",
                    displayIDs: ["built-in", "external-lg"]
                ),
                ContextDefinition(
                    id: "context-2",
                    order: 2,
                    name: "Review",
                    displayIDs: ["built-in"]
                ),
                ContextDefinition(
                    id: "context-3",
                    order: 3,
                    name: "Docs",
                    displayIDs: ["external-lg"]
                )
            ],
            currentContextID: "context-1"
        )

        let intent = plan.activationIntent(forContextID: "context-3")

        XCTAssertTrue(intent.shouldExecute)
        XCTAssertEqual(intent.targetContext?.id, "context-3")
        XCTAssertEqual(intent.targetDisplayIDs, ["external-lg"])
        XCTAssertNil(intent.diagnostic)
    }

    func testContextActivationIntentWorksWhenPlanNeedsSync() {
        var plan = ContextPlan(
            contexts: [
                ContextDefinition(id: "context-1", order: 1, name: "Code", displayIDs: ["built-in"]),
                ContextDefinition(id: "context-2", order: 2, name: "Review", displayIDs: ["built-in"])
            ],
            currentContextID: "context-1"
        )
        plan.markNeedsSync()

        let intent = plan.activationIntent(forContextID: "context-2")

        XCTAssertTrue(intent.shouldExecute)
        XCTAssertEqual(intent.targetContext?.id, "context-2")
        XCTAssertEqual(intent.targetDisplayIDs, ["built-in"])
    }

    func testContextActivationIntentRejectsMissingContext() {
        let intent = ContextPlan.default.activationIntent(forContextID: "missing")

        XCTAssertFalse(intent.shouldExecute)
        XCTAssertNil(intent.targetContext)
        XCTAssertEqual(intent.targetDisplayIDs, [])
    }

    func testSuccessfulUnpinnedSwitchMarksNeedsSyncWithoutChangingCurrentContext() {
        var plan = ContextPlan.default

        plan.setPinned(false)
        plan.applySuccessfulSwitch(.next)

        XCTAssertEqual(plan.currentContext?.id, "context-1")
        XCTAssertEqual(plan.syncState, .needsSync)
    }

    func testSuccessfulPinnedSwitchTracksTargetContext() {
        var plan = ContextPlan.default

        plan.applySuccessfulSwitch(.next)

        XCTAssertEqual(plan.currentContext?.id, "context-2")
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

    func testSuccessfulUnknownNavigationMarksPlanNeedsSync() {
        var plan = ContextPlan.default
        plan.setCurrentContext(id: "context-3")

        plan.applySuccessfulNavigation(.next)

        XCTAssertEqual(plan.currentContext?.name, "Context 3")
        XCTAssertEqual(plan.syncState, .needsSync)
    }

    func testShouldTrackCurrentContextRequiresEnabledAndPinned() {
        var plan = ContextPlan.default

        XCTAssertTrue(
            ExternalSpaceChangeContextPolicy.shouldTrackCurrentContext(isSidebyEnabled: true, plan: plan)
        )
        XCTAssertFalse(
            ExternalSpaceChangeContextPolicy.shouldTrackCurrentContext(isSidebyEnabled: false, plan: plan)
        )

        plan.setPinned(false)
        XCTAssertFalse(
            ExternalSpaceChangeContextPolicy.shouldTrackCurrentContext(isSidebyEnabled: true, plan: plan)
        )
    }

    func testShouldTrackCurrentContextEvenWhenNeedsSync() {
        var plan = ContextPlan.default
        plan.markNeedsSync()

        XCTAssertTrue(
            ExternalSpaceChangeContextPolicy.shouldTrackCurrentContext(isSidebyEnabled: true, plan: plan)
        )
    }
}
