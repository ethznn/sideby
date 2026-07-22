import AppKit
import Combine
import CoreGraphics
import OSLog
import SidebyCore
import SidebySystem
import SidebyUI
import SwiftUI
import UniformTypeIdentifiers

@main
struct SidebyApp: App {
    @StateObject private var model = SidebyAppModel()
    @StateObject private var updater: SidebyUpdater
    @AppStorage("sideby.v1.onboarding-complete") private var didCompleteOnboarding = false

    init() {
        MenuBarOnlyApplicationPresentation.apply()

        if SingleInstanceGuard.activateExistingApplicationAndReturnShouldTerminate() {
            Thread.sleep(forTimeInterval: 0.1)
            exit(0)
        }

        _updater = StateObject(wrappedValue: SidebyUpdater())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarControlView(
                model: model,
                updater: updater,
                didCompleteOnboarding: $didCompleteOnboarding
            )
        } label: {
            ProductMenuBarLabelView(didCompleteOnboarding: $didCompleteOnboarding)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Sideby", id: "main") {
            ProductRootView(
                model: model,
                updater: updater,
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

private final class SidebyAppObserverTokens {
    var settingsObserver: NSObjectProtocol?
    var externalSpaceObserver: NSObjectProtocol?

    deinit {
        if let settingsObserver {
            DistributedNotificationCenter.default().removeObserver(settingsObserver)
        }
        if let externalSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(externalSpaceObserver)
        }
    }
}

struct ContextKeyboardCommandCoordinator {
    private(set) var gate: ContextKeyboardExecutionGate

    init(settlingDuration: Double = 0.75) {
        gate = ContextKeyboardExecutionGate(settlingDuration: settlingDuration)
    }

    mutating func handle(
        _ event: ContextKeyboardShortcutInputEvent,
        contextPlan: ContextPlan,
        isSidebyEnabled: Bool,
        isSwitching: Bool,
        isCapturing: Bool,
        at timestamp: Double
    ) -> ContextKeyboardAction {
        switch event {
        case .pressed(let command):
            guard !isBusy(at: timestamp) else {
                return .ignore
            }

            let action = ContextKeyboardShortcutPolicy.action(
                command: command,
                contextPlan: contextPlan,
                isSidebyEnabled: isSidebyEnabled,
                isSwitching: isSwitching,
                isCapturing: isCapturing
            )
            switch action {
            case .activate, .move:
                _ = gate.reserve(command, at: timestamp)
                return .ignore
            case .ignore, .showSidebyOff, .showMissingContext, .waitForModifierRelease:
                return action
            }

        case .released(let command):
            guard gate.state == .pending(command) else {
                return .ignore
            }

            return .waitForModifierRelease(command)
        }
    }

    mutating func resumeAfterModifierRelease(
        _ command: ContextKeyboardCommand,
        contextPlan: ContextPlan,
        isSidebyEnabled: Bool,
        isSwitching: Bool,
        isCapturing: Bool
    ) -> ContextKeyboardAction {
        guard gate.beginExecution(for: command) else {
            return .ignore
        }

        let action = ContextKeyboardShortcutPolicy.action(
            command: command,
            contextPlan: contextPlan,
            isSidebyEnabled: isSidebyEnabled,
            isSwitching: isSwitching,
            isCapturing: isCapturing
        )
        switch action {
        case .activate, .move:
            return action
        case .ignore, .showSidebyOff, .showMissingContext, .waitForModifierRelease:
            gate.reset()
            return .ignore
        }
    }

    mutating func finishExecution(at timestamp: Double) {
        gate.finishExecution(at: timestamp)
    }

    private mutating func isBusy(at timestamp: Double) -> Bool {
        if case let .settling(until) = gate.state, timestamp >= until {
            gate.reset()
        }

        return gate.state != .idle
    }
}

enum ContextKeyboardResolvedExecution: Equatable {
    case activate(contextID: String)
    case move(SwitchCommand)
}

enum ContextKeyboardExecutionResolver {
    static func execution(
        for action: ContextKeyboardAction,
        contextPlan: ContextPlan
    ) -> ContextKeyboardResolvedExecution? {
        switch action {
        case .activate(let contextID):
            return .activate(contextID: contextID)
        case .move(let command):
            let intent = contextPlan.switchIntent(for: command)
            if intent.shouldExecute, let targetContext = intent.targetContext {
                return .activate(contextID: targetContext.id)
            }
            return .move(command)
        case .ignore, .showSidebyOff, .showMissingContext, .waitForModifierRelease:
            return nil
        }
    }
}

enum SpaceCommandExecutionStrategy: Sendable {
    case ordinary
    case fixedContextKeyboard

    func baseExecutor() -> any SpaceCommandExecuting {
        switch self {
        case .ordinary:
            MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster())
        case .fixedContextKeyboard:
            FixedContextKeyboardSpaceCommandExecutor()
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
private final class ProductContextHUDController {
    static let shared = ProductContextHUDController()

    private var panels: [NSPanel] = []
    private var hideWorkItem: DispatchWorkItem?
    private var presentationGeneration = HUDPresentationGeneration()

    private init() {}

    func show(_ state: HUDPresentationState, screen: NSScreen? = NSScreen.main) {
        show(state, screens: [screen ?? NSScreen.main ?? NSScreen.screens.first].compactMap(\.self))
    }

    func show(_ state: HUDPresentationState, displayIDs: Set<String>, displayLayout: DisplayLayout) {
        let screens = screens(for: displayIDs, displayLayout: displayLayout)
        show(screenStates: screens.map { ($0, state) }, timing: state)
    }

    func show(
        statesByDisplayID: [String: HUDPresentationState],
        displayLayout: DisplayLayout,
        timing: HUDPresentationState
    ) {
        let screenStates = displayLayout.displays.compactMap { display -> (NSScreen, HUDPresentationState)? in
            guard let state = statesByDisplayID[display.id],
                  let screen = screen(forDisplayID: display.id)
            else {
                return nil
            }
            return (screen, state)
        }
        show(screenStates: screenStates, timing: timing)
    }

    private func show(_ state: HUDPresentationState, screens requestedScreens: [NSScreen]) {
        show(screenStates: requestedScreens.map { ($0, state) }, timing: state)
    }

    private func show(
        screenStates requestedScreenStates: [(NSScreen, HUDPresentationState)],
        timing: HUDPresentationState
    ) {
        let generation = presentationGeneration.advance()
        hideWorkItem?.cancel()

        let screenStates = requestedScreenStates.isEmpty
            ? [NSScreen.main ?? NSScreen.screens.first].compactMap(\.self).map { ($0, timing) }
            : requestedScreenStates
        guard !screenStates.isEmpty else {
            return
        }

        while panels.count < screenStates.count {
            panels.append(makePanel())
        }

        var activePanels: [NSPanel] = []
        for (index, panel) in panels.enumerated() {
            guard index < screenStates.count else {
                panel.orderOut(nil)
                continue
            }

            let (screen, state) = screenStates[index]
            panel.alphaValue = 1
            let hostingController = NSHostingController(rootView: HUDView(state: state))
            panel.contentViewController = hostingController
            applyContentSize(to: panel, hostingView: hostingController.view, state: state)
            position(panel, on: screen)
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
            position(panel, on: screen)
            recenterAfterLayout(panel, on: screen)
            activePanels.append(panel)
        }

        scheduleFadeOut(activePanels, state: timing, generation: generation)
    }

    private func screen(forDisplayID displayID: String) -> NSScreen? {
        NSScreen.screens.first { Self.stableDisplayID(for: $0) == displayID }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 180, height: 52)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior.insert([
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient
        ])
        return panel
    }

    private func applyContentSize(
        to panel: NSPanel,
        hostingView: NSView,
        state: HUDPresentationState
    ) {
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let contentSize = HUDPanelLayout.contentSize(
            fittingSize: fittingSize,
            text: state.text,
            visualScale: state.visualScale
        )
        panel.setContentSize(contentSize)
    }

    private func position(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen else {
            return
        }

        let frame = panel.frame
        panel.setFrame(
            NSRect(
                origin: HUDPanelLayout.centeredOrigin(panelSize: frame.size, screenFrame: screen.frame),
                size: frame.size
            ),
            display: true
        )
    }

    private func recenterAfterLayout(_ panel: NSPanel, on screen: NSScreen) {
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible else {
                return
            }

            self.position(panel, on: screen)
        }
    }

    private func screens(for displayIDs: Set<String>, displayLayout: DisplayLayout) -> [NSScreen] {
        let requestedDisplayIDs = displayIDs.isEmpty
            ? Set(displayLayout.displays.map(\.id))
            : displayIDs
        let screensByDisplayID = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (String, NSScreen)? in
                guard let displayID = Self.stableDisplayID(for: screen) else {
                    return nil
                }
                return (displayID, screen)
            }
        )
        let screens = displayLayout.displays.compactMap { display -> NSScreen? in
            guard requestedDisplayIDs.contains(display.id) else {
                return nil
            }
            return screensByDisplayID[display.id]
        }

        return screens.isEmpty ? NSScreen.screens : screens
    }

    private static func stableDisplayID(for screen: NSScreen) -> String? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return nil
        }

        let displayID = CGDirectDisplayID(number.uint32Value)
        return [
            String(CGDisplayVendorNumber(displayID)),
            String(CGDisplayModelNumber(displayID)),
            String(CGDisplaySerialNumber(displayID)),
            String(displayID)
        ].joined(separator: "-")
    }

    private func scheduleFadeOut(
        _ activePanels: [NSPanel],
        state: HUDPresentationState,
        generation: Int
    ) {
        let workItem = DispatchWorkItem { [weak self, activePanels] in
            guard let self, self.presentationGeneration.isCurrent(generation) else {
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = state.fadeOutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                activePanels.forEach { panel in
                    panel.animator().alphaValue = 0
                }
            } completionHandler: { [weak self, activePanels] in
                Task { @MainActor [weak self, activePanels] in
                    guard let self, self.presentationGeneration.isCurrent(generation) else {
                        return
                    }

                    activePanels.forEach { panel in
                        guard panel.alphaValue == 0 else {
                            return
                        }
                        panel.orderOut(nil)
                        panel.alphaValue = 1
                    }
                }
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + state.duration, execute: workItem)
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
    @Published private var runtimeDiagnostics: [DiagnosticState] = []
    @Published var lastSwitchResult = "No switch attempted"
    @Published var isSwitching = false
    @Published var isEnabled = false
    @Published var isInputRunning = false
    @Published var inputStatus = "Sideby off"
    @Published var lastInputEvent = "Use the configured swipe gesture."
    @Published var loginItemStatus = "Start at login off"
    @Published var onboardingDetectedGestureCount = 0
    @Published var didFinishMiniOnboarding = false
    @Published var visibleContextSuggestionsByOrder: [Int: [VisibleAppSuggestion]] = [:]
    @Published var contextCaptureSession: ContextCaptureSession?
    @Published var contextCaptureStatus: String?
    @Published private(set) var contextDeletionMinimumCount: Int? = nil

    private let settingsStore = UserDefaultsSettingsStore()
    private let permissionService = AccessibilityPermissionService()
    private let displayObserver = MacDisplayObserver()
    private let loginItemService = MacLoginItemService()
    private let automationPermissionProbe = SystemEventsAutomationPermissionProbe()
    private let systemEventsAutomationProbe = SystemEventsAutomationProbe<NSAppleScriptRunner>()
    private let setupFlow = V1SetupFlow()
    private let visibleAppSuggestionProvider = MacVisibleAppSuggestionProvider()
    private let spaceLayoutReader: any SpaceLayoutReading = SLSSpaceLayoutReader()
    private let contextHUDPolicy = ContextSwitchHUDPolicy()
    private let contextKeyboardModifierReleaseWaiter = ContextKeyboardModifierReleaseWaiter()
    private let observerTokens = SidebyAppObserverTokens()
    private static let enabledDefaultsKey = "sideby.enabled"
    private static let contextCaptureConfiguration = ContextCaptureConfiguration.automatic
    private static let contextCaptureObserverWait: TimeInterval = contextCaptureConfiguration.observerWait
    private static let contextCaptureAlignmentRetryDelay: TimeInterval = contextCaptureConfiguration.alignmentRetryDelay
    private static let contextCaptureForwardRetryDelay: TimeInterval = contextCaptureConfiguration.forwardRetryDelay
    private static let contextCaptureCompletionIgnoreInterval: TimeInterval = 2.5
    private static let contextCaptureLog = Logger(
        subsystem: "dev.sideby.Sideby",
        category: "ContextCapture"
    )
    private var didInitializeSelectedDisplays = false
    private var swipeInputSource: GlobalEventTapInputSource?
    private var contextKeyboardInputSource: GlobalContextKeyboardShortcutInputSource?
    private var contextKeyboardCoordinator = ContextKeyboardCommandCoordinator()
    @Published private var failedContextKeyboardCommands: [ContextKeyboardCommand] = []
    private var swipePipeline = SwipeInputPipeline(settings: .default)
    private var inputLatch = InputCommandLatch()
    private var inputSessionID = 0
    private var switchSessionID = 0
    private var contextCaptureSessionID = 0
    private var contextCaptureActiveDisplayIDs: Set<String> = []
    /// Displays whose presence at the current capture order was actually
    /// observed. Only these become members of the recorded context;
    /// `contextCaptureActiveDisplayIDs` may additionally hold displays that
    /// are merely within their no-move grace window.
    private var contextCaptureMemberDisplayIDs: Set<String> = []
    private var contextCaptureNoMoveStreaks: [String: Int] = [:]
    private var permissionPollingID = 0
    private var lastScrollStatusUpdate = 0.0
    private var isOnboardingGestureTestActive = false
    private var ignoresExternalSpaceChangesUntil: Date?

    var diagnostics: [DiagnosticState] {
        get {
            ContextKeyboardDiagnosticMerger.diagnostics(
                runtimeDiagnostics: runtimeDiagnostics,
                failedCommands: failedContextKeyboardCommands,
                strings: strings
            )
        }
        set { runtimeDiagnostics = newValue }
    }

    init() {
        var loadedSettings = settingsStore.load()
        loadedSettings.mode = .shortcut
        self.settings = loadedSettings
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        let strings = SBSStrings(language: loadedSettings.language)
        self.lastSwitchResult = strings.noSwitchAttempted
        self.inputStatus = strings.sidebyOff
        self.lastInputEvent = Self.inputHint(for: loadedSettings, strings: strings)
        self.loginItemStatus = strings.startAtLoginStatus(isEnabled: loginItemService.isEnabled)
        startSettingsChangeObserver()
        startExternalSpaceChangeObserver()
        refresh()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.startContextKeyboardInput()
            if self.isEnabled {
                self.resumeEnabledInputIfNeeded()
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
        refreshContextEditAvailability()
        permissionState = permissionService.currentState
        postEventAccessGranted = CGPreflightPostEventAccess()
        automationAccessGranted = automationPermissionProbe.checkAccessWithoutPrompt().isGranted
        loginItemStatus = strings.startAtLoginStatus(isEnabled: loginItemService.isEnabled)
        diagnostics = currentDiagnostics()
    }

    private func currentDiagnostics() -> [DiagnosticState] {
        var values = DiagnosticRule.evaluate(
            decision: ModePolicy().decision(
                for: settings.mode,
                inputMethod: .shortcut,
                runtimeState: runtimeState
            )
        )

        if settings.contextPlan.isPinned,
           settings.contextPlan.syncState == .needsSync,
           let diagnostic = settings.contextPlan.navigation(for: .next).diagnostic {
            values.append(
                DiagnosticState(
                    severity: diagnostic.severity,
                    title: diagnostic.title,
                    message: diagnostic.message,
                    actionLabel: "Align Displays"
                )
            )
        }

        return values
    }

    private func startContextKeyboardInput() {
        let source = GlobalContextKeyboardShortcutInputSource(handler: { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleContextKeyboardEvent(event)
            }
        })
        let result = source.start()
        contextKeyboardInputSource = source
        failedContextKeyboardCommands = result.failedCommands
        diagnostics = currentDiagnostics()
    }

    private func handleContextKeyboardEvent(_ event: ContextKeyboardShortcutInputEvent) {
        let action = contextKeyboardCoordinator.handle(
            event,
            contextPlan: settings.contextPlan,
            isSidebyEnabled: isEnabled,
            isSwitching: isSwitching,
            isCapturing: contextCaptureSession != nil,
            at: ProcessInfo.processInfo.systemUptime
        )

        routeContextKeyboardAction(action)
    }

    private func routeContextKeyboardAction(_ action: ContextKeyboardAction) {
        switch action {
        case .ignore:
            return
        case .showSidebyOff:
            ProductContextHUDController.shared.show(
                HUDPresenter().stateForSidebyToggleOff(strings: strings)
            )
        case .showMissingContext(let position):
            ProductContextHUDController.shared.show(
                HUDPresenter().stateForMissingContext(position: position, strings: strings)
            )
        case .waitForModifierRelease(let command):
            contextKeyboardModifierReleaseWaiter.waitUntilReleased(
                triggerModifiers: ContextKeyboardShortcutCatalog.triggerModifiers
            ) { [weak self] in
                guard let self else { return }
                let resumedAction = self.contextKeyboardCoordinator.resumeAfterModifierRelease(
                    command,
                    contextPlan: self.settings.contextPlan,
                    isSidebyEnabled: self.isEnabled,
                    isSwitching: self.isSwitching,
                    isCapturing: self.contextCaptureSession != nil
                )
                self.routeContextKeyboardAction(resumedAction)
            }
        case .activate, .move:
            guard let execution = ContextKeyboardExecutionResolver.execution(
                for: action,
                contextPlan: settings.contextPlan
            ) else {
                return
            }
            switch execution {
            case .activate(let contextID):
                activateContext(
                    contextID: contextID,
                    executionStrategy: .ordinary
                ) { [weak self] _ in
                    self?.finishContextKeyboardExecution()
                }
            case .move(let switchCommand):
                performSwitch(
                    switchCommand,
                    label: "context-keyboard",
                    executionStrategy: .ordinary
                ) { [weak self] _ in
                    self?.finishContextKeyboardExecution()
                }
            }
        }
    }

    private func finishContextKeyboardExecution() {
        contextKeyboardCoordinator.finishExecution(
            at: ProcessInfo.processInfo.systemUptime
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
        refreshContextEditAvailability()
    }

    func selectAllDisplayTargets() {
        selectedDisplayIDs = Set(displayLayout.displays.map(\.id))
        refreshContextEditAvailability()
    }

    var canAddContext: Bool {
        !isSwitching && contextCaptureSession == nil
    }

    var canDeleteContext: Bool {
        canAddContext && ContextEditPolicy.canDelete(
            contextCount: settings.contextPlan.contexts.count,
            minimumContextCount: contextDeletionMinimumCount
        )
    }

    func addEmptyContext() {
        guard canAddContext else { return }
        updateContextPlan { plan in
            plan.addEmptyContext()
        }
    }

    func contextDeletionRequiresConfirmation(contextID: String) -> Bool {
        ContextEditAction.requiresDeleteConfirmation(
            contextID: contextID,
            contexts: settings.contextPlan.contexts
        )
    }

    @discardableResult
    func deleteContext(contextID: String) -> Bool {
        guard canAddContext else {
            refreshContextEditAvailability()
            return false
        }

        var deleted = false
        updateContextPlan { plan in
            deleted = ContextEditAction.deleteContext(
                id: contextID,
                from: &plan,
                isEditingAllowed: canAddContext,
                selectedDisplayIDs: selectedDisplayIDs,
                readLiveDisplays: selectedDisplaySpaces
            )
        }
        refreshContextEditAvailability()
        return deleted
    }

    func setContextName(contextID: String, name: String) {
        updateContextPlan { plan in
            plan.renameContext(id: contextID, name: name)
        }
    }

    var canActivateContext: Bool {
        ContextActivationAvailability.canActivate(
            isSidebyEnabled: isEnabled,
            isSwitching: isSwitching,
            isCapturing: contextCaptureSession != nil
        )
    }

    func setContextPinning(_ isPinned: Bool) {
        updateContextPlan { plan in
            plan.setPinned(isPinned)
        }
    }

    func setCurrentContext(contextID: String) {
        updateContextPlan { plan in
            _ = plan.setCurrentContext(id: contextID)
        }
    }

    func activateContext(
        contextID: String,
        executionStrategy: SpaceCommandExecutionStrategy = .ordinary,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        guard isEnabled else {
            diagnostics = [
                DiagnosticState(
                    severity: .warning,
                    title: strings.sidebyOffTitle,
                    message: strings.sidebyOffMessage,
                    actionLabel: nil
                )
            ]
            lastSwitchResult = strings.sidebyOffReason
            completion?(false)
            return
        }
        guard canActivateContext else {
            completion?(false)
            return
        }

        let intent = settings.contextPlan.activationIntent(forContextID: contextID)
        guard intent.shouldExecute, let targetContext = intent.targetContext else {
            if let diagnostic = intent.diagnostic {
                diagnostics = [diagnostic]
                lastSwitchResult = strings.localizedDiagnosticTitle(diagnostic.title)
            }
            completion?(false)
            return
        }
        guard hasPostEventAccess(command: .next, label: "context") else {
            completion?(false)
            return
        }

        performContextActivation(
            targetContext: targetContext,
            executionStrategy: executionStrategy,
            completion: completion
        )
    }

    func moveDisplaySpace(displayID: String, spaceIndex: Int, toContextID: String) {
        updateContextPlan { plan in
            _ = plan.moveDisplaySpace(
                displayID: displayID,
                spaceIndex: spaceIndex,
                toContextID: toContextID
            )
        }
    }

    func moveContextDisplayRow(displayID: String, to targetDisplayID: String) {
        let nextOrder = ContextMatrixModel.displayRowOrder(
            moving: displayID,
            to: targetDisplayID,
            visibleDisplayIDs: displayLayout.displays.map(\.id),
            currentOrder: settings.displayRowOrder
        )
        guard nextOrder != settings.displayRowOrder else {
            return
        }

        settings.displayRowOrder = nextOrder
        settingsStore.save(settings)
    }

    private func performContextActivation(
        targetContext: ContextDefinition,
        executionStrategy: SpaceCommandExecutionStrategy = .ordinary,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        let decision = ModePolicy().decision(
            for: settings.mode,
            inputMethod: .shortcut,
            runtimeState: runtimeState
        )
        let modeDiagnostics = DiagnosticRule.evaluate(decision: decision)
        guard decision.isAllowed else {
            diagnostics = modeDiagnostics
            if let diagnostic = modeDiagnostics.first(where: { $0.severity == .blocker }) ?? modeDiagnostics.first {
                lastSwitchResult = strings.localizedDiagnosticTitle(diagnostic.title)
            }
            completion?(false)
            return
        }

        guard let displays = selectedDisplaySpaces(), !displays.isEmpty else {
            updateContextPlan { plan in
                plan.markNeedsSync()
            }
            diagnostics = currentDiagnostics()
            lastSwitchResult = strings.alignFailed
            completion?(false)
            return
        }

        let targetMemberDisplayIDs = Set(displays.compactMap { display in
            targetContext.spaceIndex(for: display.displayID) == nil ? nil : display.displayID
        })
        guard !targetMemberDisplayIDs.isEmpty else {
            diagnostics = [
                DiagnosticState(
                    severity: .blocker,
                    title: strings.noMoveTargetsTitle,
                    message: strings.noMoveTargetsMessage,
                    actionLabel: nil
                )
            ]
            lastSwitchResult = strings.noMoveTargetsReason
            completion?(false)
            return
        }

        let moves = ContextDisplayMovePlanner.moves(
            displays: displays,
            targetContext: targetContext
        )
        guard !moves.isEmpty else {
            diagnostics = modeDiagnostics
            updateContextPlan { plan in
                _ = plan.setCurrentContext(id: targetContext.id)
            }
            lastSwitchResult = strings.alignedToContext(
                settings.contextPlan.currentContext?.name ?? targetContext.name
            )
            ProductContextHUDController.shared.show(
                HUDPresenter().stateForContextSwitch(contextName: targetContext.name),
                displayIDs: targetMemberDisplayIDs,
                displayLayout: displayLayout
            )
            completion?(true)
            return
        }

        ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(30)
        isSwitching = true
        switchSessionID += 1
        let sessionID = switchSessionID
        let reader = spaceLayoutReader
        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: displayObserver.currentSnapshots(),
            uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )

        DispatchQueue.global(qos: .userInitiated).async {
            func readIndexes() -> [String: Int]? {
                guard let layouts = reader.readLayout() else {
                    return nil
                }
                var indexes: [String: Int] = [:]
                for layout in layouts {
                    guard let stableID = mapping[layout.displayUUID],
                          let index = layout.spaceIDs.firstIndex(of: layout.currentSpaceID)
                    else {
                        continue
                    }
                    indexes[stableID] = index
                }
                return indexes
            }

            let acknowledger = SpaceLayoutStepAcknowledger()
            var didMoveAll = true

            for move in moves {
                let executor = HiddenCursorDisplaySpaceCommandExecutor(
                    baseExecutor: executionStrategy.baseExecutor(),
                    targetProvider: CGDisplaySwitchTargetProvider(includedStableIDs: [move.displayID])
                )
                var index = move.currentIndex
                while index != move.targetIndex {
                    let step: SwitchCommand = index < move.targetIndex ? .next : .previous
                    guard executor.execute(step),
                          let newIndex = acknowledger.waitForIndexChange(
                              of: move.displayID,
                              from: index,
                              timeout: 1.0,
                              readIndexes: readIndexes
                          )
                    else {
                        didMoveAll = false
                        break
                    }
                    index = newIndex
                }
                if !didMoveAll {
                    break
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion?(false)
                    return
                }
                guard self.switchSessionID == sessionID else {
                    completion?(false)
                    return
                }
                self.isSwitching = false
                self.ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(0.75)

                if didMoveAll {
                    self.diagnostics = modeDiagnostics
                    self.updateContextPlan { plan in
                        _ = plan.setCurrentContext(id: targetContext.id)
                    }
                    self.lastSwitchResult = self.strings.alignedToContext(
                        self.settings.contextPlan.currentContext?.name ?? targetContext.name
                    )
                    ProductContextHUDController.shared.show(
                        HUDPresenter().stateForContextSwitch(contextName: targetContext.name),
                        displayIDs: targetMemberDisplayIDs,
                        displayLayout: self.displayLayout
                    )
                } else {
                    self.updateContextPlan { plan in
                        plan.markNeedsSync()
                    }
                    self.diagnostics = modeDiagnostics + [
                        DiagnosticState(
                            severity: .warning,
                            title: self.strings.spaceCommandNotAcceptedTitle,
                            message: self.strings.spaceCommandNotAcceptedMessage,
                            actionLabel: nil
                        )
                    ]
                    self.lastSwitchResult = self.strings.alignFailed
                }
                Self.contextCaptureLog.notice(
                    "context-activate target=\(targetContext.id, privacy: .public) moved=\(moves.count, privacy: .public) success=\(didMoveAll, privacy: .public)"
                )
                completion?(didMoveAll)
            }
        }
    }

    func alignDisplaysToCurrentSpace() {
        guard !isSwitching, contextCaptureSession == nil else {
            return
        }
        guard let displays = selectedDisplaySpaces(), !displays.isEmpty else {
            lastSwitchResult = strings.alignFailed
            return
        }

        let referenceID = alignmentReferenceDisplayID() ?? displays[0].displayID
        let reference = displays.first { $0.displayID == referenceID } ?? displays[0]
        guard let target = settings.contextPlan.contexts
            .sorted(by: { $0.order < $1.order })
            .first(where: { $0.spaceIndex(for: reference.displayID) == reference.currentSpaceIndex })
        else {
            lastSwitchResult = strings.alignFailed
            return
        }

        let moves = displays.compactMap { display -> (display: InstantCaptureDisplay, targetIndex: Int)? in
            guard display.displayID != reference.displayID,
                  let targetIndex = target.spaceIndex(for: display.displayID),
                  display.currentSpaceIndex != targetIndex
            else {
                return nil
            }
            return (display, targetIndex)
        }

        let alignFeedback = AlignFeedbackPolicy.feedback(
            displays: displays,
            referenceDisplayID: reference.displayID,
            targetContext: target
        )

        guard !moves.isEmpty else {
            updateContextPlan { plan in
                _ = plan.setCurrentContext(id: target.id)
            }
            lastSwitchResult = strings.alignedToContext(
                settings.contextPlan.currentContext?.name ?? target.name
            )
            diagnostics = currentDiagnostics()
            showAlignFeedbackHUD(alignFeedback)
            return
        }

        isSwitching = true
        ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(30)
        switchSessionID += 1
        let sessionID = switchSessionID
        let reader = spaceLayoutReader
        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: displayObserver.currentSnapshots(),
            uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )

        DispatchQueue.global(qos: .userInitiated).async {
            func readIndexes() -> [String: Int]? {
                guard let layouts = reader.readLayout() else {
                    return nil
                }
                var indexes: [String: Int] = [:]
                for layout in layouts {
                    guard let stableID = mapping[layout.displayUUID],
                          let index = layout.spaceIDs.firstIndex(of: layout.currentSpaceID)
                    else {
                        continue
                    }
                    indexes[stableID] = index
                }
                return indexes
            }

            let acknowledger = SpaceLayoutStepAcknowledger()
            var didAlignAll = true

            for move in moves {
                let executor = HiddenCursorDisplaySpaceCommandExecutor(
                    baseExecutor: MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster()),
                    targetProvider: CGDisplaySwitchTargetProvider(includedStableIDs: [move.display.displayID])
                )
                var index = move.display.currentSpaceIndex
                while index != move.targetIndex {
                    let command: SwitchCommand = index < move.targetIndex ? .next : .previous
                    guard executor.execute(command),
                          let newIndex = acknowledger.waitForIndexChange(
                              of: move.display.displayID,
                              from: index,
                              timeout: 1.0,
                              readIndexes: readIndexes
                          )
                    else {
                        didAlignAll = false
                        break
                    }
                    index = newIndex
                }
                if !didAlignAll {
                    break
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.switchSessionID == sessionID else {
                    return
                }
                self.isSwitching = false
                self.ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(0.75)
                if didAlignAll {
                    self.updateContextPlan { plan in
                        _ = plan.setCurrentContext(id: target.id)
                    }
                    self.lastSwitchResult = self.strings.alignedToContext(
                        self.settings.contextPlan.currentContext?.name ?? target.name
                    )
                    self.showAlignFeedbackHUD(alignFeedback)
                } else {
                    self.updateContextPlan { plan in
                        plan.markNeedsSync()
                    }
                    self.lastSwitchResult = self.strings.alignFailed
                }
                self.diagnostics = self.currentDiagnostics()
                Self.contextCaptureLog.notice(
                    "align-displays target=\(target.id, privacy: .public) moved=\(moves.count, privacy: .public) success=\(didAlignAll, privacy: .public)"
                )
            }
        }
    }

    private func showAlignFeedbackHUD(_ feedback: [AlignDisplayFeedback]) {
        guard !feedback.isEmpty else {
            return
        }

        let statesByDisplayID = Dictionary(
            feedback.map { ($0.displayID, Self.alignFeedbackHUDState(text: alignFeedbackText(for: $0.reason))) },
            uniquingKeysWith: { first, _ in first }
        )
        ProductContextHUDController.shared.show(
            statesByDisplayID: statesByDisplayID,
            displayLayout: displayLayout,
            timing: Self.alignFeedbackHUDTiming
        )
    }

    private func alignFeedbackText(for reason: AlignFeedbackReason) -> String {
        switch reason {
        case .alreadyAligned:
            strings.alignFeedbackAlreadyAligned
        case .notInContext:
            strings.alignFeedbackNotInContext
        }
    }

    private static let alignFeedbackHUDTiming = alignFeedbackHUDState(text: "")

    private static func alignFeedbackHUDState(text: String) -> HUDPresentationState {
        HUDPresentationState(
            text: text,
            duration: 1.8,
            fadeOutDuration: 0.3,
            visualScale: 2.0,
            backgroundOpacity: 0.66
        )
    }

    /// Display hosting the Sideby window, falling back to the display under
    /// the cursor. Used as the alignment reference ("the screen the button
    /// was pressed on").
    private func alignmentReferenceDisplayID() -> String? {
        let snapshots = displayObserver.currentSnapshots()
        func stableID(for screen: NSScreen?) -> String? {
            guard
                let number = screen?.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber,
                let snapshot = snapshots.first(where: { $0.displayID == number.uint32Value })
            else {
                return nil
            }
            return DisplayLayoutMapper.stableID(for: snapshot)
        }

        if let windowScreen = NSApp.keyWindow?.screen, let id = stableID(for: windowScreen) {
            return id
        }
        let mouseLocation = NSEvent.mouseLocation
        let cursorScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
        return stableID(for: cursorScreen)
    }

    /// Reads the live Space layout for selected displays that expose
    /// independent Spaces, in layout order. Mirrored displays can be present
    /// as screens without independent Space layout, so they are skipped.
    private func selectedDisplaySpaces() -> [InstantCaptureDisplay]? {
        guard let layouts = spaceLayoutReader.readLayout(), !layouts.isEmpty else {
            return nil
        }

        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: displayObserver.currentSnapshots(),
            uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )
        return DisplayLayoutMapper.instantCaptureDisplays(
            selectedDisplayIDs: selectedDisplayIDs,
            displayLayout: displayLayout,
            layouts: layouts,
            stableIDsByUUID: mapping
        )
    }

    private func refreshContextEditAvailability() {
        contextDeletionMinimumCount = ContextEditAction.minimumContextCount(
            selectedDisplayIDs: selectedDisplayIDs,
            readLiveDisplays: selectedDisplaySpaces
        )
    }

    /// Builds the context plan directly from the Space layout. Returns false
    /// when the layout is unavailable so the caller can fall back to the
    /// walk-based capture.
    private func startInstantContextCapture() -> Bool {
        guard let captureDisplays = selectedDisplaySpaces(), !captureDisplays.isEmpty else {
            return false
        }

        guard let instantPlan = InstantContextCapturePlanner.plan(for: captureDisplays) else {
            return false
        }

        let currentOrder = instantPlan.contexts
            .first { $0.id == instantPlan.currentContextID }?.order ?? 1
        let currentName = suggestedContextName(order: currentOrder)
        let contexts = instantPlan.contextsRenamingCurrentContext(to: currentName)

        updateContextPlan { plan in
            plan.replaceContexts(
                contexts,
                currentContextID: instantPlan.currentContextID
            )
            if !instantPlan.isSynchronized {
                plan.markNeedsSync()
            }
        }
        contextCaptureStatus = strings.contextCaptureReadySummary(
            count: contexts.count,
            currentName: settings.contextPlan.currentContext?.name ?? currentName
        )
        Self.contextCaptureLog.notice(
            "instant-capture displays=\(captureDisplays.count, privacy: .public) contexts=\(contexts.count, privacy: .public) synchronized=\(instantPlan.isSynchronized, privacy: .public)"
        )
        return true
    }

    func startContextCapture() {
        refresh()
        guard InputControlStartPolicy.decision(
            hasAccessibilityPermission: hasAccessibilityPermission,
            hasSwitchingAccess: hasSwitchingAccess
        ) == .startListeners else {
            requestPermissions()
            contextCaptureStatus = strings.couldNotStartInput
            return
        }
        guard hasSelectedMoveTargets(command: .next, label: "context-capture") else {
            return
        }
        guard !isSwitching, contextCaptureSession == nil else {
            return
        }

        if startInstantContextCapture() {
            return
        }
        // Instant capture unavailable — fall back to the walk-based capture below.

        contextCaptureSessionID += 1
        let sessionID = contextCaptureSessionID
        contextCaptureActiveDisplayIDs = selectedDisplayIDs
        contextCaptureMemberDisplayIDs = selectedDisplayIDs
        contextCaptureNoMoveStreaks = [:]
        contextCaptureSession = ContextCaptureSession(
            maxAlignmentAttempts: Self.contextCaptureConfiguration.maxAlignmentAttempts
        )
        updateContextCaptureStatus()
        continueContextCaptureAlignment(sessionID: sessionID)
    }

    func stopContextCapture() {
        var session = contextCaptureSession
        session?.stop()
        contextCaptureSessionID += 1
        contextCaptureActiveDisplayIDs = []
        contextCaptureMemberDisplayIDs = []
        contextCaptureNoMoveStreaks = [:]
        ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(Self.contextCaptureCompletionIgnoreInterval)
        contextCaptureSession = nil
        contextCaptureStatus = session.map {
            ContextCaptureStatusDisplay.statusText(session: $0, strings: strings)
        } ?? strings.contextCaptureStopped
    }

    private func suggestedContextName(order: Int) -> String {
        let suggestions = visibleAppSuggestionProvider.suggestions(for: displayLayout)
        visibleContextSuggestionsByOrder[order] = suggestions

        var seen = Set<String>()
        let labels = suggestions.compactMap { suggestion -> String? in
            let rawLabel = suggestion.titleLabel ?? suggestion.appLabel
            let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !seen.contains(label) else {
                return nil
            }
            seen.insert(label)
            return label
        }

        return labels.isEmpty ? "Context \(order)" : labels.joined(separator: " / ")
    }

    private func commitContextCapture(_ session: ContextCaptureSession) {
        guard let contexts = session.completedContextDefinitions,
              case .completed(let currentContextID) = session.phase
        else {
            return
        }

        updateContextPlan { plan in
            plan.replaceContexts(
                contexts,
                currentContextID: currentContextID
            )
        }
        contextCaptureActiveDisplayIDs = []
    }

    private func continueContextCaptureAlignment(sessionID: Int) {
        guard contextCaptureSessionID == sessionID else {
            return
        }
        guard let session = contextCaptureSession else {
            return
        }
        guard case .aligning = session.phase else {
            continueContextCaptureForward(sessionID: sessionID)
            return
        }

        updateContextCaptureStatus()
        let alignmentDisplayIDs = contextCaptureActiveDisplayIDs
        let fingerprintsBefore = visibleContextFingerprints(for: alignmentDisplayIDs)
        performAcknowledgedSwitch(
            .previous,
            targetDisplayIDs: alignmentDisplayIDs,
            label: "context-capture-align",
            observerWait: Self.contextCaptureObserverWait
        ) { [weak self] result in
            guard let self,
                  self.contextCaptureSessionID == sessionID,
                  var activeSession = self.contextCaptureSession
            else {
                return
            }

            guard result.didPost else {
                activeSession.fail(reason: self.strings.systemEventsFailedReason)
                self.contextCaptureSession = activeSession
                self.updateContextCaptureStatus()
                self.ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(Self.contextCaptureCompletionIgnoreInterval)
                self.contextCaptureSession = nil
                return
            }

            let fingerprintsAfter = self.visibleContextFingerprints(for: alignmentDisplayIDs)
            let observations = alignmentDisplayIDs.map { displayID in
                ContextCaptureDisplayMovementObservation(
                    displayID: displayID,
                    didObserveActiveSpaceChange: false,
                    visibleFingerprintBefore: fingerprintsBefore[displayID],
                    visibleFingerprintAfter: fingerprintsAfter[displayID]
                )
            }
            let previousDidChange = ContextCaptureMovementPolicy.didObserveAnyMovement(
                didObserveActiveSpaceChange: result.didObserveAnyChange,
                observations: observations
            )
            Self.contextCaptureLog.notice(
                "align posted=\(result.didPost, privacy: .public) activeSpaceChange=\(result.didObserveAnyChange, privacy: .public) fingerprintChanges=\(observations.filter(\.didChangeVisibleFingerprint).count, privacy: .public)"
            )

            activeSession.recordAlignment(previousDidChange: previousDidChange)
            self.contextCaptureSession = activeSession
            self.updateContextCaptureStatus()

            guard !self.clearTerminalContextCaptureIfNeeded(activeSession) else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.contextCaptureAlignmentRetryDelay) { [weak self] in
                guard let self,
                      self.contextCaptureSessionID == sessionID,
                      self.contextCaptureSession != nil
                else {
                    return
                }
                self.continueContextCaptureAlignment(sessionID: sessionID)
            }
        }
    }

    private func continueContextCaptureForward(sessionID: Int) {
        guard contextCaptureSessionID == sessionID else {
            return
        }
        guard var session = contextCaptureSession else {
            return
        }
        guard let order = session.currentCaptureOrder else {
            if clearTerminalContextCaptureIfNeeded(session) {
                return
            }
            finishContextCaptureIfNeeded(session)
            return
        }

        let activeDisplayIDs = contextCaptureActiveDisplayIDs
        let name = suggestedContextName(order: order)
        session.recordCurrentSpace(name: name, displayIDs: Array(contextCaptureMemberDisplayIDs))
        contextCaptureSession = session
        updateContextCaptureStatus()

        guard !activeDisplayIDs.isEmpty else {
            session.recordForwardSwitch(movedDisplayIDs: [])
            contextCaptureSession = session
            finishContextCaptureIfNeeded(session)
            return
        }

        performAcknowledgedSwitchPerDisplay(
            .next,
            targetDisplayIDs: activeDisplayIDs,
            label: "context-capture",
            observerWait: Self.contextCaptureObserverWait
        ) { [weak self] movedDisplayIDs, didPost in
            guard let self,
                  self.contextCaptureSessionID == sessionID,
                  var activeSession = self.contextCaptureSession
            else {
                return
            }

            guard didPost else {
                activeSession.fail(reason: self.strings.systemEventsFailedReason)
                self.contextCaptureSession = activeSession
                self.updateContextCaptureStatus()
                self.ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(Self.contextCaptureCompletionIgnoreInterval)
                self.contextCaptureSession = nil
                return
            }

            let decision = ContextCaptureMovementPolicy.forwardDecision(
                activeDisplayIDs: activeDisplayIDs,
                movedDisplayIDs: movedDisplayIDs,
                noMoveStreaks: self.contextCaptureNoMoveStreaks
            )
            self.contextCaptureNoMoveStreaks = decision.noMoveStreaks

            if movedDisplayIDs.isEmpty, !decision.activeDisplayIDs.isEmpty {
                // No confirmed movement, but some displays still have grace:
                // re-press them at the same order instead of ending the capture
                // on a possibly missed observation.
                self.contextCaptureActiveDisplayIDs = decision.activeDisplayIDs
                self.updateContextCaptureStatus()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.contextCaptureForwardRetryDelay) { [weak self] in
                    guard let self,
                          self.contextCaptureSessionID == sessionID,
                          self.contextCaptureSession != nil
                    else {
                        return
                    }
                    self.continueContextCaptureForward(sessionID: sessionID)
                }
                return
            }

            activeSession.recordForwardSwitch(movedDisplayIDs: decision.activeDisplayIDs)
            self.contextCaptureActiveDisplayIDs = decision.activeDisplayIDs
            self.contextCaptureMemberDisplayIDs = decision.confirmedDisplayIDs
            self.contextCaptureSession = activeSession
            self.updateContextCaptureStatus()

            guard !self.clearTerminalContextCaptureIfNeeded(activeSession) else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.contextCaptureForwardRetryDelay) { [weak self] in
                guard let self,
                      self.contextCaptureSessionID == sessionID,
                      self.contextCaptureSession != nil
                else {
                    return
                }
                self.continueContextCaptureForward(sessionID: sessionID)
            }
        }
    }

    private func finishContextCaptureIfNeeded(_ session: ContextCaptureSession) {
        guard session.shouldCommitDrafts else {
            return
        }
        commitContextCapture(session)
        ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(Self.contextCaptureCompletionIgnoreInterval)
        contextCaptureSession = nil
        contextCaptureStatus = ContextCaptureStatusDisplay.statusText(
            session: session,
            currentContextName: settings.contextPlan.currentContext?.name,
            strings: strings
        )
    }

    private func clearTerminalContextCaptureIfNeeded(_ session: ContextCaptureSession) -> Bool {
        switch session.phase {
        case .failed, .stopped:
            ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(Self.contextCaptureCompletionIgnoreInterval)
            contextCaptureSession = nil
            contextCaptureStatus = ContextCaptureStatusDisplay.statusText(
                session: session,
                strings: strings
            )
            return true
        case .completed:
            finishContextCaptureIfNeeded(session)
            return true
        case .aligning, .capturing:
            return false
        }
    }

    private func updateContextCaptureStatus() {
        guard let session = contextCaptureSession else {
            contextCaptureStatus = nil
            return
        }
        contextCaptureStatus = ContextCaptureStatusDisplay.statusText(
            session: session,
            strings: strings
        )
    }

    private func applyOnboardingCompletionDefaults() {
        refresh()
        let defaults = OnboardingCompletionPolicy().completionDefaults(for: displayLayout)
        selectedDisplayIDs = defaults.selectedDisplayIDs
        refreshContextEditAvailability()
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
        guard KeyboardShortcutValidator.isValidGestureModifierSet(newSettings.requiredModifiers) else {
            lastInputEvent = strings.shortcutSettingsNotSaved
            return
        }

        var savedSettings = newSettings
        savedSettings.mode = .shortcut
        settings = savedSettings
        settingsStore.save(savedSettings)
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
        refreshLocalizedStatus()
        lastInputEvent = Self.inputHint(for: settings, strings: strings)

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
        observerTokens.settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: UserDefaultsSettingsStore.settingsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadSettingsFromStoreIfChanged()
            }
        }
    }

    private func startExternalSpaceChangeObserver() {
        observerTokens.externalSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleExternalSpaceChange()
            }
        }
    }

    private func handleExternalSpaceChange() {
        if isSwitching || contextCaptureSession != nil {
            ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(0.75)
            return
        }

        if let ignoreUntil = ignoresExternalSpaceChangesUntil,
           Date() < ignoreUntil {
            return
        }

        let plan = settings.contextPlan
        if ExternalSpaceChangeContextPolicy.shouldTrackCurrentContext(
            isSidebyEnabled: isEnabled,
            plan: plan
        ),
            let displays = selectedDisplaySpaces() {
            let indexes = Dictionary(
                uniqueKeysWithValues: displays.map { ($0.displayID, $0.currentSpaceIndex) }
            )
            if let matchedID = ContextCurrentMatcher.currentContextID(
                contexts: plan.contexts,
                displayIndexes: indexes
            ) {
                if matchedID != plan.currentContextID || plan.syncState != .synchronized {
                    updateContextPlan { plan in
                        _ = plan.setCurrentContext(id: matchedID)
                    }
                    lastSwitchResult = strings.followingContext(
                        settings.contextPlan.currentContext?.name ?? matchedID
                    )
                }
            } else if plan.syncState == .synchronized {
                updateContextPlan { plan in
                    plan.markNeedsSync()
                }
                lastSwitchResult = strings.contextNeedsAlignment
            }
            diagnostics = currentDiagnostics()
            return
        }

        guard ExternalSpaceChangeContextPolicy.shouldPauseContextMatching(
            isSidebyEnabled: isEnabled,
            plan: settings.contextPlan
        ) else {
            return
        }

        updateContextPlan { plan in
            plan.pauseContextMatchingForUnsynchronizedMovement()
        }

        diagnostics = currentDiagnostics()
        lastSwitchResult = strings.contextMatchingPaused
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
        lastInputEvent = Self.inputHint(for: settings, strings: strings)

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
        guard contextCaptureSession == nil else {
            lastSwitchResult = strings.ignoredSwitchContextCaptureActive(label: "button", command: command)
            return false
        }
        guard !isSwitching else {
            lastSwitchResult = strings.ignoredSwitchAlreadyRunning(command: command)
            return false
        }
        guard isEnabled else {
            blockSwitchBecauseSidebyIsOff(command: command, label: "button")
            return false
        }
        let intent = settings.contextPlan.switchIntent(for: command)
        guard intent.shouldExecute else {
            if let diagnostic = intent.diagnostic {
                diagnostics = [diagnostic]
                lastSwitchResult = strings.blockedSwitch(
                    label: "button",
                    command: command,
                    reason: strings.localizedDiagnosticTitle(diagnostic.title)
                )
            }
            return false
        }
        guard hasSwitchMoveTargets(for: intent, label: "button") else {
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

        guard InputControlStartPolicy.decision(
            hasAccessibilityPermission: hasAccessibilityPermission,
            hasSwitchingAccess: hasSwitchingAccess
        ) == .startListeners else {
            stopRunningInputSources()
            isInputRunning = false
            inputStatus = strings.couldNotStartInput
            lastInputEvent = strings.couldNotStartInput
            return false
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
        let didStartSwipe = Self.didStartInputSource(swipeSource.start())
        guard didStartSwipe else {
            swipeSource.stop()
            swipeInputSource = nil
            isInputRunning = false
            inputStatus = strings.couldNotStartInput
            lastInputEvent = strings.swipeListenerFailed
            return false
        }

        swipeInputSource = swipeSource
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
        swipeInputSource = nil
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

    private func performAcknowledgedSwitch(
        _ command: SwitchCommand,
        targetDisplayIDs requestedTargetDisplayIDs: Set<String>? = nil,
        label: String,
        observerWait: TimeInterval = 0.85,
        completion: @escaping @MainActor @Sendable (AcknowledgedSpaceSwitchResult) -> Void
    ) {
        guard !isSwitching else {
            completion(
                AcknowledgedSpaceSwitchResult(
                    command: command,
                    didPost: false,
                    expectedChangeCount: 1,
                    observedChangeCount: 0
                )
            )
            return
        }

        ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(1.5)
        isSwitching = true
        switchSessionID += 1
        let sessionID = switchSessionID
        let targetDisplayIDs = requestedTargetDisplayIDs ?? selectedDisplayIDs

        DispatchQueue.global(qos: .userInitiated).async {
            let targetProvider = CGDisplaySwitchTargetProvider(includedStableIDs: targetDisplayIDs)
            let executor = HiddenCursorDisplaySpaceCommandExecutor(
                baseExecutor: MacSpaceCommandExecutor(poster: AppleScriptKeyEventPoster()),
                targetProvider: targetProvider
            )
            let switcher = AcknowledgedSpaceSwitcher(
                executor: executor,
                targetProvider: targetProvider,
                observerWait: observerWait
            )
            let result = switcher.execute(command)

            DispatchQueue.main.async { [weak self] in
                guard let self, self.switchSessionID == sessionID else {
                    return
                }
                self.isSwitching = false
                self.ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(0.75)
                self.lastSwitchResult = result.didPost
                    ? self.strings.postedSwitch(label: label, command: command)
                    : self.strings.blockedSwitch(
                        label: label,
                        command: command,
                        reason: self.strings.systemEventsFailedReason
                    )
                completion(result)
            }
        }
    }

    private func performAcknowledgedSwitchPerDisplay(
        _ command: SwitchCommand,
        targetDisplayIDs requestedTargetDisplayIDs: Set<String>,
        label: String,
        observerWait: TimeInterval = 0.85,
        completion: @escaping @MainActor @Sendable (Set<String>, Bool) -> Void
    ) {
        let orderedDisplayIDs = displayLayout.displays
            .map(\.id)
            .filter { requestedTargetDisplayIDs.contains($0) }

        guard !orderedDisplayIDs.isEmpty else {
            completion([], true)
            return
        }

        var movedDisplayIDs = Set<String>()
        var observations: [ContextCaptureDisplayMovementObservation] = []

        func switchDisplay(at index: Int) {
            guard index < orderedDisplayIDs.count else {
                completion(
                    ContextCaptureMovementPolicy.movedDisplayIDs(from: observations),
                    true
                )
                return
            }

            let displayID = orderedDisplayIDs[index]
            let visibleFingerprintBefore = visibleContextFingerprint(for: displayID)
            performAcknowledgedSwitch(
                command,
                targetDisplayIDs: [displayID],
                label: label,
                observerWait: observerWait
            ) { result in
                guard result.didPost else {
                    completion(movedDisplayIDs, false)
                    return
                }

                let visibleFingerprintAfter = self.visibleContextFingerprint(for: displayID)
                let observation = ContextCaptureDisplayMovementObservation(
                    displayID: displayID,
                    didObserveActiveSpaceChange: result.didObserveAnyChange,
                    visibleFingerprintBefore: visibleFingerprintBefore,
                    visibleFingerprintAfter: visibleFingerprintAfter
                )
                observations.append(observation)
                Self.contextCaptureLog.notice(
                    "display=\(displayID, privacy: .public) posted=\(result.didPost, privacy: .public) activeSpaceChange=\(result.didObserveAnyChange, privacy: .public) fingerprintChange=\(observation.didChangeVisibleFingerprint, privacy: .public)"
                )

                if observation.didMove {
                    movedDisplayIDs.insert(displayID)
                }
                switchDisplay(at: index + 1)
            }
        }

        switchDisplay(at: 0)
    }

    private func visibleContextFingerprint(for displayID: String) -> String? {
        visibleContextFingerprints(for: [displayID])[displayID]
    }

    private func visibleContextFingerprints(for displayIDs: Set<String>) -> [String: String] {
        let suggestions = visibleAppSuggestionProvider.suggestions(for: displayLayout)
        var fingerprints: [String: String] = [:]
        for displayID in displayIDs {
            if let label = suggestions.first(where: { $0.displayID == displayID })?.combinedLabel {
                fingerprints[displayID] = label
            }
        }
        return fingerprints
    }

    private func performSwitch(
        _ command: SwitchCommand,
        label: String,
        inputMethod: InputMethod = .shortcut,
        executionStrategy: SpaceCommandExecutionStrategy = .ordinary,
        resumeInputAfterCompletion shouldResumeInput: Bool? = nil,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        guard contextCaptureSession == nil else {
            lastSwitchResult = strings.ignoredSwitchContextCaptureActive(label: label, command: command)
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }
        let intent = settings.contextPlan.switchIntent(for: command)
        guard intent.shouldExecute else {
            if let diagnostic = intent.diagnostic {
                diagnostics = [diagnostic]
                lastSwitchResult = strings.blockedSwitch(
                    label: label,
                    command: command,
                    reason: strings.localizedDiagnosticTitle(diagnostic.title)
                )
            }
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }
        guard hasPostEventAccess(command: command, label: label) else {
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }
        guard !isSwitching else {
            lastSwitchResult = strings.ignoredSwitchAlreadyRunning(label: label, command: command)
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }

        if settings.contextPlan.isPinned,
           let targetContext = intent.targetContext,
           settings.contextPlan.contexts.contains(where: { !$0.usesDefaultSpaceIndexes }) {
            performIndexedContextSwitch(
                command,
                targetContext: targetContext,
                label: label,
                inputMethod: inputMethod,
                intent: intent,
                executionStrategy: executionStrategy,
                resumeInputAfterCompletion: shouldResumeInput,
                completion: completion
            )
            return
        }

        let targetDisplayIDs = targetDisplayIDs(for: intent)
        guard !targetDisplayIDs.isEmpty else {
            diagnostics = [
                DiagnosticState(
                    severity: .blocker,
                    title: strings.noMoveTargetsTitle,
                    message: strings.noMoveTargetsMessage,
                    actionLabel: nil
                )
            ]
            lastSwitchResult = strings.blockedSwitch(label: label, command: command, reason: strings.noMoveTargetsReason)
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }

        ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(1.5)
        isSwitching = true
        switchSessionID += 1
        let sessionID = switchSessionID
        let mode = settings.mode
        let state = runtimeState

        DispatchQueue.global(qos: .userInitiated).async {
            let executor = HiddenCursorDisplaySpaceCommandExecutor(
                baseExecutor: executionStrategy.baseExecutor(),
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
                guard let self else {
                    completion?(false)
                    return
                }
                guard self.switchSessionID == sessionID else {
                    completion?(false)
                    return
                }

                self.applySwitchResult(
                    result,
                    command: command,
                    label: label,
                    intent: intent,
                    executedDisplayIDs: targetDisplayIDs,
                    navigationDiagnostic: intent.diagnostic
                )
                self.isSwitching = false
                self.ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(0.75)
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
        label: String,
        intent: ContextSwitchIntent,
        executedDisplayIDs: Set<String>,
        navigationDiagnostic: DiagnosticState?
    ) {
        diagnostics = result.diagnostics
        if result.didExecute {
            let targetContext = intent.targetContext
            updateContextPlan { plan in
                if let targetContext {
                    _ = plan.setCurrentContext(id: targetContext.id)
                } else {
                    plan.markNeedsSync()
                }
            }
            if targetContext == nil, let navigationDiagnostic {
                diagnostics = result.diagnostics + [navigationDiagnostic]
            }
            lastSwitchResult = strings.postedSwitch(label: label, command: command)
            if let presentation = contextHUDPolicy.presentation(
                for: intent,
                didExecute: result.didExecute,
                executedDisplayIDs: executedDisplayIDs
            ) {
                ProductContextHUDController.shared.show(
                    presentation.state,
                    displayIDs: presentation.displayIDs,
                    displayLayout: displayLayout
                )
            }
        } else {
            updateContextPlan { plan in
                plan.applyFailedNavigation(command)
            }
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

    private func performIndexedContextSwitch(
        _ command: SwitchCommand,
        targetContext: ContextDefinition,
        label: String,
        inputMethod: InputMethod,
        intent: ContextSwitchIntent,
        executionStrategy: SpaceCommandExecutionStrategy = .ordinary,
        resumeInputAfterCompletion shouldResumeInput: Bool?,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        let decision = ModePolicy().decision(
            for: settings.mode,
            inputMethod: inputMethod,
            runtimeState: runtimeState
        )
        let modeDiagnostics = DiagnosticRule.evaluate(decision: decision)
        guard decision.isAllowed else {
            diagnostics = modeDiagnostics
            if let diagnostic = modeDiagnostics.first(where: { $0.severity == .blocker }) ?? modeDiagnostics.first {
                lastSwitchResult = strings.blockedSwitch(
                    label: label,
                    command: command,
                    reason: strings.localizedDiagnosticTitle(diagnostic.title)
                )
            }
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }

        guard let displays = selectedDisplaySpaces(), !displays.isEmpty else {
            updateContextPlan { plan in
                plan.markNeedsSync()
            }
            diagnostics = currentDiagnostics()
            lastSwitchResult = strings.alignFailed
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }

        let targetMemberDisplayIDs = Set(displays.compactMap { display in
            targetContext.spaceIndex(for: display.displayID) == nil ? nil : display.displayID
        })
        guard !targetMemberDisplayIDs.isEmpty else {
            diagnostics = [
                DiagnosticState(
                    severity: .blocker,
                    title: strings.noMoveTargetsTitle,
                    message: strings.noMoveTargetsMessage,
                    actionLabel: nil
                )
            ]
            lastSwitchResult = strings.blockedSwitch(label: label, command: command, reason: strings.noMoveTargetsReason)
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }

        let moves = displays.compactMap { display -> (display: InstantCaptureDisplay, targetIndex: Int)? in
            guard let targetIndex = targetContext.spaceIndex(for: display.displayID),
                  display.currentSpaceIndex != targetIndex
            else {
                return nil
            }
            return (display, targetIndex)
        }

        guard !moves.isEmpty else {
            diagnostics = modeDiagnostics
            updateContextPlan { plan in
                _ = plan.setCurrentContext(id: targetContext.id)
            }
            lastSwitchResult = strings.postedSwitch(label: label, command: command)
            if let presentation = contextHUDPolicy.presentation(
                for: intent,
                didExecute: true,
                executedDisplayIDs: targetMemberDisplayIDs
            ) {
                ProductContextHUDController.shared.show(
                    presentation.state,
                    displayIDs: presentation.displayIDs,
                    displayLayout: displayLayout
                )
            }
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(true)
            return
        }

        ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(30)
        isSwitching = true
        switchSessionID += 1
        let sessionID = switchSessionID
        let reader = spaceLayoutReader
        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: displayObserver.currentSnapshots(),
            uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )

        DispatchQueue.global(qos: .userInitiated).async {
            func readIndexes() -> [String: Int]? {
                guard let layouts = reader.readLayout() else {
                    return nil
                }
                var indexes: [String: Int] = [:]
                for layout in layouts {
                    guard let stableID = mapping[layout.displayUUID],
                          let index = layout.spaceIDs.firstIndex(of: layout.currentSpaceID)
                    else {
                        continue
                    }
                    indexes[stableID] = index
                }
                return indexes
            }

            let acknowledger = SpaceLayoutStepAcknowledger()
            var didMoveAll = true

            for move in moves {
                let executor = HiddenCursorDisplaySpaceCommandExecutor(
                    baseExecutor: executionStrategy.baseExecutor(),
                    targetProvider: CGDisplaySwitchTargetProvider(includedStableIDs: [move.display.displayID])
                )
                var index = move.display.currentSpaceIndex
                while index != move.targetIndex {
                    let step: SwitchCommand = index < move.targetIndex ? .next : .previous
                    guard executor.execute(step),
                          let newIndex = acknowledger.waitForIndexChange(
                              of: move.display.displayID,
                              from: index,
                              timeout: 1.0,
                              readIndexes: readIndexes
                          )
                    else {
                        didMoveAll = false
                        break
                    }
                    index = newIndex
                }
                if !didMoveAll {
                    break
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion?(false)
                    return
                }
                guard self.switchSessionID == sessionID else {
                    completion?(false)
                    return
                }
                self.isSwitching = false
                self.ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(0.75)

                if didMoveAll {
                    self.diagnostics = modeDiagnostics
                    self.updateContextPlan { plan in
                        _ = plan.setCurrentContext(id: targetContext.id)
                    }
                    self.lastSwitchResult = self.strings.postedSwitch(label: label, command: command)
                    if let presentation = self.contextHUDPolicy.presentation(
                        for: intent,
                        didExecute: true,
                        executedDisplayIDs: targetMemberDisplayIDs
                    ) {
                        ProductContextHUDController.shared.show(
                            presentation.state,
                            displayIDs: presentation.displayIDs,
                            displayLayout: self.displayLayout
                        )
                    }
                } else {
                    self.updateContextPlan { plan in
                        plan.markNeedsSync()
                    }
                    self.diagnostics = modeDiagnostics + [
                        DiagnosticState(
                            severity: .warning,
                            title: self.strings.spaceCommandNotAcceptedTitle,
                            message: self.strings.spaceCommandNotAcceptedMessage,
                            actionLabel: nil
                        )
                    ]
                    self.lastSwitchResult = self.strings.blockedSwitch(
                        label: label,
                        command: command,
                        reason: self.strings.systemEventsFailedReason
                    )
                }
                Self.contextCaptureLog.notice(
                    "context-switch-indexed target=\(targetContext.id, privacy: .public) moved=\(moves.count, privacy: .public) success=\(didMoveAll, privacy: .public)"
                )
                if let shouldResumeInput {
                    self.finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
                }
                completion?(didMoveAll)
            }
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

    private func hasSwitchMoveTargets(for intent: ContextSwitchIntent, label: String) -> Bool {
        guard intent.shouldExecute else {
            return true
        }

        guard !targetDisplayIDs(for: intent).isEmpty else {
            lastSwitchResult = strings.blockedSwitch(
                label: label,
                command: intent.command,
                reason: strings.noMoveTargetsReason
            )
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
                executeSwipeCommand(latchedCommand.command)
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

        let intent = settings.contextPlan.switchIntent(for: command)
        guard hasSwitchMoveTargets(for: intent, label: "modifier-swipe") else {
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
        let intent = settings.contextPlan.switchIntent(for: command)
        guard hasSwitchMoveTargets(for: intent, label: "modifier-swipe") else {
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

    private func releasedPendingInputCommand(for event: InputEvent) -> LatchedInputCommand? {
        guard case let .pending(latchedCommand) = inputLatch.state,
              latchedCommand.source == .swipe
        else {
            return nil
        }

        guard InputModifierReleasePolicy.didReleaseAllTriggerModifiers(
            currentModifiers: event.modifierFlags,
            triggerModifiers: settings.requiredModifiers
        ),
              let command = inputLatch.releasePending(source: .swipe)
        else {
            return nil
        }

        return LatchedInputCommand(command: command, source: .swipe)
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

    private func updateContextPlan(_ mutate: (inout ContextPlan) -> Void) {
        var plan = settings.contextPlan
        mutate(&plan)

        guard plan != settings.contextPlan else {
            return
        }

        settings.contextPlan = plan
        settingsStore.save(settings)
        diagnostics = currentDiagnostics()
        refreshLocalizedStatus()
    }

    private func selectedTargetProvider() -> CGDisplaySwitchTargetProvider {
        CGDisplaySwitchTargetProvider(includedStableIDs: selectedDisplayIDs)
    }

    private func targetDisplayIDs(for intent: ContextSwitchIntent) -> Set<String> {
        guard settings.contextPlan.isPinned,
              intent.targetContext != nil,
              !intent.targetDisplayIDs.isEmpty
        else {
            return selectedDisplayIDs
        }

        let liveDisplayIDs = Set(displayLayout.displays.map(\.id))
        return Set(intent.targetDisplayIDs).intersection(liveDisplayIDs)
    }

    private func hiddenExecutorForSelectedDisplays() -> HiddenCursorDisplaySpaceCommandExecutor {
        HiddenCursorDisplaySpaceCommandExecutor(
            targetProvider: selectedTargetProvider()
        )
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

    private static func inputHint(for settings: AppSettings, strings: SBSStrings) -> String {
        "\(strings.horizontalScrollGesture(settings.requiredModifiers)) · \(strings.contextKeyboardLayerHint)"
    }
}

private struct ProductRootView: View {
    @ObservedObject var model: SidebyAppModel
    let updater: SidebyUpdater
    @Binding var didCompleteOnboarding: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if didCompleteOnboarding {
            ProductMenuOnlySettingsRedirectView(
                model: model,
                openMenuPanel: {
                    openMenuPanelForPresentationTrigger(.settingsRedirect)
                }
            )
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
        didCompleteOnboarding = true
        openMenuPanelForPresentationTrigger(.onboardingCompletion)
    }

    private func openMenuPanelForPresentationTrigger(
        _ trigger: FloatingMenuPanelPresentationTrigger,
        initialExpansion: FloatingMenuSectionExpansion = .default
    ) {
        let sourceWindow: NSWindow?
        switch FloatingMenuPanelPresentationPolicy.anchor(for: trigger) {
        case .sourceWindow:
            sourceWindow = currentMainWindow
        case .menuBarFallback:
            sourceWindow = nil
        }

        openMenuPanel(from: sourceWindow, initialExpansion: initialExpansion)
    }

    private func openMenuPanel(
        from sourceWindow: NSWindow? = NSApplication.shared.keyWindow,
        initialExpansion: FloatingMenuSectionExpansion = .default
    ) {
        ProductFloatingMenuPanelController.shared.present(
            from: sourceWindow,
            model: model,
            actions: menuActions,
            initialExpansion: initialExpansion
        )
        ProductMainWindowPresenter.hideIfVisible()
    }

    private var currentMainWindow: NSWindow? {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first { window in
                window.identifier == ProductMainWindowPresenter.windowIdentifier
                    || window.title == "Sideby"
            }
    }

    private var menuActions: ProductMenuPanelActions {
        ProductMenuPanelActions(
            updater: updater,
            openSettings: {
                openMenuPanel(initialExpansion: .opening(.overview))
            },
            replayOnboarding: {
                ProductFloatingMenuPanelController.shared.close()
                model.prepareMiniOnboarding()
                didCompleteOnboarding = false
                openWindow(id: "main")
                ProductMainWindowPresenter.present()
            },
            customizeShortcuts: {
                openMenuPanel(initialExpansion: .opening(.input))
            },
            quit: {
                NSApplication.shared.terminate(nil)
            }
        )
    }
}

private struct ProductMenuOnlySettingsRedirectView: View {
    @ObservedObject var model: SidebyAppModel
    let openMenuPanel: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            SidebyMenuBarIcon()
                .frame(width: 32, height: 26)
            Text(model.strings.settings)
                .font(.title3.weight(.semibold))
            Button(model.strings.openSettings, action: openMenuPanel)
                .pointingHandCursor()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.async {
                openMenuPanel()
            }
        }
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

private extension FloatingMenuSectionExpansion {
    static func opening(_ destination: SettingsAccessDestination) -> FloatingMenuSectionExpansion {
        var expansion = FloatingMenuSectionExpansion.default
        switch destination {
        case .overview:
            break
        case .input:
            expansion.showsInput = true
        }
        return expansion
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
            .pointingHandCursor()
            Text(model.loginItemStatus)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MenuBarControlView: View {
    @ObservedObject var model: SidebyAppModel
    let updater: SidebyUpdater
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

    private func openFloatingMenu(
        from sourceWindow: NSWindow?,
        initialExpansion: FloatingMenuSectionExpansion = .default
    ) {
        guard !didOpenFloatingMenu else {
            return
        }

        didOpenFloatingMenu = true
        ProductFloatingMenuPanelController.shared.toggle(
            from: sourceWindow,
            model: model,
            actions: menuActions,
            initialExpansion: initialExpansion
        )
        closeMenuBarWindow()
    }

    private func openMainWindow() {
        openWindow(id: "main")
        closeMenuBarWindow()
        ProductMainWindowPresenter.present()
    }

    private func openMenuPanel(opening destination: SettingsAccessDestination) {
        ProductFloatingMenuPanelController.shared.present(
            from: menuWindow,
            model: model,
            actions: menuActions,
            initialExpansion: .opening(destination)
        )
        ProductMainWindowPresenter.hideIfVisible()
        closeMenuBarWindow()
    }

    private func handleMenuRoute(_ route: SettingsAccessRoute) {
        switch route {
        case .menuPanel(let destination):
            openMenuPanel(opening: destination)
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
            updater: updater,
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
    let updater: SidebyUpdater
    let openSettings: () -> Void
    let replayOnboarding: () -> Void
    let customizeShortcuts: () -> Void
    let quit: () -> Void
}

private struct ProductMenuContentView: View {
    @ObservedObject var model: SidebyAppModel
    let actions: ProductMenuPanelActions
    @ObservedObject private var updater: SidebyUpdater
    @State private var expansion = FloatingMenuSectionExpansion.default

    init(
        model: SidebyAppModel,
        actions: ProductMenuPanelActions,
        initialExpansion: FloatingMenuSectionExpansion = .default
    ) {
        self.model = model
        self.actions = actions
        self._updater = ObservedObject(wrappedValue: actions.updater)
        self._expansion = State(initialValue: initialExpansion)
    }

    var body: some View {
        let strings = model.strings
        let diagnosticsSection = FloatingMenuDiagnosticsContent.section(
            for: model.diagnostics,
            strings: strings
        )

        VStack(alignment: .leading, spacing: 8) {
            MoveTargetsView(
                model: model,
                showsSummary: true,
                wrapsInGroupBox: true
            )

            contextsSection

            if let diagnosticsSection {
                ProductMenuDiagnosticsView(section: diagnosticsSection)
            }

            ForEach(FloatingMenuCollapsibleSectionContent.defaultItems, id: \.self) { section in
                disclosureSection(section, strings: strings)
            }

            menuActions
        }
    }

    private var contextsSection: some View {
        GroupBox(model.strings.contextPlanner) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(
                    Array(FloatingMenuContextSectionContent.defaultItems.enumerated()),
                    id: \.offset
                ) { index, item in
                    if index > 0 {
                        Divider()
                    }

                    switch item {
                    case .captureControls:
                        ContextCaptureControlsView(model: model, wrapsInGroupBox: false)
                    case .matrix:
                        ContextsView(
                            model: model,
                            wrapsInGroupBox: false,
                            showsHelp: false,
                            isCompact: true
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { model.settings },
            set: { model.updateSettings($0) }
        )
    }

    @ViewBuilder
    private func disclosureSection(
        _ section: FloatingMenuCollapsibleSection,
        strings: SBSStrings
    ) -> some View {
        switch section {
        case .input:
            CompactDisclosureSection(
                title: strings.input,
                systemImage: "keyboard",
                isExpanded: expansionBinding(for: .input)
            ) {
                ShortcutSettingsView(
                    settings: settingsBinding,
                    showsInputExperiment: false
                )
            }
        case .permissions:
            CompactDisclosureSection(
                title: strings.permissions,
                systemImage: "lock",
                isExpanded: expansionBinding(for: .permissions)
            ) {
                PrivacyPermissionsView(model: model)
            }
        case .general:
            CompactDisclosureSection(
                title: strings.general,
                systemImage: "gearshape",
                isExpanded: expansionBinding(for: .general)
            ) {
                generalSettings
            }
        }
    }

    private func expansionBinding(for section: FloatingMenuCollapsibleSection) -> Binding<Bool> {
        Binding(
            get: { expansion.isExpanded(section) },
            set: { expansion.set(section, isExpanded: $0) }
        )
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            LanguageSettingsView(settings: settingsBinding)

            Divider()

            LaunchAtLoginControls(model: model)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    generalButtons
                }

                VStack(alignment: .leading, spacing: 6) {
                    generalButtons
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generalButtons: some View {
        ForEach(FloatingMenuGeneralActionContent.defaultItems, id: \.self) { item in
            generalButton(for: item)
        }
    }

    @ViewBuilder
    private func generalButton(for item: FloatingMenuGeneralActionItem) -> some View {
        switch item {
        case .replayOnboarding:
            Button(model.strings.replayOnboarding, action: actions.replayOnboarding)
                .pointingHandCursor()
        case .refresh:
            Button(model.strings.refresh) {
                model.refresh()
            }
            .pointingHandCursor()
        case .checkForUpdates:
            Button(model.strings.checkForUpdates) {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
            .pointingHandCursor()
        }
    }

    private var menuActions: some View {
        Button(model.strings.quit, action: actions.quit)
            .pointingHandCursor()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .font(.caption)
    }
}

private struct ProductMenuDiagnosticsView: View {
    let section: FloatingMenuDiagnosticsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(section.items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Divider()
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: systemImage(for: item.severity))
                        .foregroundStyle(tint(for: item.severity))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        Text(item.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func systemImage(for severity: DiagnosticSeverity) -> String {
        switch severity {
        case .info:
            "info.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .blocker:
            "xmark.octagon.fill"
        }
    }

    private func tint(for severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .info:
            .blue
        case .warning:
            .orange
        case .blocker:
            .red
        }
    }
}

private struct CompactDisclosureSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .pointingHandCursor()

            if isExpanded {
                content()
                    .padding(.top, 8)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    private var pendingInitialExpansion: FloatingMenuSectionExpansion = .default
    private var didObserveSwitching = false

    private init() {}

    func toggle(
        from sourceWindow: NSWindow?,
        model: SidebyAppModel,
        actions: ProductMenuPanelActions,
        initialExpansion: FloatingMenuSectionExpansion = .default
    ) {
        if panel?.isVisible == true {
            close()
            return
        }

        present(
            from: sourceWindow,
            model: model,
            actions: actions,
            initialExpansion: initialExpansion
        )
    }

    func present(
        from sourceWindow: NSWindow?,
        model: SidebyAppModel,
        actions: ProductMenuPanelActions,
        initialExpansion: FloatingMenuSectionExpansion = .default
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
                    initialExpansion: initialExpansion,
                    alreadySwitching: true
                )
            }
        }

        show(
            model: model,
            relocation: relocation,
            actions: actions,
            initialExpansion: initialExpansion
        )
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
        initialExpansion: FloatingMenuSectionExpansion,
        alreadySwitching: Bool = false
    ) {
        pendingRelocation = ProductMenuBarWindowRelocation.capture(window: sourceWindow)
            ?? ProductMenuBarWindowRelocation.fallback()
        pendingModel = model
        pendingActions = actions
        pendingInitialExpansion = initialExpansion
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

        let initialExpansion = pendingInitialExpansion
        clearPendingReopen()
        switchObserver = nil
        show(
            model: model,
            relocation: relocation,
            actions: actions,
            initialExpansion: initialExpansion
        )
    }

    private func clearPendingReopen() {
        showWorkItem?.cancel()
        showWorkItem = nil
        pendingRelocation = nil
        pendingModel = nil
        pendingActions = nil
        pendingInitialExpansion = .default
        didObserveSwitching = false
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func show(
        model: SidebyAppModel,
        relocation: ProductMenuBarWindowRelocation,
        actions: ProductMenuPanelActions,
        initialExpansion: FloatingMenuSectionExpansion
    ) {
        let isNewPanel = panel == nil
        let panel = panel ?? makePanel()
        let capturedExistingContentSize = isNewPanel ? nil : panel.contentView?.bounds.size
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
                        actions: actions,
                        initialExpansion: initialExpansion
                    )
                },
                actions: ProductMenuPanelActions(
                    updater: actions.updater,
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
                ),
                initialExpansion: initialExpansion
            )
        )
        applyContentSize(
            to: panel,
            relocation: relocation,
            isNewPanel: isNewPanel,
            capturedExistingContentSize: capturedExistingContentSize
        )
        position(panel, using: relocation)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = DismissibleFloatingPanel(
            contentRect: NSRect(origin: .zero, size: FloatingMenuPanelLayout.defaultSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
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
        panel.contentMinSize = FloatingMenuPanelLayout.minimumSize
        panel.collectionBehavior.insert([
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ])
        return panel
    }

    private func applyContentSize(
        to panel: NSPanel,
        relocation: ProductMenuBarWindowRelocation,
        isNewPanel: Bool,
        capturedExistingContentSize: NSSize?
    ) {
        let visibleFrame = ProductMenuBarWindowConfigurator.targetScreen(for: relocation)?.visibleFrame
        let currentSize = panel.contentView?.bounds.size
        let contentSize = FloatingMenuPanelLayout.presentationContentSize(
            capturedExistingContentSize: capturedExistingContentSize,
            currentContentSize: currentSize,
            isNewPanel: isNewPanel,
            visibleFrame: visibleFrame
        )
        panel.setContentSize(contentSize)
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
    let initialExpansion: FloatingMenuSectionExpansion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProductPinnedMenuControlsView(
                model: model,
                onSwitchQueued: onSwitchQueued
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
            .zIndex(1)

            ScrollView(.vertical) {
                ProductMenuContentView(
                    model: model,
                    actions: actions,
                    initialExpansion: initialExpansion
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(
            minWidth: FloatingMenuPanelLayout.minimumSize.width,
            maxWidth: .infinity,
            minHeight: FloatingMenuPanelLayout.minimumSize.height,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ProductPinnedMenuControlsView: View {
    @ObservedObject var model: SidebyAppModel
    let onSwitchQueued: (SwitchCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(FloatingMenuPinnedHeaderContent.defaultItems, id: \.self) { item in
                pinnedItemView(item)
            }
        }
    }

    @ViewBuilder
    private func pinnedItemView(_ item: FloatingMenuPinnedHeaderItem) -> some View {
        switch item {
        case .masterControl:
            MenuBarMasterControl(model: model)
        case .navigationControls:
            ScreenSwitchingControls(
                model: model,
                visibleItems: FloatingMenuSwitchSectionContent.pinnedItems,
                showsTargetSummary: false,
                showsHint: false,
                onSwitchQueued: onSwitchQueued
            )
        }
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

private struct MenuBarMasterControl: View {
    @ObservedObject var model: SidebyAppModel

    var body: some View {
        let strings = model.strings

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
            .pointingHandCursor()
        }
    }
}

private struct ContextCaptureControlsView: View {
    @ObservedObject var model: SidebyAppModel
    var wrapsInGroupBox = true

    var body: some View {
        let strings = model.strings

        if wrapsInGroupBox {
            GroupBox(strings.captureContexts) {
                content(strings: strings)
            }
        } else {
            content(strings: strings)
        }
    }

    private func content(strings: SBSStrings) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { model.settings.contextPlan.isPinned },
                    set: { model.setContextPinning($0) }
                )
            ) {
                Text(strings.pinContexts)
            }
            .toggleStyle(.checkbox)
            .pointingHandCursor()

            HStack(alignment: .center, spacing: 8) {
                if model.contextCaptureSession == nil {
                    Button {
                        model.startContextCapture()
                    } label: {
                        Label(strings.captureContexts, systemImage: "rectangle.stack")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!FloatingMenuContextCaptureAvailability.canStart(
                        displayCount: model.displayLayout.displayCount,
                        isSwitching: model.isSwitching,
                        isCapturing: model.contextCaptureSession != nil
                    ))
                    .pointingHandCursor(FloatingMenuContextCaptureAvailability.canStart(
                        displayCount: model.displayLayout.displayCount,
                        isSwitching: model.isSwitching,
                        isCapturing: model.contextCaptureSession != nil
                    ))
                } else {
                    Button(strings.stopCapture) {
                        model.stopContextCapture()
                    }
                    .buttonStyle(.bordered)
                    .pointingHandCursor()
                }

                Button(strings.alignDisplays) {
                    model.alignDisplaysToCurrentSpace()
                }
                .buttonStyle(.bordered)
                .disabled(model.isSwitching || model.contextCaptureSession != nil)
                .pointingHandCursor()

            }

            if let contextCaptureStatus = model.contextCaptureStatus {
                Text(contextCaptureStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let session = model.contextCaptureSession {
                ProgressView(value: ContextCaptureStatusDisplay.progressValue(session: session))
                    .progressViewStyle(.linear)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ContextsView: View {
    @ObservedObject var model: SidebyAppModel
    var wrapsInGroupBox = true
    var showsHelp = true
    var isCompact = false
    @State private var displayColumnWidthOverride: CGFloat?
    @State private var displayColumnResizeStartWidth: CGFloat?
    @State private var contextHeaderHeight: CGFloat = 0
    @State private var pendingContextDeletion: ContextDefinition?

    private var defaultDisplayColumnWidth: CGFloat {
        FloatingMenuContextMatrixLayout.displayColumnWidth(isCompact: isCompact)
    }

    private var displayColumnWidth: CGFloat {
        FloatingMenuContextMatrixLayout.clampedDisplayColumnWidth(
            displayColumnWidthOverride ?? defaultDisplayColumnWidth,
            isCompact: isCompact
        )
    }

    private var contextColumnWidth: CGFloat {
        FloatingMenuContextMatrixLayout.contextColumnWidth(isCompact: isCompact)
    }

    private var usesDenseContextColumns: Bool {
        isCompact && contextColumnWidth <= 72
    }

    private var rowHeight: CGFloat { isCompact ? 32 : 36 }

    var body: some View {
        let strings = model.strings
        let matrix = ContextMatrixModel.matrix(
            plan: model.settings.contextPlan,
            displays: model.displayLayout.displays,
            displayRowOrder: model.settings.displayRowOrder
        )

        if wrapsInGroupBox {
            GroupBox(strings.contextPlanner) {
                content(strings: strings, matrix: matrix)
            }
        } else {
            content(strings: strings, matrix: matrix)
        }
    }

    private func content(strings: SBSStrings, matrix: ContextMatrix) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHelp {
                Text(strings.contextPlannerHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            contextEditToolbar(strings: strings, matrix: matrix)

            HStack(alignment: .top, spacing: 8) {
                displayColumn(rows: matrix.rows)
                    .overlay(alignment: .trailing) {
                        displayColumnResizeHandle(rowCount: matrix.rows.count)
                            .offset(x: 5)
                    }

                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(matrix.columns) { column in
                                contextHeader(column)
                            }
                        }

                        ForEach(matrix.rows) { row in
                            HStack(spacing: 8) {
                                ForEach(row.cells) { cell in
                                    membershipCell(cell)
                                }
                            }
                            .frame(height: rowHeight)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
            .onPreferenceChange(FloatingMenuContextMatrixHeaderHeightPreferenceKey.self) { height in
                guard abs(contextHeaderHeight - height) > 0.5 else {
                    return
                }
                contextHeaderHeight = height
            }
        }
        .confirmationDialog(
            pendingContextDeletion.map { strings.deleteContextConfirmationTitle($0.name) }
                ?? strings.deleteContext,
            isPresented: Binding(
                get: { pendingContextDeletion != nil },
                set: { if !$0 { pendingContextDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(strings.deleteContext, role: .destructive) {
                if let contextID = pendingContextDeletion?.id {
                    _ = model.deleteContext(contextID: contextID)
                }
                pendingContextDeletion = nil
            }
            Button(strings.cancel, role: .cancel) {
                pendingContextDeletion = nil
            }
        } message: {
            Text(strings.deleteContextConfirmationMessage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contextEditToolbar(strings: SBSStrings, matrix: ContextMatrix) -> some View {
        HStack(spacing: 8) {
            Button {
                model.addEmptyContext()
            } label: {
                Label(strings.addContext, systemImage: "plus")
            }
            .disabled(!model.canAddContext)

            Menu {
                ForEach(matrix.columns) { column in
                    Button("\(strings.contextOrder(column.order)) · \(column.name)") {
                        requestContextDeletion(column.id)
                    }
                }
            } label: {
                Label(strings.deleteContext, systemImage: "minus")
            }
            .disabled(!model.canDeleteContext)

            Spacer(minLength: 0)
        }
    }

    private func requestContextDeletion(_ contextID: String) {
        guard let context = model.settings.contextPlan.contexts.first(where: { $0.id == contextID }) else {
            return
        }
        if model.contextDeletionRequiresConfirmation(contextID: contextID) {
            pendingContextDeletion = context
        } else {
            _ = model.deleteContext(contextID: contextID)
        }
    }

    private func displayColumnResizeHandle(rowCount: Int) -> some View {
        let rowGaps = max(rowCount - 1, 0)
        let height = contextHeaderHeight
            + CGFloat(rowCount) * rowHeight
            + CGFloat(rowGaps) * 8

        return ZStack {
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 3, height: max(height, rowHeight))
        }
        .frame(width: 10, height: max(height, rowHeight))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if displayColumnResizeStartWidth == nil {
                        displayColumnResizeStartWidth = displayColumnWidth
                    }
                    let startWidth = displayColumnResizeStartWidth ?? displayColumnWidth
                    displayColumnWidthOverride = FloatingMenuContextMatrixLayout.clampedDisplayColumnWidth(
                        startWidth + value.translation.width,
                        isCompact: isCompact
                    )
                }
                .onEnded { _ in
                    displayColumnResizeStartWidth = nil
                }
        )
        .help("Drag to resize display names")
        .pointingHandCursor()
    }

    private func displayColumn(rows: [ContextMatrixRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            matrixAxisHeader(strings: model.strings)

            ForEach(rows) { row in
                displayNameCell(row)
                    .onDrag {
                        NSItemProvider(
                            object: ContextMatrixDisplayRowDragPayload(
                                displayID: row.displayID
                            ).rawValue as NSString
                        )
                    }
                    .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                        handleDisplayRowDrop(providers: providers, targetDisplayID: row.displayID)
                    }
            }
        }
    }

    private func matrixAxisHeader(strings: SBSStrings) -> some View {
        ZStack {
            Text("\(axisLabel(FloatingMenuContextMatrixAxisHeaderContent.topTrailing, strings: strings)) →")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            Text("\(axisLabel(FloatingMenuContextMatrixAxisHeaderContent.bottomLeading, strings: strings)) ↓")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(
            width: displayColumnWidth,
            height: contextHeaderHeight > 0 ? contextHeaderHeight : nil
        )
    }

    private func axisLabel(
        _ axis: FloatingMenuContextMatrixAxis,
        strings: SBSStrings
    ) -> String {
        switch axis {
        case .contexts:
            strings.contextPlanner
        case .displays:
            strings.displays
        }
    }

    private func displayNameCell(_ row: ContextMatrixRow) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(row.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: rowHeight, alignment: .center)
                .padding(.trailing, 10)
        }
        .frame(width: displayColumnWidth, height: rowHeight, alignment: .leading)
        .clipped()
        .help(row.displayName)
    }

    private func contextHeader(_ column: ContextMatrixColumn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: usesDenseContextColumns ? 4 : 6) {
                Text(usesDenseContextColumns ? "C\(column.order)" : model.strings.contextOrder(column.order))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                if let statusTitle = contextStatusTitle(for: column) {
                    if usesDenseContextColumns {
                        Circle()
                            .fill(contextStatusColor(for: column.state))
                            .frame(width: 6, height: 6)
                            .help(statusTitle)
                    } else {
                        Text(statusTitle)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(contextStatusColor(for: column.state))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(contextStatusColor(for: column.state).opacity(0.14))
                            )
                    }
                }

                Spacer(minLength: 2)

                goToContextButton(column)
            }

            TextField(
                model.strings.contextLabelPlaceholder,
                text: Binding(
                    get: {
                        model.settings.contextPlan.contexts
                            .first { $0.id == column.id }?
                            .name ?? column.name
                    },
                    set: { model.setContextName(contextID: column.id, name: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(usesDenseContextColumns ? .system(size: 10, weight: .semibold) : .caption.weight(.semibold))
            .lineLimit(usesDenseContextColumns ? 1 : FloatingMenuContextMatrixLayout.nameLineLimit(isCompact: isCompact))
            .help(column.name)
        }
        .frame(width: contextColumnWidth, alignment: .topLeading)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FloatingMenuContextMatrixHeaderHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    private func goToContextButton(_ column: ContextMatrixColumn) -> some View {
        Button {
            model.activateContext(contextID: column.id)
        } label: {
            Text(model.strings.goToContext)
                .font(.system(size: usesDenseContextColumns ? 9 : 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .padding(.horizontal, usesDenseContextColumns ? 5 : 7)
                .frame(height: usesDenseContextColumns ? 16 : 20)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(model.strings.goToContext)
        .accessibilityLabel(model.strings.goToContext)
        .disabled(!model.canActivateContext)
        .pointingHandCursor(model.canActivateContext)
    }

    private func contextStatusTitle(for column: ContextMatrixColumn) -> String? {
        FloatingMenuContextMatrixLayout.statusTitle(
            for: column.state,
            isCompact: true,
            strings: model.strings
        )
    }

    private func contextStatusColor(for state: ContextRowState) -> Color {
        state == .needsSync ? .orange : Color.accentColor
    }

    @ViewBuilder
    private func membershipCell(_ cell: ContextMatrixCell) -> some View {
        if let spaceIndex = cell.spaceIndex {
            membershipCellContent(cell)
                .onDrag {
                    NSItemProvider(
                        object: ContextMatrixSpaceDragPayload(
                            displayID: cell.displayID,
                            spaceIndex: spaceIndex
                        ).rawValue as NSString
                    )
                }
                .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                    handleSpaceDrop(providers: providers, target: cell)
                }
        } else {
            membershipCellContent(cell)
                .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                    handleSpaceDrop(providers: providers, target: cell)
                }
        }
    }

    private func membershipCellContent(_ cell: ContextMatrixCell) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(cell.isIncluded ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))

            if let spaceIndex = cell.spaceIndex {
                Text(model.strings.spaceNumber(spaceIndex + 1))
                    .font(usesDenseContextColumns ? .system(size: 9, weight: .semibold) : .caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(usesDenseContextColumns ? 0.55 : 0.72)
                    .padding(.horizontal, usesDenseContextColumns ? 2 : 6)
            } else {
                Text("-")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: contextColumnWidth, height: rowHeight)
        .accessibilityLabel(cell.spaceIndex.map { model.strings.spaceNumber($0 + 1) } ?? "Not included")
    }

    private func handleSpaceDrop(providers: [NSItemProvider], target: ContextMatrixCell) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            let rawValue: String?
            if let text = item as? String {
                rawValue = text
            } else if let text = item as? NSString {
                rawValue = text as String
            } else if let data = item as? Data {
                rawValue = String(data: data, encoding: .utf8)
            } else {
                rawValue = nil
            }

            guard let rawValue,
                  let payload = ContextMatrixSpaceDragPayload(rawValue: rawValue),
                  payload.displayID == target.displayID
            else {
                return
            }

            DispatchQueue.main.async {
                model.moveDisplaySpace(
                    displayID: payload.displayID,
                    spaceIndex: payload.spaceIndex,
                    toContextID: target.contextID
                )
            }
        }
        return true
    }

    private func handleDisplayRowDrop(providers: [NSItemProvider], targetDisplayID: String) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            let rawValue: String?
            if let text = item as? String {
                rawValue = text
            } else if let text = item as? NSString {
                rawValue = text as String
            } else if let data = item as? Data {
                rawValue = String(data: data, encoding: .utf8)
            } else {
                rawValue = nil
            }

            guard let rawValue,
                  let payload = ContextMatrixDisplayRowDragPayload(rawValue: rawValue),
                  payload.displayID != targetDisplayID
            else {
                return
            }

            DispatchQueue.main.async {
                model.moveContextDisplayRow(
                    displayID: payload.displayID,
                    to: targetDisplayID
                )
            }
        }
        return true
    }
}

private struct ContextMatrixSpaceDragPayload: Equatable {
    let displayID: String
    let spaceIndex: Int

    var rawValue: String {
        "\(displayID)|\(spaceIndex)"
    }

    init(displayID: String, spaceIndex: Int) {
        self.displayID = displayID
        self.spaceIndex = spaceIndex
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let spaceIndex = Int(parts[1]),
              spaceIndex >= 0
        else {
            return nil
        }
        self.displayID = parts[0]
        self.spaceIndex = spaceIndex
    }
}

private struct ContextMatrixDisplayRowDragPayload: Equatable {
    private static let prefix = "display-row"

    let displayID: String

    var rawValue: String {
        "\(Self.prefix)|\(displayID)"
    }

    init(displayID: String) {
        self.displayID = displayID
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              parts[0] == Self.prefix,
              !parts[1].isEmpty
        else {
            return nil
        }
        self.displayID = parts[1]
    }
}

private struct MoveTargetsView: View {
    @ObservedObject var model: SidebyAppModel
    var showsSummary = true
    var wrapsInGroupBox = true

    var body: some View {
        let strings = model.strings

        if wrapsInGroupBox {
            GroupBox(strings.moveTargets) {
                content(strings: strings)
            }
        } else {
            content(strings: strings)
        }
    }

    private func content(strings: SBSStrings) -> some View {
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
                .pointingHandCursor()

                if showsSummary {
                    Text(model.selectedDisplaySummary)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .frame(height: FloatingMenuDisplayArrangementLayout.stageHeight)
            } else {
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(displays, id: \.id) { display in
                        displayButton(for: display, size: fallbackSize(for: display))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func arrangedDisplays(in size: CGSize) -> some View {
        let displaysByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        let placements = FloatingMenuDisplayArrangementLayout.placements(
            for: displays.compactMap { display in
                guard let frame = display.frame else {
                    return nil
                }
                return FloatingMenuDisplayLayoutInput(displayID: display.id, frame: frame)
            },
            in: size
        )

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            ForEach(placements, id: \.displayID) { placement in
                if let display = displaysByID[placement.displayID] {
                    displayButton(
                        for: display,
                        size: placement.frame.size
                    )
                    .position(
                        x: placement.frame.midX,
                        y: placement.frame.midY
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
        .pointingHandCursor()
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .padding(-4)
        }
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.18) : .black.opacity(0.14),
            radius: isSelected ? 5 : 3,
            x: 0,
            y: isSelected ? 2 : 1
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
                        .pointingHandCursor()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(strings.enablePermissions) {
                            model.requestPermissions()
                        }
                        .pointingHandCursor()
                        Button(strings.accessibilitySettings) {
                            model.openAccessibilitySettings()
                        }
                        .pointingHandCursor()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScreenSwitchingControls: View {
    @ObservedObject var model: SidebyAppModel
    var visibleItems = FloatingMenuSwitchSectionContent.defaultItems
    var showsTargetSummary = true
    var showsHint = true
    var onSwitchQueued: (SwitchCommand) -> Void = { _ in }

    var body: some View {
        let strings = model.strings

        VStack(alignment: .leading, spacing: 10) {
            if visibleItems.contains(.navigationControls) {
                navigationControls(strings: strings)
            }

            if visibleItems.contains(.targetSummary), showsTargetSummary {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text(strings.targets)
                        Text(model.selectedDisplaySummary)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if visibleItems.contains(.hint), showsHint {
                Text(model.isEnabled ? strings.testButtonsUseActivePath : strings.turnOnForTestButtons)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func navigationControls(strings: SBSStrings) -> some View {
        HStack {
            Button("<- \(strings.previous)") {
                if model.switchContext(.previous) {
                    onSwitchQueued(.previous)
                }
            }
            .disabled(!model.isEnabled || model.isSwitching || model.contextCaptureSession != nil)
            .pointingHandCursor(model.isEnabled && !model.isSwitching && model.contextCaptureSession == nil)

            Button("\(strings.next) ->") {
                if model.switchContext(.next) {
                    onSwitchQueued(.next)
                }
            }
            .disabled(!model.isEnabled || model.isSwitching || model.contextCaptureSession != nil)
            .pointingHandCursor(model.isEnabled && !model.isSwitching && model.contextCaptureSession == nil)
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
