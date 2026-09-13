extension SidebyAppModel {
    /// Only explicit Preparation Continue may apply this one-time compatibility default.
    /// The flag records permission preparation even if the existing input starter fails.
    func prepareFirstWorkspaceGuideIfNeeded(preferences: any ProductUIPreferences) {
        guard OnboardingPreparationPolicy.shouldApplyInitialDefaults(
            didCompletePermissionSetup: preferences.didCompletePermissionSetup,
            hasRequiredPermissions: hasAccessibilityPermission && hasSwitchingAccess
        ) else { return }
        preferences.didCompletePermissionSetup = true
        if !isEnabled { setSidebyEnabled(true) }
    }

    /// Explicit guide retry authorization only; the existing runner and verified result
    /// callback still own admission, execution, and progress. Never call on open/appear.
    func prepareFirstWorkspaceGuideRetry() {
        workspaceGuideIsRecording = !firstWorkProgress.isComplete
        if !firstWorkProgress.isComplete { isShowingFirstWorkGuide = true }
    }
}
