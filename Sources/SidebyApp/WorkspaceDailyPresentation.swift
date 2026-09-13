import SidebyCore

struct WorkspaceDailyPresentation: Equatable {
    enum Status: Equatable {
        case busy, recovery, disabled, permissions, empty, ready
        case connection(WorkspaceConnectionStatus)
    }
    let status: Status
    let currentContextID: String?
    let failedTargetID: String?

    init(plan: ContextPlan, isSwitching: Bool, isCapturing: Bool,
         isEnabled: Bool, hasRequiredPermissions: Bool,
         connectionStatus: WorkspaceConnectionStatus, recovery: WorkspaceRecoveryState?,
         verifiedCurrentContextID: String?, failedTargetID: String?) {
        let ids = Self.preparedContextIDs(in: plan)
        self.currentContextID = !isSwitching && !isCapturing && connectionStatus == .ready
            ? verifiedCurrentContextID.flatMap { ids.contains($0) ? $0 : nil } : nil
        self.failedTargetID = failedTargetID.flatMap { ids.contains($0) ? $0 : nil }
        if isSwitching || isCapturing { status = .busy }
        else if self.failedTargetID != nil, let recovery, !recovery.isResolved { status = .recovery }
        else if !isEnabled { status = .disabled }
        else if !hasRequiredPermissions { status = .permissions }
        else if ids.isEmpty { status = .empty }
        else if connectionStatus != .ready { status = .connection(connectionStatus) }
        else { status = .ready }
    }

    static func preparedContextIDs(in plan: ContextPlan) -> [String] {
        plan.contexts.sorted { $0.order < $1.order }.filter { !$0.displaySpaceIndexes.isEmpty }.map(\.id)
    }
}

enum ProductApplicationRequest {
    case settings, customizeInput, permissions, workspaces, replay, resume
    case review(contextID: String?, displayID: String?)
}

enum ProductApplicationRoute: Equatable {
    case settings(ProductSettingsRoute?)
    case onboarding(replay: Bool)
}

enum ProductApplicationRouting {
    static func route(for request: ProductApplicationRequest) -> ProductApplicationRoute {
        switch request {
        case .settings: .settings(nil)
        case .customizeInput: .settings(.init(pane: .input))
        case .permissions: .settings(.init(pane: .permissions))
        case .workspaces: .settings(.init(pane: .workspaces))
        case .review(let contextID, let displayID):
            .settings(.init(pane: .workspaces, contextID: contextID, displayID: displayID, returnTo: .daily))
        case .replay: .onboarding(replay: true)
        case .resume: .onboarding(replay: false)
        }
    }
}

struct ProductInitialGuidePresentation {
    private var didPresent = false

    mutating func shouldPresent(isRoundTripComplete: Bool, isDismissed: Bool) -> Bool {
        guard !didPresent, !isRoundTripComplete, !isDismissed else { return false }
        didPresent = true
        return true
    }
}

enum ProductGuideRecordingPolicy {
    static func shouldRecord(stage: ProductOnboardingStage, progress: WorkspaceFirstRunProgress) -> Bool {
        stage == .roundTrip && progress.originContextID != nil && !progress.isComplete
    }
}
