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
    private var copy: CurrentConnectionStrings { model.connectionCopy }
    private var facts: ProductOnboardingFacts { .init(model: model) }
    private var hasPermissions: Bool { model.permissionState == .granted && model.hasSwitchingAccess }
    private var preparing: Bool { !hasPermissions || presentation.state.stage == .preparation }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Text(copy.text("1  Allow access", "1  접근 허용")).foregroundStyle(preparing ? NativeSurfaceStyle.primaryText : NativeSurfaceStyle.secondaryText)
                        Image(systemName: "chevron.right").font(.system(size: 10))
                        Text(copy.text("2  Connect Spaces", "2  Space 연결")).foregroundStyle(preparing ? NativeSurfaceStyle.secondaryText : NativeSurfaceStyle.primaryText)
                    }.font(.system(size: 12, weight: .medium))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(preparing ? copy.text("Move your displays together.", "여러 화면을 함께 넘기세요.")
                            : copy.text("Pair the Spaces you already use.", "지금 쓰는 Space의 짝만 맞추세요."))
                            .font(.system(size: 25, weight: .semibold)).accessibilityAddTraits(.isHeader)
                        Text(preparing ? copy.text("Sideby connects existing Spaces — desktops and full-screen apps — so your usual gesture can move your displays together.", "Space는 데스크탑과 전체 화면 앱을 포함하는 macOS 작업 공간입니다. 함께 볼 Space를 연결하면 평소 제스처로 여러 모니터를 함께 넘길 수 있습니다.")
                            : copy.text("Start in the current order, then change any cell. No names or separate saves are needed.", "현재 순서로 시작한 뒤 필요한 칸만 바꾸세요. 이름을 붙이거나 따로 저장할 필요가 없습니다."))
                            .font(.system(size: 13)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    }
                    if preparing { preparationContent }
                    else {
                        CurrentConnectionsView(model: model)
                        VStack(alignment: .leading, spacing: 9) {
                            Label(model.strings.horizontalScrollGesture(model.settings.requiredModifiers), systemImage: "hand.draw")
                            if let shortcut = model.availableWorkspaceChooserShortcut {
                                Text(copy.text("Hold \(shortcut) and click a column to move your displays together.", "\(shortcut)를 누른 채 열을 눌러 함께 이동하세요."))
                            }
                            Text(copy.text("You can always open the same table from the menu bar.", "메뉴 막대에서도 같은 연결표를 열 수 있습니다."))
                                .foregroundStyle(NativeSurfaceStyle.secondaryText)
                        }.font(.system(size: 12)).padding(14)
                            .background(NativeSurfaceStyle.headerBackground, in: RoundedRectangle(cornerRadius: 9))
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                if !preparing { Button(copy.text("Back", "뒤로")) { presentation.goBack() }.pointingHandCursor() }
                Button(copy.text("Later", "나중에"), action: finish).pointingHandCursor().keyboardShortcut(.cancelAction)
                Spacer()
                Button(preparing ? copy.text("Continue", "계속") : copy.text("Start using Sideby", "Sideby 사용하기")) {
                    model.refreshWorkspaceStatus()
                    if preparing {
                        model.prepareFirstWorkspaceGuideIfNeeded(preferences: preferences)
                        _ = presentation.continueIfAllowed(using: facts)
                    } else {
                        preferences.didDismissOnboarding = true
                        model.dismissFirstWorkGuide()
                        actions.finishToDaily()
                    }
                }.buttonStyle(.borderedProminent).pointingHandCursor().keyboardShortcut(.defaultAction)
                    .disabled(!presentation.state.canContinue(using: facts))
                    .accessibilityIdentifier("guide-continue")
            }.controlSize(.large).padding(18).background(NativeSurfaceStyle.sidebarBackground)
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText).background(NativeSurfaceStyle.windowBackground).tint(NativeSurfaceStyle.accent)
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
            Text(hasPermissions ? copy.text("Access is ready. Continue to connect your Spaces.", "접근 권한이 준비됐어요. 계속해서 Space 연결을 확인하세요.") : strings.permissionsNeeded)
                .foregroundStyle(NativeSurfaceStyle.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

}
