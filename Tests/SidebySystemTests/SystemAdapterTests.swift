import ApplicationServices
import CoreGraphics
import XCTest
@testable import SidebyCore
@testable import SidebySystem

final class SystemAdapterTests: XCTestCase {
    func testSpaceCommandExecutorPostsControlArrowKey() {
        let poster = RecordingKeyEventPoster()
        let executor = MacSpaceCommandExecutor(poster: poster)

        XCTAssertTrue(executor.execute(.next))
        XCTAssertEqual(poster.recordedKeys, [124])
        XCTAssertEqual(poster.recordedFlags, [.maskControl])
    }

    func testAppleScriptKeyEventPosterBuildsControlArrowScript() {
        let runner = RecordingAppleScriptRunner()
        let poster = AppleScriptKeyEventPoster(runner: runner)

        XCTAssertTrue(poster.postKey(virtualKey: 124, flags: .maskControl))
        XCTAssertEqual(runner.sources.count, 1)
        XCTAssertTrue(runner.sources[0].contains("tell application \"System Events\""))
        XCTAssertTrue(runner.sources[0].contains("key code 124 using {control down}"))
    }

    func testAppleScriptModifierNeutralizingExecutorReleasesModifiersBeforeControlArrow() {
        let runner = RecordingAppleScriptRunner()
        let executor = AppleScriptModifierNeutralizingSpaceCommandExecutor(
            modifiers: [.shift, .command],
            runner: runner
        )

        XCTAssertTrue(executor.execute(.next))
        XCTAssertEqual(runner.sources.count, 1)
        let source = runner.sources[0]
        XCTAssertTrue(source.contains("key up shift"))
        XCTAssertTrue(source.contains("key up command"))
        XCTAssertTrue(source.contains("key code 124 using {control down}"))
        XCTAssertLessThan(
            source.range(of: "key up command")!.lowerBound,
            source.range(of: "key code 124 using {control down}")!.lowerBound
        )
    }

    func testPrivateCGEventSpaceCommandExecutorPostsControlArrowOnly() {
        let poster = RecordingKeyEventPoster()
        let executor = PrivateCGEventSpaceCommandExecutor(poster: poster)

        XCTAssertTrue(executor.execute(.previous))
        XCTAssertEqual(poster.recordedKeys, [123])
        XCTAssertEqual(poster.recordedFlags, [.maskControl])
    }

    func testEventTapModifierRewriterKeepsOnlyControlForArrowKeys() {
        let rewrittenFlags = EventTapModifierRewriter.rewrittenFlags(
            type: .keyDown,
            keyCode: 124,
            originalFlags: [.maskShift, .maskAlternate, .maskControl]
        )

        XCTAssertEqual(rewrittenFlags, .maskControl)
        XCTAssertNil(
            EventTapModifierRewriter.rewrittenFlags(
                type: .keyDown,
                keyCode: 49,
                originalFlags: [.maskShift, .maskAlternate]
            )
        )
    }

    func testSystemEventsAutomationProbeBuildsPermissionSafeScript() {
        let runner = RecordingAppleScriptRunner()
        let probe = SystemEventsAutomationProbe(runner: runner)

        XCTAssertTrue(probe.requestAccess())
        XCTAssertEqual(runner.sources.count, 1)
        XCTAssertTrue(runner.sources[0].contains("tell application \"System Events\""))
        XCTAssertTrue(runner.sources[0].contains("count processes"))
    }

    func testAccessibilitySettingsDeepLinkTargetsPrivacyPane() {
        let url = SystemSettingsLink.accessibility

        XCTAssertEqual(
            url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testAutomationSettingsDeepLinkTargetsPrivacyPane() {
        let url = SystemSettingsLink.automation

        XCTAssertEqual(
            url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )
    }

    func testAutomationPermissionResultSummarizesKnownStatusCodes() {
        XCTAssertEqual(AutomationPermissionResult(statusCode: Int32(noErr)).statusText, "granted")
        XCTAssertEqual(
            AutomationPermissionResult(statusCode: Int32(errAEEventNotPermitted)).statusText,
            "blocked (-1743)"
        )
        XCTAssertEqual(
            AutomationPermissionResult(statusCode: Int32(errAEEventWouldRequireUserConsent)).statusText,
            "needs consent (-1744)"
        )
        XCTAssertEqual(
            AutomationPermissionResult(statusCode: Int32(procNotFound)).statusText,
            "System Events not running (-600)"
        )
    }

    func testSingleInstanceGuardAllowsFirstProductInstance() {
        let guarder = SingleInstanceGuard(
            currentProcessIdentifier: 10,
            bundleIdentifier: "dev.sideby.Sideby",
            runningApplications: []
        )

        XCTAssertEqual(guarder.startupDecision(), .continueLaunch)
    }

    func testSingleInstanceGuardActivatesExistingProductInstance() {
        let existing = RunningApplicationSnapshot(
            processIdentifier: 20,
            bundleIdentifier: "dev.sideby.Sideby"
        )
        let guarder = SingleInstanceGuard(
            currentProcessIdentifier: 10,
            bundleIdentifier: "dev.sideby.Sideby",
            runningApplications: [existing]
        )

        XCTAssertEqual(guarder.startupDecision(), .activateExisting(existing))
    }

    func testShortcutsBridgeBuildsEscapedRunScript() {
        let script = ShortcutsBridgeProbe<RecordingAppleScriptExecutor>.script(
            shortcutName: "Side \"Next\" \\ Space"
        )

        XCTAssertTrue(script.contains("tell application \"Shortcuts Events\""))
        XCTAssertTrue(script.contains("run shortcut \"Side \\\"Next\\\" \\\\ Space\""))
    }

    func testShortcutsBridgeExecutesGeneratedScript() {
        let executor = RecordingAppleScriptExecutor()
        let probe = ShortcutsBridgeProbe(executor: executor)

        let result = probe.runShortcut(named: "Sideby Next")

        XCTAssertTrue(result.didExecute)
        XCTAssertEqual(executor.sources.count, 1)
        XCTAssertTrue(executor.sources[0].contains("Sideby Next"))
    }

    func testShortcutsCommandLineProbeParsesListedShortcuts() {
        let names = ShortcutsCommandLineProbe<RecordingProcessCommandExecutor>.shortcutNames(
            from: "Sideby Next\nPhotos Resize\n\n"
        )

        XCTAssertEqual(names, ["Sideby Next", "Photos Resize"])
    }

    func testShortcutsCommandLinePreflightChecksExactShortcutName() {
        let executor = RecordingProcessCommandExecutor(
            results: [
                ProcessExecutionResult(
                    exitCode: 0,
                    output: "Sideby Next\nPhotos Resize\n",
                    errorOutput: ""
                )
            ]
        )
        let probe = ShortcutsCommandLineProbe(executor: executor, executablePath: "/usr/bin/shortcuts")

        let result = probe.preflight(shortcutName: "Sideby Next")

        XCTAssertTrue(result.exactMatchExists)
        XCTAssertEqual(result.shortcutNames.count, 2)
        XCTAssertEqual(executor.calls, [
            ProcessCommandCall(executablePath: "/usr/bin/shortcuts", arguments: ["list"])
        ])
    }

    func testShortcutsCommandLineRunUsesShortcutCommand() {
        let executor = RecordingProcessCommandExecutor(
            results: [
                ProcessExecutionResult(exitCode: 0, output: "ok", errorOutput: "")
            ]
        )
        let probe = ShortcutsCommandLineProbe(executor: executor, executablePath: "/usr/bin/shortcuts")

        let result = probe.runShortcut(named: "Sideby Next")

        XCTAssertTrue(result.didSucceed)
        XCTAssertEqual(executor.calls, [
            ProcessCommandCall(executablePath: "/usr/bin/shortcuts", arguments: ["run", "Sideby Next"])
        ])
    }

    func testWindowListDiffSummarizesOwnerChanges() {
        let before = WindowListSnapshot(
            onScreenCount: 2,
            allCount: 5,
            onScreenOwners: ["Arc", "Xcode"],
            onScreenWindowSignatures: ["Arc#1@L0[0,0,100,100]", "Xcode#2@L0[100,0,100,100]"]
        )
        let after = WindowListSnapshot(
            onScreenCount: 3,
            allCount: 6,
            onScreenOwners: ["Arc", "Notes", "Xcode"],
            onScreenWindowSignatures: [
                "Arc#1@L0[0,0,100,100]",
                "Notes#3@L0[200,0,100,100]",
                "Xcode#2@L0[100,0,100,100]"
            ]
        )

        let diff = WindowListDiffResult(before: before, after: after)

        XCTAssertEqual(diff.appearedOwners, ["Notes"])
        XCTAssertEqual(diff.disappearedOwners, [])
        XCTAssertEqual(diff.appearedWindows, ["Notes#3@L0[200,0,100,100]"])
        XCTAssertEqual(diff.disappearedWindows, [])
        XCTAssertTrue(diff.didChangeVisibleWindows)
        XCTAssertTrue(diff.summary.contains("onScreen 2->3"))
    }

    func testActiveSpaceSwitchObservationSummarizesDetectedChange() {
        let observation = ActiveSpaceSwitchObservation(
            command: .next,
            didExecuteCommand: true,
            beforeChangeCount: 4,
            afterChangeCount: 6
        )

        XCTAssertEqual(observation.observedChangeCount, 2)
        XCTAssertTrue(observation.didObserveSpaceChange)
        XCTAssertTrue(observation.summary.contains("notifications 4->6"))
    }

    func testHiddenSwitchTimingEstimatesExecutorDuration() {
        let timing = HiddenSwitchTimingConfiguration(
            focusDelay: 0.04,
            switchDelay: 0.32,
            observerWait: 0.85
        )

        XCTAssertEqual(timing.estimatedExecutorDuration(displayCount: 2), 0.84, accuracy: 0.0001)
        XCTAssertTrue(timing.summary.contains("focus=0.04"))
        XCTAssertTrue(timing.summary.contains("transition=0.10"))
        XCTAssertEqual(HiddenSwitchTimingConfiguration.optimizedCandidate.switchDelay, 0.20, accuracy: 0.0001)
        XCTAssertEqual(HiddenSwitchTimingConfiguration.conservativeCandidate.switchDelay, 0.21, accuracy: 0.0001)
        XCTAssertEqual(HiddenCursorDisplaySpaceCommandExecutor.defaultHideSettleDelay, 0.02, accuracy: 0.0001)
        XCTAssertEqual(HiddenCursorDisplaySpaceCommandExecutor.defaultSwitchDelay, 0.20, accuracy: 0.0001)
        XCTAssertEqual(HiddenCursorDisplaySpaceCommandExecutor.defaultTransitionSettleDelay, 0.10, accuracy: 0.0001)
        XCTAssertEqual(HiddenCursorDisplaySpaceCommandExecutor.defaultRestoreDelay, 0.04, accuracy: 0.0001)
    }

    func testAckingHiddenSwitchProbeResultRequiresAckAndWindowChange() {
        let timing = HiddenSwitchTimingConfiguration(
            focusDelay: 0.04,
            switchDelay: 0.32,
            observerWait: 0.85
        )
        let before = WindowListSnapshot(
            onScreenCount: 1,
            allCount: 2,
            onScreenOwners: ["Arc"],
            onScreenWindowSignatures: ["Arc#1@L0[0,0,100,100]"]
        )
        let after = WindowListSnapshot(
            onScreenCount: 1,
            allCount: 2,
            onScreenOwners: ["Xcode"],
            onScreenWindowSignatures: ["Xcode#2@L0[0,0,100,100]"]
        )
        let result = AckingHiddenSwitchProbeResult(
            command: .next,
            timing: timing,
            displayTargetCount: 2,
            didPost: true,
            activeSpaceObservation: ActiveSpaceSwitchObservation(
                command: .next,
                didExecuteCommand: true,
                beforeChangeCount: 0,
                afterChangeCount: 2
            ),
            windowDiff: WindowListDiffResult(before: before, after: after),
            elapsedSeconds: 1.2
        )

        XCTAssertEqual(result.expectedNotificationCount, 2)
        XCTAssertTrue(result.didAcknowledgeAllTargets)
        XCTAssertTrue(result.isAckConfirmedSuccess)
        XCTAssertTrue(result.summary.contains("ack confirmed"))
    }

    func testAckingHiddenRunnerExecutesAndReturnsDiagnostics() {
        let executor = RecordingSpaceCommandExecutor()
        let timing = HiddenSwitchTimingConfiguration.optimizedCandidate
        let runner = AckingHiddenSpaceCommandRunner(
            executor: executor,
            targetProvider: StaticDisplaySwitchTargetProvider(points: [
                CGPoint(x: 10, y: 10),
                CGPoint(x: 20, y: 20)
            ]),
            activeSpaceObserver: StaticActiveSpaceChangeObserver(afterChangeCount: 2),
            windowSnapshotProvider: StaticWindowListSnapshotProvider(
                snapshots: [
                    WindowListSnapshot(
                        onScreenCount: 1,
                        allCount: 2,
                        onScreenOwners: ["Arc"],
                        onScreenWindowSignatures: ["Arc#1@L0[0,0,100,100]"]
                    ),
                    WindowListSnapshot(
                        onScreenCount: 1,
                        allCount: 2,
                        onScreenOwners: ["Xcode"],
                        onScreenWindowSignatures: ["Xcode#2@L0[0,0,100,100]"]
                    )
                ]
            ),
            timing: timing
        )

        let result = runner.executeWithDiagnostics(.next)

        XCTAssertEqual(executor.commands, [.next])
        XCTAssertTrue(result.isAckConfirmedSuccess)
        XCTAssertEqual(result.activeSpaceObservation.observedChangeCount, 2)
        XCTAssertEqual(result.windowDiff.appearedOwners, ["Xcode"])
    }

    func testVisibleAppSuggestionResolverPrefersAccessibilityCandidate() {
        let display = DisplayInfo(
            id: "external-lg",
            name: "LG",
            isPrimary: false,
            isBuiltin: false,
            frame: DisplayFrame(x: 0, y: 0, width: 1000, height: 800)
        )
        let accessibilitySuggestion = VisibleAppSuggestion(
            displayID: display.id,
            appName: "Xcode",
            windowTitle: "SidebyApp.swift",
            source: .accessibility
        )

        let suggestion = VisibleAppSuggestionResolver.suggestion(
            for: display,
            accessibilitySuggestion: accessibilitySuggestion,
            windows: [
                VisibleWindowCandidate(
                    ownerName: "Arc",
                    windowTitle: "Docs",
                    bounds: CGRect(x: 0, y: 0, width: 1000, height: 800),
                    processIdentifier: 123,
                    layer: 0
                )
            ]
        )

        XCTAssertEqual(suggestion, accessibilitySuggestion)
    }

    func testVisibleAppSuggestionResolverFallsBackToLargestIntersectingWindow() {
        let display = DisplayInfo(
            id: "built-in",
            name: "Built-in",
            isPrimary: true,
            isBuiltin: true,
            frame: DisplayFrame(x: 0, y: 0, width: 1200, height: 800)
        )

        let suggestion = VisibleAppSuggestionResolver.suggestion(
            for: display,
            accessibilitySuggestion: nil,
            windows: [
                VisibleWindowCandidate(
                    ownerName: "Arc",
                    windowTitle: "Reference",
                    bounds: CGRect(x: 0, y: 0, width: 400, height: 800),
                    processIdentifier: 100,
                    layer: 0
                ),
                VisibleWindowCandidate(
                    ownerName: "Xcode",
                    windowTitle: "SidebyApp.swift",
                    bounds: CGRect(x: 300, y: 0, width: 900, height: 800),
                    processIdentifier: 200,
                    layer: 0
                ),
                VisibleWindowCandidate(
                    ownerName: "Menu",
                    windowTitle: nil,
                    bounds: CGRect(x: 0, y: 0, width: 1200, height: 20),
                    processIdentifier: nil,
                    layer: 25
                )
            ]
        )

        XCTAssertEqual(
            suggestion,
            VisibleAppSuggestion(
                displayID: display.id,
                appName: "Xcode",
                windowTitle: "SidebyApp.swift",
                source: .windowList
            )
        )
    }

    func testDisplaySwitchTargetOrderingCanFilterSelectedDisplays() {
        let candidates = [
            DisplaySwitchTargetCandidate(
                stableID: "right",
                isMain: false,
                originX: 1200,
                point: CGPoint(x: 1500, y: 500)
            ),
            DisplaySwitchTargetCandidate(
                stableID: "main",
                isMain: true,
                originX: 0,
                point: CGPoint(x: 500, y: 500)
            ),
            DisplaySwitchTargetCandidate(
                stableID: "left",
                isMain: false,
                originX: -1000,
                point: CGPoint(x: -500, y: 500)
            )
        ]

        let allPoints = DisplaySwitchTargetOrdering.targetPoints(from: candidates)
        let selectedPoints = DisplaySwitchTargetOrdering.targetPoints(
            from: candidates,
            includedStableIDs: ["left", "right"]
        )

        XCTAssertEqual(allPoints, [
            CGPoint(x: 500, y: 500),
            CGPoint(x: -500, y: 500),
            CGPoint(x: 1500, y: 500)
        ])
        XCTAssertEqual(selectedPoints, [
            CGPoint(x: -500, y: 500),
            CGPoint(x: 1500, y: 500)
        ])
    }

    func testDisplaySwitchTargetProviderUsesEdgeClippedFocusPoint() {
        let point = CGDisplaySwitchTargetProvider.focusPoint(
            in: CGRect(x: 100, y: 200, width: 1000, height: 800)
        )

        XCTAssertEqual(point, CGPoint(x: 1098, y: 998))
    }

    func testCoordinatedDisplayExecutorMovesCursorAcrossTargetsAndRestoresIt() {
        let baseExecutor = RecordingSpaceCommandExecutor()
        let targetProvider = StaticDisplaySwitchTargetProvider(points: [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 900, y: 100)
        ])
        let cursor = RecordingCursorPositioner(originalLocation: CGPoint(x: 12, y: 34))
        let executor = CoordinatedDisplaySpaceCommandExecutor(
            baseExecutor: baseExecutor,
            targetProvider: targetProvider,
            cursor: cursor,
            postEventAccessChecker: AllowingPostEventAccessChecker(),
            focusDelay: 0,
            switchDelay: 0
        )

        XCTAssertTrue(executor.execute(.previous))
        XCTAssertEqual(baseExecutor.commands, [.previous, .previous])
        XCTAssertEqual(cursor.movedPoints, [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 900, y: 100),
            CGPoint(x: 12, y: 34)
        ])
    }

    func testHiddenCursorExecutorHidesCursorWhileSweepingDisplays() {
        let baseExecutor = RecordingSpaceCommandExecutor()
        let targetProvider = StaticDisplaySwitchTargetProvider(points: [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 900, y: 100)
        ])
        let cursor = RecordingCursorPositioner(originalLocation: CGPoint(x: 12, y: 34))
        let visibility = RecordingCursorVisibilityController()
        let cursorShield = RecordingCursorShield()
        let association = RecordingMouseCursorAssociationController()
        let executor = HiddenCursorDisplaySpaceCommandExecutor(
            baseExecutor: baseExecutor,
            targetProvider: targetProvider,
            cursor: cursor,
            visibilityController: visibility,
            cursorShield: cursorShield,
            cursorAssociationController: association,
            postEventAccessChecker: AllowingPostEventAccessChecker(),
            hideSettleDelay: 0,
            focusDelay: 0,
            switchDelay: 0,
            transitionSettleDelay: 0,
            restoreDelay: 0
        )

        XCTAssertTrue(executor.execute(.next))
        XCTAssertEqual(baseExecutor.commands, [.next, .next])
        XCTAssertEqual(cursor.movedPoints, [
            CGPoint(x: 900, y: 100),
            CGPoint(x: 12, y: 34)
        ])
        XCTAssertEqual(visibility.actions, [
            "hide",
            "hide",
            "hide",
            "hide",
            "hide",
            "hide",
            "hide",
            "hide",
            "hide",
            "hide",
            "hide",
            "hide",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show"
        ])
        XCTAssertEqual(association.actions, [
            "disconnect",
            "connect"
        ])
        XCTAssertEqual(cursorShield.actions, [
            "begin",
            "end"
        ])
    }

    func testHiddenCursorExecutorStartsFromTargetNearestOriginalCursor() {
        let baseExecutor = RecordingSpaceCommandExecutor()
        let targetProvider = StaticDisplaySwitchTargetProvider(points: [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 900, y: 100)
        ])
        let cursor = RecordingCursorPositioner(originalLocation: CGPoint(x: 920, y: 110))
        let executor = HiddenCursorDisplaySpaceCommandExecutor(
            baseExecutor: baseExecutor,
            targetProvider: targetProvider,
            cursor: cursor,
            visibilityController: RecordingCursorVisibilityController(),
            cursorShield: RecordingCursorShield(),
            cursorAssociationController: RecordingMouseCursorAssociationController(),
            postEventAccessChecker: AllowingPostEventAccessChecker(),
            hideSettleDelay: 0,
            focusDelay: 0,
            switchDelay: 0,
            transitionSettleDelay: 0,
            restoreDelay: 0
        )

        XCTAssertTrue(executor.execute(.next))
        XCTAssertEqual(baseExecutor.commands, [.next, .next])
        XCTAssertEqual(cursor.movedPoints, [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 920, y: 110)
        ])
    }

    func testHiddenCursorExecutorShowsCursorOnlyAfterRestoringOriginalLocation() {
        let log = CursorOperationLog()
        let baseExecutor = LoggingSpaceCommandExecutor(log: log)
        let targetProvider = StaticDisplaySwitchTargetProvider(points: [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 900, y: 100)
        ])
        let cursor = LoggingCursorPositioner(
            log: log,
            originalLocation: CGPoint(x: 12, y: 34)
        )
        let visibility = LoggingCursorVisibilityController(log: log)
        let cursorShield = LoggingCursorShield(log: log)
        let association = LoggingMouseCursorAssociationController(log: log)
        let executor = HiddenCursorDisplaySpaceCommandExecutor(
            baseExecutor: baseExecutor,
            targetProvider: targetProvider,
            cursor: cursor,
            visibilityController: visibility,
            cursorShield: cursorShield,
            cursorAssociationController: association,
            postEventAccessChecker: AllowingPostEventAccessChecker(),
            hideSettleDelay: 0,
            focusDelay: 0,
            switchDelay: 0,
            transitionSettleDelay: 0,
            restoreDelay: 0
        )

        XCTAssertTrue(executor.execute(.next))
        XCTAssertEqual(log.entries, [
            "shield begin",
            "hide",
            "disconnect",
            "hide",
            "hide",
            "execute next",
            "hide",
            "hide",
            "move 900,100",
            "hide",
            "hide",
            "execute next",
            "hide",
            "hide",
            "move 12,34",
            "hide",
            "hide",
            "connect",
            "hide",
            "shield end",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show",
            "show"
        ])
    }

    func testCursorVisibilityControllerAppliesToEveryActiveDisplay() {
        let applier = RecordingCursorVisibilityApplier()
        let controller = CGCursorVisibilityController(
            displayProvider: StaticCursorVisibilityDisplayProvider(ids: [11, 22]),
            applier: applier
        )

        XCTAssertTrue(controller.hide())
        XCTAssertTrue(controller.show())
        XCTAssertEqual(applier.actions, [
            "hide 11",
            "hide 22",
            "show 11",
            "show 22"
        ])
    }

    func testOverlayClickExecutorClicksTargetsBeforeSwitching() {
        let baseExecutor = RecordingSpaceCommandExecutor()
        let targetProvider = StaticDisplaySwitchTargetProvider(points: [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 900, y: 100)
        ])
        let clicker = RecordingDisplayTargetClicker()
        let executor = OverlayClickDisplaySpaceCommandExecutor(
            baseExecutor: baseExecutor,
            targetProvider: targetProvider,
            clicker: clicker,
            postEventAccessChecker: AllowingPostEventAccessChecker(),
            clickDelay: 0,
            switchDelay: 0
        )

        XCTAssertTrue(executor.execute(.next))
        XCTAssertEqual(clicker.clickedPoints, [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 900, y: 100)
        ])
        XCTAssertEqual(clicker.cleanupCount, 1)
        XCTAssertEqual(baseExecutor.commands, [.next, .next])
    }

    func testAXFocusAnchorExecutorProbesTargetsBeforeSwitching() {
        let baseExecutor = RecordingSpaceCommandExecutor()
        let anchorProbe = RecordingAXFocusAnchorProbe()
        let targetProvider = StaticDisplaySwitchTargetProvider(points: [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 900, y: 100)
        ])
        let executor = AXFocusAnchorDisplaySpaceCommandExecutor(
            baseExecutor: baseExecutor,
            targetProvider: targetProvider,
            anchorProbe: anchorProbe,
            focusDelay: 0,
            switchDelay: 0
        )

        XCTAssertTrue(executor.execute(.next))
        XCTAssertEqual(anchorProbe.points, [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 900, y: 100)
        ])
        XCTAssertEqual(baseExecutor.commands, [.next, .next])
    }

    func testDisplayLayoutMapperBuildsStableDisplayLayout() {
        let snapshots = [
            DisplaySnapshot(
                displayID: 1,
                name: "Built-in Display",
                isPrimary: true,
                isBuiltin: true,
                vendorNumber: 10,
                modelNumber: 20,
                serialNumber: 30,
                frame: DisplayFrame(x: 0, y: 0, width: 1440, height: 900)
            ),
            DisplaySnapshot(
                displayID: 2,
                name: "LG Display",
                isPrimary: false,
                isBuiltin: false,
                vendorNumber: 11,
                modelNumber: 21,
                serialNumber: 31,
                frame: DisplayFrame(x: 1440, y: -120, width: 1920, height: 1080)
            )
        ]

        let layout = DisplayLayoutMapper.layout(from: snapshots)

        XCTAssertEqual(layout.displayCount, 2)
        XCTAssertTrue(layout.hasExternalDisplay)
        XCTAssertEqual(layout.primaryDisplay?.name, "Built-in Display")
        XCTAssertEqual(layout.primaryDisplay?.frame, DisplayFrame(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(layout.stableKey, "10-20-30-1|11-21-31-2")
    }

    func testEventTapModifierMapping() {
        let flags: CGEventFlags = [.maskAlternate, .maskCommand]

        let modifiers = EventTapInputNormalizer.modifierFlags(from: flags)

        XCTAssertTrue(modifiers.contains(.option))
        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertFalse(modifiers.contains(.control))
    }

    func testEventTapScrollNormalization() {
        let event = EventTapInputNormalizer.normalizedScroll(
            deltaX: 90,
            deltaY: 4,
            flags: [.maskAlternate],
            timestamp: 7,
            isMomentum: true
        )

        XCTAssertEqual(event.deltaX, 90)
        XCTAssertEqual(event.deltaY, 4)
        XCTAssertEqual(event.modifierFlags, [.option])
        XCTAssertEqual(event.timestamp, 7)
        XCTAssertTrue(event.isMomentum)
    }

    func testEventTapScrollDeltaPrefersTrackpadPointDelta() {
        XCTAssertEqual(
            EventTapInputNormalizer.preferredScrollDelta(discrete: 0, point: 42, fixed: 12),
            42
        )
        XCTAssertEqual(
            EventTapInputNormalizer.preferredScrollDelta(discrete: 0, point: 0, fixed: 12),
            12
        )
        XCTAssertEqual(
            EventTapInputNormalizer.preferredScrollDelta(discrete: 3, point: 0, fixed: 0),
            3
        )
    }

    func testEventTapMomentumUsesMomentumPhaseNotContinuousScroll() {
        XCTAssertFalse(EventTapInputNormalizer.isMomentumScroll(momentumPhase: 0))
        XCTAssertTrue(EventTapInputNormalizer.isMomentumScroll(momentumPhase: 1))
    }

    func testGlobalEventTapSuppressesOnlyOptionScroll() {
        XCTAssertTrue(
            GlobalEventTapInputSource.shouldSuppressOptionScroll(type: .scrollWheel, flags: [.maskAlternate])
        )
        XCTAssertFalse(
            GlobalEventTapInputSource.shouldSuppressOptionScroll(type: .scrollWheel, flags: [])
        )
        XCTAssertFalse(
            GlobalEventTapInputSource.shouldSuppressOptionScroll(type: .flagsChanged, flags: [.maskAlternate])
        )
    }

    func testGlobalEventTapSuppressesConfiguredModifierScroll() {
        XCTAssertTrue(
            GlobalEventTapInputSource.shouldSuppressScroll(
                type: .scrollWheel,
                flags: [.maskControl, .maskCommand],
                requiredModifiers: [.control, .command]
            )
        )
        XCTAssertFalse(
            GlobalEventTapInputSource.shouldSuppressScroll(
                type: .scrollWheel,
                flags: [.maskShift, .maskControl, .maskCommand],
                requiredModifiers: [.control, .command]
            )
        )
        XCTAssertFalse(
            GlobalEventTapInputSource.shouldSuppressScroll(
                type: .scrollWheel,
                flags: [.maskControl],
                requiredModifiers: [.control, .command]
            )
        )
    }

    func testEventTapMapsModifierKeyCodes() {
        XCTAssertEqual(EventTapInputNormalizer.modifierFlag(forKeyCode: 56), .shift)
        XCTAssertEqual(EventTapInputNormalizer.modifierFlag(forKeyCode: 58), .option)
        XCTAssertEqual(EventTapInputNormalizer.modifierFlag(forKeyCode: 59), .control)
        XCTAssertEqual(EventTapInputNormalizer.modifierFlag(forKeyCode: 55), .command)
        XCTAssertNil(EventTapInputNormalizer.modifierFlag(forKeyCode: 124))
    }

    func testGlobalEventTapSuppressesConfiguredModifierFlagChanges() {
        XCTAssertTrue(
            GlobalEventTapInputSource.shouldSuppressModifierFlagChange(
                type: .flagsChanged,
                keyCode: 55,
                requiredModifiers: [.shift, .command]
            )
        )
        XCTAssertFalse(
            GlobalEventTapInputSource.shouldSuppressModifierFlagChange(
                type: .flagsChanged,
                keyCode: 59,
                requiredModifiers: [.shift, .command]
            )
        )
        XCTAssertFalse(
            GlobalEventTapInputSource.shouldSuppressModifierFlagChange(
                type: .keyDown,
                keyCode: 55,
                requiredModifiers: [.shift, .command]
            )
        )
    }

    func testKeyboardShortcutInputNormalizerBuildsKeyboardEvent() throws {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true))
        event.flags = [.maskShift, .maskCommand]

        let keyboardEvent = KeyboardShortcutInputNormalizer.keyboardEvent(type: .keyDown, event: event)

        XCTAssertEqual(keyboardEvent?.keyCode, 124)
        XCTAssertEqual(keyboardEvent?.modifiers, [.shift, .command])
    }

    func testGlobalShortcutInputSourceHandlesAndSuppressesMatchingShortcut() throws {
        let shortcutInput = ShortcutInputSource(
            previousShortcut: KeyboardShortcut(keyCode: 123, modifiers: [.shift, .command]),
            nextShortcut: KeyboardShortcut(keyCode: 124, modifiers: [.shift, .command])
        )
        var commands: [SwitchCommand] = []
        let source = GlobalShortcutInputSource(
            shortcutInputSource: shortcutInput,
            commandHandler: { commands.append($0) }
        )

        let matchingEvent = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true))
        matchingEvent.flags = [.maskShift, .maskCommand]
        let didMatch = source.handle(type: .keyDown, event: matchingEvent)

        XCTAssertTrue(didMatch)
        XCTAssertTrue(GlobalShortcutInputSource.shouldSuppressShortcutEvent(didMatchShortcut: didMatch))
        XCTAssertEqual(commands, [.next])
    }

    func testGlobalShortcutInputSourceHandlesMatchingShortcutRelease() throws {
        let shortcutInput = ShortcutInputSource(
            previousShortcut: KeyboardShortcut(keyCode: 123, modifiers: [.shift, .command]),
            nextShortcut: KeyboardShortcut(keyCode: 124, modifiers: [.shift, .command])
        )
        var releases: [SwitchCommand] = []
        let source = GlobalShortcutInputSource(
            shortcutInputSource: shortcutInput,
            commandHandler: { _ in },
            releaseHandler: { releases.append($0) }
        )

        let matchingEvent = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 123, keyDown: false))
        matchingEvent.flags = [.maskShift, .maskCommand]
        let didMatch = source.handleRelease(type: .keyUp, event: matchingEvent)

        XCTAssertTrue(didMatch)
        XCTAssertTrue(GlobalShortcutInputSource.shouldSuppressShortcutEvent(didMatchShortcut: didMatch))
        XCTAssertEqual(releases, [.previous])
    }
}

private final class RecordingKeyEventPoster: KeyEventPosting, @unchecked Sendable {
    private(set) var recordedKeys: [CGKeyCode] = []
    private(set) var recordedFlags: [CGEventFlags] = []

    func postKey(virtualKey: CGKeyCode, flags: CGEventFlags) -> Bool {
        recordedKeys.append(virtualKey)
        recordedFlags.append(flags)
        return true
    }
}

private final class RecordingAppleScriptRunner: AppleScriptRunning, @unchecked Sendable {
    private(set) var sources: [String] = []

    func run(source: String) -> Bool {
        sources.append(source)
        return true
    }
}

private final class RecordingAppleScriptExecutor: AppleScriptExecuting, @unchecked Sendable {
    private(set) var sources: [String] = []

    func execute(source: String) -> AppleScriptExecutionResult {
        sources.append(source)
        return AppleScriptExecutionResult(didExecute: true, output: "ok", errorMessage: nil)
    }
}

private struct ProcessCommandCall: Equatable {
    let executablePath: String
    let arguments: [String]
}

private final class RecordingProcessCommandExecutor: ProcessCommandExecuting, @unchecked Sendable {
    private var results: [ProcessExecutionResult]
    private(set) var calls: [ProcessCommandCall] = []

    init(results: [ProcessExecutionResult]) {
        self.results = results
    }

    func execute(executablePath: String, arguments: [String]) -> ProcessExecutionResult {
        calls.append(ProcessCommandCall(executablePath: executablePath, arguments: arguments))
        guard !results.isEmpty else {
            return ProcessExecutionResult(exitCode: 0, output: "", errorOutput: "")
        }

        return results.removeFirst()
    }
}

private final class RecordingSpaceCommandExecutor: SpaceCommandExecuting, @unchecked Sendable {
    private(set) var commands: [SwitchCommand] = []

    func execute(_ command: SwitchCommand) -> Bool {
        commands.append(command)
        return true
    }
}

private final class CursorOperationLog: @unchecked Sendable {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}

private final class LoggingSpaceCommandExecutor: SpaceCommandExecuting, @unchecked Sendable {
    private let log: CursorOperationLog

    init(log: CursorOperationLog) {
        self.log = log
    }

    func execute(_ command: SwitchCommand) -> Bool {
        log.append("execute \(command)")
        return true
    }
}

private struct StaticActiveSpaceChangeObserver: ActiveSpaceChangeObserving {
    let afterChangeCount: Int

    func runObservingChanges(wait: TimeInterval, action: () -> Bool) -> ActiveSpaceObservedRun {
        ActiveSpaceObservedRun(
            didPost: action(),
            beforeChangeCount: 0,
            afterChangeCount: afterChangeCount
        )
    }
}

private final class StaticWindowListSnapshotProvider: WindowListSnapshotProviding, @unchecked Sendable {
    private var snapshots: [WindowListSnapshot]

    init(snapshots: [WindowListSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() -> WindowListSnapshot {
        guard !snapshots.isEmpty else {
            return WindowListSnapshot(onScreenCount: 0, allCount: 0, onScreenOwners: [])
        }

        return snapshots.removeFirst()
    }
}

private struct StaticDisplaySwitchTargetProvider: DisplaySwitchTargetProviding {
    let points: [CGPoint]

    func targetPoints() -> [CGPoint] {
        points
    }
}

private final class RecordingCursorPositioner: CursorPositioning, @unchecked Sendable {
    private let originalLocation: CGPoint?
    private(set) var movedPoints: [CGPoint] = []

    init(originalLocation: CGPoint?) {
        self.originalLocation = originalLocation
    }

    func currentLocation() -> CGPoint? {
        originalLocation
    }

    func move(to point: CGPoint) {
        movedPoints.append(point)
    }
}

private final class LoggingCursorPositioner: CursorPositioning, @unchecked Sendable {
    private let log: CursorOperationLog
    private let originalLocation: CGPoint?

    init(log: CursorOperationLog, originalLocation: CGPoint?) {
        self.log = log
        self.originalLocation = originalLocation
    }

    func currentLocation() -> CGPoint? {
        originalLocation
    }

    func move(to point: CGPoint) {
        log.append("move \(Int(point.x)),\(Int(point.y))")
    }
}

private final class RecordingCursorVisibilityController: CursorVisibilityControlling, @unchecked Sendable {
    private(set) var actions: [String] = []

    func hide() -> Bool {
        actions.append("hide")
        return true
    }

    func show() -> Bool {
        actions.append("show")
        return true
    }
}

private final class LoggingCursorVisibilityController: CursorVisibilityControlling, @unchecked Sendable {
    private let log: CursorOperationLog

    init(log: CursorOperationLog) {
        self.log = log
    }

    func hide() -> Bool {
        log.append("hide")
        return true
    }

    func show() -> Bool {
        log.append("show")
        return true
    }
}

private final class RecordingCursorShield: CursorShielding, @unchecked Sendable {
    private(set) var actions: [String] = []

    func begin() -> Bool {
        actions.append("begin")
        return true
    }

    func end() {
        actions.append("end")
    }
}

private final class LoggingCursorShield: CursorShielding, @unchecked Sendable {
    private let log: CursorOperationLog

    init(log: CursorOperationLog) {
        self.log = log
    }

    func begin() -> Bool {
        log.append("shield begin")
        return true
    }

    func end() {
        log.append("shield end")
    }
}

private final class RecordingMouseCursorAssociationController: MouseCursorAssociationControlling, @unchecked Sendable {
    private(set) var actions: [String] = []

    func disconnect() -> Bool {
        actions.append("disconnect")
        return true
    }

    func connect() -> Bool {
        actions.append("connect")
        return true
    }
}

private final class LoggingMouseCursorAssociationController: MouseCursorAssociationControlling, @unchecked Sendable {
    private let log: CursorOperationLog

    init(log: CursorOperationLog) {
        self.log = log
    }

    func disconnect() -> Bool {
        log.append("disconnect")
        return true
    }

    func connect() -> Bool {
        log.append("connect")
        return true
    }
}

private struct StaticCursorVisibilityDisplayProvider: CursorVisibilityDisplayProviding {
    let ids: [CGDirectDisplayID]

    func displayIDs() -> [CGDirectDisplayID] {
        ids
    }
}

private final class RecordingCursorVisibilityApplier: CursorVisibilityApplying, @unchecked Sendable {
    private(set) var actions: [String] = []

    func hide(displayID: CGDirectDisplayID) -> Bool {
        actions.append("hide \(displayID)")
        return true
    }

    func show(displayID: CGDirectDisplayID) -> Bool {
        actions.append("show \(displayID)")
        return true
    }
}

private final class RecordingDisplayTargetClicker: DisplayTargetClicking, @unchecked Sendable {
    private(set) var clickedPoints: [CGPoint] = []
    private(set) var cleanupCount = 0

    func click(point: CGPoint) -> Bool {
        clickedPoints.append(point)
        return true
    }

    func cleanup() {
        cleanupCount += 1
    }
}

private final class RecordingAXFocusAnchorProbe: AXFocusAnchorProbing, @unchecked Sendable {
    private(set) var points: [CGPoint] = []

    func probe(point: CGPoint, performRaise: Bool) -> AXFocusAnchorResult {
        points.append(point)
        return AXFocusAnchorResult(
            point: point,
            lookupErrorCode: AXError.success.rawValue,
            raiseErrorCode: AXError.success.rawValue,
            processIdentifier: 123,
            role: "AXWindow",
            title: "Test"
        )
    }
}

private struct AllowingPostEventAccessChecker: PostEventAccessChecking {
    func hasOrRequestAccess() -> Bool {
        true
    }
}
