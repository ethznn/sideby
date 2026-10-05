import Combine
import SidebyCore

struct ProductOnboardingFacts: Equatable {
    var hasAccessibilityPermission: Bool
    var hasSwitchingAccess: Bool
    var selectedDisplayCount: Int
    var participatingContextIDs: [String]
    var connectionStatus: WorkspaceConnectionStatus
    var isBusy: Bool
    var isEnabled: Bool
    var progress: WorkspaceFirstRunProgress
}

struct ProductOnboardingState: Equatable {
    var stage: ProductOnboardingStage

    init(stage: ProductOnboardingStage = .preparation) {
        // Old save/return guides resume at the single live connection table.
        self.stage = stage == .preparation ? .preparation : .workspaces
    }

    func canContinue(using facts: ProductOnboardingFacts) -> Bool {
        guard !facts.isBusy else { return false }
        guard facts.hasAccessibilityPermission, facts.hasSwitchingAccess else { return false }
        if stage == .preparation { return true }
        guard facts.selectedDisplayCount > 0 else { return false }
        return !facts.participatingContextIDs.isEmpty && facts.connectionStatus == .ready
    }

    @discardableResult
    mutating func continueIfAllowed(using facts: ProductOnboardingFacts) -> Bool {
        guard canContinue(using: facts) else { return false }
        switch stage {
        case .preparation: stage = .workspaces
        case .displays: stage = .workspaces
        case .workspaces, .roundTrip: break // The view finishes here; no save or switching rehearsal.
        }
        return true
    }

    mutating func goBack() {
        switch stage {
        case .preparation: break
        case .displays: stage = .preparation
        case .workspaces: stage = .preparation
        case .roundTrip: stage = .workspaces
        }
    }

    mutating func reconcileAfterRelaunch(using facts: ProductOnboardingFacts) {
        // Reconciliation can move backward only. Permission/Space notifications never advance UI.
        let latestEligible: ProductOnboardingStage
        if !facts.hasAccessibilityPermission || !facts.hasSwitchingAccess {
            latestEligible = .preparation
        } else if facts.selectedDisplayCount == 0 || facts.participatingContextIDs.isEmpty || facts.connectionStatus != .ready {
            latestEligible = .workspaces
        } else { latestEligible = .workspaces }
        if stage.rawValue > latestEligible.rawValue { stage = latestEligible }
    }
}

@MainActor
final class ProductOnboardingPresentation: ObservableObject {
    @Published private(set) var state: ProductOnboardingState
    private let preferences: any ProductUIPreferences

    init(preferences: any ProductUIPreferences) {
        self.preferences = preferences
        state = ProductOnboardingState(stage: preferences.onboardingStage)
    }

    func open(replay: Bool, facts: ProductOnboardingFacts) {
        if replay {
            state = ProductOnboardingState()
        } else {
            state.reconcileAfterRelaunch(using: facts)
        }
        preferences.onboardingStage = state.stage
    }

    @discardableResult
    func continueIfAllowed(using facts: ProductOnboardingFacts) -> Bool {
        guard state.continueIfAllowed(using: facts) else { return false }
        preferences.onboardingStage = state.stage
        return true
    }

    func goBack() {
        state.goBack()
        preferences.onboardingStage = state.stage
    }
}

enum OnboardingPreparationPolicy {
    static func shouldApplyInitialDefaults(
        didCompletePermissionSetup: Bool,
        hasRequiredPermissions: Bool
    ) -> Bool {
        !didCompletePermissionSetup && hasRequiredPermissions
    }
}

/// Transient UI observation only. An unreadable/busy layout must never retain a
/// prior count or masquerade as a zero-workspace result.
struct ProductOnboardingObservationState {
    private(set) var didCheckObservation = false
    private(set) var contextCount: Int?

    var isUnavailable: Bool { didCheckObservation && contextCount == nil }

    mutating func invalidate() {
        didCheckObservation = false
        contextCount = nil
    }

    mutating func refresh(isBusy: Bool, readContextCount: () -> Int?) {
        invalidate()
        guard !isBusy else { return }
        contextCount = readContextCount()
        didCheckObservation = true
    }

    func hasShortage(hasReadOrSavedAssignments: Bool) -> Bool {
        guard hasReadOrSavedAssignments, let contextCount else { return false }
        return contextCount < 2
    }
}

// Presentation-only recovery priority; advancement remains guarded by onboarding facts.
enum ProductOnboardingDisplayAction: Equatable {
    case permissions, refresh, advance

    static func resolve(hasRequiredPermissions: Bool, connectedDisplayCount: Int) -> Self {
        if !hasRequiredPermissions { return .permissions }
        return connectedDisplayCount == 0 ? .refresh : .advance
    }
}
