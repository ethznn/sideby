import SidebyCore

/// A description of the latest cached state, never an executable switch plan.
struct HeldWorkspaceRecoveryPresentation: Equatable {
    enum Kind: Equatable { case offline, noParticipants, unreadable, review, pending, unknown }
    enum Action: Equatable { case refresh, review, retry }
    let contextID: String
    let name: String
    let displayIDs: [String]
    let kind: Kind
    let action: Action

    init?(target: ContextDefinition, configuredIDs: Set<String>, connectedIDs: Set<String>,
          selectedIDs: Set<String>, displayOrder: [String], observation: WorkspaceLayoutObservation?,
          blockedIDs: Set<String>, unresolvedIDs: Set<String>, sessionStatus: WorkspaceConnectionStatus) {
        contextID = target.id; name = target.name
        let members = Set(target.displayIDs)
        let required = members.intersection(selectedIDs).intersection(connectedIDs)
        let offline = members.intersection(configuredIDs).subtracting(connectedIDs)
        let state = WorkspaceRecoveryState(targetContext: target, selectedDisplayIDs: required,
                                           displays: observation?.displays)
        var readable = WorkspaceConnectionSession()
        let layouts = observation?.spaceIDsByDisplayID.filter { required.contains($0.key) } ?? [:]
        let hasReadableLayout = required.isSubset(of: Set(layouts.keys)) && readable.confirm(spaceIDsByDisplayID: layouts)
        let affected: Set<String>
        if !offline.isEmpty {
            kind = .offline; action = .review; affected = offline
        } else if required.isEmpty {
            kind = .noParticipants; action = .review; affected = []
        } else if !hasReadableLayout || !state.unavailableDisplayIDs.isEmpty {
            kind = .unreadable; action = .refresh
            affected = state.unavailableDisplayIDs.isEmpty ? required : state.unavailableDisplayIDs
        } else {
            let invalid = required.intersection(blockedIDs.union(unresolvedIDs)).union(state.invalidDisplayIDs)
            if !invalid.isEmpty {
                kind = .review; action = .review; affected = invalid
            } else {
                switch sessionStatus {
                case .unavailable(let ids):
                    kind = .unreadable; action = .refresh; affected = ids.intersection(required)
                case .unconfirmed:
                    kind = .review; action = .review; affected = required
                case .changed(let ids):
                    kind = .review; action = .review; affected = ids.intersection(required)
                case .ready:
                    if state.isResolved { return nil }
                    if state.canRetry {
                        kind = .pending; action = .retry; affected = state.pendingDisplayIDs
                    } else {
                        kind = .unknown; action = .review; affected = required
                    }
                }
            }
        }
        var seen = Set<String>()
        displayIDs = (displayOrder + affected.sorted()).filter { affected.contains($0) && seen.insert($0).inserted }
    }

    func matchesAction(_ other: Self) -> Bool {
        contextID == other.contextID && displayIDs == other.displayIDs && kind == other.kind && action == other.action
    }

    func message(language: AppLanguage, displayNames: [String]) -> String {
        let names = displayNames.joined(separator: ", ")
        switch kind {
        case .offline: return language == .korean ? "모니터 연결 확인: \(names)" : "Reconnect displays: \(names)"
        case .noParticipants: return language == .korean ? "참여 모니터를 확인하세요." : "Review participating displays."
        case .unreadable: return language == .korean ? "모니터 상태를 읽지 못했습니다." : "Couldn't read the display state."
        case .review: return language == .korean ? "연결한 Space를 확인하세요." : "Review this connection's Spaces."
        case .pending: return language == .korean ? "아직 이동할 모니터: \(names)" : "Still to move: \(names)"
        case .unknown: return language == .korean ? "다시 시도하기 전에 연결을 확인하세요." : "Review the connection before trying again."
        }
    }

    func actionTitle(language: AppLanguage) -> String {
        switch action {
        case .refresh: language == .korean ? "다시 확인" : "Check again"
        case .review: language == .korean ? "Space 확인" : "Review Spaces"
        case .retry: language == .korean ? "다시 시도" : "Retry"
        }
    }
}

extension SidebyAppModel {
    var heldWorkspaceRecovery: HeldWorkspaceRecoveryPresentation? {
        guard !settingsStore.hasUnreadableSettings, isEnabled, !isSwitching,
              contextCaptureSession == nil, pendingContextCaptureAlignment == nil,
              permissionState == .granted, hasSwitchingAccess,
              let id = workspaceRecoveryTargetID,
              let target = settings.contextPlan.contexts.first(where: { $0.id == id }) else { return nil }
        let observation = workspaceLatestObservation
        let required = Set(target.displayIDs).intersection(selectedDisplayIDs)
        return HeldWorkspaceRecoveryPresentation(target: target,
            configuredIDs: settings.displaySelection.hasInitialized ? settings.displaySelection.selectedDisplayIDs : selectedDisplayIDs,
            connectedIDs: Set(displayLayout.displays.map(\.id)), selectedIDs: selectedDisplayIDs,
            displayOrder: settings.displayRowOrder + connectedWorkspaceDisplayIDs,
            observation: observation, blockedIDs: workspaceIdentityBlockedDisplayIDs,
            unresolvedIDs: unresolvedWorkspaceMembers(target, observation: observation),
            sessionStatus: workspaceConnectionSession.status(for: required, spaceIDsByDisplayID: observation?.spaceIDsByDisplayID))
    }

    /// Reconciliation may update stored indexes; this never invents assignments or bypasses activation guards.
    func performHeldWorkspaceRecovery(_ expected: HeldWorkspaceRecoveryPresentation,
        select: (HeldWorkspaceColumn) -> Void, edit: (ConnectionEditorRevealRequest) -> Void) {
        guard let before = heldWorkspaceRecovery, before.matchesAction(expected) else { return }
        refreshWorkspaceStatus()
        guard expected.action != .refresh,
              let current = heldWorkspaceRecovery, current.matchesAction(expected) else { return }
        switch current.action {
        case .refresh: break
        case .review:
            edit(ConnectionEditorRevealRequest(contextID: current.contextID, displayID: current.displayIDs.first))
        case .retry:
            let snapshot = HeldWorkspaceSnapshot(model: self)
            guard let column = snapshot.columns.first(where: { $0.id == current.contextID }),
                  heldMatrixCanActivate(column, displayIDs: snapshot.displayIDs) else { return }
            select(column)
        }
    }
}
