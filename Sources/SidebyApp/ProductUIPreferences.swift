import Foundation

@MainActor
protocol ProductUIPreferences: AnyObject {
    var lastSettingsPane: ProductSettingsPane { get set }
    var onboardingStage: ProductOnboardingStage { get set }
    var didCompletePermissionSetup: Bool { get set }
    var didDismissOnboarding: Bool { get set }
}

@MainActor
final class UserDefaultsProductUIPreferences: ProductUIPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var lastSettingsPane: ProductSettingsPane {
        get {
            guard let value = defaults.object(forKey: "sideby.ui.settings-pane") as? String,
                  let pane = ProductSettingsPane(rawValue: value) else { return .workspaces }
            return pane
        }
        set { defaults.set(newValue.rawValue, forKey: "sideby.ui.settings-pane") }
    }

    var onboardingStage: ProductOnboardingStage {
        get {
            guard let value = defaults.object(forKey: "sideby.ui.onboarding-stage") as? Int,
                  let stage = ProductOnboardingStage(rawValue: value) else { return .preparation }
            return stage
        }
        set { defaults.set(newValue.rawValue, forKey: "sideby.ui.onboarding-stage") }
    }

    var didCompletePermissionSetup: Bool {
        get { defaults.object(forKey: "sideby.v1.onboarding-complete") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "sideby.v1.onboarding-complete") }
    }

    var didDismissOnboarding: Bool {
        get { defaults.object(forKey: "sideby.workspace-guide-dismissed") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "sideby.workspace-guide-dismissed") }
    }
}

@MainActor
final class MemoryProductUIPreferences: ProductUIPreferences {
    var lastSettingsPane: ProductSettingsPane = .workspaces
    var onboardingStage: ProductOnboardingStage = .preparation
    var didCompletePermissionSetup = false
    var didDismissOnboarding = false

    init() {}
}
