import AppKit
import SwiftUI
import SidebyCore
import SidebyUI

struct ProductOnboardingActions {
    var close: () -> Void
    var finishToDaily: () -> Void
    var openInputSettings: () -> Void
    var openWorkspaceSettings: (String?, String?) -> Void
}

struct ProductOnboardingView: View {
    @ObservedObject var model: SidebyAppModel
    @ObservedObject var presentation: ProductOnboardingPresentation
    let preferences: any ProductUIPreferences
    let actions: ProductOnboardingActions
    private var strings: OnboardingRefreshStrings { .init(language: model.settings.language) }
    private var copy: WorkspaceSaveStrings { model.saveCopy }
    private var hasPermissions: Bool { model.permissionState == .granted && model.hasSwitchingAccess }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(copy.text("Back to your work, in one action.", "하던 일로, 가볍게 돌아가기."))
                        .font(.system(size: 27, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text(hasPermissions
                        ? copy.text("Use your desktops as usual. When you want to remember a setup, save it here.", "평소처럼 데스크탑을 쓰다가 기억하고 싶은 구성을 저장하세요.")
                        : copy.text("First, allow Sideby to switch desktops when you ask.", "먼저, 요청한 데스크탑으로 이동할 수 있도록 접근을 허용해 주세요."))
                        .font(.system(size: 13)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    if hasPermissions {
                        HStack(spacing: 8) {
                            Image(systemName: "keyboard")
                            if model.heldMatrixConfiguration.isEnabled && model.heldMatrixShortcutError == nil {
                                Text(KeyboardShortcutFormatter.shortcutText(model.heldMatrixConfiguration.shortcut))
                                Text(copy.text("opens this matrix near your pointer.", "로 포인터 근처에서 매트릭스를 열 수 있어요."))
                            } else { Text(copy.text("Open Sideby in the menu bar to save and choose setups.", "메뉴 막대의 Sideby에서 구성을 저장하고 선택할 수 있어요.")) }
                        }.font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.accent)
                        SavedWorkspaceBrowser(model: model).frame(height: 490)
                    } else { preparationContent }
                }.padding(28)
            }
            Divider()
            HStack {
                Button(copy.text("Later", "나중에")) { finish() }.keyboardShortcut(.cancelAction)
                Spacer()
                if hasPermissions {
                    Button(copy.text("Start using Sideby", "Sideby 사용하기")) {
                        model.prepareFirstWorkspaceGuideIfNeeded(preferences: preferences)
                        preferences.didDismissOnboarding = true
                        model.dismissFirstWorkGuide()
                        actions.finishToDaily()
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(copy.text("Check access again", "접근 권한 다시 확인")) { model.refresh() }
                }
            }.controlSize(.large).padding(18).background(NativeSurfaceStyle.sidebarBackground)
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText).background(NativeSurfaceStyle.windowBackground).tint(NativeSurfaceStyle.accent)
        .onAppear { model.loadWorkspaceNamesIfNeeded() }
        .onChange(of: model.isSwitching) { _, busy in if !busy { model.loadWorkspaceNamesIfNeeded() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }

    private func finish() { preferences.didDismissOnboarding = true; model.dismissFirstWorkGuide(); actions.close() }

    private var preparationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativePermissionRow(name: model.strings.accessibility,
                reason: model.strings.permissionAccessibilitySubtitle,
                status: model.permissionState == .granted ? model.strings.granted : model.strings.notGranted) {
                if model.permissionState != .granted {
                    Button(model.strings.openAccessibilitySettingsButton) { model.openSystemSettingsAccessibility() }
                        .disabled(model.isSwitching)
                }
            }
            NativePermissionRow(name: model.strings.switchingAccess,
                reason: model.strings.permissionSwitchingAccessSubtitle,
                status: model.hasSwitchingAccess ? model.strings.granted : model.strings.notGranted) {
                if !model.hasSwitchingAccess {
                    Button(model.strings.checkSwitchingAccess) { model.requestSwitchingAccess() }
                        .disabled(model.isSwitching)
                }
            }
            if let feedback = model.permissionRequestFeedback {
                NativeStatusSection(tone: .warning, title: model.strings.permissions,
                                    message: model.strings.permissionRequestFeedback(feedback)) {
                    if let action = feedback.action {
                        Button(model.strings.permissionRequestActionTitle(action)) { model.openAccessibilitySettings() }
                    }
                }
            }
            DisclosureGroup(strings.permissionDetails) {
                Text(model.strings.inputPrivacyNote).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            Text(hasPermissions ? strings.accessReady : strings.permissionsNeeded)
                .foregroundStyle(NativeSurfaceStyle.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

}
