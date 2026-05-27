import AppKit
import Combine
import CoreGraphics
import OSLog
import SidebyCore
import SidebySystem
import SidebyUI
import SwiftUI

@main
struct SidebyApp: App {
    @StateObject private var model = SidebyAppModel()
    @AppStorage("sideby.v1.onboarding-complete") private var didCompleteOnboarding = false

    init() {
        if ProductCommandLineRunner.runIfRequested() {
            Thread.sleep(forTimeInterval: 0.2)
            exit(0)
        }

        if SingleInstanceGuard.activateExistingApplicationAndReturnShouldTerminate() {
            Thread.sleep(forTimeInterval: 0.1)
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarControlView(
                model: model,
                didCompleteOnboarding: $didCompleteOnboarding
            )
        } label: {
            ProductMenuBarLabelView(didCompleteOnboarding: $didCompleteOnboarding)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Sideby", id: "main") {
            ProductRootView(
                model: model,
                didCompleteOnboarding: $didCompleteOnboarding
            )
            .frame(
                minWidth: didCompleteOnboarding ? 760 : 480,
                minHeight: didCompleteOnboarding ? 560 : 380
            )
            .onAppear {
                model.refresh()
            }
            .background(ProductMainWindowConfigurator())
        }
        .defaultSize(
            width: didCompleteOnboarding ? 760 : 480,
            height: didCompleteOnboarding ? 560 : 380
        )
    }
}

private struct ProductMenuBarLabelView: View {
    @Binding var didCompleteOnboarding: Bool
    @Environment(\.openWindow) private var openWindow
    @State private var didRequestInitialOnboardingWindow = false

    var body: some View {
        SidebyMenuBarIcon()
            .frame(width: 22, height: 18)
            .accessibilityLabel("Sideby")
            .onAppear {
                openInitialOnboardingWindowIfNeeded()
            }
            .onChange(of: didCompleteOnboarding) { _, _ in
                openInitialOnboardingWindowIfNeeded()
            }
    }

    private func openInitialOnboardingWindowIfNeeded() {
        guard !didCompleteOnboarding, !didRequestInitialOnboardingWindow else {
            return
        }

        didRequestInitialOnboardingWindow = true
        DispatchQueue.main.async {
            openWindow(id: "main")
            ProductMainWindowPresenter.present()
        }
    }
}

private struct SidebyMenuBarIcon: View {
    var body: some View {
        Image(nsImage: SidebyMenuBarIconImage.image)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}

private enum SidebyMenuBarIconImage {
    @MainActor
    static let image: NSImage = {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        NSGraphicsContext.current?.shouldAntialias = true
        NSColor.black.setStroke()
        NSColor.black.setFill()

        if let symbol = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 18.8, weight: .semibold)
        ) {
            symbol.draw(
                in: NSRect(x: 1.2, y: -0.5, width: 19.6, height: 19.6),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        let frontRect = NSRect(x: 9.05, y: 5.05, width: 5.8, height: 4.65)
        let backRect = NSRect(x: 6.75, y: 7.35, width: 5.8, height: 4.65)
        let monitorStrokeWidth = 1.2
        let backMonitor = NSBezierPath(roundedRect: backRect, xRadius: 1.0, yRadius: 1.0)
        backMonitor.lineWidth = monitorStrokeWidth
        backMonitor.lineCapStyle = .round
        backMonitor.lineJoinStyle = .round
        backMonitor.stroke()

        let frontMonitor = NSBezierPath(roundedRect: frontRect, xRadius: 1.05, yRadius: 1.05)
        frontMonitor.lineWidth = monitorStrokeWidth
        frontMonitor.lineCapStyle = .round
        frontMonitor.lineJoinStyle = .round
        frontMonitor.fill()
        frontMonitor.stroke()

        return image
    }()
}

private enum ProductCommandLineRunner {
    private static let probeLog = Logger(
        subsystem: "dev.sideby.Sideby",
        category: "ProductProbe"
    )

    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard let strategyName = argumentValue(after: "--probe-product-input-strategy", in: arguments),
              let strategy = ProductInputProbeStrategy(rawValue: strategyName)
        else {
            return false
        }

        let count = argumentValue(after: "--count", in: arguments).flatMap(Int.init) ?? 1
        runInputStrategyProbe(strategy: strategy, count: max(1, count))
        return true
    }

    private static func runInputStrategyProbe(strategy: ProductInputProbeStrategy, count: Int) {
        let timing = HiddenSwitchTimingConfiguration.optimizedCandidate
        var nextConfirmed = 0
        var previousConfirmed = 0
        var totalElapsed: TimeInterval = 0
        printAndLog("ProductInputStrategy[\(strategy.rawValue)]: start count=\(count)")

        for index in 1...count {
            let next = execute(strategy: strategy, command: .next, timing: timing)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let previous = execute(strategy: strategy, command: .previous, timing: timing)
            if next.isAckConfirmedSuccess {
                nextConfirmed += 1
            }
            if previous.isAckConfirmedSuccess {
                previousConfirmed += 1
            }
            totalElapsed += next.elapsedSeconds + previous.elapsedSeconds
            printAndLog("ProductInputStrategyRun[\(strategy.rawValue)] \(index): \(next.summary) | \(previous.summary)")
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }

        printAndLog(
            "ProductInputStrategySummary[\(strategy.rawValue)]: nextConfirmed=\(nextConfirmed)/\(count), previousConfirmed=\(previousConfirmed)/\(count), avgRoundTripElapsed=\(String(format: "%.2f", totalElapsed / Double(count)))s"
        )
    }

    private static func execute(
        strategy: ProductInputProbeStrategy,
        command: SwitchCommand,
        timing: HiddenSwitchTimingConfiguration
    ) -> AckingHiddenSwitchProbeResult {
        releaseAllProbeModifiers()
        applyHeldModifiers(for: strategy)
        defer {
            releaseAllProbeModifiers()
        }

        let targetProvider = CGDisplaySwitchTargetProvider()
        let executor = HiddenCursorDisplaySpaceCommandExecutor(
            baseExecutor: strategy.spaceCommandExecutor,
            targetProvider: targetProvider,
            hideSettleDelay: timing.hideSettleDelay,
            focusDelay: timing.focusDelay,
            switchDelay: timing.switchDelay,
            transitionSettleDelay: timing.transitionSettleDelay,
            restoreDelay: timing.restoreDelay
        )
        let runner = AckingHiddenSpaceCommandRunner(
            executor: executor,
            targetProvider: targetProvider,
            activeSpaceObserver: NSWorkspaceActiveSpaceChangeObserver(),
            windowSnapshotProvider: CGWindowListSnapshotProvider(),
            timing: timing
        )
        return runner.executeWithDiagnostics(command)
    }

    private static func applyHeldModifiers(for strategy: ProductInputProbeStrategy) {
        switch strategy {
        case .button, .releaseSwipe, .releaseKeyboard, .suppressSwipe, .suppressKeyboard:
            break
        case .immediateSwipe, .privateSwipe, .privateSessionSwipe, .rewriteSwipe:
            setModifiers(probeModifiers(for: AppSettings.defaultGestureModifiers), isDown: true)
        case .immediateKeyboard, .privateKeyboard, .privateSessionKeyboard, .rewriteKeyboard:
            setModifiers(probeModifiers(for: AppSettings.defaultShortcutModifiers), isDown: true)
        case .controlSwipe:
            setModifiers([.control], isDown: true)
        }
    }

    private static func probeModifiers(for modifiers: ModifierFlags) -> [ProbeModifier] {
        var probeModifiers: [ProbeModifier] = []
        if modifiers.contains(.shift) {
            probeModifiers.append(.shift)
        }
        if modifiers.contains(.option) {
            probeModifiers.append(.option)
        }
        if modifiers.contains(.command) {
            probeModifiers.append(.command)
        }
        if modifiers.contains(.control) {
            probeModifiers.append(.control)
        }
        return probeModifiers
    }

    private static func releaseAllProbeModifiers() {
        setModifiers([.shift, .option, .command, .control], isDown: false)
    }

    private static func setModifiers(_ modifiers: [ProbeModifier], isDown: Bool) {
        guard !modifiers.isEmpty else {
            return
        }

        let flags = combinedFlags(for: modifiers, isDown: isDown)
        let source = CGEventSource(stateID: .hidSystemState)
        for modifier in modifiers {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: modifier.keyCode,
                keyDown: isDown
            ) else {
                continue
            }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private static func combinedFlags(for modifiers: [ProbeModifier], isDown: Bool) -> CGEventFlags {
        guard isDown else {
            return []
        }

        return modifiers.reduce(into: CGEventFlags()) { flags, modifier in
            flags.insert(modifier.cgFlag)
        }
    }

    @discardableResult
    private static func runSystemEventsScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            return false
        }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        if let error {
            printAndLog("ProductInputStrategyScriptError: \(error)")
            return false
        }
        return true
    }

    private static func printAndLog(_ message: String) {
        print(message)
        NSLog("%@", message)
        probeLog.notice("\(message, privacy: .public)")
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        let urls = [
            URL(fileURLWithPath: "/tmp/sideby-product-probe.log"),
            FileManager.default.temporaryDirectory.appendingPathComponent("sideby-product-probe.log")
        ]
        for url in urls {
            append(data, to: url)
        }
    }

    private static func append(_ data: Data, to url: URL) {
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
            return
        }
        try? data.write(to: url)
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }
}

private enum ProductInputProbeStrategy: String {
    case button
    case immediateSwipe = "immediate-swipe"
    case releaseSwipe = "release-swipe"
    case suppressSwipe = "suppress-swipe"
    case controlSwipe = "control-swipe"
    case privateSwipe = "private-swipe"
    case privateSessionSwipe = "private-session-swipe"
    case rewriteSwipe = "rewrite-swipe"
    case immediateKeyboard = "immediate-keyboard"
    case releaseKeyboard = "release-keyboard"
    case suppressKeyboard = "suppress-keyboard"
    case privateKeyboard = "private-keyboard"
    case privateSessionKeyboard = "private-session-keyboard"
    case rewriteKeyboard = "rewrite-keyboard"

    var spaceCommandExecutor: any SpaceCommandExecuting {
        switch self {
        case .button, .releaseSwipe, .releaseKeyboard, .suppressSwipe, .suppressKeyboard, .controlSwipe:
            MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster())
        case .immediateSwipe:
            AppleScriptModifierNeutralizingSpaceCommandExecutor(modifiers: AppSettings.defaultGestureModifiers)
        case .immediateKeyboard:
            AppleScriptModifierNeutralizingSpaceCommandExecutor(modifiers: AppSettings.defaultShortcutModifiers)
        case .privateSwipe, .privateKeyboard:
            PrivateCGEventSpaceCommandExecutor()
        case .privateSessionSwipe, .privateSessionKeyboard:
            PrivateCGEventSpaceCommandExecutor(
                poster: CGEventKeyEventPoster(
                    tap: .cgSessionEventTap,
                    sourceStateID: .privateState,
                    sendsModifierFlagEvents: false
                )
            )
        case .rewriteSwipe, .rewriteKeyboard:
            EventTapModifierRewritingSpaceCommandExecutor(
                baseExecutor: MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster())
            )
        }
    }
}

private enum ProbeModifier {
    case shift
    case option
    case command
    case control

    var keyCode: CGKeyCode {
        switch self {
        case .shift:
            56
        case .option:
            58
        case .command:
            55
        case .control:
            59
        }
    }

    var cgFlag: CGEventFlags {
        switch self {
        case .shift:
            .maskShift
        case .option:
            .maskAlternate
        case .command:
            .maskCommand
        case .control:
            .maskControl
        }
    }
}

@MainActor
private enum ProductMainWindowPresenter {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("sideby-main-window")

    static func present(after delay: TimeInterval = 0.08) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            bringMainWindowToFront()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            bringMainWindowToFront()
        }
    }

    static func configure(_ window: NSWindow) {
        window.identifier = windowIdentifier
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    static func hideIfVisible() {
        NSApplication.shared.windows
            .filter { window in
                window.identifier == windowIdentifier || window.title == "Sideby"
            }
            .forEach { window in
                window.orderOut(nil)
            }
    }

    private static func bringMainWindowToFront() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let window = NSApplication.shared.windows.first(where: { window in
            window.identifier == windowIdentifier || window.title == "Sideby"
        }) else {
            return
        }

        configure(window)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

@MainActor
private final class SidebyAppModel: ObservableObject, SBSOnboardingViewModel {
    @Published var settings: AppSettings
    @Published var displayLayout = DisplayLayout(displays: [])
    @Published var permissionState: PermissionState = .notDetermined
    @Published var postEventAccessGranted = false
    @Published var automationAccessGranted = false
    @Published var permissionRequestFeedback: PermissionRequestFeedback?
    @Published var selectedDisplayIDs: Set<String> = []
    @Published var diagnostics: [DiagnosticState] = []
    @Published var lastSwitchResult = "No switch attempted"
    @Published var isSwitching = false
    @Published var isEnabled = false
    @Published var isInputRunning = false
    @Published var inputStatus = "Sideby off"
    @Published var lastInputEvent = "Use the configured swipe gesture."
    @Published var loginItemStatus = "Start at login off"
    @Published var onboardingDetectedGestureCount = 0
    @Published var didFinishMiniOnboarding = false
    @Published var visibleSpaceSuggestionsByDisplayID: [String: [Int: VisibleAppSuggestion]] = [:]
    @Published var spaceCaptureSession: SpaceCaptureSession?
    @Published var spaceCaptureStatus: String?
    @Published var spacesToCapture = DisplaySpacePlan.default.defaultCaptureCount

    private let settingsStore = UserDefaultsSettingsStore()
    private let permissionService = AccessibilityPermissionService()
    private let displayObserver = MacDisplayObserver()
    private let visibleAppSuggestionProvider = MacVisibleAppSuggestionProvider()
    private let loginItemService = MacLoginItemService()
    private let automationPermissionProbe = SystemEventsAutomationPermissionProbe()
    private let systemEventsAutomationProbe = SystemEventsAutomationProbe<NSAppleScriptRunner>()
    private let setupFlow = V1SetupFlow()
    private static let enabledDefaultsKey = "sideby.enabled"
    private var didInitializeSelectedDisplays = false
    private var swipeInputSource: GlobalEventTapInputSource?
    private var keyboardShortcutInputSource: GlobalShortcutInputSource?
    private var swipePipeline = SwipeInputPipeline(settings: .default)
    private var inputLatch = InputCommandLatch()
    private var inputSessionID = 0
    private var switchSessionID = 0
    private var permissionPollingID = 0
    private var lastScrollStatusUpdate = 0.0
    private var isOnboardingGestureTestActive = false
    private var settingsObserver: NSObjectProtocol?

    init() {
        var loadedSettings = settingsStore.load()
        loadedSettings.mode = .shortcut
        self.settings = loadedSettings
        self.spacesToCapture = loadedSettings.displaySpacePlan.defaultCaptureCount
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        let strings = SBSStrings(language: loadedSettings.language)
        self.lastSwitchResult = strings.noSwitchAttempted
        self.inputStatus = strings.sidebyOff
        self.lastInputEvent = Self.inputHint(for: loadedSettings, strings: strings)
        self.loginItemStatus = strings.startAtLoginStatus(isEnabled: loginItemService.isEnabled)
        startSettingsChangeObserver()
        refresh()
        if isEnabled {
            DispatchQueue.main.async { [weak self] in
                self?.resumeEnabledInputIfNeeded()
            }
        }
    }

    var selectedDisplaySummary: String {
        let selectedCount = selectedDisplayIDs.count
        let displayCount = displayLayout.displayCount

        return strings.selectedDisplaySummary(selected: selectedCount, total: displayCount)
    }

    var gestureInputSummary: String {
        strings.horizontalScrollGesture(settings.requiredModifiers)
    }

    var keyboardCommandSummary: String {
        settings.keyboardShortcutsEnabled ? Self.keyboardShortcutSummary(for: settings) : strings.keyboardShortcutsOff
    }

    var keyboardShortcutModifierSummary: String {
        strings.modifierText(keyboardShortcutModifiers)
    }

    var hasAccessibilityPermission: Bool {
        permissionService.currentState == .granted
    }

    var hasSwitchingAccess: Bool {
        postEventAccessGranted && automationAccessGranted
    }

    var detectedGestureCount: Int {
        onboardingDetectedGestureCount
    }

    var displayCount: Int {
        displayLayout.displayCount
    }

    var strings: SBSStrings {
        SBSStrings(language: settings.language)
    }

    var setupViewState: V1SetupViewState {
        setupFlow.viewState(
            for: V1SetupStatus(
                displayCount: displayLayout.displayCount,
                selectedTargetCount: selectedDisplayIDs.count,
                accessibilityPermission: permissionState,
                isSidebyEnabled: isEnabled,
                didCompleteOnboarding: false
            )
        )
    }

    var runtimeState: RuntimeState {
        RuntimeState(
            accessibilityPermission: permissionState,
            displayLayout: displayLayout,
            availableSpaceCount: 3
        )
    }

    func refresh() {
        displayLayout = displayObserver.currentLayout()
        syncSelectedDisplays(with: displayLayout)
        syncDisplaySpacePlan(with: displayLayout)
        permissionState = permissionService.currentState
        postEventAccessGranted = CGPreflightPostEventAccess()
        automationAccessGranted = automationPermissionProbe.checkAccessWithoutPrompt().isGranted
        loginItemStatus = strings.startAtLoginStatus(isEnabled: loginItemService.isEnabled)
        diagnostics = DiagnosticRule.evaluate(
            decision: ModePolicy().decision(
                for: settings.mode,
                inputMethod: .shortcut,
                runtimeState: runtimeState
            )
        )
    }

    func requestPermissions() {
        if permissionService.currentState != .granted {
            openSystemSettingsAccessibility()
            return
        } else if !hasSwitchingAccess {
            requestSwitchingAccess()
            pollPermissionsForOnboarding()
            return
        }
        refresh()
    }

    func openSystemSettingsAccessibility() {
        permissionRequestFeedback = nil
        openAccessibilitySettings()
        refresh()
        pollPermissionsForOnboarding()
    }

    func openSystemSettingsAutomation() {
        permissionRequestFeedback = nil
        openAutomationSettings()
        refresh()
        pollPermissionsForOnboarding()
    }

    func requestSwitchingAccess() {
        permissionRequestFeedback = .switchingAccessRequesting
        NSApplication.shared.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else {
                return
            }

            let didGrantPostEvents = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
            let didGrantAutomation = systemEventsAutomationProbe.requestAccess()
            refresh()
            updateSwitchingAccessFeedback(
                postEventsGranted: didGrantPostEvents || postEventAccessGranted,
                automationStatusCode: (didGrantAutomation || automationAccessGranted) ? Int32(noErr) : Int32(errAEEventNotPermitted)
            )
            pollPermissionsForOnboarding()
        }
    }

    private func updateSwitchingAccessFeedback(
        postEventsGranted: Bool,
        automationStatusCode: Int32
    ) {
        permissionRequestFeedback = PermissionRequestFeedbackResolver()
            .switchingAccessFeedback(
                postEventsGranted: postEventsGranted,
                automationStatusCode: automationStatusCode
            )
    }

    func skipGestureTest() {
        isOnboardingGestureTestActive = false
        onboardingDetectedGestureCount = max(onboardingDetectedGestureCount, 1)
        if !isEnabled {
            stopInputControl()
        }
    }

    func finish() {
        isOnboardingGestureTestActive = false
        applyOnboardingCompletionDefaults()
        didFinishMiniOnboarding = true
    }

    func prepareMiniOnboarding() {
        isOnboardingGestureTestActive = true
        didFinishMiniOnboarding = false
        onboardingDetectedGestureCount = 0
        refresh()
        if hasAccessibilityPermission {
            startInputControl(requestsPermissions: false)
        }
    }

    func setDisplayTarget(_ display: DisplayInfo, isSelected: Bool) {
        var selected = selectedDisplayIDs
        if isSelected {
            selected.insert(display.id)
        } else {
            selected.remove(display.id)
        }
        selectedDisplayIDs = selected
    }

    func selectAllDisplayTargets() {
        selectedDisplayIDs = Set(displayLayout.displays.map(\.id))
    }

    func setSpacesToCapture(_ count: Int) {
        let normalizedCount = min(max(count, 1), 12)
        spacesToCapture = normalizedCount
        updateDisplaySpacePlan { plan in
            plan.defaultCaptureCount = normalizedCount
            for display in displayLayout.displays {
                plan.ensureSpaces(displayID: display.id, upTo: normalizedCount)
            }
        }
    }

    func displaySpaceLabel(displayID: String, spaceOrder: Int) -> String {
        settings.displaySpacePlan.label(displayID: displayID, spaceOrder: spaceOrder) ?? ""
    }

    func setDisplaySpaceLabel(displayID: String, spaceOrder: Int, label: String) {
        updateDisplaySpacePlan { plan in
            plan.updateLabel(displayID: displayID, spaceOrder: spaceOrder, label: label)
        }
    }

    func visibleSpaceSuggestion(displayID: String, spaceOrder: Int) -> VisibleAppSuggestion? {
        visibleSpaceSuggestionsByDisplayID[displayID]?[spaceOrder]
    }

    func visibleSpaceCount(displayID: String) -> Int {
        let suggestionOrders = visibleSpaceSuggestionsByDisplayID[displayID]
            .map { Set($0.keys) } ?? []
        return settings.displaySpacePlan.visibleSpaceCount(
            displayID: displayID,
            captureCount: spacesToCapture,
            suggestionOrders: suggestionOrders
        )
    }

    func scanVisibleAppsForCurrentSpace() {
        scanVisibleApps(spaceOrder: 1)
    }

    private func scanVisibleApps(spaceOrder: Int) {
        refresh()
        let normalizedOrder = max(spaceOrder, 1)
        updateDisplaySpacePlan { plan in
            for display in displayLayout.displays {
                plan.ensureSpaces(displayID: display.id, upTo: max(normalizedOrder, spacesToCapture))
            }
        }

        var suggestionsByDisplayID = visibleSpaceSuggestionsByDisplayID
        for suggestion in visibleAppSuggestionProvider.suggestions(for: displayLayout) {
            suggestionsByDisplayID[suggestion.displayID, default: [:]][normalizedOrder] = suggestion
        }
        visibleSpaceSuggestionsByDisplayID = suggestionsByDisplayID
    }

    func useVisibleSpaceSuggestionAppName(displayID: String, spaceOrder: Int) {
        guard let suggestion = visibleSpaceSuggestion(displayID: displayID, spaceOrder: spaceOrder) else {
            return
        }

        setDisplaySpaceLabel(displayID: displayID, spaceOrder: spaceOrder, label: suggestion.appLabel)
    }

    func useVisibleSpaceSuggestionWindowTitle(displayID: String, spaceOrder: Int) {
        guard let suggestion = visibleSpaceSuggestion(displayID: displayID, spaceOrder: spaceOrder),
              let titleLabel = suggestion.titleLabel
        else {
            return
        }

        setDisplaySpaceLabel(displayID: displayID, spaceOrder: spaceOrder, label: titleLabel)
    }

    func startSpaceCapture() {
        refresh()
        guard isEnabled else {
            blockSwitchBecauseSidebyIsOff(command: .next, label: "space-capture")
            return
        }
        guard hasSelectedMoveTargets(command: .next, label: "space-capture") else {
            return
        }
        guard !isSwitching,
              spaceCaptureSession == nil
        else {
            return
        }

        spaceCaptureSession = SpaceCaptureSession(spaceCount: spacesToCapture)
        continueSpaceCapture()
    }

    func stopSpaceCapture() {
        var session = spaceCaptureSession
        session?.stop()
        spaceCaptureSession = nil
        spaceCaptureStatus = nil
    }

    private func continueSpaceCapture() {
        guard let session = spaceCaptureSession else {
            spaceCaptureStatus = nil
            return
        }

        scanVisibleApps(spaceOrder: session.currentSpaceOrder)
        updateSpaceCaptureStatus(session: session)

        guard let command = session.nextCommand() else {
            spaceCaptureSession = nil
            spaceCaptureStatus = nil
            return
        }

        performSwitch(command, label: "space-capture", completion: { [weak self] didExecute in
            guard let self else {
                return
            }
            guard didExecute, var activeSession = self.spaceCaptureSession else {
                self.spaceCaptureSession = nil
                self.spaceCaptureStatus = nil
                return
            }

            activeSession.advanceAfterSuccessfulSwitch()
            self.spaceCaptureSession = activeSession
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.continueSpaceCapture()
            }
        })
    }

    private func updateSpaceCaptureStatus(session: SpaceCaptureSession) {
        spaceCaptureStatus = SpaceCaptureStatusDisplay.statusText(
            currentSpace: session.currentStep,
            totalSpaces: session.totalSteps,
            strings: strings
        )
    }

    private func applyOnboardingCompletionDefaults() {
        refresh()
        let defaults = OnboardingCompletionPolicy().completionDefaults(for: displayLayout)
        selectedDisplayIDs = defaults.selectedDisplayIDs
        isEnabled = defaults.isSidebyEnabled
        UserDefaults.standard.set(defaults.isSidebyEnabled, forKey: Self.enabledDefaultsKey)

        guard defaults.isSidebyEnabled else {
            stopInputControl()
            return
        }

        let didStart = startInputControl(requestsPermissions: false)
        if !didStart {
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
        }
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try loginItemService.setEnabled(isEnabled)
            settings.launchAtLogin = isEnabled
            settingsStore.save(settings)
            loginItemStatus = strings.startAtLoginStatus(isEnabled: isEnabled)
        } catch {
            loginItemStatus = strings.startAtLoginCouldNotChange
        }
    }

    func updateSettings(_ newSettings: AppSettings) {
        let issues = KeyboardShortcutValidator.issues(
            previous: newSettings.shortcutPrevious,
            next: newSettings.shortcutNext,
            gestureModifiers: newSettings.requiredModifiers
        )
        guard issues.isEmpty else {
            lastInputEvent = strings.shortcutSettingsNotSaved
            return
        }

        var savedSettings = newSettings
        savedSettings.mode = .shortcut
        settings = savedSettings
        settingsStore.save(savedSettings)
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
        refreshLocalizedStatus()
        lastInputEvent = strings.inputSettingsSaved(gesture: gestureInputSummary, keyboard: keyboardCommandSummary)

        guard isInputRunning else {
            return
        }

        let didStart = startInputControl(requestsPermissions: false)
        if !didStart {
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
        }
    }

    private func startSettingsChangeObserver() {
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: UserDefaultsSettingsStore.settingsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadSettingsFromStoreIfChanged()
            }
        }
    }

    private func reloadSettingsFromStoreIfChanged() {
        var loadedSettings = settingsStore.load()
        loadedSettings.mode = .shortcut
        guard loadedSettings != settings else {
            return
        }

        settings = loadedSettings
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
        refreshLocalizedStatus()
        lastInputEvent = strings.inputSettingsUpdated(gesture: gestureInputSummary, keyboard: keyboardCommandSummary)

        guard isInputRunning else {
            return
        }

        let didStart = startInputControl(requestsPermissions: false)
        if !didStart {
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
        }
    }

    private func refreshLocalizedStatus() {
        loginItemStatus = strings.startAtLoginStatus(isEnabled: loginItemService.isEnabled)
        if isInputRunning {
            inputStatus = isEnabled
                ? strings.sidebyOnTargets(selectedDisplaySummary)
                : strings.gestureTestListeningTargets(selectedDisplaySummary)
        } else {
            inputStatus = strings.sidebyOff
        }
    }

    @discardableResult
    func switchContext(_ command: SwitchCommand) -> Bool {
        refresh()
        guard !isSwitching else {
            lastSwitchResult = strings.ignoredSwitchAlreadyRunning(command: command)
            return false
        }
        guard isEnabled else {
            blockSwitchBecauseSidebyIsOff(command: command, label: "button")
            return false
        }
        guard hasSelectedMoveTargets(command: command, label: "button") else {
            return false
        }

        lastSwitchResult = strings.queuedSwitch(command: command, summary: selectedDisplaySummary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.performSwitch(command, label: "button")
        }
        return true
    }

    func setSidebyEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else {
            return
        }

        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)

        if enabled {
            let didStart = startInputControl(requestsPermissions: true)
            if !didStart {
                isEnabled = false
                UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
            }
        } else {
            stopInputControl()
            lastInputEvent = strings.sidebyIsOffInputEvent
        }
    }

    func toggleInputControl() {
        setSidebyEnabled(!isEnabled)
    }

    @discardableResult
    func startInputControl() -> Bool {
        startInputControl(requestsPermissions: true)
    }

    @discardableResult
    private func startInputControl(requestsPermissions: Bool) -> Bool {
        if requestsPermissions {
            requestPermissions()
        } else {
            refresh()
        }
        stopRunningInputSources()
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
        inputLatch.reset()
        inputSessionID += 1
        let sessionID = inputSessionID
        lastScrollStatusUpdate = 0

        let swipeSource = GlobalEventTapInputSource(
            suppressedScrollModifiers: settings.requiredModifiers,
            suppressedModifierFlags: nil
        ) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                guard self?.inputSessionID == sessionID else {
                    return
                }
                self?.handleSwipeInput(event)
            }
        }
        let shortcutSource: GlobalShortcutInputSource?
        if settings.keyboardShortcutsEnabled {
            shortcutSource = GlobalShortcutInputSource(
                shortcutInputSource: ShortcutInputSource(
                    previousShortcut: settings.shortcutPrevious,
                    nextShortcut: settings.shortcutNext
                ),
                suppressedModifierFlags: nil,
                commandHandler: { [weak self] command in
                    DispatchQueue.main.async { [weak self] in
                        guard self?.inputSessionID == sessionID else {
                            return
                        }
                        self?.handleKeyboardCommand(command)
                    }
                },
                releaseHandler: { [weak self] command in
                    DispatchQueue.main.async { [weak self] in
                        guard self?.inputSessionID == sessionID else {
                            return
                        }
                        self?.handleKeyboardShortcutRelease(command)
                    }
                }
            )
        } else {
            shortcutSource = nil
        }

        let didStartSwipe = Self.didStartInputSource(swipeSource.start())
        let didStartShortcut = shortcutSource.map { Self.didStartInputSource($0.start()) } ?? true
        guard didStartSwipe && didStartShortcut else {
            swipeSource.stop()
            shortcutSource?.stop()
            swipeInputSource = nil
            keyboardShortcutInputSource = nil
            isInputRunning = false
            inputStatus = strings.couldNotStartInput
            lastInputEvent = didStartSwipe ? strings.keyboardListenerFailed : strings.swipeListenerFailed
            return false
        }

        swipeInputSource = swipeSource
        keyboardShortcutInputSource = shortcutSource
        isInputRunning = true
        inputStatus = isEnabled
            ? strings.sidebyOnTargets(selectedDisplaySummary)
            : strings.gestureTestListeningTargets(selectedDisplaySummary)
        return true
    }

    func stopInputControl() {
        stopRunningInputSources()
        inputLatch.reset()
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
        isInputRunning = false
        inputStatus = strings.sidebyOff
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(SystemSettingsLink.root)
    }

    func openAccessibilitySettings() {
        permissionRequestFeedback = nil
        if !NSWorkspace.shared.open(SystemSettingsLink.accessibility) {
            openSystemSettings()
        }
    }

    func openAutomationSettings() {
        permissionRequestFeedback = nil
        if !NSWorkspace.shared.open(SystemSettingsLink.automation) {
            openSystemSettings()
        }
    }

    private func pollPermissionsForOnboarding(remainingAttempts: Int = 40) {
        permissionPollingID += 1
        let pollingID = permissionPollingID
        pollPermissionsForOnboarding(
            pollingID: pollingID,
            remainingAttempts: remainingAttempts
        )
    }

    private func pollPermissionsForOnboarding(
        pollingID: Int,
        remainingAttempts: Int
    ) {
        guard remainingAttempts > 0, pollingID == permissionPollingID else {
            return
        }

        refresh()
        if hasAccessibilityPermission && hasSwitchingAccess {
            startInputControl(requestsPermissions: false)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.pollPermissionsForOnboarding(
                pollingID: pollingID,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    private static func didStartInputSource(_ result: GlobalEventTapStartResult) -> Bool {
        switch result {
        case .started, .alreadyRunning:
            return true
        case .failedToCreateTap:
            return false
        }
    }

    private func stopRunningInputSources() {
        inputSessionID += 1
        swipeInputSource?.stop()
        keyboardShortcutInputSource?.stop()
        swipeInputSource = nil
        keyboardShortcutInputSource = nil
    }

    private func resumeEnabledInputIfNeeded() {
        guard isEnabled else {
            return
        }

        let didStart = startInputControl(requestsPermissions: false)
        if !didStart {
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
        }
    }

    private var currentGestureSettings: GestureSettings {
        GestureSettings(
            requiredModifiers: settings.requiredModifiers,
            horizontalThreshold: settings.horizontalThreshold,
            dominanceRatio: 1.4,
            ignoresMomentum: true,
            naturalScrollingEnabled: true
        )
    }

    private var keyboardShortcutModifiers: ModifierFlags {
        settings.shortcutPrevious.modifiers.union(settings.shortcutNext.modifiers)
    }

    private func performSwitch(
        _ command: SwitchCommand,
        label: String,
        inputMethod: InputMethod = .shortcut,
        resumeInputAfterCompletion shouldResumeInput: Bool? = nil,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        guard hasPostEventAccess(command: command, label: label) else {
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }
        guard !isSwitching else {
            lastSwitchResult = "Ignored \(label) \(command): switch already running"
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }

        isSwitching = true
        switchSessionID += 1
        let sessionID = switchSessionID
        let mode = settings.mode
        let state = runtimeState
        let targetDisplayIDs = selectedDisplayIDs

        DispatchQueue.global(qos: .userInitiated).async {
            let executor = HiddenCursorDisplaySpaceCommandExecutor(
                baseExecutor: MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster()),
                targetProvider: CGDisplaySwitchTargetProvider(includedStableIDs: targetDisplayIDs)
            )
            let engine = ContextSwitchEngine(executor: executor)
            let result = engine.switchContext(
                command,
                mode: mode,
                inputMethod: inputMethod,
                runtimeState: state
            )

            DispatchQueue.main.async { [weak self] in
                guard let self, self.switchSessionID == sessionID else {
                    return
                }

                self.applySwitchResult(
                    result,
                    command: command,
                    label: label
                )
                self.isSwitching = false
                if let shouldResumeInput {
                    self.finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
                }
                completion?(result.didExecute)
            }
        }
    }

    private func applySwitchResult(
        _ result: ContextSwitchResult,
        command: SwitchCommand,
        label: String
    ) {
        diagnostics = result.diagnostics
        if result.didExecute {
            lastSwitchResult = strings.postedSwitch(label: label, command: command)
        } else {
            diagnostics = result.diagnostics + [
                DiagnosticState(
                    severity: .warning,
                    title: strings.spaceCommandNotAcceptedTitle,
                    message: strings.spaceCommandNotAcceptedMessage,
                    actionLabel: nil
                )
            ]
            lastSwitchResult = strings.blockedSwitch(label: label, command: command, reason: strings.systemEventsFailedReason)
        }
    }

    private func hasSelectedMoveTargets(command: SwitchCommand, label: String) -> Bool {
        guard !selectedDisplayIDs.isEmpty else {
            lastSwitchResult = strings.blockedSwitch(label: label, command: command, reason: strings.noMoveTargetsReason)
            diagnostics = [
                DiagnosticState(
                    severity: .blocker,
                    title: strings.noMoveTargetsTitle,
                    message: strings.noMoveTargetsMessage,
                    actionLabel: nil
                )
            ]
            return false
        }

        return true
    }

    private func blockSwitchBecauseSidebyIsOff(command: SwitchCommand, label: String) {
        lastSwitchResult = strings.blockedSwitch(label: label, command: command, reason: strings.sidebyOffReason)
        diagnostics = [
            DiagnosticState(
                severity: .warning,
                title: strings.sidebyOffTitle,
                message: strings.sidebyOffMessage,
                actionLabel: nil
            )
        ]
    }

    private func hasPostEventAccess(command: SwitchCommand, label: String) -> Bool {
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            postEventAccessGranted = false
            diagnostics = [
                DiagnosticState(
                    severity: .blocker,
                    title: strings.postEventsOffTitle,
                    message: strings.postEventsOffMessage,
                    actionLabel: strings.accessibilitySettings
                )
            ]
            lastSwitchResult = strings.blockedSwitch(label: label, command: command, reason: strings.postEventsOffReason)
            return false
        }

        postEventAccessGranted = true
        return true
    }

    private func handleSwipeInput(_ event: InputEvent) {
        let event = eventWithCurrentModifierState(event)
        let timestamp = ProcessInfo.processInfo.systemUptime

        switch event.type {
        case .scrollWheel:
            guard inputLatch.allowsInput(at: timestamp) else {
                return
            }
            updateScrollStatusIfNeeded(event, at: timestamp)
        case .flagsChanged:
            if let latchedCommand = releasedPendingInputCommand(for: event) {
                switch latchedCommand.source {
                case .swipe:
                    executeSwipeCommand(latchedCommand.command)
                case .keyboard:
                    executeKeyboardCommand(latchedCommand.command)
                }
                return
            }
            resetSwipeRecognitionIfNeeded(for: event)
            guard inputLatch.allowsInput(at: timestamp) else {
                return
            }
            lastInputEvent = strings.modifiersStatus(modifierSummary(event.modifierFlags))
            return
        default:
            break
        }

        guard inputLatch.allowsInput(at: timestamp) else {
            return
        }
        guard let command = swipePipeline.command(for: event) else {
            return
        }

        if isOnboardingGestureTestActive {
            completeOnboardingGestureDetection(command: command)
            return
        }

        guard hasSelectedMoveTargets(command: command, label: "modifier-swipe") else {
            inputStatus = strings.noMoveTargetsStatus
            return
        }
        onboardingDetectedGestureCount += 1
        guard inputLatch.accept(command, source: .swipe, at: timestamp) else {
            return
        }
        lastInputEvent = strings.acceptedCommand(command: command, modifiers: strings.modifierText(settings.requiredModifiers))
        inputStatus = strings.releaseGestureModifier
    }

    private func eventWithCurrentModifierState(_ event: InputEvent) -> InputEvent {
        guard event.type == .scrollWheel else {
            return event
        }

        let currentModifiers = EventTapInputNormalizer.modifierFlags(
            from: CGEventSource.flagsState(.combinedSessionState)
        )
        let effectiveModifiers = InputModifierStateCombiner.effectiveModifiers(
            eventModifiers: event.modifierFlags,
            currentModifiers: currentModifiers
        )
        return event.replacingModifierFlags(effectiveModifiers)
    }

    private func completeOnboardingGestureDetection(command: SwitchCommand) {
        onboardingDetectedGestureCount = max(onboardingDetectedGestureCount, 1)
        isOnboardingGestureTestActive = false
        lastInputEvent = strings.acceptedCommand(command: command, modifiers: strings.modifierText(settings.requiredModifiers))
        inputStatus = strings.detected
        if !isEnabled {
            stopRunningInputSources()
            inputLatch.reset()
            swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
            isInputRunning = false
        }
    }

    private func executeSwipeCommand(_ command: SwitchCommand) {
        guard hasSelectedMoveTargets(command: command, label: "modifier-swipe") else {
            inputLatch.reset()
            inputStatus = strings.noMoveTargetsStatus
            return
        }

        let shouldResumeInput = isInputRunning
        stopRunningInputSources()
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
        lastInputEvent = strings.switchingFromSwipe(command: command, modifiers: strings.modifierText(settings.requiredModifiers))
        inputStatus = strings.switchingInputPaused(command: command)
        performSwitch(
            command,
            label: "modifier-swipe",
            inputMethod: .swipe,
            resumeInputAfterCompletion: shouldResumeInput
        )
    }

    private func handleKeyboardCommand(_ command: SwitchCommand) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        guard inputLatch.allowsInput(at: timestamp) else {
            return
        }
        guard hasSelectedMoveTargets(command: command, label: "keyboard-command") else {
            inputStatus = strings.noMoveTargetsStatus
            return
        }
        guard inputLatch.accept(command, source: .keyboard, at: timestamp) else {
            return
        }
        lastInputEvent = strings.acceptedCommand(command: command, modifiers: strings.modifierText(shortcutModifiers(for: command)))
        inputStatus = strings.releaseShortcutModifier
    }

    private func handleKeyboardShortcutRelease(_ command: SwitchCommand) {
        waitForKeyboardShortcutModifiersToRelease(
            command: command,
            modifiers: shortcutModifiers(for: command)
        )
    }

    private func waitForKeyboardShortcutModifiersToRelease(
        command: SwitchCommand,
        modifiers: ModifierFlags,
        remainingAttempts: Int = 40
    ) {
        guard remainingAttempts > 0 else {
            return
        }

        let currentModifiers = EventTapInputNormalizer.modifierFlags(
            from: CGEventSource.flagsState(.combinedSessionState)
        )
        guard currentModifiers.contains(modifiers) else {
            guard case let .pending(latchedCommand) = inputLatch.state,
                  latchedCommand.source == .keyboard,
                  latchedCommand.command == command,
                  inputLatch.releasePending(source: .keyboard) != nil
            else {
                return
            }

            executeKeyboardCommand(command)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.waitForKeyboardShortcutModifiersToRelease(
                command: command,
                modifiers: modifiers,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    private func executeKeyboardCommand(_ command: SwitchCommand) {
        guard hasSelectedMoveTargets(command: command, label: "keyboard-command") else {
            inputLatch.reset()
            inputStatus = strings.noMoveTargetsStatus
            return
        }

        let shouldResumeInput = isInputRunning
        stopRunningInputSources()
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
        lastInputEvent = strings.switchingFromShortcut(command: command, modifiers: keyboardShortcutModifierSummary)
        inputStatus = strings.switchingInputPaused(command: command)
        performSwitch(
            command,
            label: "keyboard-command",
            resumeInputAfterCompletion: shouldResumeInput
        )
    }

    private func releasedPendingInputCommand(for event: InputEvent) -> LatchedInputCommand? {
        guard case let .pending(latchedCommand) = inputLatch.state else {
            return nil
        }

        let releaseModifiers: ModifierFlags
        switch latchedCommand.source {
        case .swipe:
            releaseModifiers = settings.requiredModifiers
        case .keyboard:
            releaseModifiers = shortcutModifiers(for: latchedCommand.command)
        }

        guard InputModifierReleasePolicy.didReleaseAllTriggerModifiers(
            currentModifiers: event.modifierFlags,
            triggerModifiers: releaseModifiers
        ),
              let command = inputLatch.releasePending(source: latchedCommand.source)
        else {
            return nil
        }

        return LatchedInputCommand(command: command, source: latchedCommand.source)
    }

    private func resetSwipeRecognitionIfNeeded(for event: InputEvent) {
        guard !event.modifierFlags.contains(settings.requiredModifiers) else {
            return
        }

        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
    }

    private func updateScrollStatusIfNeeded(_ event: InputEvent, at timestamp: Double) {
        guard timestamp - lastScrollStatusUpdate >= 0.15 else {
            return
        }

        lastScrollStatusUpdate = timestamp
        lastInputEvent = strings.scrollStatus(dx: Int(event.deltaX), dy: Int(event.deltaY))
    }

    private func finishLatchedInputSwitch(shouldResumeInput: Bool) {
        inputLatch.finishSwitch(at: ProcessInfo.processInfo.systemUptime)

        guard shouldResumeInput else {
            inputLatch.reset()
            inputStatus = isEnabled ? strings.sidebyPaused : strings.sidebyOff
            return
        }

        inputStatus = strings.inputCooldown
        DispatchQueue.main.asyncAfter(deadline: .now() + inputLatch.cooldownInterval) { [weak self] in
            guard let self, self.isInputRunning else {
                return
            }

            self.startInputControl(requestsPermissions: false)
        }
    }

    private func syncSelectedDisplays(with layout: DisplayLayout) {
        let currentIDs = Set(layout.displays.map(\.id))
        if !didInitializeSelectedDisplays {
            selectedDisplayIDs = currentIDs
            didInitializeSelectedDisplays = true
        } else {
            selectedDisplayIDs = selectedDisplayIDs.intersection(currentIDs)
        }
    }

    private func syncDisplaySpacePlan(with layout: DisplayLayout) {
        var plan = settings.displaySpacePlan
        plan.reconcile(with: layout)
        guard plan != settings.displaySpacePlan else {
            spacesToCapture = plan.defaultCaptureCount
            return
        }

        settings.displaySpacePlan = plan
        spacesToCapture = plan.defaultCaptureCount
        settingsStore.save(settings)
    }

    private func updateDisplaySpacePlan(_ mutate: (inout DisplaySpacePlan) -> Void) {
        var plan = settings.displaySpacePlan
        mutate(&plan)
        plan.reconcile(with: displayLayout)

        guard plan != settings.displaySpacePlan else {
            spacesToCapture = plan.defaultCaptureCount
            return
        }

        settings.displaySpacePlan = plan
        spacesToCapture = plan.defaultCaptureCount
        settingsStore.save(settings)
        refreshLocalizedStatus()
    }

    private func selectedTargetProvider() -> CGDisplaySwitchTargetProvider {
        CGDisplaySwitchTargetProvider(includedStableIDs: selectedDisplayIDs)
    }

    private func hiddenExecutorForSelectedDisplays() -> HiddenCursorDisplaySpaceCommandExecutor {
        HiddenCursorDisplaySpaceCommandExecutor(
            targetProvider: selectedTargetProvider()
        )
    }

    private func shortcutModifiers(for command: SwitchCommand) -> ModifierFlags {
        switch command {
        case .previous:
            settings.shortcutPrevious.modifiers
        case .next:
            settings.shortcutNext.modifiers
        }
    }

    private func modifierSummary(_ modifiers: ModifierFlags) -> String {
        var names: [String] = []
        if modifiers.contains(.shift) { names.append(strings.modifierChoiceTitle(.shift)) }
        if modifiers.contains(.control) { names.append(strings.modifierChoiceTitle(.control)) }
        if modifiers.contains(.option) { names.append(strings.modifierChoiceTitle(.option)) }
        if modifiers.contains(.command) { names.append(strings.modifierChoiceTitle(.command)) }
        if modifiers.contains(.function) { names.append("fn") }
        return names.isEmpty ? strings.none : names.joined(separator: "+")
    }

    private static func keyboardShortcutSummary(for settings: AppSettings) -> String {
        "\(KeyboardShortcutFormatter.shortcutText(settings.shortcutPrevious)) / \(KeyboardShortcutFormatter.shortcutText(settings.shortcutNext))"
    }

    private static func inputHint(for settings: AppSettings, strings: SBSStrings) -> String {
        let gesture = strings.horizontalScrollGesture(settings.requiredModifiers)
        guard settings.keyboardShortcutsEnabled else {
            return strings.useGestureHint(gesture: gesture)
        }

        return strings.useInputHint(
            gesture: gesture,
            keyboard: keyboardShortcutSummary(for: settings)
        )
    }
}

private struct ProductRootView: View {
    @ObservedObject var model: SidebyAppModel
    @Binding var didCompleteOnboarding: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if didCompleteOnboarding {
            V1SettingsView(model: model, didCompleteOnboarding: $didCompleteOnboarding)
        } else {
            OnboardingFlowView(viewModel: model, language: model.settings.language) {
                finishOnboardingToSettings()
            }
            .onAppear {
                model.prepareMiniOnboarding()
            }
            .onChange(of: model.didFinishMiniOnboarding) { _, didFinish in
                if didFinish {
                    didCompleteOnboarding = true
                }
            }
        }
    }

    private func finishOnboardingToSettings() {
        let sourceWindow = NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first { window in
                window.identifier == ProductMainWindowPresenter.windowIdentifier
                    || window.title == "Sideby"
            }

        didCompleteOnboarding = true
        ProductFloatingMenuPanelController.shared.close()
        ProductFloatingSettingsPanelController.shared.show(
            from: sourceWindow,
            model: model,
            didCompleteOnboarding: $didCompleteOnboarding,
            initialSection: .overview
        )
        ProductMainWindowPresenter.hideIfVisible()
    }

    private func openSettingsPanel(initialSection: SettingsPanelSection = .overview) {
        ProductFloatingMenuPanelController.shared.close()
        ProductFloatingSettingsPanelController.shared.show(
            from: NSApplication.shared.keyWindow,
            model: model,
            didCompleteOnboarding: $didCompleteOnboarding,
            initialSection: initialSection
        )
        ProductMainWindowPresenter.hideIfVisible()
    }

    private var menuActions: ProductMenuPanelActions {
        ProductMenuPanelActions(
            openSettings: {
                openSettingsPanel()
            },
            replayOnboarding: {
                ProductFloatingMenuPanelController.shared.close()
                ProductFloatingSettingsPanelController.shared.close()
                model.prepareMiniOnboarding()
                didCompleteOnboarding = false
                openWindow(id: "main")
                ProductMainWindowPresenter.present()
            },
            customizeShortcuts: {
                openSettingsPanel(initialSection: .input)
            },
            quit: {
                NSApplication.shared.terminate(nil)
            }
        )
    }
}

private struct ProductMainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(windowFor: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(windowFor: nsView)
    }

    private func configure(windowFor view: NSView) {
        DispatchQueue.main.async {
            if let window = view.window {
                ProductMainWindowPresenter.configure(window)
            }
        }
    }
}

private struct V1SettingsView: View {
    @ObservedObject var model: SidebyAppModel
    @Binding var didCompleteOnboarding: Bool
    @State private var selectedSection: SettingsPanelSection?
    let settingsVariant: SettingsPanelVariant
    let onSwitchQueued: (SwitchCommand) -> Void

    init(
        model: SidebyAppModel,
        didCompleteOnboarding: Binding<Bool>,
        initialSection: SettingsPanelSection = .overview,
        settingsVariant: SettingsPanelVariant = .product,
        onSwitchQueued: @escaping (SwitchCommand) -> Void = { _ in }
    ) {
        self.model = model
        self._didCompleteOnboarding = didCompleteOnboarding
        self._selectedSection = State(initialValue: initialSection)
        self.settingsVariant = settingsVariant
        self.onSwitchQueued = onSwitchQueued
    }

    var body: some View {
        let strings = model.strings

        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(SettingsPanelPolicy.sections(for: settingsVariant)) { section in
                    Label(section.title(strings), systemImage: section.systemImage)
                        .tag(section as SettingsPanelSection?)
                }
            }
            .navigationTitle(strings.settings)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            let section = selectedSection ?? .overview
            SettingsDetailPage(
                title: section.title(strings),
                subtitle: section.subtitle(strings)
            ) {
                settingsDetail(for: section)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func settingsDetail(for section: SettingsPanelSection) -> some View {
        let strings = model.strings

        switch section {
        case .overview:
            VStack(alignment: .leading, spacing: 10) {
                SidebyActivationView(
                    model: model,
                    showsLastInputStatus: SettingsPanelPolicy.showsLastInputStatus(for: settingsVariant)
                )

                GroupBox(strings.screenSwitching) {
                    ScreenSwitchingControls(
                        model: model,
                        onSwitchQueued: onSwitchQueued
                    )
                }

                DiagnosticsView(model: model)
            }
        case .displays:
            VStack(alignment: .leading, spacing: 12) {
                MoveTargetsView(model: model)
                DisplaySpacesView(model: model)
            }
        case .input:
            ShortcutSettingsView(
                settings: Binding(
                    get: { model.settings },
                    set: { model.updateSettings($0) }
                ),
                showsInputExperiment: false
            )
        case .permissions:
            PrivacyPermissionsView(model: model)
        case .general:
            VStack(alignment: .leading, spacing: 12) {
                LanguageSettingsView(settings: Binding(
                    get: { model.settings },
                    set: { model.updateSettings($0) }
                ))

                Divider()

                LaunchAtLoginControls(model: model)

                Divider()

                HStack {
                    Button(strings.replayOnboarding) {
                        model.prepareMiniOnboarding()
                        didCompleteOnboarding = false
                    }
                    Button(strings.refresh) {
                        model.refresh()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .advanced:
            GroupBox(strings.labs) {
                InputExperimentSettingsView(
                    settings: Binding(
                        get: { model.settings },
                        set: { model.updateSettings($0) }
                    )
                )
            }
        }
    }
}

private extension SettingsPanelSection {
    var systemImage: String {
        switch self {
        case .overview:
            return "switch.2"
        case .displays:
            return "rectangle.connected.to.line.below"
        case .input:
            return "keyboard"
        case .permissions:
            return "lock"
        case .general:
            return "gearshape"
        case .advanced:
            return "testtube.2"
        }
    }

    func title(_ strings: SBSStrings) -> String {
        switch self {
        case .overview:
            return strings.overview
        case .displays:
            return strings.displays
        case .input:
            return strings.input
        case .permissions:
            return strings.permissions
        case .general:
            return strings.general
        case .advanced:
            return strings.advanced
        }
    }

    func subtitle(_ strings: SBSStrings) -> String {
        switch self {
        case .overview:
            return strings.overviewSubtitle
        case .displays:
            return strings.displaysSubtitle
        case .input:
            return strings.inputSubtitle
        case .permissions:
            return strings.permissionsSubtitle
        case .general:
            return strings.generalSubtitle
        case .advanced:
            return strings.advancedSubtitle
        }
    }

    init(_ destination: SettingsAccessDestination) {
        switch destination {
        case .overview:
            self = .overview
        case .input:
            self = .input
        }
    }
}

private struct SettingsDetailPage<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProductHeaderView(title: title, subtitle: subtitle)
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor
private final class ProductFloatingSettingsPanelController {
    static let shared = ProductFloatingSettingsPanelController()

    private var panel: NSPanel?
    private var lockedRelocation: ProductMenuBarWindowRelocation?
    private var activeSpaceObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private let panelSize = NSSize(width: 760, height: 560)

    private init() {
        startPlacementObservers()
    }

    func show(
        from sourceWindow: NSWindow?,
        model: SidebyAppModel,
        didCompleteOnboarding: Binding<Bool>,
        initialSection: SettingsPanelSection = .overview
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let relocation = ProductMenuBarWindowRelocation.capture(window: sourceWindow)
            ?? ProductMenuBarWindowRelocation.fallback()
        lockedRelocation = relocation
        panel.title = model.strings.settings
        panel.contentViewController = NSHostingController(
            rootView: V1SettingsView(
                model: model,
                didCompleteOnboarding: didCompleteOnboarding,
                initialSection: initialSection
            )
        )
        panel.setContentSize(panelSize)
        position(panel, using: relocation)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func startPlacementObservers() {
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleLockedReposition()
            }
        }

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleLockedReposition()
            }
        }
    }

    private func scheduleLockedReposition() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.repositionIfVisible(orderFront: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.repositionIfVisible(orderFront: false)
        }
    }

    private func repositionIfVisible(orderFront: Bool) {
        guard let panel,
              panel.isVisible,
              let relocation = lockedRelocation
        else {
            return
        }

        position(panel, using: relocation)
        if orderFront {
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior.insert([
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ])
        return panel
    }

    private func position(_ panel: NSPanel, using relocation: ProductMenuBarWindowRelocation) {
        let targetScreen = ProductMenuBarWindowConfigurator.targetScreen(for: relocation)
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let targetScreen else {
            return
        }

        let visibleFrame = targetScreen.visibleFrame
        let windowFrame = panel.frame
        let xRange = max(visibleFrame.width - windowFrame.width, 1)
        let yRange = max(visibleFrame.height - windowFrame.height, 1)
        let x = visibleFrame.minX + xRange * min(max(relocation.xRatio, 0), 1)
        let y = visibleFrame.maxY - windowFrame.height - relocation.topInset
        panel.setFrameOrigin(CGPoint(
            x: min(max(x, visibleFrame.minX), visibleFrame.minX + xRange),
            y: min(max(y, visibleFrame.minY), visibleFrame.minY + yRange)
        ))
    }
}

private struct LaunchAtLoginControls: View {
    @ObservedObject var model: SidebyAppModel

    var body: some View {
        let strings = model.strings

        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                strings.startAtLogin,
                isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            Text(model.loginItemStatus)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MenuBarControlView: View {
    @ObservedObject var model: SidebyAppModel
    @Binding var didCompleteOnboarding: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var menuWindow: NSWindow?
    @State private var didOpenFloatingMenu = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background {
                ProductMenuWindowReader { window in
                    menuWindow = window
                    ProductMenuBarWindowConfigurator.configure(window)
                }
            }
            .onAppear {
                didOpenFloatingMenu = false
                model.refresh()
                openFloatingMenuWhenReady()
            }
            .onDisappear {
                didOpenFloatingMenu = false
            }
    }

    private func openFloatingMenuWhenReady(retryCount: Int = 3) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard !didOpenFloatingMenu else {
                return
            }

            guard let sourceWindow = menuWindow ?? NSApplication.shared.keyWindow else {
                if retryCount > 0 {
                    openFloatingMenuWhenReady(retryCount: retryCount - 1)
                    return
                }

                openFloatingMenu(from: nil)
                return
            }

            openFloatingMenu(from: sourceWindow)
        }
    }

    private func openFloatingMenu(from sourceWindow: NSWindow?) {
        guard !didOpenFloatingMenu else {
            return
        }

        didOpenFloatingMenu = true
        ProductFloatingMenuPanelController.shared.toggle(
            from: sourceWindow,
            model: model,
            actions: menuActions
        )
        closeMenuBarWindow()
    }

    private func openMainWindow() {
        ProductFloatingSettingsPanelController.shared.close()
        openWindow(id: "main")
        closeMenuBarWindow()
        ProductMainWindowPresenter.present()
    }

    private func openSettingsPanel(initialSection: SettingsPanelSection = .overview) {
        ProductFloatingSettingsPanelController.shared.show(
            from: menuWindow,
            model: model,
            didCompleteOnboarding: $didCompleteOnboarding,
            initialSection: initialSection
        )
        ProductMainWindowPresenter.hideIfVisible()
        closeMenuBarWindow()
    }

    private func handleMenuRoute(_ route: SettingsAccessRoute) {
        switch route {
        case .mainSettings(let destination):
            openSettingsPanel(initialSection: SettingsPanelSection(destination))
        case .onboarding:
            model.prepareMiniOnboarding()
            didCompleteOnboarding = false
            openMainWindow()
        }
    }

    private func closeMenuBarWindow() {
        let menuWindow = menuWindow ?? NSApplication.shared.keyWindow
        dismiss()
        menuWindow?.orderOut(nil)
    }

    private var menuActions: ProductMenuPanelActions {
        ProductMenuPanelActions(
            openSettings: {
                handleMenuRoute(
                    SettingsAccessRoute.route(
                        for: .openSettings,
                        didCompleteOnboarding: didCompleteOnboarding
                    )
                )
            },
            replayOnboarding: {
                handleMenuRoute(
                    SettingsAccessRoute.route(
                        for: .replayOnboarding,
                        didCompleteOnboarding: didCompleteOnboarding
                    )
                )
            },
            customizeShortcuts: {
                handleMenuRoute(
                    SettingsAccessRoute.route(
                        for: .customizeShortcuts,
                        didCompleteOnboarding: didCompleteOnboarding
                    )
                )
            },
            quit: {
                NSApplication.shared.terminate(nil)
            }
        )
    }
}

private struct ProductMenuPanelActions {
    let openSettings: () -> Void
    let replayOnboarding: () -> Void
    let customizeShortcuts: () -> Void
    let quit: () -> Void
}

private struct ProductMenuContentView: View {
    @ObservedObject var model: SidebyAppModel
    let onSwitchQueued: (SwitchCommand) -> Void
    let actions: ProductMenuPanelActions

    var body: some View {
        let strings = model.strings

        VStack(alignment: .leading, spacing: 10) {
            MenuBarStatusHeader(model: model)

            MoveTargetsView(model: model, showsSummary: false)
            GroupBox(strings.switchSection) {
                ScreenSwitchingControls(
                    model: model,
                    showsTargetSummary: false,
                    showsHint: false,
                    onSwitchQueued: onSwitchQueued
                )
            }

            Button(strings.openSettings, action: actions.openSettings)
            Button(strings.replayOnboarding, action: actions.replayOnboarding)
            Button(strings.customizeShortcuts, action: actions.customizeShortcuts)
            Button(strings.quit, action: actions.quit)
        }
    }
}

private struct ProductMenuWindowReader: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onWindowChange(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onWindowChange(nsView.window)
        }
    }
}

@MainActor
private enum ProductMenuBarWindowConfigurator {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("sideby-menu-window")

    static func configure(_ window: NSWindow?) {
        guard let window else {
            return
        }

        window.identifier = windowIdentifier
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    static func relocate(_ window: NSWindow?, using relocation: ProductMenuBarWindowRelocation) {
        guard let window else {
            return
        }

        configure(window)
        let targetScreen = targetScreen(for: relocation)
            ?? window.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let targetScreen else {
            return
        }

        let visibleFrame = targetScreen.visibleFrame
        let windowFrame = window.frame
        let xRange = max(visibleFrame.width - windowFrame.width, 1)
        let yRange = max(visibleFrame.height - windowFrame.height, 1)
        let x = visibleFrame.minX + xRange * min(max(relocation.xRatio, 0), 1)
        let y = visibleFrame.maxY - windowFrame.height - relocation.topInset
        let origin = CGPoint(
            x: min(max(x, visibleFrame.minX), visibleFrame.minX + xRange),
            y: min(max(y, visibleFrame.minY), visibleFrame.minY + yRange)
        )

        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
    }

    static func targetScreen(for relocation: ProductMenuBarWindowRelocation) -> NSScreen? {
        relocation.sourceScreen ?? NSScreen.main
    }
}

@MainActor
private final class ProductFloatingMenuPanelController {
    static let shared = ProductFloatingMenuPanelController()

    private var panel: NSPanel?
    private var switchObserver: AnyCancellable?
    private var showWorkItem: DispatchWorkItem?
    private var pendingRelocation: ProductMenuBarWindowRelocation?
    private weak var pendingModel: SidebyAppModel?
    private var pendingActions: ProductMenuPanelActions?
    private var didObserveSwitching = false
    private let panelSize = NSSize(width: 360, height: 620)

    private init() {}

    func toggle(
        from sourceWindow: NSWindow?,
        model: SidebyAppModel,
        actions: ProductMenuPanelActions
    ) {
        if panel?.isVisible == true {
            close()
            return
        }

        present(from: sourceWindow, model: model, actions: actions)
    }

    func present(
        from sourceWindow: NSWindow?,
        model: SidebyAppModel,
        actions: ProductMenuPanelActions
    ) {
        let relocation = ProductMenuBarWindowRelocation.capture(window: sourceWindow)
            ?? ProductMenuBarWindowRelocation.fallback()
        clearPendingReopen()
        switchObserver = model.$isSwitching.sink { [weak self, weak model] isSwitching in
            guard isSwitching else {
                return
            }

            Task { @MainActor [weak self, weak model] in
                guard let self, let model else {
                    return
                }

                self.queueReopenAfterSwitch(
                    from: self.panel,
                    model: model,
                    actions: actions,
                    alreadySwitching: true
                )
            }
        }

        show(model: model, relocation: relocation, actions: actions)
    }

    func close() {
        clearPendingReopen()
        switchObserver = nil
        hidePanel()
    }

    private func queueReopenAfterSwitch(
        from sourceWindow: NSWindow?,
        model: SidebyAppModel,
        actions: ProductMenuPanelActions,
        alreadySwitching: Bool = false
    ) {
        pendingRelocation = ProductMenuBarWindowRelocation.capture(window: sourceWindow)
            ?? ProductMenuBarWindowRelocation.fallback()
        pendingModel = model
        pendingActions = actions
        didObserveSwitching = alreadySwitching
        showWorkItem?.cancel()

        switchObserver = model.$isSwitching.sink { [weak self] isSwitching in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                if isSwitching {
                    self.didObserveSwitching = true
                    self.hidePanel()
                    return
                }

                guard self.didObserveSwitching else {
                    return
                }

                self.scheduleShowPending(after: 0.22)
            }
        }

        scheduleShowPending(after: 1.15)
        hidePanel()
    }

    private func scheduleShowPending(after delay: TimeInterval) {
        guard pendingRelocation != nil else {
            return
        }

        showWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.showPending()
            }
        }
        showWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func showPending() {
        guard let relocation = pendingRelocation,
              let model = pendingModel,
              let actions = pendingActions
        else {
            clearPendingReopen()
            switchObserver = nil
            return
        }

        guard !model.isSwitching else {
            scheduleShowPending(after: 0.25)
            return
        }

        clearPendingReopen()
        switchObserver = nil
        show(model: model, relocation: relocation, actions: actions)
    }

    private func clearPendingReopen() {
        showWorkItem?.cancel()
        showWorkItem = nil
        pendingRelocation = nil
        pendingModel = nil
        pendingActions = nil
        didObserveSwitching = false
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func show(
        model: SidebyAppModel,
        relocation: ProductMenuBarWindowRelocation,
        actions: ProductMenuPanelActions
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = NSHostingController(
            rootView: ProductFloatingMenuPanelView(
                model: model,
                onSwitchQueued: { [weak self, weak model, weak panel] _ in
                    guard let self, let model else {
                        return
                    }

                    queueReopenAfterSwitch(
                        from: panel,
                        model: model,
                        actions: actions
                    )
                },
                actions: ProductMenuPanelActions(
                    openSettings: { [weak self] in
                        self?.close()
                        actions.openSettings()
                    },
                    replayOnboarding: { [weak self] in
                        self?.close()
                        actions.replayOnboarding()
                    },
                    customizeShortcuts: { [weak self] in
                        self?.close()
                        actions.customizeShortcuts()
                    },
                    quit: actions.quit
                )
            )
        )
        panel.setContentSize(panelSize)
        position(panel, using: relocation)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = DismissibleFloatingPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.onDismissShortcut = { [weak self] in
            self?.close()
        }
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.identifier = ProductMenuBarWindowConfigurator.windowIdentifier
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.collectionBehavior.insert([
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ])
        return panel
    }

    private func position(_ panel: NSPanel, using relocation: ProductMenuBarWindowRelocation) {
        let targetScreen = ProductMenuBarWindowConfigurator.targetScreen(for: relocation)
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let targetScreen else {
            return
        }

        let visibleFrame = targetScreen.visibleFrame
        let windowFrame = panel.frame
        let xRange = max(visibleFrame.width - windowFrame.width, 1)
        let yRange = max(visibleFrame.height - windowFrame.height, 1)
        let x = visibleFrame.minX + xRange * min(max(relocation.xRatio, 0), 1)
        let y = visibleFrame.maxY - windowFrame.height - relocation.topInset
        panel.setFrameOrigin(CGPoint(
            x: min(max(x, visibleFrame.minX), visibleFrame.minX + xRange),
            y: min(max(y, visibleFrame.minY), visibleFrame.minY + yRange)
        ))
    }
}

private struct ProductFloatingMenuPanelView: View {
    @ObservedObject var model: SidebyAppModel
    let onSwitchQueued: (SwitchCommand) -> Void
    let actions: ProductMenuPanelActions

    var body: some View {
        ProductMenuContentView(
            model: model,
            onSwitchQueued: onSwitchQueued,
            actions: actions
        )
        .padding()
        .frame(width: 360, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ProductMenuBarWindowRelocation {
    let sourceScreen: NSScreen?
    let xRatio: CGFloat
    let topInset: CGFloat

    @MainActor
    static func capture(window: NSWindow?) -> ProductMenuBarWindowRelocation? {
        guard let window else {
            return nil
        }

        let sourceScreen = window.screen ?? screen(containing: window.frame)
        guard let visibleFrame = sourceScreen?.visibleFrame else {
            return nil
        }

        let xRange = max(visibleFrame.width - window.frame.width, 1)
        let xRatio = (window.frame.minX - visibleFrame.minX) / xRange
        let topInset = max(visibleFrame.maxY - window.frame.maxY, 0)
        return ProductMenuBarWindowRelocation(
            sourceScreen: sourceScreen,
            xRatio: min(max(xRatio, 0), 1),
            topInset: topInset
        )
    }

    @MainActor
    static func fallback() -> ProductMenuBarWindowRelocation {
        ProductMenuBarWindowRelocation(
            sourceScreen: NSScreen.main ?? NSScreen.screens.first,
            xRatio: 1,
            topInset: 8
        )
    }

    @MainActor
    private static func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens
            .map { screen in
                (screen: screen, area: screen.visibleFrame.intersection(frame).area)
            }
            .filter { $0.area > 0 }
            .max { $0.area < $1.area }?
            .screen
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else {
            return 0
        }

        return max(width, 0) * max(height, 0)
    }
}

private struct MenuBarStatusHeader: View {
    @ObservedObject var model: SidebyAppModel

    var body: some View {
        let strings = model.strings

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(strings.sideby)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Toggle(
                    model.isEnabled ? strings.on : strings.off,
                    isOn: Binding(
                        get: { model.isEnabled },
                        set: { model.setSidebyEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var statusText: String {
        if model.isEnabled {
            return "\(SBSStrings(language: model.settings.language).listening) \(model.selectedDisplaySummary)"
        }

        return "\(SBSStrings(language: model.settings.language).off) · \(model.inputStatus)"
    }
}

private struct ProductHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DisplaySpacesView: View {
    @ObservedObject var model: SidebyAppModel

    var body: some View {
        let strings = model.strings

        GroupBox(strings.displaySpaces) {
            VStack(alignment: .leading, spacing: 12) {
                Text(strings.displaySpacesHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center, spacing: 8) {
                    Stepper(
                        value: Binding(
                            get: { model.spacesToCapture },
                            set: { model.setSpacesToCapture($0) }
                        ),
                        in: 1...12
                    ) {
                        Text(strings.spacesToCapture(model.spacesToCapture))
                    }

                    Spacer(minLength: 8)

                    Button {
                        model.scanVisibleAppsForCurrentSpace()
                    } label: {
                        Label(strings.scanCurrentSpace, systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.displayLayout.displays.isEmpty || model.spaceCaptureSession != nil)

                    if model.spaceCaptureSession == nil {
                        Button {
                            model.startSpaceCapture()
                        } label: {
                            Label(strings.captureSpaces, systemImage: "rectangle.stack")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.displayLayout.displays.isEmpty || model.isSwitching || !model.isEnabled)
                    } else {
                        Button(strings.stopCapture) {
                            model.stopSpaceCapture()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let spaceCaptureStatus = model.spaceCaptureStatus {
                    Text(spaceCaptureStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.displayLayout.displays.isEmpty {
                    Text(strings.selectedDisplaySummary(selected: 0, total: 0))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        displaySpaceGrid(strings: strings)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            model.scanVisibleAppsForCurrentSpace()
        }
    }

    private var gridRows: [DisplaySpaceGridRow] {
        DisplaySpaceGridModel.rows(
            displays: model.displayLayout.displays,
            plan: model.settings.displaySpacePlan,
            captureCount: model.spacesToCapture,
            suggestionsByDisplayID: model.visibleSpaceSuggestionsByDisplayID
        )
    }

    private func displaySpaceGrid(strings: SBSStrings) -> some View {
        let rows = gridRows
        let spaceOrders = rows.first?.cells.map(\.spaceOrder) ?? []

        return Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text(strings.displays)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 168, alignment: .leading)

                ForEach(spaceOrders, id: \.self) { spaceOrder in
                    Text(strings.spaceName(spaceOrder))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 240, alignment: .leading)
                }
            }

            ForEach(rows) { row in
                GridRow {
                    displayTitle(row, strings: strings)
                    ForEach(row.cells) { cell in
                        displaySpaceCell(
                            cell,
                            strings: strings
                        )
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func displayTitle(
        _ row: DisplaySpaceGridRow,
        strings: SBSStrings
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(row.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if row.isPrimary {
                    Text(strings.primaryDisplayTag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if row.isBuiltin {
                    Text(strings.builtInDisplayTag)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 168, alignment: .leading)
    }

    private func displaySpaceCell(
        _ cell: DisplaySpaceGridCell,
        strings: SBSStrings
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField(
                strings.spaceLabelPlaceholder,
                text: Binding(
                    get: {
                        model.displaySpaceLabel(
                            displayID: cell.displayID,
                            spaceOrder: cell.spaceOrder
                        )
                    },
                    set: { label in
                        model.setDisplaySpaceLabel(
                            displayID: cell.displayID,
                            spaceOrder: cell.spaceOrder,
                            label: label
                        )
                    }
                )
            )
            .textFieldStyle(.roundedBorder)

            if let suggestion = cell.suggestion {
                Text(VisibleAppSuggestionDisplay.detectedText(for: suggestion, strings: strings))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Button(strings.useApp) {
                        model.useVisibleSpaceSuggestionAppName(
                            displayID: cell.displayID,
                            spaceOrder: cell.spaceOrder
                        )
                    }

                    if suggestion.titleLabel != nil {
                        Button(strings.useTitle) {
                            model.useVisibleSpaceSuggestionWindowTitle(
                                displayID: cell.displayID,
                                spaceOrder: cell.spaceOrder
                            )
                        }
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
        }
        .frame(width: 240, alignment: .leading)
    }
}

private struct MoveTargetsView: View {
    @ObservedObject var model: SidebyAppModel
    var showsSummary = true

    var body: some View {
        let strings = model.strings

        GroupBox(strings.moveTargets) {
            VStack(alignment: .leading, spacing: 10) {
                if model.displayLayout.displays.isEmpty {
                    Text(strings.selectedDisplaySummary(selected: 0, total: 0))
                        .foregroundStyle(.secondary)
                } else {
                    DisplayArrangementView(
                        displays: model.displayLayout.displays,
                        selectedDisplayIDs: model.selectedDisplayIDs,
                        strings: strings,
                        toggleDisplay: { display in
                            model.setDisplayTarget(
                                display,
                                isSelected: !model.selectedDisplayIDs.contains(display.id)
                            )
                        }
                    )
                    .padding(.bottom, 2)
                }

                HStack {
                    Button(strings.allDisplaysButton) {
                        model.selectAllDisplayTargets()
                    }

                    if showsSummary {
                        Text(model.selectedDisplaySummary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DisplayArrangementView: View {
    let displays: [DisplayInfo]
    let selectedDisplayIDs: Set<String>
    let strings: SBSStrings
    let toggleDisplay: (DisplayInfo) -> Void

    private var hasFrames: Bool {
        displays.allSatisfy { $0.frame != nil }
    }

    var body: some View {
        VStack(spacing: 12) {
            if hasFrames {
                GeometryReader { proxy in
                    arrangedDisplays(in: proxy.size)
                }
                .frame(height: 238)
            } else {
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(displays, id: \.id) { display in
                        displayButton(for: display, size: fallbackSize(for: display))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func arrangedDisplays(in size: CGSize) -> some View {
        let frames = displays.compactMap(\.frame)
        let minX = frames.map(\.x).min() ?? 0
        let minY = frames.map(\.y).min() ?? 0
        let maxX = frames.map { $0.x + $0.width }.max() ?? 1
        let maxY = frames.map { $0.y + $0.height }.max() ?? 1
        let unionWidth = max(maxX - minX, 1)
        let unionHeight = max(maxY - minY, 1)
        let padding: CGFloat = 26
        let availableWidth = max(size.width - padding * 2, 1)
        let availableHeight = max(size.height - padding * 2, 1)
        let scale = min(
            availableWidth / CGFloat(unionWidth),
            availableHeight / CGFloat(unionHeight)
        )
        let contentWidth = CGFloat(unionWidth) * scale
        let contentHeight = CGFloat(unionHeight) * scale
        let offsetX = (size.width - contentWidth) / 2
        let offsetY = (size.height - contentHeight) / 2

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            ForEach(displays, id: \.id) { display in
                if let frame = display.frame {
                    let displayWidth = max(CGFloat(frame.width) * scale, 72)
                    let displayHeight = max(CGFloat(frame.height) * scale, 46)
                    let x = offsetX + CGFloat(frame.x - minX) * scale
                    let y = offsetY + CGFloat(frame.y - minY) * scale

                    displayButton(
                        for: display,
                        size: CGSize(width: displayWidth, height: displayHeight)
                    )
                    .position(
                        x: x + displayWidth / 2,
                        y: y + displayHeight / 2
                    )
                }
            }
        }
    }

    private func displayButton(for display: DisplayInfo, size: CGSize) -> some View {
        let isSelected = selectedDisplayIDs.contains(display.id)

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                toggleDisplay(display)
            }
        } label: {
            DisplayThumbnail(
                display: display,
                isSelected: isSelected,
                size: size,
                strings: strings
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(display.name)
        .accessibilityValue(isSelected ? strings.selected : strings.notSelected)
        .help(display.name)
    }

    private func fallbackSize(for display: DisplayInfo) -> CGSize {
        let aspect = display.frame?.aspectRatio ?? (display.isBuiltin ? 16.0 / 10.0 : 16.0 / 9.0)
        let width = min(max(aspect * 76, 110), 150)
        return CGSize(width: width, height: width / aspect)
    }
}

private struct DisplayThumbnail: View {
    let display: DisplayInfo
    let isSelected: Bool
    let size: CGSize
    let strings: SBSStrings

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .black).opacity(0.88))

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(screenGradient)
                .overlay(alignment: .bottom) {
                    landscape
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .overlay(alignment: .bottomLeading) {
                    namePlate
                        .padding(display.isBuiltin ? 8 : 9)
                }
                .padding(display.isBuiltin ? 5 : 6)

            if display.isBuiltin {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .frame(width: min(size.width * 0.12, 18), height: 4)
                    .padding(.top, 3)
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(isSelected ? 1 : 0.68)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2.5 : 1)
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                .padding(-5)
        }
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.24) : .black.opacity(0.18),
            radius: isSelected ? 7 : 4,
            x: 0,
            y: isSelected ? 3 : 2
        )
        .overlay(alignment: .bottom) {
            if !display.isBuiltin {
                Capsule()
                    .fill(Color(nsColor: .tertiaryLabelColor))
                    .frame(width: max(size.width * 0.28, 34), height: 4)
                    .offset(y: 8)
            }
        }
    }

    private var namePlate: some View {
        HStack(spacing: 5) {
            Text(display.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            if display.isPrimary {
                Text(strings.mainDisplay)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(isSelected ? 1 : 0.72))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: max(size.width - 22, 54), alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(isSelected ? 0.50 : 0.60),
                    Color.black.opacity(isSelected ? 0.30 : 0.46)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var screenGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: .systemBlue).opacity(0.82),
                Color(nsColor: .systemTeal).opacity(0.82)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var landscape: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(nsColor: .systemGreen).opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Path { path in
                path.move(to: CGPoint(x: 0, y: size.height * 0.70))
                path.addCurve(
                    to: CGPoint(x: size.width, y: size.height * 0.64),
                    control1: CGPoint(x: size.width * 0.24, y: size.height * 0.52),
                    control2: CGPoint(x: size.width * 0.62, y: size.height * 0.82)
                )
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.closeSubpath()
            }
            .fill(Color.black.opacity(0.18))
        }
    }
}

private struct PrivacyPermissionsView: View {
    @ObservedObject var model: SidebyAppModel

    var body: some View {
        let strings = model.strings

        GroupBox(strings.privacyPermissions) {
            VStack(alignment: .leading, spacing: 10) {
                StatusRow(label: strings.accessibility, value: strings.permissionState(model.permissionState))
                StatusRow(label: strings.switchingAccess, value: model.hasSwitchingAccess ? strings.granted : strings.notGranted)
                Text(strings.inputPrivacyNote)
                    .foregroundStyle(.secondary)

                if let feedback = model.permissionRequestFeedback {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text(strings.permissionRequestFeedback(feedback))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let action = feedback.action {
                        Button(strings.permissionRequestActionTitle(action)) {
                            switch action {
                            case .openAccessibilitySettings:
                                model.openAccessibilitySettings()
                            case .openAutomationSettings:
                                model.openAutomationSettings()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(strings.enablePermissions) {
                            model.requestPermissions()
                        }
                        Button(strings.accessibilitySettings) {
                            model.openAccessibilitySettings()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScreenSwitchingControls: View {
    @ObservedObject var model: SidebyAppModel
    var showsTargetSummary = true
    var showsHint = true
    var onSwitchQueued: (SwitchCommand) -> Void = { _ in }

    var body: some View {
        let strings = model.strings

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("<- \(strings.previous)") {
                    if model.switchContext(.previous) {
                        onSwitchQueued(.previous)
                    }
                }
                .disabled(!model.isEnabled || model.isSwitching)

                Button("\(strings.next) ->") {
                    if model.switchContext(.next) {
                        onSwitchQueued(.next)
                    }
                }
                .disabled(!model.isEnabled || model.isSwitching)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                if showsTargetSummary {
                    GridRow {
                        Text(strings.targets)
                        Text(model.selectedDisplaySummary)
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text(strings.lastSwitch)
                    Text(model.lastSwitchResult)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if showsHint {
                Text(model.isEnabled ? strings.testButtonsUseActivePath : strings.turnOnForTestButtons)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SidebyActivationView: View {
    @ObservedObject var model: SidebyAppModel
    var showsLastInputStatus = false

    var body: some View {
        let strings = model.strings

        GroupBox(strings.sideby) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    strings.sideby,
                    isOn: Binding(
                        get: { model.isEnabled },
                        set: { model.setSidebyEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Text(model.inputStatus)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    StatusRow(label: strings.swipe, value: model.gestureInputSummary)
                    StatusRow(label: strings.command, value: model.keyboardCommandSummary)
                    if showsLastInputStatus {
                        StatusRow(label: strings.lastInput, value: model.lastInputEvent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DiagnosticsView: View {
    @ObservedObject var model: SidebyAppModel

    var body: some View {
        let strings = model.strings

        GroupBox(strings.status) {
            VStack(alignment: .leading, spacing: 8) {
                StatusRow(label: strings.displays, value: "\(model.displayLayout.displayCount)")
                StatusRow(label: strings.accessibility, value: strings.permissionState(model.permissionState))
                StatusRow(label: strings.switchingAccess, value: model.hasSwitchingAccess ? strings.granted : strings.notGranted)

                if model.diagnostics.isEmpty {
                    Text(strings.noDiagnostics)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(strings.localizedDiagnosticTitle(diagnostic.title))
                                .foregroundStyle(diagnostic.severity == .blocker ? .red : .primary)
                            Text(strings.localizedDiagnosticMessage(diagnostic.message))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}
