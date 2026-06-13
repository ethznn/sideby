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

    func testFloatingMenuLayoutUsesResizableDefaults() {
        XCTAssertEqual(FloatingMenuPanelLayout.defaultSize.width, 720)
        XCTAssertEqual(FloatingMenuPanelLayout.defaultSize.height, 640)
        XCTAssertEqual(FloatingMenuPanelLayout.minimumSize.width, 520)
        XCTAssertEqual(FloatingMenuPanelLayout.minimumSize.height, 420)
    }

    func testFloatingMenuLayoutClampsSavedSizeToVisibleFrame() {
        let size = FloatingMenuPanelLayout.clampedContentSize(
            NSSize(width: 1600, height: 1200),
            visibleFrame: NSRect(x: 0, y: 0, width: 900, height: 700)
        )

        XCTAssertEqual(size.width, 876)
        XCTAssertEqual(size.height, 676)
    }

    func testFloatingMenuLayoutKeepsUserResizedPanelSize() {
        let resized = NSSize(width: 650, height: 500)

        XCTAssertEqual(
            FloatingMenuPanelLayout.contentSize(
                currentContentSize: resized,
                isNewPanel: false,
                visibleFrame: nil
            ),
            resized
        )
        XCTAssertEqual(
            FloatingMenuPanelLayout.contentSize(
                currentContentSize: nil,
                isNewPanel: true,
                visibleFrame: nil
            ),
            FloatingMenuPanelLayout.defaultSize
        )
    }

    func testFloatingMenuLayoutPreservesExistingPanelSizeWhenRebuildingContent() {
        let resizedBeforeContentRebuild = NSSize(width: 650, height: 500)
        let replacementContentDefault = FloatingMenuPanelLayout.defaultSize

        XCTAssertEqual(
            FloatingMenuPanelLayout.presentationContentSize(
                capturedExistingContentSize: resizedBeforeContentRebuild,
                currentContentSize: replacementContentDefault,
                isNewPanel: false,
                visibleFrame: nil
            ),
            resizedBeforeContentRebuild
        )
    }

    func testCompactContextMatrixUsesTwoThirdsContextColumnWidth() {
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.contextColumnWidth(isCompact: true),
            170 * 2 / 3,
            accuracy: 0.001
        )
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.contextColumnWidth(isCompact: false),
            220
        )
    }

    func testCompactContextMatrixUsesShortSingleLineStatusLabels() {
        let strings = SBSStrings(language: .english)

        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.statusTitle(for: .current, isCompact: true, strings: strings),
            "Current"
        )
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.statusTitle(for: .needsSync, isCompact: true, strings: strings),
            "Sync"
        )
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.statusTitle(for: .paused, isCompact: true, strings: strings),
            "Paused"
        )
        XCTAssertNil(
            FloatingMenuContextMatrixLayout.statusTitle(for: .normal, isCompact: true, strings: strings)
        )
        XCTAssertEqual(FloatingMenuContextMatrixLayout.headerLineLimit, 1)
    }

    func testFloatingMenuInteractiveControlsUsePointingHandCursor() {
        XCTAssertTrue(FloatingMenuInteractiveCursorPolicy.usesPointingHand(for: .button))
        XCTAssertTrue(FloatingMenuInteractiveCursorPolicy.usesPointingHand(for: .toggle))
        XCTAssertTrue(FloatingMenuInteractiveCursorPolicy.usesPointingHand(for: .picker))
    }

    func testFloatingMenuSectionsDefaultToCompactState() {
        let expansion = FloatingMenuSectionExpansion.default

        XCTAssertEqual(
            expansion,
            FloatingMenuSectionExpansion(
                showsInput: false,
                showsPermissions: false,
                showsGeneral: false,
                showsDiagnostics: false
            )
        )
        XCTAssertFalse(expansion.showsInput)
        XCTAssertFalse(expansion.showsPermissions)
        XCTAssertFalse(expansion.showsGeneral)
        XCTAssertFalse(expansion.showsDiagnostics)
    }

    func testFloatingMenuPresentationUsesMenuBarFallbackAfterOnboarding() {
        XCTAssertEqual(
            FloatingMenuPanelPresentationPolicy.anchor(for: .onboardingCompletion),
            .menuBarFallback
        )
        XCTAssertEqual(
            FloatingMenuPanelPresentationPolicy.anchor(for: .settingsRedirect),
            .menuBarFallback
        )
        XCTAssertEqual(
            FloatingMenuPanelPresentationPolicy.anchor(for: .menuBarIcon),
            .sourceWindow
        )
    }

    func testFloatingMenuSectionExpansionTogglesIndividualSections() {
        var expansion = FloatingMenuSectionExpansion.default

        XCTAssertFalse(expansion.isExpanded(.input))
        expansion.toggle(.input)
        XCTAssertTrue(expansion.isExpanded(.input))

        XCTAssertFalse(expansion.isExpanded(.permissions))
        expansion.set(.permissions, isExpanded: true)
        XCTAssertTrue(expansion.isExpanded(.permissions))
        XCTAssertFalse(expansion.isExpanded(.general))
        XCTAssertFalse(expansion.isExpanded(.diagnostics))
    }

    func testFloatingMenuContextSectionGroupsCaptureBeforeMatrix() {
        XCTAssertEqual(
            FloatingMenuContextSectionContent.defaultItems,
            [.captureControls, .matrix]
        )
    }

    func testContextCaptureButtonAvailabilityDoesNotDependOnSidebyEnabled() {
        XCTAssertTrue(
            FloatingMenuContextCaptureAvailability.canStart(
                displayCount: 1,
                isSwitching: false,
                isCapturing: false
            )
        )
        XCTAssertFalse(
            FloatingMenuContextCaptureAvailability.canStart(
                displayCount: 0,
                isSwitching: false,
                isCapturing: false
            )
        )
    }

    func testHUDPresenterUsesDirectionAndContextName() {
        let hud = HUDPresenter().state(for: .next, contextName: "Work")

        XCTAssertEqual(hud.text, "-> Work")
        XCTAssertEqual(hud.duration, 0.8)
    }

    func testHUDPresenterShowsContextNameOnlyForSuccessfulContextSwitch() {
        let hud = HUDPresenter().stateForContextSwitch(contextName: "Work")

        XCTAssertEqual(hud.text, "Work")
        XCTAssertFalse(hud.isCompact)
        XCTAssertEqual(hud.duration, 1.0)
        XCTAssertEqual(hud.fadeOutDuration, 0.28)
        XCTAssertEqual(hud.visualScale, 4.0)
        XCTAssertEqual(hud.backgroundOpacity, 0.66)
    }

    func testHUDPanelLayoutCentersAgainstFullScreenFrame() {
        let origin = HUDPanelLayout.centeredOrigin(
            panelSize: NSSize(width: 400, height: 200),
            screenFrame: NSRect(x: -1000, y: 40, width: 900, height: 700)
        )

        XCTAssertEqual(origin.x, -750)
        XCTAssertEqual(origin.y, 290)
    }

    func testHUDPanelLayoutPrefersMeasuredContentSizeOverTextEstimate() {
        let size = HUDPanelLayout.contentSize(
            fittingSize: NSSize(width: 360, height: 120),
            text: "Long Context Name",
            visualScale: 4
        )

        XCTAssertEqual(size.width, 528)
        XCTAssertEqual(size.height, 176)
    }

    func testHUDPresentationGenerationRejectsStaleFadeCompletion() {
        var generation = HUDPresentationGeneration()

        let firstPresentation = generation.advance()
        let secondPresentation = generation.advance()

        XCTAssertFalse(generation.isCurrent(firstPresentation))
        XCTAssertTrue(generation.isCurrent(secondPresentation))
    }

    func testContextSwitchHUDPolicyShowsTargetContextNameForExecutedContextMove() {
        let intent = ContextSwitchIntent(
            command: .next,
            targetContext: ContextDefinition(
                id: "context-2",
                order: 2,
                name: "Review",
                displayIDs: ["built-in"]
            ),
            targetDisplayIDs: ["built-in"],
            diagnostic: nil,
            shouldExecute: true
        )

        let presentation = ContextSwitchHUDPolicy().presentation(
            for: intent,
            didExecute: true,
            executedDisplayIDs: ["built-in", "external"]
        )

        XCTAssertEqual(presentation?.state.text, "Review")
        XCTAssertEqual(presentation?.displayIDs, ["built-in", "external"])
    }

    func testContextSwitchHUDPolicySkipsGeneralMovementWithoutTargetContext() {
        let intent = ContextSwitchIntent(
            command: .next,
            targetContext: nil,
            targetDisplayIDs: [],
            diagnostic: nil,
            shouldExecute: true
        )

        XCTAssertNil(
            ContextSwitchHUDPolicy().presentation(
                for: intent,
                didExecute: true,
                executedDisplayIDs: ["built-in"]
            )
        )
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

    func testContextListRowsExposeCurrentAndNeedsSyncState() {
        var plan = ContextPlan.default
        plan.renameContext(id: "context-2", name: "Research")
        plan.markNeedsSync()

        let rows = ContextListModel.rows(plan: plan)

        XCTAssertEqual(rows.map(\.name), ["Context 1", "Research", "Context 3"])
        XCTAssertEqual(rows[0].state, .needsSync)
        XCTAssertEqual(rows[1].state, .normal)
    }

    func testContextListRowsExposePausedStateWhenMatchingIsPaused() {
        var plan = ContextPlan.default
        plan.pauseContextMatchingForUnsynchronizedMovement()

        let rows = ContextListModel.rows(plan: plan)

        XCTAssertEqual(rows[0].state, .paused)
        XCTAssertEqual(rows[1].state, .normal)
    }

    func testContextRowsReflectRenamedCurrentContext() {
        var settings = AppSettings.default
        settings.contextPlan.renameContext(id: "context-1", name: "Work")
        let rows = ContextListModel.rows(plan: settings.contextPlan)

        XCTAssertEqual(rows.first?.name, "Work")
        XCTAssertEqual(rows.first?.state, .current)
    }

    func testContextRowsExposeCapturedDisplayMembership() {
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "Focus",
                    displayIDs: ["built-in", "external-lg"]
                ),
                ContextDefinition(
                    id: "context-2",
                    order: 2,
                    name: "Solo",
                    displayIDs: ["built-in"]
                )
            ],
            currentContextID: "context-1"
        )

        let rows = ContextListModel.rows(plan: plan)

        XCTAssertEqual(rows.map(\.displayIDs), [["built-in", "external-lg"], ["built-in"]])
    }

    func testContextMatrixUsesDisplaysAsRowsAndContextsAsColumns() {
        let displays = RuntimeState.dualDisplay.displayLayout.displays
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "Shared",
                    displayIDs: ["built-in", "external-lg"]
                ),
                ContextDefinition(
                    id: "context-2",
                    order: 2,
                    name: "Built-in only",
                    displayIDs: ["built-in"]
                )
            ],
            currentContextID: "context-1"
        )

        let matrix = ContextMatrixModel.matrix(plan: plan, displays: displays)

        XCTAssertEqual(matrix.columns.map(\.name), ["Shared", "Built-in only"])
        XCTAssertEqual(matrix.rows.map(\.displayID), ["built-in", "external-lg"])
        XCTAssertEqual(matrix.rows[0].cells.map(\.isIncluded), [true, true])
        XCTAssertEqual(matrix.rows[1].cells.map(\.isIncluded), [true, false])
    }

    func testContextCaptureStatusDisplayShowsAligningCapturingAndCompleted() {
        let strings = SBSStrings(language: .english)

        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .aligning(attempt: 2),
                captureLimit: 5,
                maxAlignmentAttempts: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Finding first Space · try 2/5"
        )
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .capturing(order: 3),
                captureLimit: 5,
                maxAlignmentAttempts: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Capturing Context 3 · up to 5"
        )
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .completed(currentContextID: "captured-final"),
                captureLimit: 5,
                maxAlignmentAttempts: 5,
                completedContextCount: 4,
                strings: strings
            ),
            "Captured 4 Contexts · Now at Context 4"
        )
    }

    func testContextCaptureStatusDisplayAnnouncesPinnedMatchingAndCurrentContextName() {
        let english = ContextCaptureStatusDisplay.statusText(
            phase: .completed(currentContextID: "context-4"),
            captureLimit: 4,
            maxAlignmentAttempts: 5,
            completedContextCount: 4,
            currentContextName: "Design / Docs",
            strings: SBSStrings(language: .english)
        )
        XCTAssertEqual(
            english,
            "Captured 4 Contexts · Move by Contexts on · Current: Design / Docs"
        )

        let korean = ContextCaptureStatusDisplay.statusText(
            phase: .completed(currentContextID: "context-4"),
            captureLimit: 4,
            maxAlignmentAttempts: 5,
            completedContextCount: 4,
            currentContextName: "Design / Docs",
            strings: SBSStrings(language: .korean)
        )
        XCTAssertEqual(
            korean,
            "컨텍스트 4개 캡처됨 · 컨텍스트대로 움직이기 켜짐 · 현재: Design / Docs"
        )
    }

    func testContextCaptureStatusDisplayFallsBackWithoutCurrentContextName() {
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .completed(currentContextID: "context-4"),
                captureLimit: 4,
                maxAlignmentAttempts: 5,
                completedContextCount: 4,
                currentContextName: nil,
                strings: SBSStrings(language: .english)
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
                maxAlignmentAttempts: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Capture failed: No Space movement detected"
        )
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .stopped,
                captureLimit: 5,
                maxAlignmentAttempts: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Capture stopped. Existing Contexts were kept."
        )
    }

    func testContextCaptureStatusDisplayReportsProgress() {
        var session = ContextCaptureSession(captureLimit: 4, maxAlignmentAttempts: 4)

        XCTAssertEqual(ContextCaptureStatusDisplay.progressValue(session: session), 0.04, accuracy: 0.0001)

        session.recordAlignment(previousDidChange: true)
        XCTAssertEqual(ContextCaptureStatusDisplay.progressValue(session: session), 0.08, accuracy: 0.0001)

        session.recordAlignment(previousDidChange: false)
        XCTAssertEqual(ContextCaptureStatusDisplay.progressValue(session: session), 0.16, accuracy: 0.0001)

        session.recordCurrentSpace(name: "Context 1", displayIDs: ["built-in"])
        XCTAssertEqual(ContextCaptureStatusDisplay.progressValue(session: session), 0.25, accuracy: 0.0001)
    }

    func testContextCaptureStatusDisplayUsesSessionCompletedCount() {
        var session = ContextCaptureSession(captureLimit: 1)
        session.recordAlignment(previousDidChange: false)
        session.recordCurrentSpace(name: "Context 1", displayIDs: ["built-in"])
        session.recordForwardSwitch(movedDisplayIDs: [])

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

    func testAlignAndTrackingStringsLocalize() {
        let korean = SBSStrings(language: .korean)
        let english = SBSStrings(language: .english)

        XCTAssertEqual(english.alignDisplays, "Align Displays")
        XCTAssertEqual(korean.alignDisplays, "컨텍스트 맞추기")
        XCTAssertEqual(korean.alignedToContext("Docs"), "Docs에 맞췄습니다")
        XCTAssertEqual(english.alignedToContext("Docs"), "Aligned to Docs")
        XCTAssertEqual(korean.alignFailed, "맞추지 못했습니다 — 컨텍스트를 다시 캡처해 주세요")
        XCTAssertEqual(english.followingContext("Docs"), "Following Docs")
        XCTAssertEqual(korean.localizedActionLabel("Align Displays"), "컨텍스트 맞추기")
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
