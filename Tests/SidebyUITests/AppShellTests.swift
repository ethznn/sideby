import XCTest
@testable import SidebyCore
@testable import SidebyUI

final class AppShellTests: XCTestCase {
    func testMenuBarStateSummarizesDisplays() {
        let coordinator = AppCoordinator()
        let state = coordinator.state(settings: .default, runtimeState: .dualDisplay)
        let menuState = MenuBarState(coordinatorState: state)

        XCTAssertEqual(menuState.displaySummary, "2 displays")
        XCTAssertEqual(menuState.mode, .together)
    }

    func testHUDPresenterUsesDirectionAndContextName() {
        let hud = HUDPresenter().state(for: .next, contextName: "Work")

        XCTAssertEqual(hud.text, "-> Work")
        XCTAssertEqual(hud.duration, 0.8)
    }

    func testHUDPresenterCanShowDiagnosticCompactly() {
        let diagnostic = DiagnosticState(
            severity: .blocker,
            title: "Only one Space is available",
            message: "Add another Desktop in Mission Control before switching contexts.",
            actionLabel: "Add Desktop"
        )

        let hud = HUDPresenter().state(for: diagnostic, compact: true)

        XCTAssertEqual(hud.text, "Only one Space is available")
        XCTAssertTrue(hud.isCompact)
    }

    func testContextSummaryUsesContextNameOnly() {
        let plan = ContextPlan.default

        let summary = ContextPlanSummary.summary(
            for: plan.currentContext!,
            displays: RuntimeState.dualDisplay.displayLayout.displays,
            strings: SBSStrings(language: .english)
        )

        XCTAssertEqual(summary, "Context 1")
    }

    func testContextSummaryIgnoresDisplayCount() {
        let plan = ContextPlan.default

        let summary = ContextPlanSummary.summary(
            for: plan.currentContext!,
            displays: RuntimeState.dualDisplay.displayLayout.displays,
            strings: SBSStrings(language: .english)
        )

        XCTAssertEqual(summary, "Context 1")
    }

    func testVisibleAppSuggestionDisplayShowsDetectedCombinedLabel() {
        let suggestion = VisibleAppSuggestion(
            displayID: "built-in",
            appName: "Xcode",
            windowTitle: "SidebyApp.swift",
            source: .accessibility
        )

        XCTAssertEqual(
            VisibleAppSuggestionDisplay.detectedText(
                for: suggestion,
                strings: SBSStrings(language: .english)
            ),
            "Detected: Xcode - SidebyApp.swift"
        )
    }

    func testContextCaptureStatusDisplayShowsProgress() {
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                contextName: "Context 2",
                currentStep: 2,
                totalSteps: 3,
                strings: SBSStrings(language: .english)
            ),
            "Capturing Context 2 of 3: Context 2"
        )
    }

    func testContextListRowsExposeCurrentAndNeedsSyncState() {
        var plan = ContextPlan.default
        plan.renameContext(id: "context-2", name: "Research")
        plan.markNeedsSync()

        let rows = ContextListModel.rows(plan: plan)

        XCTAssertEqual(rows.map(\.name), ["Context 1", "Research", "Context 3"])
        XCTAssertEqual(rows[0].state, .needsSync)
        XCTAssertEqual(rows[1].state, .normal)
    }

    func testContextRowsReflectRenamedCurrentContext() {
        var settings = AppSettings.default
        settings.contextPlan.renameContext(id: "context-1", name: "Work")
        let rows = ContextListModel.rows(plan: settings.contextPlan)

        XCTAssertEqual(rows.first?.name, "Work")
        XCTAssertEqual(rows.first?.state, .current)
    }

    func testContextCaptureStatusDisplayShowsAligningCapturingAndCompleted() {
        let strings = SBSStrings(language: .english)

        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .aligning(attempt: 2),
                captureLimit: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Aligning to first Space"
        )
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .capturing(order: 3),
                captureLimit: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Capturing Context 3 of up to 5"
        )
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .completed(currentContextID: "captured-final"),
                captureLimit: 5,
                completedContextCount: 4,
                strings: strings
            ),
            "Captured 4 Contexts · Now at Context 4"
        )
    }

    func testContextCaptureStatusDisplayShowsFailedAndStopped() {
        let strings = SBSStrings(language: .english)

        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .failed(reason: "No Space movement detected"),
                captureLimit: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Capture failed: No Space movement detected"
        )
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .stopped,
                captureLimit: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Capture stopped. Existing Contexts were kept."
        )
    }

    func testContextCaptureStatusDisplayUsesSessionCompletedCount() {
        var session = ContextCaptureSession(captureLimit: 5)
        session.recordAlignment(previousDidChange: false)
        session.recordCurrentSpace(name: "Context 1")
        session.recordForwardSwitch(didMoveAllTargets: false)

        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(session: session, strings: SBSStrings(language: .english)),
            "Captured 1 Context · Now at Context 1"
        )
    }

    func testContextCaptureStatusDisplayFailsInvalidCompletedSession() {
        let session = ContextCaptureSession(
            captureLimit: 5,
            phase: .completed(currentContextID: "missing"),
            draftContexts: []
        )

        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(session: session, strings: SBSStrings(language: .english)),
            "Capture failed: Invalid completed Context capture"
        )
    }

    func testHUDPresenterShowsContextSyncWarning() {
        let hud = HUDPresenter().stateForContextNeedsSync()

        XCTAssertEqual(hud.text, "Context needs sync")
        XCTAssertTrue(hud.isCompact)
    }

    func testHUDPresenterLocalizesContextSyncWarning() {
        let strings = SBSStrings(language: .korean)

        let hud = HUDPresenter().stateForContextNeedsSync(strings: strings)

        XCTAssertEqual(hud.text, "컨텍스트 동기화 필요")
        XCTAssertTrue(hud.isCompact)
        XCTAssertEqual(
            strings.localizedDiagnosticTitle("Context needs sync"),
            "컨텍스트 동기화 필요"
        )
    }

    func testOnboardingStateMachineProgressesThroughTryFlow() {
        let machine = OnboardingStateMachine()
        var state = OnboardingState(step: .displayCheck)

        state = machine.reduce(state, event: .displaysDetected)
        state = machine.reduce(state, event: .gestureChosen)
        state = machine.reduce(state, event: .permissionPromptAccepted)
        state = machine.reduce(state, event: .rightSwitchSucceeded)
        state = machine.reduce(state, event: .leftSwitchSucceeded)

        XCTAssertEqual(state.step, .completed)
    }

    func testOnboardingViewModelStartsWithDisplayCount() {
        let viewModel = OnboardingViewModel()
        let viewState = viewModel.viewState(
            for: OnboardingState(step: .displayCheck),
            displayLayout: RuntimeState.dualDisplay.displayLayout
        )

        XCTAssertEqual(viewState.title, "2 displays connected")
        XCTAssertEqual(viewState.step, .displayCheck)
    }
}

private extension RuntimeState {
    static let dualDisplay = RuntimeState(
        accessibilityPermission: .granted,
        displayLayout: DisplayLayout(
            displays: [
                DisplayInfo(id: "built-in", name: "Built-in Display", isPrimary: true, isBuiltin: true),
                DisplayInfo(id: "external-lg", name: "LG Display", isPrimary: false, isBuiltin: false)
            ]
        ),
        availableSpaceCount: 3
    )
}
