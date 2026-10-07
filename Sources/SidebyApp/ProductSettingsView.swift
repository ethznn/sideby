import AppKit
import SidebyCore
import SidebyUI
import SwiftUI

struct ProductSettingsActions {
    var checkForUpdates: () -> Void
    var openOnboarding: () -> Void
    var finishAssignmentReview: () -> Void
}

struct ProductSettingsView: View {
    @ObservedObject var model: SidebyAppModel
    @ObservedObject var navigation: ProductUINavigation
    let canCheckForUpdates: Bool
    let updaterLanguageRequiresRestart: Bool
    let actions: ProductSettingsActions
    @State private var isPracticing = false
    @State private var hostingWindow: NSWindow?
    @State private var invalidSettingsMessage: String?
    @FocusState private var focusedPane: ProductSettingsPane?
    @ScaledMetric(relativeTo: .body) private var bodySize = 13.0
    @ScaledMetric(relativeTo: .title2) private var titleSize = 22.0
    private var strings: SettingsRefreshStrings { .init(language: model.settings.language) }

    init(model: SidebyAppModel, navigation: ProductUINavigation, canCheckForUpdates: Bool,
         updaterLanguageRequiresRestart: Bool = false,
         actions: ProductSettingsActions) {
        self.model = model
        self.navigation = navigation
        self.canCheckForUpdates = canCheckForUpdates
        self.updaterLanguageRequiresRestart = updaterLanguageRequiresRestart
        self.actions = actions
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = WorkspaceTablePresentation(windowWidth: geometry.size.width,
                displayCount: model.displayLayout.displays.count)
            HStack(spacing: 0) {
                sidebar.frame(width: layout.sidebarWidth)
                Divider()
                VStack(spacing: 0) {
                    if navigation.settingsRoute.pane == .workspaces {
                        CurrentConnectionsView(model: model, showsDesktopSources: true,
                            availableHeight: geometry.size.height - layout.inset * 2)
                            .padding(layout.inset)
                            .frame(maxHeight: .infinity, alignment: .top)
                        if !model.isEnabled {
                            Button(DailyRefreshStrings(language: model.settings.language).turnOn) { model.setSidebyEnabled(true) }
                                .buttonStyle(.borderedProminent).padding(.bottom, 12)
                        }
                        if model.permissionState != .granted || !model.hasSwitchingAccess {
                            Button(DailyRefreshStrings(language: model.settings.language).permissions) { navigation.selectPane(.permissions) }
                                .padding(.bottom, 12)
                        }
                    } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(strings.pane(navigation.settingsRoute.pane))
                                .font(.system(size: titleSize, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            paneContent
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(layout.inset)
                    }
                    }
                }
            }
        }
        .font(.system(size: bodySize))
        .foregroundStyle(NativeSurfaceStyle.primaryText)
        .background(NativeSurfaceStyle.windowBackground)
        .background(ProductSettingsWindowReader { hostingWindow = $0 })
        .onChange(of: navigation.settingsRoute.pane) { _, pane in
            if pane != .input { endPractice() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if let window = notification.object as? NSWindow, window === hostingWindow { endPractice() }
        }
        .onDisappear { endPractice() }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
            ForEach(ProductSettingsPane.allCases) { pane in
                Button {
                    navigation.selectPane(pane)
                } label: {
                    Label(strings.pane(pane), systemImage: strings.paneSymbol(pane))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointingHandCursor()
                .accessibilityIdentifier("settings-pane-" + pane.rawValue)
                .focused($focusedPane, equals: pane)
                .background(navigation.settingsRoute.pane == pane ? NativeSurfaceStyle.selectionBackground : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: focusedPane == pane ? 2 : (navigation.settingsRoute.pane == pane ? 1 : 0)))
                .accessibilityAddTraits(navigation.settingsRoute.pane == pane ? .isSelected : [])
            }
            }
            .padding(12)
        }
                .frame(maxHeight: .infinity)
        .background(NativeSurfaceStyle.sidebarBackground)
    }

    @ViewBuilder private var paneContent: some View {
        switch navigation.settingsRoute.pane {
        case .workspaces: EmptyView()
        case .input: inputPane
        case .permissions: permissionsPane
        case .general: generalPane
        }
    }

    private var settingsBinding: Binding<AppSettings> {
        Binding(get: { model.settings }, set: { candidate in
            guard KeyboardShortcutValidator.isValidGestureModifierSet(candidate.requiredModifiers) else {
                invalidSettingsMessage = model.strings.shortcutSettingsNotSaved
                return
            }
            invalidSettingsMessage = nil
            model.updateSettings(candidate)
        })
    }

    private var inputPane: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(strings.inputDescription).foregroundStyle(NativeSurfaceStyle.secondaryText)
            ShortcutSettingsView(settings: settingsBinding, showsInputExperiment: false)
            HeldMatrixShortcutSettingsView(model: model)
            if let invalidSettingsMessage {
                Text(invalidSettingsMessage).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            if isPracticing {
                TryGestureStepView(detectedGestureCount: model.detectedGestureCount,
                                   displayCount: model.displayCount, language: model.settings.language,
                                   skipTest: endPractice)
                Button(strings.finishPractice, action: endPractice).controlSize(.large).pointingHandCursor()
            } else {
                Button(strings.gesturePractice) {
                    isPracticing = true
                    model.prepareMiniOnboarding()
                }
                .controlSize(.large).pointingHandCursor()
                .disabled(model.permissionState != .granted)
                if model.permissionState != .granted {
                    Text(strings.permissionBeforePractice).foregroundStyle(NativeSurfaceStyle.secondaryText)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var permissionsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            NativePermissionRow(name: model.strings.accessibility,
                                reason: model.strings.permissionAccessibilitySubtitle,
                                status: model.strings.permissionState(model.permissionState)) {
                Button(model.strings.openAccessibilitySettingsButton) { model.openSystemSettingsAccessibility() }.pointingHandCursor()
            }
            Divider()
            NativePermissionRow(name: model.strings.switchingAccess,
                                reason: model.strings.permissionSwitchingAccessSubtitle,
                                status: model.hasSwitchingAccess ? model.strings.granted : model.strings.notGranted) {
                if !model.hasSwitchingAccess {
                    Button(model.strings.checkSwitchingAccess) { model.requestSwitchingAccess() }.pointingHandCursor()
                }
            }
            if let feedback = model.permissionRequestFeedback {
                NativeStatusSection(tone: .warning, title: model.strings.switchingAccess,
                                    message: model.strings.permissionRequestFeedback(feedback)) {
                    if let action = feedback.action {
                        Button(model.strings.permissionRequestActionTitle(action)) { model.openSystemSettingsAccessibility() }.pointingHandCursor()
                    }
                }
            }
            Text(model.strings.inputPrivacyNote).foregroundStyle(NativeSurfaceStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(strings.generalDescription).foregroundStyle(NativeSurfaceStyle.secondaryText)
            LanguageSettingsView(settings: settingsBinding)
            if updaterLanguageRequiresRestart {
                Text(model.saveCopy.text("The update window will use this language after you reopen Sideby.",
                    "업데이트 창의 언어 변경은 Sideby를 다시 열면 적용됩니다."))
                    .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .accessibilityIdentifier("updater-language-restart")
            }
            Divider()
            Toggle(model.strings.startAtLogin, isOn: Binding(
                get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) }
            )).pointingHandCursor()
            Text(model.loginItemStatus).foregroundStyle(NativeSurfaceStyle.secondaryText)
            Divider()
            Button(model.strings.checkForUpdates, action: actions.checkForUpdates)
                .controlSize(.large).pointingHandCursor().disabled(!canCheckForUpdates)
            Button(strings.replay, action: actions.openOnboarding).controlSize(.large).pointingHandCursor()
        }
    }

    private func endPractice() {
        guard isPracticing else { return }
        isPracticing = false
        model.skipGestureTest()
    }
}

struct ProductSettingsWindowReader: NSViewRepresentable {
    let didMove: (NSWindow?) -> Void
    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.didMove = didMove
        return view
    }
    func updateNSView(_ nsView: WindowReaderView, context: Context) { nsView.didMove = didMove }
    final class WindowReaderView: NSView {
        var didMove: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let window = window
            DispatchQueue.main.async { [weak self] in self?.didMove?(window) }
        }
    }
}
