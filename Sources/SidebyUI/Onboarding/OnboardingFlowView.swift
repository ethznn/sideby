import SidebyCore
import SwiftUI

public struct OnboardingFlowView<ViewModel: SBSOnboardingViewModel>: View {
    @ObservedObject private var vm: ViewModel
    @State private var step: OnboardingFlowStep = .permission

    private let language: AppLanguage
    private let onFinish: () -> Void

    public init(
        viewModel: ViewModel,
        language: AppLanguage = .english,
        onFinish: @escaping () -> Void = {}
    ) {
        self.vm = viewModel
        self.language = language
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                StepDots(currentStep: step, language: language)
            }
            .padding(.horizontal, Tokens.padding.window)
            .padding(.top, 16)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, Tokens.padding.window)
                .padding(.top, 10)

            Divider()

            footer
        }
        .frame(width: 480, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: scheduleInitialAutoAdvanceIfNeeded)
        .onChange(of: vm.hasAccessibilityPermission) { _, hasPermission in
            if hasPermission && vm.hasSwitchingAccess {
                scheduleAutoAdvance(from: .permission, to: .tryGesture)
            }
        }
        .onChange(of: vm.hasSwitchingAccess) { _, hasPermission in
            if hasPermission && vm.hasAccessibilityPermission {
                scheduleAutoAdvance(from: .permission, to: .tryGesture)
            }
        }
        .onChange(of: vm.detectedGestureCount) { _, count in
            if count >= 1 {
                scheduleAutoAdvance(from: .tryGesture, to: .done, delay: 1.0)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .permission:
            VStack(alignment: .leading, spacing: 12) {
                PermissionStepView(
                    hasAccessibilityPermission: vm.hasAccessibilityPermission,
                    hasSwitchingAccess: vm.hasSwitchingAccess,
                    language: language
                )

                if let feedback = vm.permissionRequestFeedback {
                    PermissionRequestFeedbackView(
                        feedback: feedback,
                        language: language,
                        action: { action in
                            switch action {
                            case .openAccessibilitySettings:
                                vm.openSystemSettingsAccessibility()
                            case .openAutomationSettings:
                                vm.openSystemSettingsAutomation()
                            }
                        }
                    )
                }
            }
        case .tryGesture:
            TryGestureStepView(
                detectedGestureCount: vm.detectedGestureCount,
                displayCount: vm.displayCount,
                language: language,
                skipTest: {
                    vm.skipGestureTest()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        step = .done
                    }
                }
            )
        case .done:
            DoneStepView(language: language)
        }
    }

    private var footer: some View {
        let strings = SBSStrings(language: language)

        return HStack(spacing: 12) {
            Spacer()

            Button(strings.back, action: goBack)
                .buttonStyle(.bordered)
                .disabled(step == .permission)

            Button(primaryButtonTitle, action: continueFlow)
                .buttonStyle(.borderedProminent)
                .disabled(primaryButtonDisabled)
        }
        .padding(.horizontal, Tokens.padding.window)
        .padding(.vertical, 14)
    }

    private var primaryButtonTitle: String {
        let strings = SBSStrings(language: language)

        switch step {
        case .permission:
            if !vm.hasAccessibilityPermission {
                return strings.enableAccessibility
            }
            if !vm.hasSwitchingAccess {
                return strings.checkSwitchingAccess
            }
            return strings.continue
        case .tryGesture:
            return strings.continue
        case .done:
            return strings.onboardingCompletionActionTitle
        }
    }

    private var primaryButtonDisabled: Bool {
        step == .tryGesture && vm.detectedGestureCount < 1
    }

    private var hasRequiredPermissions: Bool {
        vm.hasAccessibilityPermission && vm.hasSwitchingAccess
    }

    private func continueFlow() {
        switch step {
        case .permission:
            if hasRequiredPermissions {
                move(to: .tryGesture)
            } else if !vm.hasAccessibilityPermission {
                vm.openSystemSettingsAccessibility()
            } else {
                vm.requestSwitchingAccess()
            }
        case .tryGesture:
            move(to: .done)
        case .done:
            vm.finish()
            onFinish()
        }
    }

    private func goBack() {
        switch step {
        case .permission:
            break
        case .tryGesture:
            move(to: .permission)
        case .done:
            move(to: .tryGesture)
        }
    }

    private func move(to newStep: OnboardingFlowStep) {
        withAnimation(.easeInOut(duration: 0.18)) {
            step = newStep
        }
    }

    private func scheduleInitialAutoAdvanceIfNeeded() {
        if hasRequiredPermissions {
            scheduleAutoAdvance(from: .permission, to: .tryGesture)
        }

        if vm.detectedGestureCount >= 1 {
            scheduleAutoAdvance(from: .tryGesture, to: .done)
        }
    }

    private func scheduleAutoAdvance(
        from expectedStep: OnboardingFlowStep,
        to targetStep: OnboardingFlowStep,
        delay: TimeInterval = 0.35
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard step == expectedStep else {
                return
            }

            move(to: targetStep)
        }
    }
}

private struct PermissionRequestFeedbackView: View {
    let feedback: PermissionRequestFeedback
    let language: AppLanguage
    let action: (PermissionRequestAction) -> Void

    var body: some View {
        let strings = SBSStrings(language: language)

        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13, weight: .semibold))

            Text(strings.permissionRequestFeedback(feedback))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let requestAction = feedback.action {
                Button(strings.permissionRequestActionTitle(requestAction)) {
                    action(requestAction)
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.corner.panel, style: .continuous))
    }
}

private enum OnboardingFlowStep: Int, CaseIterable {
    case permission
    case tryGesture
    case done
}

private struct StepDots: View {
    let currentStep: OnboardingFlowStep
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingFlowStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step == currentStep ? Tokens.accent : Color(nsColor: .separatorColor))
                .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel(SBSStrings(language: language).stepAccessibilityLabel(current: currentStep.rawValue + 1, total: 3))
    }
}

#if DEBUG
private final class OnboardingPreviewViewModel: SBSOnboardingViewModel {
    @Published var hasAccessibilityPermission = false
    @Published var hasSwitchingAccess = false
    @Published var permissionRequestFeedback: PermissionRequestFeedback?
    @Published var detectedGestureCount = 0
    var displayCount = 2

    func openSystemSettingsAccessibility() {
        hasAccessibilityPermission = true
    }

    func openSystemSettingsAutomation() {
        hasSwitchingAccess = true
    }

    func requestSwitchingAccess() {
        permissionRequestFeedback = .automationDenied
    }

    func skipGestureTest() {
        detectedGestureCount = 1
    }

    func finish() {}
}

#Preview("Onboarding") {
    OnboardingFlowView(viewModel: OnboardingPreviewViewModel())
}
#endif
