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

    func testSpaceCaptureStatusDisplayShowsProgress() {
        XCTAssertEqual(
            SpaceCaptureStatusDisplay.statusText(
                currentSpace: 2,
                totalSpaces: 4,
                strings: SBSStrings(language: .english)
            ),
            "Capturing Space 2 of 4"
        )
    }

    func testDisplaySpaceGridUsesDisplayRowsAndMaxSpaceColumns() {
        var plan = DisplaySpacePlan.default
        plan.reconcile(with: RuntimeState.dualDisplay.displayLayout)
        plan.updateLabel(displayID: "built-in", spaceOrder: 3, label: "Code")

        let suggestion = VisibleAppSuggestion(
            displayID: "external-lg",
            appName: "Arc",
            windowTitle: nil,
            source: .accessibility
        )
        let rows = DisplaySpaceGridModel.rows(
            displays: RuntimeState.dualDisplay.displayLayout.displays,
            plan: plan,
            captureCount: 2,
            suggestionsByDisplayID: ["external-lg": [5: suggestion]]
        )

        XCTAssertEqual(rows.map(\.displayID), ["built-in", "external-lg"])
        XCTAssertEqual(rows[0].cells.map(\.spaceOrder), [1, 2, 3, 4, 5])
        XCTAssertEqual(rows[1].cells.map(\.spaceOrder), [1, 2, 3, 4, 5])
        XCTAssertEqual(rows[0].cells[2].label, "Code")
        XCTAssertEqual(rows[1].cells[4].suggestion, suggestion)
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
