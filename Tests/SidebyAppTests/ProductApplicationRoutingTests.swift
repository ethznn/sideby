import XCTest
import SidebyCore
@testable import SidebyApp

final class ProductApplicationRoutingTests: XCTestCase {
    func testSettingsAndShortcutEntryResolveToIndependentSettingsRoutes() {
        XCTAssertEqual(ProductApplicationRouting.route(for: .settings), .settings(nil))
        XCTAssertEqual(ProductApplicationRouting.route(for: .customizeInput), .settings(.init(pane: .input)))
        XCTAssertEqual(ProductApplicationRouting.route(for: .review(contextID: "review", displayID: "desk")),
                       .settings(.init(pane: .workspaces, contextID: "review", displayID: "desk", returnTo: .daily)))
        XCTAssertEqual(ProductApplicationRouting.route(for: .permissions), .settings(.init(pane: .permissions)))
    }

    func testReplayAndResumeAreDistinctWithoutResettingCompletion() {
        XCTAssertEqual(ProductApplicationRouting.route(for: .replay), .onboarding(replay: true))
        XCTAssertEqual(ProductApplicationRouting.route(for: .resume), .onboarding(replay: false))
    }

    func testInitialGuideRequiresIncompleteUndismissedProgressOnlyOnce() {
        var gate = ProductInitialGuidePresentation()
        XCTAssertTrue(gate.shouldPresent(isRoundTripComplete: false, isDismissed: false))
        XCTAssertFalse(gate.shouldPresent(isRoundTripComplete: false, isDismissed: false))
        var dismissed = ProductInitialGuidePresentation()
        XCTAssertFalse(dismissed.shouldPresent(isRoundTripComplete: false, isDismissed: true))
        var completed = ProductInitialGuidePresentation()
        XCTAssertFalse(completed.shouldPresent(isRoundTripComplete: true, isDismissed: false))
    }

    @MainActor func testGenericCommandSettingsUsesLastPaneWithoutOldRecoveryIntent() {
        let preferences = MemoryProductUIPreferences()
        let navigation = ProductUINavigation(preferences: preferences)
        navigation.openSettings(.init(pane: .workspaces, contextID: "a", returnTo: .daily))
        navigation.selectPane(.general)
        guard case .settings(let route) = ProductApplicationRouting.route(for: .settings) else {
            return XCTFail("Settings command must reach the native settings coordinator")
        }
        navigation.openSettings(route)
        XCTAssertEqual(navigation.settingsRoute, .init(pane: .general))
        XCTAssertNil(navigation.consumeReturnDestination())
    }

    @MainActor func testResumedVerifiedOriginRecordsKeyboardOrGestureSuccessWithoutAnExtraButton() {
        var settings = AppSettings.default
        settings.contextPlan = .init(contexts: [
            .init(id: "a", order: 1, name: "Build", displaySpaceIndexes: ["desk": 0]),
            .init(id: "b", order: 2, name: "Review", displaySpaceIndexes: ["desk": 1])
        ], currentContextID: "a")
        let model = SidebyAppModel(testSettings: settings, selectedDisplayIDs: ["desk"],
            selectedDisplaySpaces: { [.init(displayID: "desk", spaceCount: 2, currentSpaceIndex: 0)] },
            postEventAccessGranted: true)
        model.displayLayout = .init(displays: [.init(id: "desk", name: "Desk", isPrimary: true, isBuiltin: false)])
        model.permissionState = .granted
        model.workspaceSpaceIDsOverride = { ["desk": [11, 12]] }
        XCTAssertTrue(model.confirmWorkspaceConnections())
        model.workspaceGuideIsRecording = true
        model.recordWorkspaceActivation(settings.contextPlan.contexts[0], succeeded: true)
        model.dismissFirstWorkGuide()
        let preferences = MemoryProductUIPreferences()
        preferences.onboardingStage = .roundTrip
        let presentation = ProductOnboardingPresentation(preferences: preferences)
        presentation.open(replay: false, facts: ProductOnboardingFacts(model: model))
        model.workspaceGuideIsRecording = ProductGuideRecordingPolicy.shouldRecord(stage: presentation.state.stage, progress: model.firstWorkProgress)
        model.recordWorkspaceActivation(settings.contextPlan.contexts[1], succeeded: true)
        model.recordWorkspaceActivation(settings.contextPlan.contexts[0], succeeded: true)
        XCTAssertTrue(model.firstWorkProgress.isComplete)
        XCTAssertEqual(model.settings.contextPlan, settings.contextPlan)
    }

    func testReplayFallbackAndUnverifiedOriginDoNotArmRecording() {
        var partial = WorkspaceFirstRunProgress()
        partial.recordSuccessfulVisit(contextID: "a")
        for stage in [ProductOnboardingStage.preparation, .displays, .workspaces] {
            XCTAssertFalse(ProductGuideRecordingPolicy.shouldRecord(stage: stage, progress: partial))
        }
        XCTAssertFalse(ProductGuideRecordingPolicy.shouldRecord(stage: .roundTrip, progress: WorkspaceFirstRunProgress()))
        partial.recordSuccessfulVisit(contextID: "b")
        partial.recordSuccessfulVisit(contextID: "a")
        XCTAssertFalse(ProductGuideRecordingPolicy.shouldRecord(stage: .roundTrip, progress: partial))
    }
}
