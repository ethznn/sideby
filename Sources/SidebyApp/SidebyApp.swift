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
    @StateObject private var model: SidebyAppModel
    @StateObject private var updater: SidebyUpdater
    private let preferences: UserDefaultsProductUIPreferences
    private let windows: ProductWindowCoordinator
    private let menuActions: ProductMenuPanelActions

    init() {
        MenuBarOnlyApplicationPresentation.apply()
        if SingleInstanceGuard.activateExistingApplicationAndReturnShouldTerminate() {
            Thread.sleep(forTimeInterval: 0.1)
            exit(0)
        }
        let model = SidebyAppModel()
        let updater = SidebyUpdater()
        let preferences = UserDefaultsProductUIPreferences(defaults: .standard)
        let navigation = ProductUINavigation(preferences: preferences)
        let presentation = ProductOnboardingPresentation(preferences: preferences)
        // A restored eligibility flag is not evidence that a guide window is visible.
        model.isShowingFirstWorkGuide = false
        model.workspaceGuideIsRecording = false
        let windows = ProductWindowCoordinator(
            navigation: navigation,
            settingsContent: { [model, navigation, updater] window in
                AnyView(ProductSettingsHost(model: model, navigation: navigation, updater: updater,
                    actions: ProductSettingsActions(
                        checkForUpdates: { [weak updater] in updater?.checkForUpdates() },
                        openOnboarding: { [weak window] in window?.showOnboarding(replay: true) },
                        finishAssignmentReview: { [weak window] in window?.returnAfterAssignmentReview() })))
            },
            onboardingContent: { [model, presentation, preferences] window in
                AnyView(ProductOnboardingView(model: model, presentation: presentation, preferences: preferences,
                    actions: ProductOnboardingActions(
                        close: { [weak window] in window?.closeOnboarding() },
                        finishToDaily: { [weak window] in
                            window?.closeOnboarding()
                            window?.presentDaily?()
                        },
                        openInputSettings: { [weak window] in
                            window?.closeOnboarding()
                            window?.showSettings(.init(pane: .input))
                        },
                        openWorkspaceSettings: { [weak window] contextID, displayID in
                            window?.showSettings(.init(pane: .workspaces, contextID: contextID,
                                                      displayID: displayID, returnTo: .onboarding))
                        })))
            },
            closeDaily: { ProductFloatingMenuPanelController.shared.close() },
            refreshState: { [weak model] in model?.refresh() },
            onboardingWillShow: { [weak model, presentation, preferences] replay in
                guard let model else { return }
                model.isShowingFirstWorkGuide = true
                preferences.didDismissOnboarding = false
                presentation.open(replay: replay, facts: ProductOnboardingFacts(model: model))
                model.workspaceGuideIsRecording = ProductGuideRecordingPolicy.shouldRecord(
                    stage: presentation.state.stage, progress: model.firstWorkProgress)
            },
            onboardingWillClose: { [weak model, preferences] in
                model?.dismissFirstWorkGuide()
                preferences.didDismissOnboarding = true
            })
        let actions = ProductMenuPanelActions(route: { [weak windows] request in
            switch ProductApplicationRouting.route(for: request) {
            case .settings(let route): windows?.showSettings(route)
            case .onboarding(let replay): windows?.showOnboarding(replay: replay)
            }
        }, quit: { NSApplication.shared.terminate(nil) })
        windows.presentDaily = { [model, actions] in
            ProductFloatingMenuPanelController.shared.present(from: nil, model: model, actions: actions)
        }
        _model = StateObject(wrappedValue: model)
        _updater = StateObject(wrappedValue: updater)
        self.preferences = preferences
        self.windows = windows
        menuActions = actions
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarControlView(model: model, actions: menuActions)
        } label: {
            ProductMenuBarLabelView(model: model, preferences: preferences, windows: windows)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(DailyRefreshStrings(language: model.settings.language).settings) { windows.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

private struct ProductSettingsHost: View {
    @ObservedObject var model: SidebyAppModel
    @ObservedObject var navigation: ProductUINavigation
    @ObservedObject var updater: SidebyUpdater
    let actions: ProductSettingsActions
    var body: some View {
        ProductSettingsView(model: model, navigation: navigation,
                            canCheckForUpdates: updater.canCheckForUpdates,
                            actions: actions)
    }
}

extension ProductOnboardingFacts {
    @MainActor init(model: SidebyAppModel) {
        let selected = model.selectedDisplayIDs.intersection(model.displayLayout.displays.map(\.id))
        self.init(hasAccessibilityPermission: model.permissionState == .granted,
                  hasSwitchingAccess: model.hasSwitchingAccess, selectedDisplayCount: selected.count,
                  participatingContextIDs: model.settings.contextPlan.contexts.sorted { $0.order < $1.order }
                    .filter { !Set($0.displayIDs).isDisjoint(with: selected)
                        && model.isWorkspaceAssignmentAvailable(contextID: $0.id) }.map(\.id),
                  connectionStatus: model.workspaceConnectionStatus,
                  isBusy: model.isSwitching || model.contextCaptureSession != nil || model.pendingContextCaptureAlignment != nil,
                  isEnabled: model.isEnabled, progress: model.firstWorkProgress)
    }
}

private struct ProductMenuBarLabelView: View {
    @ObservedObject var model: SidebyAppModel
    let preferences: any ProductUIPreferences
    let windows: ProductWindowCoordinator
    @State private var initialGuide = ProductInitialGuidePresentation()

    var body: some View {
        SidebyMenuBarIcon()
            .frame(width: 22, height: 18)
            .accessibilityLabel("Sideby")
            .onAppear {
                if initialGuide.shouldPresent(isRoundTripComplete: model.firstWorkProgress.isComplete,
                                              isDismissed: preferences.didDismissOnboarding) {
                    DispatchQueue.main.async { windows.showOnboarding() }
                }
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
    var displayConfigurationObserver: NSObjectProtocol?

    deinit {
        if let displayConfigurationObserver { NotificationCenter.default.removeObserver(displayConfigurationObserver) }
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

    init() {
        gate = ContextKeyboardExecutionGate()
    }

    mutating func handle(
        _ event: ContextKeyboardShortcutInputEvent,
        contextPlan: ContextPlan,
        isSidebyEnabled: Bool,
        isSwitching: Bool,
        isCapturing: Bool,
        at timestamp: Double,
        previousContextID: String? = nil,
        shortcutSlots: [String: Int]? = nil
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
                isCapturing: isCapturing,
                previousContextID: previousContextID,
                shortcutSlots: shortcutSlots
            )
            switch action {
            case .activate, .move:
                guard gate.reserve(command, at: timestamp),
                      gate.beginExecution(for: command)
                else {
                    return .ignore
                }
                return action
            case .ignore, .showSidebyOff, .showMissingContext:
                return action
            }

        case .released:
            return .ignore
        }
    }

    mutating func finishExecution(at timestamp: Double) {
        gate.finishExecution(at: timestamp)
    }

    private mutating func isBusy(at timestamp: Double) -> Bool {
        _ = timestamp
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
        case .ignore, .showSidebyOff, .showMissingContext:
            return nil
        }
    }
}

@MainActor
private final class ProductContextHUDController {
    static let shared = ProductContextHUDController()

    private var panels: [NSPanel] = []
    private var hideWorkItem: DispatchWorkItem?
    private var presentationGeneration = HUDPresentationGeneration()

    private init() {}

    @discardableResult
    func show(_ state: HUDPresentationState, screen: NSScreen? = NSScreen.main) -> Int {
        show(state, screens: [screen ?? NSScreen.main ?? NSScreen.screens.first].compactMap(\.self))
    }

    @discardableResult
    func show(_ state: HUDPresentationState, displayIDs: Set<String>, displayLayout: DisplayLayout) -> Int {
        let screens = screens(for: displayIDs, displayLayout: displayLayout)
        return show(screenStates: screens.map { ($0, state) }, timing: state)
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
        _ = show(screenStates: screenStates, timing: timing)
    }

    private func show(_ state: HUDPresentationState, screens requestedScreens: [NSScreen]) -> Int {
        show(screenStates: requestedScreens.map { ($0, state) }, timing: state)
    }

    private func show(
        screenStates requestedScreenStates: [(NSScreen, HUDPresentationState)],
        timing: HUDPresentationState
    ) -> Int {
        let generation = presentationGeneration.advance()
        hideWorkItem?.cancel()

        let screenStates = requestedScreenStates.isEmpty
            ? [NSScreen.main ?? NSScreen.screens.first].compactMap(\.self).map { ($0, timing) }
            : requestedScreenStates
        guard !screenStates.isEmpty else {
            return generation
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

        if timing.dismissalMode == .automatic {
            scheduleFadeOut(activePanels, state: timing, generation: generation)
        }

        return generation
    }

    func dismissImmediately(generation: Int) {
        guard presentationGeneration.consumeCurrent(generation) else {
            return
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panels.forEach { panel in
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
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
        return DisplayLayoutMapper.stableID(for: DisplaySnapshot(
            displayID: displayID, name: screen.localizedName,
            isPrimary: CGDisplayIsMain(displayID) != 0, isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
            vendorNumber: CGDisplayVendorNumber(displayID), modelNumber: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID), displayUUID: DisplayLayoutMapper.displayUUID(for: displayID)
        ))
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
final class SidebyAppModel: ObservableObject, SBSOnboardingViewModel {
    private struct DiscardingSettingsStore: SettingsStoring {
        func load() -> AppSettings {
            .default
        }

        func save(_ settings: AppSettings) {
            _ = settings
        }
    }

    @Published var settings: AppSettings
    @Published var displayLayout = DisplayLayout(displays: [])
    @Published var permissionState: PermissionState = .notDetermined
    @Published var postEventAccessGranted = false
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
    @Published private var contextCaptureAlignmentCoordinator = ProductContextCaptureAlignmentCoordinator()
    @Published private(set) var contextDeletionMinimumCount: Int? = nil
    @Published var workspaceConnectionStatus: WorkspaceConnectionStatus = .unconfirmed
    @Published var workspaceObservedDisplays: [InstantCaptureDisplay]?
    var workspaceLatestObservation: WorkspaceLayoutObservation?
    @Published var verifiedCurrentWorkspaceID: String?
    @Published var workspaceRecoveryTargetID: String?
    @Published var workspaceHistory = WorkspaceVisitHistory()
    @Published var firstWorkProgress = WorkspaceFirstRunProgress()
    @Published var isShowingFirstWorkGuide = false
    @Published var workspaceSwitchTargetName: String?
    @Published var lastWorkspaceSwitchSucceeded = false
    var workspaceConnectionSession = WorkspaceConnectionSession()
    var workspaceLastObservedSpaceIDs: [String: [UInt64]] = [:]
    var workspaceLastObservedSpaceKeys: [String: [String]] = [:]
    var workspaceIdentityNeedsReview = false
    var workspaceIsReconciling = false
    @Published var workspaceIdentityBlockedDisplayIDs: Set<String> = []
    @Published var workspaceRebuildBackup: WorkspaceRebuildBackup?
    var workspaceObservationOverride: (() -> WorkspaceLayoutObservation?)?
    var workspaceSpaceIDsOverride: (() -> [String: [UInt64]]?)?
    var workspaceGuideIsRecording = false
    var workspaceConfigurationRevision = 0
    @Published var workspaceSaveDraft: WorkspaceSaveDraft?
    @Published var workspaceSaveMessage: String?
    @Published var workspaceSavedFocusID: String?
    var workspaceSaveController: WorkspaceSaveWindowController?
    var workspaceLegacyRuntimeBookmarks: [String: [String: UInt64]] = [:]
    var workspacePreferences: UserDefaults? = .standard
    @Published var workspaceDesktopNames: [String: [Int: String]] = [:]
    @Published var workspaceDesktopAliases: [String: String] = [:]
    @Published var heldMatrixConfiguration = HeldMatrixConfiguration()
    @Published var heldMatrixShortcutError: String?
    @Published var heldMatrixInputActive = false
    var heldMatrixIsRecording = false
    @Published var heldMatrixSwitchInFlight = false
    var heldMatrixController: HeldWorkspaceMatrixController?
    var workspaceDesktopNameSpaceIDs: [String: [UInt64]] = [:]
    @Published var workspaceNameRefreshCount = 0
    var workspaceNameOrigins: [String: String] = [:]
    var workspaceNameSuggestionProvider: (any SpaceNameSuggestionProviding)? = MacSpaceNameSuggestionProvider()

    var settingsStore: any SettingsStoring = UserDefaultsSettingsStore()
    private let permissionService = AccessibilityPermissionService()
    let displayObserver = MacDisplayObserver()
    private let loginItemService = MacLoginItemService()
    private let setupFlow = V1SetupFlow()
    private let visibleAppSuggestionProvider = MacVisibleAppSuggestionProvider()
    let spaceLayoutReader: any SpaceLayoutReading = SLSSpaceLayoutReader()
    private let contextHUDPolicy = ContextSwitchHUDPolicy()
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
    private var swipeInputSource: GlobalEventTapInputSource?
    private var contextKeyboardInputSource: GlobalContextKeyboardShortcutInputSource?
    private var contextKeyboardCoordinator = ContextKeyboardCommandCoordinator()
    @Published var failedContextKeyboardCommands: [ContextKeyboardCommand] = []
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
    private var contextCaptureInitialIndexes: [String: Int] = [:]
    private var contextCaptureTransitionProgress = ProductCaptureTransitionProgress()
    private var isRestoringContextCapture = false
    private var permissionPollingID = 0
    private var lastScrollStatusUpdate = 0.0
    private var isOnboardingGestureTestActive = false
    private var ignoresExternalSpaceChangesUntil: Date?
    var selectedDisplaySpacesOverride: (() -> [InstantCaptureDisplay]?)?
    private var postEventAccessOverride: Bool?

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
        loadWorkspacePersistence()
        loadFirstWorkProgress()
        startSettingsChangeObserver()
        startExternalSpaceChangeObserver()
        observerTokens.displayConfigurationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.startContextKeyboardInput()
            self.startHeldMatrixInput()
            if self.isEnabled {
                self.resumeEnabledInputIfNeeded()
            }
        }
    }

    init(
        testSettings: AppSettings,
        selectedDisplayIDs: Set<String>,
        selectedDisplaySpaces: @escaping () -> [InstantCaptureDisplay]?,
        postEventAccessGranted: Bool
    ) {
        self.settings = testSettings
        self.settingsStore = DiscardingSettingsStore()
        self.workspacePreferences = nil
        self.workspaceNameSuggestionProvider = nil
        self.selectedDisplayIDs = selectedDisplayIDs
        self.selectedDisplaySpacesOverride = selectedDisplaySpaces
        self.postEventAccessOverride = postEventAccessGranted
        self.isEnabled = true
        self.postEventAccessGranted = postEventAccessGranted
        let strings = SBSStrings(language: testSettings.language)
        self.lastSwitchResult = strings.noSwitchAttempted
        self.inputStatus = strings.sidebyOff
        self.lastInputEvent = Self.inputHint(for: testSettings, strings: strings)
        self.loginItemStatus = strings.startAtLoginStatus(isEnabled: false)
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
        postEventAccessGranted
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

    var pendingContextCaptureAlignment: ProductContextCaptureAlignmentRequest? {
        guard case let .choosing(request) = contextCaptureAlignmentCoordinator.state else {
            return nil
        }
        return request
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
        let snapshots = displayObserver.currentSnapshots()
        let oldSettings = settings
        let oldSelected = selectedDisplayIDs
        _ = DisplayIdentityMigration.migrate(settings: &settings, snapshots: snapshots)
        displayLayout = DisplayLayoutMapper.layout(from: snapshots)
        syncSelectedDisplays(with: displayLayout)
        workspaceConfigurationChanged(from: oldSettings.contextPlan, selectedIDs: oldSelected)
        if settings != oldSettings { settingsStore.save(settings) }
        refreshContextEditAvailability()
        permissionState = permissionService.currentState
        postEventAccessGranted = CGPreflightPostEventAccess()
        loginItemStatus = strings.startAtLoginStatus(isEnabled: loginItemService.isEnabled)
        refreshWorkspaceStatus()
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
        guard !heldMatrixInputActive, workspaceSaveDraft == nil else { return }
        if !isSwitching, contextCaptureSession == nil { refreshWorkspaceStatus() }
        let action = contextKeyboardCoordinator.handle(
            event,
            contextPlan: settings.contextPlan,
            isSidebyEnabled: isEnabled,
            isSwitching: isSwitching,
            isCapturing: contextCaptureSession != nil,
            at: ProcessInfo.processInfo.systemUptime,
            previousContextID: workspaceHistory.previousContextID,
            shortcutSlots: settings.savedWorkspaces.initialized ? settings.savedWorkspaces.shortcutSlots : nil
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
        case .activate, .move:
            guard let execution = ContextKeyboardExecutionResolver.execution(
                for: action,
                contextPlan: settings.contextPlan
            ) else {
                return
            }
            switch execution {
            case .activate(let contextID):
                activateContext(contextID: contextID) { [weak self] _ in
                    self?.finishContextKeyboardExecution()
                }
            case .move(let switchCommand):
                performSwitch(
                    switchCommand,
                    label: "context-keyboard"
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

    func requestSwitchingAccess() {
        permissionRequestFeedback = .switchingAccessRequesting
        NSApplication.shared.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else {
                return
            }

            let didGrantPostEvents = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
            refresh()
            updateSwitchingAccessFeedback(
                postEventsGranted: didGrantPostEvents || postEventAccessGranted
            )
            pollPermissionsForOnboarding()
        }
    }

    private func updateSwitchingAccessFeedback(
        postEventsGranted: Bool
    ) {
        permissionRequestFeedback = PermissionRequestFeedbackResolver()
            .switchingAccessFeedback(
                postEventsGranted: postEventsGranted
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
        showFirstWorkGuide()
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
        guard !isSwitching, contextCaptureSession == nil else { return }
        let previousSelected = selectedDisplayIDs
        settings.displaySelection.setSelected(isSelected, displayID: display.id, name: display.name)
        selectedDisplayIDs = settings.displaySelection.connectedSelectedDisplayIDs(in: displayLayout)
        workspaceConfigurationChanged(from: settings.contextPlan, selectedIDs: previousSelected)
        settingsStore.save(settings)
        refreshContextEditAvailability()
        refreshWorkspaceStatus()
    }

    func selectAllDisplayTargets() {
        guard !isSwitching, contextCaptureSession == nil else { return }
        let previousSelected = selectedDisplayIDs
        settings.displaySelection.selectAllConnected(in: displayLayout)
        selectedDisplayIDs = settings.displaySelection.connectedSelectedDisplayIDs(in: displayLayout)
        workspaceConfigurationChanged(from: settings.contextPlan, selectedIDs: previousSelected)
        settingsStore.save(settings)
        refreshContextEditAvailability()
        refreshWorkspaceStatus()
    }

    var canAddContext: Bool {
        !isSwitching && contextCaptureSession == nil && !settingsStore.hasUnreadableSettings
    }

    var canDeleteContext: Bool { canSaveWorkspace && !settings.contextPlan.contexts.isEmpty }

    func addEmptyContext() { showWorkspaceSave() }

    func contextDeletionRequiresConfirmation(contextID: String) -> Bool {
        ContextEditAction.requiresDeleteConfirmation(
            contextID: contextID,
            contexts: settings.contextPlan.contexts
        )
    }

    @discardableResult
    func deleteContext(contextID: String) -> Bool { deleteSavedWorkspace(contextID) }

    func setContextName(contextID: String, name: String) {
        guard let context = settings.contextPlan.contexts.first(where: { $0.id == contextID }),
              context.name != name else { return }
        updateContextPlan { plan in
            plan.renameContext(id: contextID, name: name)
        }
        rememberWorkspaceNameOrigin(contextID: contextID, automaticName: nil)
    }

    var canActivateContext: Bool {
        workspaceSaveDraft == nil && !settingsStore.hasUnreadableSettings && ContextActivationAvailability.canActivate(
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
        requiresCompleteSelectedLayout: Bool = false,
        recordsWorkspaceVisit: Bool = true,
        requestsPermissions: Bool = true,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        lastWorkspaceSwitchSucceeded = false
        guard workspaceSaveDraft == nil, !settingsStore.hasUnreadableSettings else { completion?(false); return }
        refreshWorkspaceStatus()
        if verifiedCurrentWorkspaceID == contextID {
            completion?(true)
            return
        }
        guard let checkedTarget = settings.contextPlan.contexts.first(where: { $0.id == contextID }),
              unresolvedWorkspaceMembers(checkedTarget).isEmpty else {
            workspaceSaveMessage = saveCopy.missingDesktop
            completion?(false)
            return
        }
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
        guard hasPostEventAccess(command: .next, label: "context", requestsPermissions: requestsPermissions) else {
            completion?(false)
            return
        }

        let hudIntent = ContextSwitchIntent(
            command: .next,
            targetContext: intent.targetContext,
            targetDisplayIDs: intent.targetDisplayIDs,
            diagnostic: intent.diagnostic,
            shouldExecute: intent.shouldExecute
        )
        performContextActivation(
            targetContext: targetContext,
            intent: hudIntent,
            requiresCompleteSelectedLayout: requiresCompleteSelectedLayout,
            recordsWorkspaceVisit: recordsWorkspaceVisit,
            completion: completion
        )
    }

    func moveDisplaySpace(displayID: String, spaceIndex: Int, toContextID: String) {
        guard canAddContext else { return }
        updateContextPlan { plan in
            _ = plan.moveDisplaySpace(
                displayID: displayID,
                spaceIndex: spaceIndex,
                toContextID: toContextID
            )
        }
        refreshWorkspaceStatus()
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
        intent: ContextSwitchIntent,
        requiresCompleteSelectedLayout: Bool,
        recordsWorkspaceVisit: Bool = true,
        completion: (@MainActor @Sendable (Bool) -> Void)?
    ) {
        lastWorkspaceSwitchSucceeded = false
        let decision = ModePolicy().decision(for: settings.mode, inputMethod: .shortcut, runtimeState: runtimeState)
        let modeDiagnostics = DiagnosticRule.evaluate(decision: decision)
        guard decision.isAllowed else {
            diagnostics = modeDiagnostics
            completion?(false)
            return
        }
        let observation = workspaceObservation()
        let displays = observation?.displays
        guard ProductContextActivationLayoutPolicy.isAdmitted(
            displays, selectedDisplayIDs: selectedDisplayIDs,
            requiresCompleteSelectedLayout: requiresCompleteSelectedLayout
        ), let displays else {
            updateContextPlan { $0.markNeedsSync() }
            recordWorkspaceActivation(targetContext, succeeded: false)
            lastSwitchResult = strings.workspaceLayoutUnavailable
            completion?(false)
            return
        }
        // Resolve the saved workspace again after reconciling this exact live
        // observation. A pending Mission Control reorder must not target the old index.
        if let observation { _ = reconcileWorkspaceLayout(observation); applyWorkspaceObservation(observation) }
        guard let targetContext = settings.contextPlan.contexts.first(where: { $0.id == targetContext.id }) else {
            completion?(false)
            return
        }
        let expectedSpaceIDs = observation?.spaceIDsByDisplayID
        guard admitWorkspaceActivation(targetContext, snapshot: expectedSpaceIDs) else {
            completion?(false)
            return
        }
        let readiness = WorkspaceRecoveryState(targetContext: targetContext, selectedDisplayIDs: selectedDisplayIDs, displays: displays)
        guard readiness.canRetry || readiness.isResolved else {
            recordWorkspaceActivation(targetContext, succeeded: false)
            lastSwitchResult = strings.workspaceConnectionReviewMessage
            completion?(false)
            return
        }
        let memberDisplays = displays.filter { selectedDisplayIDs.contains($0.displayID) && targetContext.spaceIndex(for: $0.displayID) != nil }
        let originContextID = settings.contextPlan.contexts.first {
            $0.id == settings.contextPlan.currentContextID && WorkspaceRecoveryState(
                targetContext: $0, selectedDisplayIDs: selectedDisplayIDs, displays: displays
            ).isResolved
        }?.id
        let targetMemberDisplayIDs = Set(memberDisplays.map(\.displayID))
        let moves = ContextDisplayMovePlanner.moves(displays: memberDisplays, targetContext: targetContext)
        workspaceRecoveryTargetID = nil
        workspaceSwitchTargetName = targetContext.name
        ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(30)
        isSwitching = true
        switchSessionID += 1
        let sessionID = switchSessionID
        let configurationRevision = workspaceConfigurationRevision
        let reader = spaceLayoutReader
        let beforeIndexes = Dictionary(uniqueKeysWithValues: memberDisplays.map { ($0.displayID, $0.currentSpaceIndex) })
        let steps = moves.flatMap {
            Self.adjacentSteps(displayID: $0.displayID, currentIndex: $0.currentIndex, targetIndex: $0.targetIndex)
        }
        let request = Self.transitionRequest(beforeIndexes: beforeIndexes, steps: steps)
        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: displayObserver.currentSnapshots(), uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )
        let hudGeneration: Int?
        if !moves.isEmpty, let presentation = contextHUDPolicy.inProgressPresentation(for: intent, executedDisplayIDs: targetMemberDisplayIDs) {
            hudGeneration = ProductContextHUDController.shared.show(presentation.state, displayIDs: presentation.displayIDs, displayLayout: displayLayout)
        } else {
            hudGeneration = nil
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Self.productRunner(
                reader: reader, stableIDsByUUID: mapping,
                includedDisplayIDs: targetMemberDisplayIDs,
                expectedSpaceIDsByDisplayID: expectedSpaceIDs
            ).run(request)
            let didMoveAll: Bool
            if case .success = result { didMoveAll = true } else { didMoveAll = false }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.switchSessionID == sessionID else {
                    completion?(false)
                    return
                }
                let succeeded = self.recordWorkspaceActivation(
                    targetContext, succeeded: didMoveAll, recordsVisit: recordsWorkspaceVisit,
                    expectedConfigurationRevision: configurationRevision, originContextID: originContextID
                )
                if succeeded {
                    self.updateContextPlan { _ = $0.setCurrentContext(id: targetContext.id) }
                    self.diagnostics = modeDiagnostics
                    self.lastSwitchResult = self.strings.workspaceMovedTo(targetContext.name)
                } else {
                    self.updateContextPlan { $0.markNeedsSync() }
                    self.diagnostics = modeDiagnostics
                    self.lastSwitchResult = self.strings.workspaceTransitionFailed(targetContext.name)
                }
                if let hudGeneration { ProductContextHUDController.shared.dismissImmediately(generation: hudGeneration) }
                self.isSwitching = false
                self.ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(0.75)
                self.refreshWorkspaceStatus()
                completion?(succeeded)
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

        activateContext(contextID: target.id, recordsWorkspaceVisit: false)
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
    func selectedDisplaySpaces() -> [InstantCaptureDisplay]? {
        workspaceObservation()?.displays
    }

    nonisolated private static func productIndexes(
        reader: any SpaceLayoutReading,
        stableIDsByUUID: [String: String],
        includedDisplayIDs: Set<String>,
        expectedSpaceIDsByDisplayID: [String: [UInt64]]? = nil
    ) -> [String: Int]? {
        guard let layouts = reader.readLayout() else {
            return nil
        }

        var indexes: [String: Int] = [:]
        for layout in layouts {
            guard includedDisplayIDs.contains(stableIDsByUUID[layout.displayUUID] ?? ""),
                  let stableID = stableIDsByUUID[layout.displayUUID],
                  let index = layout.spaceIDs.firstIndex(of: layout.currentSpaceID)
            else {
                continue
            }
            if let expectedSpaceIDsByDisplayID,
               expectedSpaceIDsByDisplayID[stableID] != layout.spaceIDs { return nil }
            guard indexes[stableID] == nil else { return nil }
            indexes[stableID] = index
        }

        return indexes.count == includedDisplayIDs.count ? indexes : nil
    }

    nonisolated private static func productRunner(
        reader: any SpaceLayoutReading,
        stableIDsByUUID: [String: String],
        includedDisplayIDs: Set<String>,
        expectedSpaceIDsByDisplayID: [String: [UInt64]]? = nil
    ) -> ProductSpaceTransitionRunner {
        ProductSpaceTransitionRunner(
            makeExecutor: { displayID in
                ProductDockSpaceExecutorFactory.make(includedStableIDs: [displayID])
            },
            verifier: .live {
                productIndexes(
                    reader: reader,
                    stableIDsByUUID: stableIDsByUUID,
                    includedDisplayIDs: includedDisplayIDs,
                    expectedSpaceIDsByDisplayID: expectedSpaceIDsByDisplayID
                )
            },
            verifiesBeforePosting: expectedSpaceIDsByDisplayID != nil
        )
    }

    nonisolated private static func adjacentSteps(
        displayID: String,
        currentIndex: Int,
        targetIndex: Int
    ) -> [ProductSpaceTransitionStep] {
        var index = currentIndex
        var steps: [ProductSpaceTransitionStep] = []
        while index != targetIndex {
            let command: SwitchCommand = index < targetIndex ? .next : .previous
            let expectedIndex = index + (command == .next ? 1 : -1)
            steps.append(.init(
                displayID: displayID,
                command: command,
                previousIndex: index,
                expectedIndex: expectedIndex
            ))
            index = expectedIndex
        }
        return steps
    }

    nonisolated private static func transitionRequest(
        beforeIndexes: [String: Int],
        steps: [ProductSpaceTransitionStep]
    ) -> ProductSpaceTransitionRequest {
        ProductSpaceTransitionRequestBuilder.complete(
            beforeIndexes: beforeIndexes,
            steps: steps
        )
    }

    func refreshContextEditAvailability() {
        contextDeletionMinimumCount = ContextEditAction.minimumContextCount(
            selectedDisplayIDs: selectedDisplayIDs,
            readLiveDisplays: selectedDisplaySpaces
        )
    }

    /// Builds the context plan directly from a complete live Space layout.
    func startInstantContextCapture() -> Bool {
        let observation = workspaceObservation()
        guard let instantPlan = ProductInstantContextCaptureStartPolicy.plan(
            for: observation?.displays,
            selectedDisplayIDs: selectedDisplayIDs
        ) else {
            contextCaptureStatus = strings.contextCaptureLayoutUnavailable
            return false
        }

        contextCaptureAlignmentCoordinator.invalidate()
        let previousContexts = settings.contextPlan.contexts
        let hasSavedAssignments = previousContexts.contains { !$0.displayIDs.isEmpty }
        var contexts: [ContextDefinition]
        if instantPlan.isSynchronized {
            let currentOrder = instantPlan.contexts
                .first { $0.id == instantPlan.currentContextID }?.order ?? 1
            contexts = instantPlan.contextsApplyingSuggestedCurrentName(
                suggestedContextName(order: currentOrder)
            )
        } else {
            contexts = instantPlan.contexts
        }

        let capturedOrder = instantPlan.contexts.first { $0.id == instantPlan.currentContextID }?.order
        if hasSavedAssignments {
            contexts = WorkspaceCaptureRefreshPolicy.contexts(
                discovered: contexts, existing: previousContexts, selectedDisplayIDs: selectedDisplayIDs
            )
        }
        let currentID = contexts.first { $0.order == capturedOrder }?.id ?? instantPlan.currentContextID
        // Capture explicitly creates position-based assignments from this layout.
        // Save those assignments against the same identity order, not an older one.
        workspaceIdentityNeedsReview = false
        workspaceIdentityBlockedDisplayIDs = []
        if let observation {
            workspaceLastObservedSpaceKeys.merge(observation.spaceKeysByDisplayID) { _, new in new }
            workspaceLastObservedSpaceIDs.merge(observation.spaceIDsByDisplayID) { _, new in new }
        }
        updateContextPlan { plan in
            plan.replaceContexts(
                contexts,
                currentContextID: currentID
            )
            if !instantPlan.isSynchronized {
                plan.markNeedsSync()
            }
        }
        workspaceConnectionSession.reset()
        workspaceHistory = WorkspaceVisitHistory()
        firstWorkProgress = WorkspaceFirstRunProgress()
        workspaceGuideIsRecording = false
        saveFirstWorkProgress()
        verifiedCurrentWorkspaceID = nil
        workspaceRecoveryTargetID = nil
        applyWorkspaceObservation(observation)
        nameNewWorkspacesUsingDesktopAliases(previousIDs: Set(previousContexts.map(\.id)))
        if instantPlan.isSynchronized {
            contextCaptureStatus = strings.contextCaptureReadySummary(
                count: instantPlan.contexts.count,
                currentName: settings.contextPlan.currentContext?.name ?? "Context 1"
            )
        } else {
            let candidates = ContextCaptureAlignmentPolicy.candidates(
                contexts: contexts,
                selectedDisplayIDs: selectedDisplayIDs
            )
            contextCaptureAlignmentCoordinator.present(candidates: candidates, requestID: UUID())
            contextCaptureStatus = candidates.isEmpty
                ? strings.contextCaptureNoCommonAlignmentTarget
                : strings.contextCaptureReadySummary(
                    count: instantPlan.contexts.count,
                    currentName: settings.contextPlan.currentContext?.name ?? "Context 1"
                )
        }
        Self.contextCaptureLog.notice(
            "instant-capture displays=\(self.selectedDisplayIDs.count, privacy: .public) contexts=\(contexts.count, privacy: .public) synchronized=\(instantPlan.isSynchronized, privacy: .public)"
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

        _ = startInstantContextCapture()
    }

    func cancelContextCaptureAlignment() {
        contextCaptureAlignmentCoordinator.cancel()
    }

    func chooseContextCaptureAlignment(contextID: String) {
        guard case let .activate(contextID, requestID) = contextCaptureAlignmentCoordinator.choose(contextID: contextID) else {
            return
        }
        guard let targetContext = settings.contextPlan.contexts.first(where: { $0.id == contextID }),
              selectedDisplayIDs.isSubset(of: Set(targetContext.displayIDs))
        else {
            contextCaptureAlignmentCoordinator.invalidate()
            contextCaptureStatus = strings.contextCaptureNoCommonAlignmentTarget
            return
        }

        activateContext(contextID: contextID, requiresCompleteSelectedLayout: true, recordsWorkspaceVisit: false) { [weak self] _ in
            self?.contextCaptureAlignmentCoordinator.finish(requestID: requestID)
        }
    }

    func stopContextCapture() {
        guard !isRestoringContextCapture else {
            return
        }
        guard var session = contextCaptureSession else {
            contextCaptureStatus = strings.contextCaptureStopped
            return
        }
        session.stop()
        contextCaptureSession = session
        contextCaptureStatus = ContextCaptureStatusDisplay.statusText(
            session: session,
            strings: strings
        )
        if contextCaptureTransitionProgress.requestStop() == .restore {
            restoreContextCaptureLayout(session: session, commitsDrafts: false)
        }
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

    func visibleContentName(contextID: String) -> String? {
        guard canAddContext, pendingContextCaptureAlignment == nil else { return nil }
        refreshWorkspaceStatus()
        guard verifiedCurrentWorkspaceID == contextID,
              let context = settings.contextPlan.contexts.first(where: { $0.id == contextID }) else { return nil }
        let name = suggestedContextName(order: context.order)
        return name == "Context \(context.order)" ? nil : name
    }

    private func commitContextCapture(
        _ session: ContextCaptureSession,
        restoredIndexes: [String: Int]
    ) {
        guard let contexts = session.completedContextDefinitions,
              case .completed(let fallbackContextID) = session.phase
        else {
            return
        }
        let selection = ProductCaptureCommitSelector.selection(
            contexts: contexts,
            restoredIndexes: restoredIndexes,
            fallbackContextID: fallbackContextID
        )

        updateContextPlan { plan in
            plan.replaceContexts(
                contexts,
                currentContextID: selection.currentContextID
            )
            if selection.needsSync {
                plan.markNeedsSync()
            }
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
                _ = self.clearTerminalContextCaptureIfNeeded(activeSession)
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
            let previousDidChange = ContextCaptureMovementPolicy.didObserveAnyProductMovement(
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
                _ = self.clearTerminalContextCaptureIfNeeded(activeSession)
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
        restoreContextCaptureLayout(session: session, commitsDrafts: true)
    }

    private func clearTerminalContextCaptureIfNeeded(_ session: ContextCaptureSession) -> Bool {
        switch session.phase {
        case .failed, .stopped:
            restoreContextCaptureLayout(session: session, commitsDrafts: false)
            return true
        case .completed:
            finishContextCaptureIfNeeded(session)
            return true
        case .aligning, .capturing:
            return false
        }
    }

    private func restoreContextCaptureLayout(
        session: ContextCaptureSession,
        commitsDrafts: Bool
    ) {
        guard !isRestoringContextCapture else {
            return
        }
        guard let request = ProductSpaceTransitionRequestBuilder.captureRestore(
            initialIndexes: contextCaptureInitialIndexes,
            successfulSteps: contextCaptureTransitionProgress.confirmedSteps
        ), !request.finalExpectedIndexes.isEmpty else {
            finishContextCaptureRestoration(
                session: session,
                commitsDrafts: commitsDrafts,
                restoredIndexes: nil
            )
            return
        }

        isRestoringContextCapture = true
        isSwitching = true
        switchSessionID += 1
        let switchID = switchSessionID
        let captureID = contextCaptureSessionID
        let reader = spaceLayoutReader
        let includedDisplayIDs = Set(request.finalExpectedIndexes.keys)
        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: displayObserver.currentSnapshots(),
            uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Self.productRunner(
                reader: reader,
                stableIDsByUUID: mapping,
                includedDisplayIDs: includedDisplayIDs
            ).run(request)
            let restoredIndexes: [String: Int]?
            if case .success(let stableIndexes) = result,
               stableIndexes == request.finalExpectedIndexes {
                restoredIndexes = stableIndexes
            } else {
                restoredIndexes = nil
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.switchSessionID == switchID,
                      self.contextCaptureSessionID == captureID
                else {
                    return
                }
                self.finishContextCaptureRestoration(
                    session: session,
                    commitsDrafts: commitsDrafts,
                    restoredIndexes: restoredIndexes
                )
            }
        }
    }

    private func finishContextCaptureRestoration(
        session: ContextCaptureSession,
        commitsDrafts: Bool,
        restoredIndexes: [String: Int]?
    ) {
        isSwitching = false
        isRestoringContextCapture = false
        ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(
            Self.contextCaptureCompletionIgnoreInterval
        )

        if let restoredIndexes, commitsDrafts {
            commitContextCapture(
                session,
                restoredIndexes: restoredIndexes
            )
        } else if restoredIndexes == nil {
            updateContextPlan { plan in
                plan.applyFailedCaptureRestoration()
            }
        }

        contextCaptureSession = nil
        contextCaptureActiveDisplayIDs = []
        contextCaptureMemberDisplayIDs = []
        contextCaptureNoMoveStreaks = [:]
        contextCaptureInitialIndexes = [:]
        contextCaptureTransitionProgress = ProductCaptureTransitionProgress()

        if restoredIndexes != nil {
            contextCaptureStatus = ContextCaptureStatusDisplay.statusText(
                session: session,
                currentContextName: commitsDrafts
                    ? settings.contextPlan.currentContext?.name
                    : nil,
                strings: strings
            )
        } else {
            contextCaptureStatus = strings.alignFailed
            lastSwitchResult = strings.alignFailed
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
        applyWorkspaceSettings(savedSettings)
        settingsStore.save(settings)
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

        refreshWorkspaceStatus()
        if verifiedCurrentWorkspaceID == nil {
            updateContextPlan { $0.markNeedsSync() }
            lastSwitchResult = strings.workspaceNotAligned
        }
        diagnostics = currentDiagnostics()
    }

    private func reloadSettingsFromStoreIfChanged() {
        var loadedSettings = settingsStore.load()
        loadedSettings.mode = .shortcut
        guard loadedSettings != settings else {
            return
        }

        applyWorkspaceSettings(loadedSettings)
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
        lastWorkspaceSwitchSucceeded = false
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
        let intent = workspaceKeyboardPlan.switchIntent(for: command)
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
        swipeSource.isPassthroughEnabled = heldMatrixInputActive
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
        let captureDisplays = selectedDisplaySpaces() ?? []
        guard !targetDisplayIDs.isEmpty else {
            isSwitching = false
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
        let relativeRequest = ProductSpaceTransitionRequestBuilder.relative(
                  displays: captureDisplays,
                  targetDisplayIDs: targetDisplayIDs,
                  command: command
              )
        let request: ProductSpaceTransitionRequest
        switch relativeRequest {
        case .request(let builtRequest):
            request = builtRequest
        case .boundary:
            isSwitching = false
            completion(
                AcknowledgedSpaceSwitchResult(
                    command: command,
                    didPost: true,
                    expectedChangeCount: 1,
                    observedChangeCount: 0
                )
            )
            return
        case .failure:
            isSwitching = false
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
        let includedDisplayIDs = Set(captureDisplays.map(\.displayID))
        let reader = spaceLayoutReader
        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: displayObserver.currentSnapshots(),
            uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )
        _ = observerWait
        runCaptureTransitionOperation(
            command: command,
            label: label,
            request: request,
            includedDisplayIDs: includedDisplayIDs,
            reader: reader,
            mapping: mapping,
            switchID: sessionID,
            captureID: contextCaptureSessionID,
            stepIndex: 0,
            currentIndexes: request.beforeIndexes,
            confirmedStepCountBefore: contextCaptureTransitionProgress.confirmedSteps.count,
            completion: completion
        )
    }

    private func runCaptureTransitionOperation(
        command: SwitchCommand,
        label: String,
        request: ProductSpaceTransitionRequest,
        includedDisplayIDs: Set<String>,
        reader: any SpaceLayoutReading,
        mapping: [String: String],
        switchID: Int,
        captureID: Int,
        stepIndex: Int,
        currentIndexes: [String: Int],
        confirmedStepCountBefore: Int,
        completion: @escaping @MainActor @Sendable (AcknowledgedSpaceSwitchResult) -> Void
    ) {
        guard switchSessionID == switchID,
              contextCaptureSessionID == captureID,
              contextCaptureTransitionProgress.beginOperation()
        else {
            return
        }

        let step = request.steps.indices.contains(stepIndex)
            ? request.steps[stepIndex]
            : nil
        let operationRequest = ProductSpaceTransitionRequestBuilder.complete(
            beforeIndexes: currentIndexes,
            steps: step.map { [$0] } ?? []
        )

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let transition = Self.productRunner(
                reader: reader,
                stableIDsByUUID: mapping,
                includedDisplayIDs: includedDisplayIDs
            ).run(operationRequest)
            let stableIndexes: [String: Int]?
            if case .success(let indexes) = transition {
                stableIndexes = indexes
            } else {
                stableIndexes = nil
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.switchSessionID == switchID,
                      self.contextCaptureSessionID == captureID
                else {
                    return
                }

                let directive = self.contextCaptureTransitionProgress.finishOperation(
                    confirmedStep: stableIndexes == nil ? nil : step
                )
                let confirmedCount =
                    self.contextCaptureTransitionProgress.confirmedSteps.count
                    - confirmedStepCountBefore
                let hasMoreSteps = step != nil && stepIndex + 1 < request.steps.count

                if directive == .continueCapture,
                   stableIndexes != nil,
                   hasMoreSteps,
                   let stableIndexes {
                    DispatchQueue.main.async { [weak self] in
                        self?.runCaptureTransitionOperation(
                            command: command,
                            label: label,
                            request: request,
                            includedDisplayIDs: includedDisplayIDs,
                            reader: reader,
                            mapping: mapping,
                            switchID: switchID,
                            captureID: captureID,
                            stepIndex: stepIndex + 1,
                            currentIndexes: stableIndexes,
                            confirmedStepCountBefore: confirmedStepCountBefore,
                            completion: completion
                        )
                    }
                    return
                }

                let didCompleteRequest = stableIndexes != nil
                    && (!hasMoreSteps || directive == .restore)
                let result = AcknowledgedSpaceSwitchResult(
                    command: command,
                    didPost: didCompleteRequest,
                    expectedChangeCount: max(1, request.steps.count),
                    observedChangeCount: confirmedCount
                )
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

                if directive == .restore,
                   let stoppedSession = self.contextCaptureSession {
                    self.restoreContextCaptureLayout(
                        session: stoppedSession,
                        commitsDrafts: false
                    )
                }
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
                    ContextCaptureMovementPolicy.productMovedDisplayIDs(from: observations),
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
        resumeInputAfterCompletion shouldResumeInput: Bool? = nil,
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        lastWorkspaceSwitchSucceeded = false
        guard contextCaptureSession == nil else {
            lastSwitchResult = strings.ignoredSwitchContextCaptureActive(label: label, command: command)
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }
        refreshWorkspaceStatus()
        let intent = workspaceKeyboardPlan.switchIntent(for: command)
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

        if settings.contextPlan.isPinned, let targetContext = intent.targetContext {
            performContextActivation(
                targetContext: targetContext, intent: intent,
                requiresCompleteSelectedLayout: false
            ) { [weak self] success in
                if let shouldResumeInput { self?.finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput) }
                completion?(success)
            }
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
        guard let displays = selectedDisplaySpaces() else {
            isSwitching = false
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }
        let relativeRequest = ProductSpaceTransitionRequestBuilder.relative(
            displays: displays,
            targetDisplayIDs: targetDisplayIDs,
            command: command
        )
        guard case .request(let request) = relativeRequest else {
            isSwitching = false
            if let shouldResumeInput {
                finishLatchedInputSwitch(shouldResumeInput: shouldResumeInput)
            }
            completion?(false)
            return
        }
        let includedDisplayIDs = Set(displays.map(\.displayID))
        let reader = spaceLayoutReader
        let mapping = DisplayLayoutMapper.stableIDsByUUID(
            snapshots: displayObserver.currentSnapshots(),
            uuidForDisplayID: DisplayLayoutMapper.displayUUID(for:)
        )
        let hudGeneration: Int?
        if let presentation = contextHUDPolicy.inProgressPresentation(
            for: intent,
            executedDisplayIDs: targetDisplayIDs
        ) {
            hudGeneration = ProductContextHUDController.shared.show(
                presentation.state,
                displayIDs: presentation.displayIDs,
                displayLayout: displayLayout
            )
        } else {
            hudGeneration = nil
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let decision = ModePolicy().decision(
                for: mode,
                inputMethod: inputMethod,
                runtimeState: state
            )
            let transition = decision.isAllowed
                ? Self.productRunner(
                    reader: reader,
                    stableIDsByUUID: mapping,
                    includedDisplayIDs: includedDisplayIDs
                ).run(request)
                : nil
            let didExecute: Bool
            if case .success = transition {
                didExecute = true
            } else {
                didExecute = false
            }
            let mayHaveMoved = transition?.mayHaveMoved ?? false
            let result = ContextSwitchResult(
                command: command,
                didExecute: didExecute,
                diagnostics: DiagnosticRule.evaluate(decision: decision)
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
                    navigationDiagnostic: intent.diagnostic,
                    mayHaveMoved: mayHaveMoved
                )
                if let hudGeneration {
                    ProductContextHUDController.shared.dismissImmediately(generation: hudGeneration)
                }
                self.isSwitching = false
                self.ignoresExternalSpaceChangesUntil = Date().addingTimeInterval(0.75)
                self.refreshWorkspaceStatus()
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
        navigationDiagnostic: DiagnosticState?,
        mayHaveMoved: Bool
    ) {
        verifiedCurrentWorkspaceID = nil
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
        } else {
            updateContextPlan { plan in
                plan.applyFailedNavigation(command, mayHaveMoved: mayHaveMoved)
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

    private func hasPostEventAccess(command: SwitchCommand, label: String, requestsPermissions: Bool = true) -> Bool {
        if let postEventAccessOverride {
            return postEventAccessOverride
        }
        guard CGPreflightPostEventAccess() || (requestsPermissions && CGRequestPostEventAccess()) else {
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
        guard !heldMatrixInputActive, workspaceSaveDraft == nil else { return }
        let event = eventWithCurrentModifierState(event)
        let timestamp = ProcessInfo.processInfo.systemUptime

        switch event.type {
        case .scrollWheel:
            guard inputLatch.allowsInput(at: timestamp) else {
                return
            }
            updateScrollStatusIfNeeded(event, at: timestamp)
        case .flagsChanged:
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

        let intent = workspaceKeyboardPlan.switchIntent(for: command)
        guard hasSwitchMoveTargets(for: intent, label: "modifier-swipe") else {
            inputStatus = strings.noMoveTargetsStatus
            return
        }
        onboardingDetectedGestureCount += 1
        guard ImmediateSwipeCommandAdmission.admit(
            command,
            latch: &inputLatch,
            at: timestamp
        ) else {
            return
        }
        lastInputEvent = strings.acceptedCommand(command: command, modifiers: strings.modifierText(settings.requiredModifiers))
        executeSwipeCommand(command)
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

    func setHeldMatrixInputActive(_ active: Bool) {
        heldMatrixInputActive = active
        swipeInputSource?.isPassthroughEnabled = active
        swipePipeline = SwipeInputPipeline(settings: currentGestureSettings)
    }

    func beginHeldMatrixShortcutRecording() {
        heldMatrixController?.suspend()
        contextKeyboardInputSource?.stop()
        heldMatrixIsRecording = true
        setHeldMatrixInputActive(true)
    }

    func endHeldMatrixShortcutRecording() {
        guard heldMatrixIsRecording else { return }
        heldMatrixIsRecording = false
        setHeldMatrixInputActive(false)
        if contextKeyboardInputSource != nil { startContextKeyboardInput() }
        if heldMatrixController != nil { startHeldMatrixInput() }
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
        let intent = workspaceKeyboardPlan.switchIntent(for: command)
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
        settings.displaySelection.reconcile(with: layout)
        selectedDisplayIDs = settings.displaySelection.connectedSelectedDisplayIDs(in: layout)
    }

    func updateContextPlan(_ mutate: (inout ContextPlan) -> Void) {
        var plan = settings.contextPlan
        mutate(&plan)

        guard plan != settings.contextPlan else {
            return
        }

        let previousPlan = settings.contextPlan
        var next = settings
        next.contextPlan = plan
        if plan.contexts != previousPlan.contexts && next.savedWorkspaces.initialized {
            let valid = Set(plan.contexts.map(\.id))
            next.savedWorkspaces.bookmarks = next.savedWorkspaces.bookmarks.filter { valid.contains($0.key) }
            next.savedWorkspaces.shortcutSlots = next.savedWorkspaces.shortcutSlots.filter { valid.contains($0.key) }
            for context in plan.contexts {
                let old = previousPlan.contexts.first { $0.id == context.id }
                next.savedWorkspaces.assignAvailableShortcut(to: context.id)
                for displayID in Set(old?.displayIDs ?? []).union(context.displayIDs)
                    where old?.spaceIndex(for: displayID) != context.spaceIndex(for: displayID) {
                    if let index = context.spaceIndex(for: displayID), let keys = workspaceLastObservedSpaceKeys[displayID], keys.indices.contains(index) {
                        next.savedWorkspaces.bookmarks[context.id, default: [:]][displayID] = keys[index]
                    } else {
                        next.savedWorkspaces.bookmarks[context.id]?.removeValue(forKey: displayID)
                    }
                    if let index = context.spaceIndex(for: displayID), let ids = workspaceLastObservedSpaceIDs[displayID], ids.indices.contains(index) {
                        workspaceLegacyRuntimeBookmarks[context.id, default: [:]][displayID] = ids[index]
                    } else { workspaceLegacyRuntimeBookmarks[context.id]?.removeValue(forKey: displayID) }
                }
            }
            next.savedWorkspaces.undo = SavedWorkspaceUndo(contexts: previousPlan.contexts,
                bookmarks: settings.savedWorkspaces.bookmarks, shortcutSlots: settings.savedWorkspaces.shortcutSlots,
                label: saveCopy.text("Setup edit", "구성 편집"), resultingContexts: plan.contexts,
                resultingBookmarks: next.savedWorkspaces.bookmarks)
        }
        guard settingsStore.saveChecked(next) else { workspaceSaveMessage = saveCopy.saveFailed; return }
        settings = next
        workspaceConfigurationChanged(from: previousPlan, selectedIDs: selectedDisplayIDs)
        let validIDs = Set(plan.contexts.map(\.id))
        workspaceHistory.reconcile(validContextIDs: validIDs)
        firstWorkProgress.reconcile(validContextIDs: validIDs)
        if let id = workspaceRecoveryTargetID, !validIDs.contains(id) { workspaceRecoveryTargetID = nil }
        settingsStore.save(settings)
        diagnostics = currentDiagnostics()
        refreshLocalizedStatus()
        saveWorkspaceIdentitySnapshot()
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
    let actions: ProductMenuPanelActions
    @Environment(\.dismiss) private var dismiss
    @State private var menuWindow: NSWindow?
    @State private var didOpenFloatingMenu = false

    var body: some View {
        Color.clear.frame(width: 1, height: 1)
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
            .onDisappear { didOpenFloatingMenu = false }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow, window === menuWindow else { return }
                // MenuBarExtra reuses its host without another onAppear.
                didOpenFloatingMenu = false
                openFloatingMenuWhenReady()
            }
    }

    private func openFloatingMenuWhenReady(retryCount: Int = 3) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard !didOpenFloatingMenu else { return }
            guard let sourceWindow = menuWindow ?? NSApplication.shared.keyWindow else {
                if retryCount > 0 { openFloatingMenuWhenReady(retryCount: retryCount - 1); return }
                openFloatingMenu(from: nil)
                return
            }
            openFloatingMenu(from: sourceWindow)
        }
    }

    private func openFloatingMenu(from sourceWindow: NSWindow?) {
        guard !didOpenFloatingMenu else { return }
        didOpenFloatingMenu = true
        let menuWindow = menuWindow
        dismiss()
        // Close the MenuBarExtra's temporary host, rather than only hiding its
        // window. Its presentation must end before the persistent panel is used.
        menuWindow?.close()
        ProductFloatingMenuPanelController.shared.toggle(from: sourceWindow, model: model, actions: actions)
    }
}

struct ProductMenuPanelActions {
    let route: (ProductApplicationRequest) -> Void
    let quit: () -> Void
}

private struct ProductMenuContentView: View {
    @ObservedObject var model: SidebyAppModel
    let actions: ProductMenuPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceChooserView(model: model, actions: WorkspaceChooserActions(
                openSettings: { actions.route(.settings) },
                editWorkspaces: { actions.route(.workspaces) },
                reviewAssignments: { actions.route(.review(contextID: $0, displayID: $1)) },
                openPermissions: { actions.route(.permissions) },
                resumeOnboarding: { actions.route(.resume) }))
            Button(DailyRefreshStrings(language: model.settings.language).quit, action: actions.quit)
                .pointingHandCursor()
                .font(.system(size: 12)).controlSize(.large)
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

    static func targetScreen(for relocation: ProductMenuBarWindowRelocation) -> NSScreen? {
        relocation.sourceScreen ?? NSScreen.main
    }
}

@MainActor
final class ProductFloatingMenuPanelController {
    static let shared = ProductFloatingMenuPanelController()

    private(set) var panel: NSPanel?
    private var presentationGeneration = 0
    private var hasFittedContent = false
    private var switchObserver: AnyCancellable?
    private let refreshModel: (SidebyAppModel) -> Void

    init(refreshModel: @escaping (SidebyAppModel) -> Void = { $0.refresh() }) {
        self.refreshModel = refreshModel
    }

    func toggle(
        from sourceWindow: NSWindow?,
        model: SidebyAppModel,
        actions: ProductMenuPanelActions
    ) {
        if panel?.isVisible == true {
            close()
            return
        }

        present(
            from: sourceWindow,
            model: model,
            actions: actions
        )
    }

    func present(
        from sourceWindow: NSWindow?,
        model: SidebyAppModel,
        actions: ProductMenuPanelActions
    ) {
        presentationGeneration += 1
        refreshModel(model)
        let relocation = ProductMenuBarWindowRelocation.capture(window: sourceWindow)
            ?? ProductMenuBarWindowRelocation.fallback()
        hasFittedContent = false
        switchObserver = model.$isSwitching.removeDuplicates().dropFirst().sink { [weak self] switching in
            guard #available(macOS 27, *) else { return }
            guard !switching, let self, let panel = self.panel, panel.isVisible else { return }
            // macOS 27 can leave an all-Spaces nonactivating panel visible but
            // unable to receive clicks after a Space change. Rebind the SAME
            // window synchronously, without animation, rebuilding, or a timer.
            // A panel explicitly closed during the move must stay closed.
            panel.orderOut(nil)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }

        show(
            model: model,
            relocation: relocation,
            actions: actions
        )
    }

    func close() {
        presentationGeneration += 1
        switchObserver = nil
        panel?.orderOut(nil)
    }

    private func show(
        model: SidebyAppModel,
        relocation: ProductMenuBarWindowRelocation,
        actions: ProductMenuPanelActions
    ) {
        let isNewPanel = panel == nil
        let generation = presentationGeneration
        let panel = panel ?? makePanel()
        let capturedExistingContentSize = isNewPanel ? nil : panel.contentView?.bounds.size
        self.panel = panel
        panel.contentViewController = NSHostingController(
            rootView: ProductFloatingMenuPanelView(
                model: model,
                actions: actions,
                onContentHeightChange: { [weak self, weak panel] height in
                    guard let self, let panel, height > 0, !self.hasFittedContent,
                          self.presentationGeneration == generation, self.panel === panel else { return }
                    // Fit once when opened. Live status/history changes stay
                    // inside the existing scroll view without moving the window.
                    self.hasFittedContent = true
                    let visibleFrame = ProductMenuBarWindowConfigurator.targetScreen(for: relocation)?.visibleFrame
                    let size = FloatingMenuPanelLayout.clampedContentSize(
                        NSSize(width: panel.contentView?.bounds.width ?? 400, height: ceil(height)), visibleFrame: visibleFrame)
                    guard abs((panel.contentView?.bounds.height ?? 0) - size.height) > 1 else { return }
                    panel.setContentSize(size)
                    self.position(panel, using: relocation)
                }
            )
        )
        // Mounting the hosting controller can replace the window's size with
        // its minimum. Apply the menu's width afterward, once per explicit open.
        applyContentSize(to: panel, relocation: relocation, isNewPanel: isNewPanel,
                         capturedExistingContentSize: capturedExistingContentSize)
        position(panel, using: relocation)
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
        panel.animationBehavior = .none
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
        let contentSize = isNewPanel ? FloatingMenuPanelLayout.clampedContentSize(
            NSSize(width: 680, height: FloatingMenuPanelLayout.defaultSize.height), visibleFrame: visibleFrame
        ) : FloatingMenuPanelLayout.presentationContentSize(
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

struct ProductFloatingMenuPanelView: View {
    @ObservedObject var model: SidebyAppModel
    let actions: ProductMenuPanelActions
    var onContentHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarMasterControl(model: model)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeSurfaceStyle.windowBackground)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: ProductDailyContentHeightKey.self, value: geometry.size.height)
            })
            .zIndex(1)

            ScrollView(.vertical) {
                ProductMenuContentView(
                    model: model,
                    actions: actions
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: ProductDailyContentHeightKey.self, value: geometry.size.height)
                })
            }
        }
        .frame(
            minWidth: FloatingMenuPanelLayout.minimumSize.width,
            maxWidth: .infinity,
            minHeight: FloatingMenuPanelLayout.minimumSize.height,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(NativeSurfaceStyle.windowBackground)
        .onPreferenceChange(ProductDailyContentHeightKey.self) { height in
            DispatchQueue.main.async { onContentHeightChange(height) }
        }
    }
}

private struct ProductDailyContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
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
        .sheet(item: Binding(
            get: { model.pendingContextCaptureAlignment },
            set: { request in
                if request == nil {
                    model.cancelContextCaptureAlignment()
                }
            }
        )) { request in
            ContextCaptureAlignmentPicker(
                request: request,
                strings: model.strings,
                choose: { model.chooseContextCaptureAlignment(contextID: $0) },
                cancel: { model.cancelContextCaptureAlignment() }
            )
        }
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

    private var rowHeight: CGFloat { 36 }

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
            .font(.system(size: 13, weight: .medium))
            .frame(minHeight: 28)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .padding(.horizontal, usesDenseContextColumns ? 5 : 7)
                .frame(minHeight: 28)
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
        .help(model.strings.workspaceGoTo(column.name))
        .accessibilityLabel(model.strings.workspaceGoTo(column.name))
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

    private func membershipCell(_ cell: ContextMatrixCell) -> some View {
        Menu {
            ForEach(model.settings.contextPlan.contexts.sorted { $0.order < $1.order }) { source in
                if let index = source.spaceIndex(for: cell.displayID) {
                    Button("\(model.strings.spaceNumber(index + 1)) · \(source.name)") {
                        model.moveDisplaySpace(displayID: cell.displayID, spaceIndex: index, toContextID: cell.contextID)
                    }
                    .disabled(source.id == cell.contextID)
                }
            }
        } label: {
            membershipCellContent(cell)
        }
        .menuStyle(.borderlessButton)
        .frame(width: contextColumnWidth, height: rowHeight)
        .disabled(!model.canAddContext)
        .accessibilityLabel("\(model.displayName(for: cell.displayID)) · \(model.settings.contextPlan.contexts.first { $0.id == cell.contextID }?.name ?? "") · \(model.strings.workspaceScreenAssignments)")
        .onDrag {
            guard let spaceIndex = cell.spaceIndex else { return NSItemProvider() }
            return NSItemProvider(object: ContextMatrixSpaceDragPayload(displayID: cell.displayID, spaceIndex: spaceIndex).rawValue as NSString)
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            handleSpaceDrop(providers: providers, target: cell)
        }
    }

    private func membershipCellContent(_ cell: ContextMatrixCell) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(cell.isIncluded ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))

            if let spaceIndex = cell.spaceIndex {
                Text(model.strings.spaceNumber(spaceIndex + 1))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)

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
