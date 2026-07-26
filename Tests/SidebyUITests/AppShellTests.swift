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
        XCTAssertEqual(FloatingMenuPanelLayout.defaultSize.width, 520)
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

    func testDisplayArrangementLayoutFitsSideBySideDisplaysInsideStage() {
        let placements = FloatingMenuDisplayArrangementLayout.placements(
            for: [
                FloatingMenuDisplayLayoutInput(
                    displayID: "built-in",
                    frame: DisplayFrame(x: 0, y: 0, width: 1728, height: 1117)
                ),
                FloatingMenuDisplayLayoutInput(
                    displayID: "external",
                    frame: DisplayFrame(x: 1728, y: -80, width: 2560, height: 1440)
                )
            ],
            in: CGSize(width: 660, height: FloatingMenuDisplayArrangementLayout.stageHeight)
        )

        XCTAssertEqual(placements.map(\.displayID), ["built-in", "external"])
        XCTAssertTrue(placements.allSatisfy { $0.frame.minX >= 0 })
        XCTAssertTrue(placements.allSatisfy { $0.frame.minY >= 0 })
        XCTAssertTrue(placements.allSatisfy { $0.frame.maxX <= 660 })
        XCTAssertTrue(placements.allSatisfy { $0.frame.maxY <= FloatingMenuDisplayArrangementLayout.stageHeight })
        XCTAssertGreaterThan(placements[1].frame.width, placements[0].frame.width)
    }

    func testDisplayArrangementLayoutCentersStackedDisplays() {
        let placements = FloatingMenuDisplayArrangementLayout.placements(
            for: [
                FloatingMenuDisplayLayoutInput(
                    displayID: "top",
                    frame: DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
                ),
                FloatingMenuDisplayLayoutInput(
                    displayID: "bottom",
                    frame: DisplayFrame(x: 240, y: 1080, width: 1440, height: 900)
                )
            ],
            in: CGSize(width: 520, height: FloatingMenuDisplayArrangementLayout.stageHeight)
        )

        let union = placements.map(\.frame).reduce(CGRect.null) { $0.union($1) }

        XCTAssertEqual(placements.count, 2)
        XCTAssertEqual(union.midX, 260, accuracy: 1.0)
        XCTAssertTrue(placements.allSatisfy { $0.frame.maxY <= FloatingMenuDisplayArrangementLayout.stageHeight })
    }

    func testDisplayArrangementLayoutPreservesMinimumReadableDisplaySize() {
        let placements = FloatingMenuDisplayArrangementLayout.placements(
            for: [
                FloatingMenuDisplayLayoutInput(
                    displayID: "tiny",
                    frame: DisplayFrame(x: 0, y: 0, width: 300, height: 200)
                ),
                FloatingMenuDisplayLayoutInput(
                    displayID: "wide",
                    frame: DisplayFrame(x: 1200, y: 0, width: 6000, height: 1440)
                )
            ],
            in: CGSize(width: 520, height: FloatingMenuDisplayArrangementLayout.stageHeight)
        )

        let tiny = placements.first { $0.displayID == "tiny" }!

        XCTAssertGreaterThanOrEqual(tiny.frame.width, FloatingMenuDisplayArrangementLayout.minimumDisplaySize.width)
        XCTAssertGreaterThanOrEqual(tiny.frame.height, FloatingMenuDisplayArrangementLayout.minimumDisplaySize.height)
    }

    func testCompactContextMatrixUsesReadableContextColumnWidth() {
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.contextColumnWidth(isCompact: true),
            72
        )
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.contextColumnWidth(isCompact: false),
            220
        )
    }

    func testCompactContextMatrixUsesNarrowScrollableDisplayColumn() {
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.displayColumnWidth(isCompact: true),
            72
        )
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.displayColumnWidth(isCompact: false),
            170
        )
    }

    func testContextMatrixAxisHeaderPlacesContextsAcrossAndDisplaysDown() {
        XCTAssertEqual(FloatingMenuContextMatrixAxisHeaderContent.topTrailing, .contexts)
        XCTAssertEqual(FloatingMenuContextMatrixAxisHeaderContent.bottomLeading, .displays)
    }

    func testContextMatrixDisplayColumnResizeIsClampedToUsefulRange() {
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.clampedDisplayColumnWidth(40, isCompact: true),
            72
        )
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.clampedDisplayColumnWidth(140, isCompact: true),
            140
        )
        XCTAssertEqual(
            FloatingMenuContextMatrixLayout.clampedDisplayColumnWidth(260, isCompact: true),
            180
        )
    }

    func testContextMatrixHeaderHeightPreferenceKeepsTallestHeader() {
        var height = FloatingMenuContextMatrixHeaderHeightPreferenceKey.defaultValue

        FloatingMenuContextMatrixHeaderHeightPreferenceKey.reduce(value: &height) { 44 }
        FloatingMenuContextMatrixHeaderHeightPreferenceKey.reduce(value: &height) { 52 }
        FloatingMenuContextMatrixHeaderHeightPreferenceKey.reduce(value: &height) { 48 }

        XCTAssertEqual(height, 52)
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
    }

    func testLocalizesContextEditingAndDeletionConfirmation() {
        let english = SBSStrings(language: .english)
        let korean = SBSStrings(language: .korean)

        XCTAssertEqual(english.deleteContext, "Delete Context")
        XCTAssertEqual(korean.deleteContext, "컨텍스트 삭제")
        XCTAssertEqual(english.deleteContextConfirmationTitle("Review"), "Delete Review?")
        XCTAssertEqual(korean.deleteContextConfirmationTitle("Review"), "Review 컨텍스트를 삭제할까요?")
        XCTAssertEqual(
            english.deleteContextConfirmationMessage,
            "Sideby will remove this Context's Space mappings. macOS Spaces will not be deleted."
        )
        XCTAssertEqual(
            korean.deleteContextConfirmationMessage,
            "Sideby의 컨텍스트 Space 매핑만 제거됩니다. 실제 macOS Space는 삭제되지 않습니다."
        )
        XCTAssertEqual(english.cancel, "Cancel")
        XCTAssertEqual(korean.cancel, "취소")
    }

    func testContextMatrixHeaderNameLineLimitAllowsReadableNames() {
        XCTAssertEqual(FloatingMenuContextMatrixLayout.nameLineLimit(isCompact: true), 2)
        XCTAssertEqual(FloatingMenuContextMatrixLayout.nameLineLimit(isCompact: false), 2)
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
                showsGeneral: false
            )
        )
        XCTAssertFalse(expansion.showsInput)
        XCTAssertFalse(expansion.showsPermissions)
        XCTAssertFalse(expansion.showsGeneral)
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
    }

    func testFloatingMenuContextSectionGroupsCaptureBeforeMatrix() {
        XCTAssertEqual(
            FloatingMenuContextSectionContent.defaultItems,
            [.captureControls, .matrix]
        )
    }

    func testFloatingMenuPinsMasterControlAndInlineNavigationControls() {
        XCTAssertEqual(
            FloatingMenuPinnedHeaderContent.defaultItems,
            [.masterControl, .navigationControls]
        )
    }

    func testFloatingMenuOnlyShowsEssentialDisclosureSections() {
        XCTAssertEqual(
            FloatingMenuCollapsibleSectionContent.defaultItems,
            [.input, .permissions, .general]
        )
    }

    func testFloatingMenuPlacesUpdateCheckInsideGeneralActions() {
        XCTAssertEqual(
            FloatingMenuGeneralActionContent.defaultItems,
            [.replayOnboarding, .refresh, .checkForUpdates]
        )
    }

    func testFloatingMenuSwitchSectionOmitsLastSwitchStatus() {
        XCTAssertEqual(
            FloatingMenuSwitchSectionContent.pinnedItems,
            [.navigationControls]
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

    func testContextMatrixUsesSavedDisplayRowOrderAndAppendsNewDisplays() {
        let displays = [
            DisplayInfo(id: "built-in", name: "Built-in Display", isPrimary: true, isBuiltin: true),
            DisplayInfo(id: "external-lg", name: "LG Display", isPrimary: false, isBuiltin: false),
            DisplayInfo(id: "ipad", name: "iPad", isPrimary: false, isBuiltin: false)
        ]

        let matrix = ContextMatrixModel.matrix(
            plan: .default,
            displays: displays,
            displayRowOrder: ["external-lg", "built-in", "missing"]
        )

        XCTAssertEqual(matrix.rows.map(\.displayID), ["external-lg", "built-in", "ipad"])
    }

    func testContextMatrixDisplayRowOrderMovesDownAfterTargetAndUpBeforeTarget() {
        let visibleDisplayIDs = ["built-in", "external-lg", "ipad"]

        let movedDown = ContextMatrixModel.displayRowOrder(
            moving: "built-in",
            to: "ipad",
            visibleDisplayIDs: visibleDisplayIDs,
            currentOrder: ["external-lg", "built-in", "missing"]
        )
        let movedUp = ContextMatrixModel.displayRowOrder(
            moving: "ipad",
            to: "external-lg",
            visibleDisplayIDs: visibleDisplayIDs,
            currentOrder: movedDown
        )

        XCTAssertEqual(movedDown, ["external-lg", "ipad", "built-in", "missing"])
        XCTAssertEqual(movedUp, ["ipad", "external-lg", "built-in", "missing"])
    }

    func testContextMatrixCellsExposeMappedSpaceIndex() {
        let displays = RuntimeState.dualDisplay.displayLayout.displays
        let plan = ContextPlan(
            contexts: [
                ContextDefinition(
                    id: "context-1",
                    order: 1,
                    name: "Shared",
                    displayIDs: ["built-in", "external-lg"],
                    displaySpaceIndexes: ["built-in": 0, "external-lg": 0]
                ),
                ContextDefinition(
                    id: "context-2",
                    order: 2,
                    name: "External",
                    displayIDs: ["external-lg"],
                    displaySpaceIndexes: ["external-lg": 1]
                ),
                ContextDefinition(
                    id: "context-3",
                    order: 3,
                    name: "Mixed",
                    displayIDs: ["built-in", "external-lg"],
                    displaySpaceIndexes: ["built-in": 1, "external-lg": 2]
                )
            ],
            currentContextID: "context-1"
        )

        let matrix = ContextMatrixModel.matrix(plan: plan, displays: displays)

        XCTAssertEqual(matrix.rows[0].cells.map(\.spaceIndex), [0, nil, 1])
        XCTAssertEqual(matrix.rows[1].cells.map(\.spaceIndex), [0, 1, 2])
    }

    func testContextCaptureStatusDisplayShowsAligningCapturingAndCompleted() {
        let strings = SBSStrings(language: .english)

        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .aligning(attempt: 2),
                maxAlignmentAttempts: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Finding first Space · try 2/5"
        )
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .capturing(order: 3),
                maxAlignmentAttempts: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Capturing Context 3"
        )
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .completed(currentContextID: "captured-final"),
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
                maxAlignmentAttempts: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Capture failed: No Space movement detected"
        )
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .stopped,
                maxAlignmentAttempts: 5,
                completedContextCount: 0,
                strings: strings
            ),
            "Capture stopped. Existing Contexts were kept."
        )
    }

    func testContextCaptureStatusDisplayUsesNoCaptureLimit() throws {
        XCTAssertEqual(
            ContextCaptureStatusDisplay.statusText(
                phase: .capturing(order: 13),
                maxAlignmentAttempts: 5,
                completedContextCount: 0,
                strings: SBSStrings(language: .english)
            ),
            "Capturing Context 13"
        )

        var session = ContextCaptureSession(maxAlignmentAttempts: 4)
        XCTAssertEqual(
            try XCTUnwrap(ContextCaptureStatusDisplay.progressValue(session: session)),
            0.04,
            accuracy: 0.0001
        )
        session.recordAlignment(previousDidChange: false)
        XCTAssertNil(ContextCaptureStatusDisplay.progressValue(session: session))
    }

    func testContextCaptureStatusDisplayUsesSessionCompletedCount() {
        var session = ContextCaptureSession()
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

    func testPermissionStepPresentsOnlyAccessibilityAndPostEventsCards() {
        XCTAssertEqual(
            PermissionStepPresentation(language: .english).cards,
            [
                PermissionCardPresentation(
                    title: "Accessibility",
                    subtitle: "Required to observe ⌥⇧-held swipes."
                ),
                PermissionCardPresentation(
                    title: "Post Events",
                    subtitle: "Required to send the requested Space switch."
                )
            ]
        )
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
        XCTAssertEqual(english.contextNeedsAlignment, "Displays need alignment")
        XCTAssertEqual(korean.contextNeedsAlignment, "디스플레이 정렬이 필요합니다")
    }

    func testUpdateCheckStringsLocalize() {
        XCTAssertEqual(SBSStrings(language: .english).checkForUpdates, "Check for Updates…")
        XCTAssertEqual(SBSStrings(language: .korean).checkForUpdates, "업데이트 확인…")
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
