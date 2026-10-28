import SidebyCore

/// Optional first-use explanations. They never advance onboarding or change a connection.
struct ConnectionGuidancePresentation: Equatable {
    struct Pairing: Equatable {
        let contextID: String
        let displayIDs: [String]
    }
    enum Usage: Equatable {
        case general, rememberCurrent, chooseDestination
    }
    var pairing: Pairing?
    var usage: Usage = .general

    init() {}

    init(contexts: [ContextDefinition], displayIDs: [String], readableIDs: Set<String>,
         availableIDs: Set<String>, resolvedIDs: Set<String>, isEligible: Bool, canEdit: Bool) {
        guard isEligible, contexts.count == 1, let context = contexts.first,
              availableIDs.contains(context.id) else { return }
        usage = resolvedIDs.contains(context.id) ? .rememberCurrent : .chooseDestination
        let assigned = Set(context.displayIDs).intersection(displayIDs)
        let missing = displayIDs.filter { !assigned.contains($0) && readableIDs.contains($0) }
        if canEdit, !assigned.isEmpty, assigned.isSubset(of: readableIDs), !missing.isEmpty {
            pairing = Pairing(contextID: context.id, displayIDs: missing)
        }
    }

    func usageMessage(language: AppLanguage) -> String? {
        switch usage {
        case .general: nil
        case .rememberCurrent: language == .korean
            ? "이 연결은 지금 화면을 기억합니다. 다른 Space에서 작업한 뒤 이 연결을 골라 돌아올 수 있어요."
            : "This connection remembers these screens. After working in other Spaces, choose it to return."
        case .chooseDestination: language == .korean
            ? "이 연결을 고르면 배정한 모니터가 함께 이동합니다."
            : "Choose this connection to move its assigned displays together."
        }
    }
}

extension SidebyAppModel {
    var connectionGuidance: ConnectionGuidancePresentation {
        let displays = connectedWorkspaceDisplayIDs.filter { selectedDisplayIDs.contains($0) }
        let observation = workspaceLatestObservation
        let readable = Set(displays.filter { composerKeys($0, observation: observation)?.isEmpty == false })
        let contexts = settings.contextPlan.contexts
        let available = Set(contexts.filter { isWorkspaceAssignmentAvailable(contextID: $0.id) }.map(\.id))
        let resolved = Set(contexts.filter { workspaceAssignmentReadiness(contextID: $0.id)?.isResolved == true }.map(\.id))
        return ConnectionGuidancePresentation(contexts: contexts, displayIDs: displays, readableIDs: readable,
            availableIDs: available, resolvedIDs: resolved,
            isEligible: isEnabled && permissionState == .granted && hasSwitchingAccess
                && !isSwitching && contextCaptureSession == nil && pendingContextCaptureAlignment == nil
                && observation != nil && !settingsStore.hasUnreadableSettings,
            canEdit: canChangeSavedWorkspaces)
    }
}
