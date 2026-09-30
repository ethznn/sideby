import AppKit
import CoreGraphics
import SidebyCore
import SidebySystem
import SidebyUI

extension SidebyAppModel {
    var workspaceRows: [WorkspaceChooserRow] {
        WorkspaceChooserModel.rows(
            plan: settings.contextPlan,
            connectedDisplayIDs: Set(displayLayout.displays.map(\.id)),
            selectedDisplayIDs: selectedDisplayIDs,
            verifiedCurrentContextID: verifiedCurrentWorkspaceID,
            failedCommands: failedContextKeyboardCommands
        )
    }

    var workspaceRecoveryState: WorkspaceRecoveryState? {
        guard let id = workspaceRecoveryTargetID,
              let target = settings.contextPlan.contexts.first(where: { $0.id == id }),
              let observation = workspaceObservation(),
              workspaceConnectionSession.status(
                for: Set(target.displayIDs).intersection(selectedDisplayIDs),
                spaceIDsByDisplayID: observation.spaceIDsByDisplayID
              ) == .ready else { return nil }
        return WorkspaceRecoveryState(
            targetContext: target, selectedDisplayIDs: selectedDisplayIDs, displays: observation.displays
        )
    }

    func displayName(for id: String) -> String {
        displayLayout.displays.first { $0.id == id }?.name
            ?? settings.displaySelection.knownDisplayNames[id]
            ?? (settings.language == .korean ? "이전에 사용한 화면" : "Previously used display")
    }

    /// Numeric Space handles remain transient; durable identity keys are local bookmarks.
    func workspaceObservation(includingUnselectedDisplays: Bool = false) -> WorkspaceLayoutObservation? {
        if let workspaceObservationOverride { return workspaceObservationOverride() }
        if let selectedDisplaySpacesOverride {
            guard let displays = selectedDisplaySpacesOverride() else { return nil }
            return WorkspaceLayoutObservation(displays: displays, spaceIDsByDisplayID: workspaceSpaceIDsOverride?() ?? [:])
        }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        let isInteractiveSession = (session[kCGSessionOnConsoleKey as String] as? Bool) == true
            && (session["CGSSessionScreenIsLocked"] as? Bool) != true
        // The login/lock screen can expose a temporary, smaller Space layout.
        // Never use that layout to rewrite the user's saved workspaces.
        guard isInteractiveSession, let layouts = spaceLayoutReader.readLayout() else { return nil }
        return WorkspaceLayoutObservation.make(
            layouts: layouts, snapshots: displayObserver.currentSnapshots(),
            selectedDisplayIDs: includingUnselectedDisplays ? Set(displayLayout.displays.map(\.id)) : selectedDisplayIDs,
            isInteractiveSession: isInteractiveSession
        )
    }

    func workspaceSpaceIDs() -> [String: [UInt64]]? {
        workspaceObservation()?.spaceIDsByDisplayID
    }

    func refreshWorkspaceStatus() {
        let observation = workspaceObservation()
        _ = reconcileWorkspaceLayout(observation)
        applyWorkspaceObservation(observation)
    }

    @discardableResult
    func refreshWorkspaceList() -> Bool {
        guard canAddContext, pendingContextCaptureAlignment == nil else { return false }
        let observation = workspaceObservation()
        let refreshed = reconcileWorkspaceLayout(observation, initializesEmptyPlan: true)
        if refreshed, let observation { refreshWorkspaceNames(observation: observation) }
        applyWorkspaceObservation(observation)
        return refreshed
    }

    func reconcileWorkspaceLayout(_ observation: WorkspaceLayoutObservation?, initializesEmptyPlan: Bool = false) -> Bool {
        reconcileSavedWorkspaceLayout(observation)
    }

    func workspaceAssignmentReadiness(contextID: String) -> WorkspaceRecoveryState? {
        guard let context = settings.contextPlan.contexts.first(where: { $0.id == contextID }) else { return nil }
        return WorkspaceRecoveryState(targetContext: context, selectedDisplayIDs: selectedDisplayIDs,
                                      displays: workspaceObservedDisplays)
    }

    func isWorkspaceAssignmentAvailable(contextID: String) -> Bool {
        if let context = settings.contextPlan.contexts.first(where: { $0.id == contextID }), !unresolvedWorkspaceMembers(context).isEmpty { return false }
        if let context = settings.contextPlan.contexts.first(where: { $0.id == contextID }),
           !Set(context.displayIDs).isDisjoint(with: workspaceIdentityBlockedDisplayIDs) { return false }
        guard let state = workspaceAssignmentReadiness(contextID: contextID) else { return false }
        return state.canRetry || state.isResolved
    }

    func applyWorkspaceObservation(_ observation: WorkspaceLayoutObservation?) {
        workspaceLatestObservation = observation
        workspaceObservedDisplays = observation?.displays
        reconcileWorkspaceDesktopNames(observation)
        let required = selectedDisplayIDs.intersection(Set(settings.contextPlan.contexts.flatMap(\.displayIDs)))
        workspaceIdentityBlockedDisplayIDs = workspaceIdentityUnavailable(in: observation)
        if !required.isDisjoint(with: workspaceIdentityBlockedDisplayIDs) {
            workspaceConnectionStatus = .changed(required.intersection(workspaceIdentityBlockedDisplayIDs))
            verifiedCurrentWorkspaceID = nil
            updateContextPlan { $0.markNeedsSync() }
            return
        }
        // Restore the released behavior: read current desktops on launch/reconnection.
        // A saved workspace does not require a separate confirmation on every app run.
        if let observation, workspaceConnectionSession.confirm(spaceIDsByDisplayID: observation.spaceIDsByDisplayID) {
            if !isSwitching, contextCaptureSession == nil, pendingContextCaptureAlignment == nil {
                let alreadyAligned = observation.spaceIDsByDisplayID.allSatisfy { id, ids in
                    workspaceLastObservedSpaceIDs[id] == nil || workspaceLastObservedSpaceIDs[id] == ids
                }
                if alreadyAligned { rememberWorkspaceObservation(observation) }
                var counts = workspacePreferences?.dictionary(forKey: "sideby.workspace-desktop-counts") as? [String: Int] ?? [:]
                for display in observation.displays { counts[display.displayID] = display.spaceCount }
                workspacePreferences?.set(counts, forKey: "sideby.workspace-desktop-counts")
            }
            workspaceConnectionStatus = workspaceConnectionSession.status(for: required,
                spaceIDsByDisplayID: observation.spaceIDsByDisplayID)
        } else {
            workspaceConnectionSession.reset()
            workspaceConnectionStatus = .unavailable(required)
        }
        verifiedCurrentWorkspaceID = nil
        guard workspaceConnectionStatus == .ready, let displays = observation?.displays else {
            updateContextPlan { $0.markNeedsSync() }
            return
        }
        let matches = settings.contextPlan.contexts.filter { context in
            unresolvedWorkspaceMembers(context, observation: observation).isEmpty && WorkspaceRecoveryState(
                targetContext: context, selectedDisplayIDs: selectedDisplayIDs, displays: displays
            ).isResolved
        }
        let preferred = matches.first { $0.id == settings.contextPlan.currentContextID }
        guard let match = preferred ?? (matches.count == 1 ? matches.first : nil) else {
            updateContextPlan { $0.markNeedsSync() }
            return
        }
        verifiedCurrentWorkspaceID = match.id
        if settings.contextPlan.currentContextID != match.id || settings.contextPlan.syncState != .synchronized {
            updateContextPlan { _ = $0.setCurrentContext(id: match.id) }
        }
    }

    @discardableResult
    func confirmWorkspaceConnections() -> Bool {
        guard !isSwitching, contextCaptureSession == nil else { return false }
        workspaceConnectionSession.reset()
        workspaceObservedDisplays = nil
        verifiedCurrentWorkspaceID = nil
        workspaceGuideIsRecording = false
        if !firstWorkProgress.isComplete { firstWorkProgress = WorkspaceFirstRunProgress() }
        guard let observation = workspaceObservation(), !selectedDisplayIDs.isEmpty else {
            workspaceConnectionStatus = .unavailable(selectedDisplayIDs)
            return false
        }
        let snapshot = observation.spaceIDsByDisplayID
        let displays = observation.displays
        if !workspaceLastObservedSpaceKeys.isEmpty { _ = reconcileWorkspaceLayout(observation) }
        guard !workspaceIdentityNeedsReview, workspaceIdentityUnavailable(in: observation).isEmpty else { return false }
        workspaceObservedDisplays = displays
        let mapped = settings.contextPlan.contexts.filter { !Set($0.displayIDs).isDisjoint(with: selectedDisplayIDs) }
        let readiness = mapped.map {
            WorkspaceRecoveryState(targetContext: $0, selectedDisplayIDs: selectedDisplayIDs, displays: displays)
        }
        // An obsolete assignment must not prevent other workspaces from using the current display layout.
        // Unreadable participating displays still require review; each target is validated again before moving.
        guard !mapped.isEmpty, readiness.allSatisfy({ $0.unavailableDisplayIDs.isEmpty }),
              readiness.contains(where: { $0.canRetry || $0.isResolved }),
              workspaceConnectionSession.confirm(spaceIDsByDisplayID: snapshot) else {
            workspaceConnectionStatus = .changed(selectedDisplayIDs)
            lastSwitchResult = strings.workspaceConnectionReviewMessage
            return false
        }
        workspaceRecoveryTargetID = nil
        applyWorkspaceObservation(observation)
        return workspaceConnectionStatus == .ready
    }

    func admitWorkspaceActivation(_ target: ContextDefinition, snapshot: [String: [UInt64]]?) -> Bool {
        let required = Set(target.displayIDs).intersection(selectedDisplayIDs)
        guard unresolvedWorkspaceMembers(target).isEmpty, required.isDisjoint(with: workspaceIdentityBlockedDisplayIDs),
              settings.savedWorkspaces.initialized || !workspaceIdentityNeedsReview,
              settings.contextPlan.contexts.first(where: { $0.id == target.id })?.displaySpaceIndexes == target.displaySpaceIndexes,
              required.allSatisfy({ workspaceLastObservedSpaceIDs[$0] == nil || workspaceLastObservedSpaceIDs[$0] == snapshot?[$0] }) else {
            workspaceConnectionStatus = .changed(required)
            workspaceRecoveryTargetID = target.id
            verifiedCurrentWorkspaceID = nil
            lastSwitchResult = strings.workspaceConnectionReviewMessage
            return false
        }
        var currentLayout = WorkspaceConnectionSession()
        guard let snapshot, currentLayout.confirm(spaceIDsByDisplayID: snapshot),
              currentLayout.status(for: required, spaceIDsByDisplayID: snapshot) == .ready else {
            workspaceConnectionStatus = .unavailable(required)
            workspaceRecoveryTargetID = target.id
            verifiedCurrentWorkspaceID = nil
            lastSwitchResult = strings.workspaceLayoutUnavailable
            return false
        }
        guard required.allSatisfy({ id in
            guard let index = target.spaceIndex(for: id), let count = snapshot[id]?.count else { return false }
            return index >= 0 && index < count
        }) else {
            workspaceRecoveryTargetID = target.id
            lastSwitchResult = strings.workspaceConnectionReviewMessage
            return false
        }
        workspaceConnectionSession = currentLayout
        workspaceConnectionStatus = .ready
        return true
    }

    @discardableResult
    func recordWorkspaceActivation(
        _ target: ContextDefinition, succeeded: Bool, recordsVisit: Bool = true,
        expectedConfigurationRevision: Int? = nil, originContextID: String? = nil
    ) -> Bool {
        let succeeded = succeeded && (expectedConfigurationRevision == nil || expectedConfigurationRevision == workspaceConfigurationRevision)
        lastWorkspaceSwitchSucceeded = succeeded
        workspaceSwitchTargetName = nil
        if succeeded {
            workspaceRecoveryTargetID = nil
            verifiedCurrentWorkspaceID = target.id
            if recordsVisit {
                if let originContextID { workspaceHistory.recordSuccessfulVisit(contextID: originContextID) }
                workspaceHistory.recordSuccessfulVisit(contextID: target.id)
                if workspaceGuideIsRecording {
                    firstWorkProgress.recordSuccessfulVisit(contextID: target.id)
                    saveFirstWorkProgress()
                }
            }
        } else {
            workspaceRecoveryTargetID = target.id
            verifiedCurrentWorkspaceID = nil
        }
        return succeeded
    }

    func retryWorkspaceTransition() {
        guard let id = workspaceRecoveryTargetID else { return }
        activateContext(contextID: id)
    }

    func workspaceConfigurationChanged(from previousPlan: ContextPlan, selectedIDs previousSelected: Set<String>) {
        let oldMappings = Dictionary(uniqueKeysWithValues: previousPlan.contexts.map { ($0.id, $0.displaySpaceIndexes) })
        let newMappings = Dictionary(uniqueKeysWithValues: settings.contextPlan.contexts.map { ($0.id, $0.displaySpaceIndexes) })
        let mappingChanged = oldMappings != newMappings
        if mappingChanged {
            workspaceConnectionSession.reset()
            workspaceConnectionStatus = .unconfirmed
            verifiedCurrentWorkspaceID = nil
            workspaceRecoveryTargetID = nil
        }
        if mappingChanged || previousSelected != selectedDisplayIDs {
            workspaceConfigurationRevision += 1
            workspaceHistory.reconcile(validContextIDs: Set(settings.contextPlan.contexts.map(\.id)))
            workspaceGuideIsRecording = false
            if !firstWorkProgress.isComplete { firstWorkProgress = WorkspaceFirstRunProgress() }
        }
        let validIDs = Set(settings.contextPlan.contexts.map(\.id))
        firstWorkProgress.reconcile(validContextIDs: validIDs)
        saveFirstWorkProgress()
    }

    func applyWorkspaceSettings(_ incoming: AppSettings) {
        let previousPlan = settings.contextPlan
        let previousSelected = selectedDisplayIDs
        settings = incoming
        settings.displaySelection.reconcile(with: displayLayout)
        selectedDisplayIDs = settings.displaySelection.connectedSelectedDisplayIDs(in: displayLayout)
        workspaceConfigurationChanged(from: previousPlan, selectedIDs: previousSelected)
        refreshWorkspaceStatus()
    }

    func loadFirstWorkProgress() {
        if let data = workspacePreferences?.data(forKey: "sideby.workspace-first-roundtrip"),
           let progress = try? JSONDecoder().decode(WorkspaceFirstRunProgress.self, from: data) {
            firstWorkProgress = progress
        }
        firstWorkProgress.reconcile(validContextIDs: Set(settings.contextPlan.contexts.map(\.id)))
        // A restarted process must establish a new verified starting point.
        if !firstWorkProgress.isComplete { firstWorkProgress = WorkspaceFirstRunProgress() }
        isShowingFirstWorkGuide = !firstWorkProgress.isComplete
            && !(workspacePreferences?.bool(forKey: "sideby.workspace-guide-dismissed") ?? false)
    }

    func saveFirstWorkProgress() {
        guard let data = try? JSONEncoder().encode(firstWorkProgress) else { return }
        workspacePreferences?.set(data, forKey: "sideby.workspace-first-roundtrip")
    }

    func beginFirstWorkRoundTrip() {
        let contexts = settings.contextPlan.contexts.sorted { $0.order < $1.order }
            .filter { isWorkspaceAssignmentAvailable(contextID: $0.id) }
        guard contexts.count >= 2, workspaceConnectionStatus == .ready, canActivateContext else { return }
        firstWorkProgress = WorkspaceFirstRunProgress()
        workspaceGuideIsRecording = true
        saveFirstWorkProgress()
        activateContext(contextID: contexts[0].id)
    }

    func dismissFirstWorkGuide() {
        isShowingFirstWorkGuide = false
        workspaceGuideIsRecording = false
        workspacePreferences?.set(true, forKey: "sideby.workspace-guide-dismissed")
    }

    func showFirstWorkGuide() {
        isShowingFirstWorkGuide = true
        workspaceGuideIsRecording = firstWorkProgress.originContextID != nil && !firstWorkProgress.isComplete
        workspacePreferences?.set(false, forKey: "sideby.workspace-guide-dismissed")
    }

    func openMissionControl() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
    }
}
