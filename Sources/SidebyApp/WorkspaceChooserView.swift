import SidebyCore
import SidebyUI
import SwiftUI

struct WorkspaceChooserActions {
    var openSettings: () -> Void
    var editWorkspaces: () -> Void
    var reviewAssignments: (String?, String?) -> Void
    var openPermissions: () -> Void
    var resumeOnboarding: () -> Void
}

struct WorkspaceChooserView: View {
    @ObservedObject var model: SidebyAppModel
    let actions: WorkspaceChooserActions
    @State private var actionMessage: String?
    @ScaledMetric(relativeTo: .body) private var bodySize = 13.0
    @ScaledMetric(relativeTo: .caption) private var detailSize = 11.0
    private var strings: SBSStrings { model.strings }
    private var copy: DailyRefreshStrings { .init(language: model.settings.language) }
    private var recovery: WorkspaceRecoveryState? { model.workspaceRecoveryState }
    private var presentation: WorkspaceDailyPresentation {
        WorkspaceDailyPresentation(plan: model.settings.contextPlan, isSwitching: model.isSwitching,
            isCapturing: model.contextCaptureSession != nil || model.pendingContextCaptureAlignment != nil,
            isEnabled: model.isEnabled, hasRequiredPermissions: model.permissionState == .granted && model.hasSwitchingAccess,
            connectionStatus: model.workspaceConnectionStatus, recovery: recovery,
            verifiedCurrentContextID: model.verifiedCurrentWorkspaceID, failedTargetID: model.workspaceRecoveryTargetID)
    }

    var body: some View {
        let matrixCopy = WorkspaceMatrixStrings(language: model.settings.language)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(matrixCopy.title).fontWeight(.semibold)
                Spacer(minLength: 8)
                Button {
                    actionMessage = model.refreshWorkspaceList() ? model.workspaceRefreshMessage : copy.refreshFailed
                } label: { Label(copy.refresh, systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderless).pointingHandCursor()
                    .disabled(!model.canAddContext || model.pendingContextCaptureAlignment != nil)
                    .help(copy.nameHelp)
            }
            stateContent
            NativeDisplaySelector(displays: model.displayLayout.displays, selectedIDs: model.selectedDisplayIDs,
                language: model.settings.language, isEnabled: model.canAddContext,
                setSelected: { model.setDisplayTarget($0, isSelected: $1) })
            WorkspaceMatrixView(model: model, compact: true)
                .frame(height: min(440, max(240, 160 + CGFloat(model.displayLayout.displays.count) * 56)))
            if let actionMessage {
                Text(actionMessage).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let id = model.workspaceHistory.previousContextID,
               id != presentation.currentContextID,
               let row = model.workspaceRows.first(where: { $0.id == id }) {
                Button { model.activateContext(contextID: id) } label: {
                    HStack {
                        Label(strings.workspacePrevious(row.name), systemImage: "arrow.uturn.backward")
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("⌥⇧Tab").foregroundStyle(.secondary)
                    }
                }.buttonStyle(.borderless).pointingHandCursor().disabled(!canActivate(row))
                .help(strings.contextKeyboardPreviousWorkspaceHint)
            }
            HStack {
                Text(SettingsRefreshStrings(language: model.settings.language).compactAutoSave)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(matrixCopy.moreSettings, action: actions.openSettings).pointingHandCursor()
            }
            if !model.firstWorkProgress.isComplete {
                Button(copy.resume, action: actions.resumeOnboarding).buttonStyle(.borderless).pointingHandCursor()
            }
        }.font(.system(size: bodySize))
    }

    @ViewBuilder private var stateContent: some View {
        switch presentation.status {
        case .busy:
            HStack(alignment: .top, spacing: 12) {
                ProgressView().controlSize(.small)
                Text(model.workspaceSwitchTargetName.map(strings.workspaceMovingTo) ?? copy.busy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .disabled:
            NativeStatusSection(tone: .neutral, title: copy.offTitle, message: strings.workspaceTurnOnToMove) {
                Button(copy.turnOn) { model.setSidebyEnabled(true) }.buttonStyle(.borderedProminent).pointingHandCursor()
            }
        case .permissions:
            NativeStatusSection(tone: .warning, title: copy.permissionTitle, message: strings.permissionsSubtitle) {
                Button(copy.permissions, action: actions.openPermissions).buttonStyle(.borderedProminent).pointingHandCursor()
            }
        case .empty:
            NativeStatusSection(tone: .neutral, title: copy.emptyTitle, message: copy.emptyMessage) {
                Button(strings.workspaceStartSetup, action: actions.resumeOnboarding).buttonStyle(.borderedProminent).pointingHandCursor()
            }
        case .connection(let status):
            NativeStatusSection(tone: status == .unconfirmed ? .neutral : .warning,
                                title: copy.reviewTitle, message: connectionMessage(status)) {
                if case .unavailable = status {
                    Button(strings.workspaceCheckAgain) { model.refreshWorkspaceStatus() }.pointingHandCursor()
                } else {
                    Button(copy.review) { actions.reviewAssignments(presentation.failedTargetID, firstAffectedDisplay(status)) }
                        .buttonStyle(.borderedProminent).pointingHandCursor()
                }
            }
        case .recovery:
            if let recovery {
                NativeStatusSection(tone: .warning,
                    title: strings.workspaceTransitionFailed(contextName(presentation.failedTargetID)),
                    message: recoveryMessage(recovery)) {
                    if !model.isEnabled {
                        Button(copy.turnOn) { model.setSidebyEnabled(true) }.pointingHandCursor()
                    } else if model.permissionState != .granted || !model.hasSwitchingAccess {
                        Button(copy.permissions, action: actions.openPermissions).pointingHandCursor()
                    } else if recovery.canRetry {
                        Button(strings.workspaceRetryDisplays(displayNames(recovery.pendingDisplayIDs))) {
                            model.retryWorkspaceTransition()
                        }
                        .buttonStyle(.borderedProminent).pointingHandCursor()
                        .disabled(!model.canActivateContext)
                    } else if !recovery.unavailableDisplayIDs.isEmpty {
                        Button(strings.workspaceCheckAgain) { model.refreshWorkspaceStatus() }.pointingHandCursor()
                    } else {
                        Button(copy.review) { actions.reviewAssignments(presentation.failedTargetID, recovery.invalidDisplayIDs.sorted().first) }.pointingHandCursor()
                    }
                }
            }
        case .ready:
            if presentation.currentContextID == nil {
                Text(strings.workspaceNotAligned).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func canActivate(_ row: WorkspaceChooserRow) -> Bool {
        model.canActivateContext && model.pendingContextCaptureAlignment == nil
            && model.permissionState == .granted && model.hasSwitchingAccess
            && row.hasMoveTargets
            && model.isWorkspaceAssignmentAvailable(contextID: row.id)
    }

    private func connectionMessage(_ status: WorkspaceConnectionStatus) -> String {
        switch status {
        case .ready: ""
        case .unconfirmed: strings.workspaceNeedsConfirmation
        case .changed(let ids): strings.workspaceConnectionsChanged + "\n" + displayNames(ids)
        case .unavailable(let ids): strings.workspaceLayoutUnavailable + "\n" + displayNames(ids)
        }
    }

    private func firstAffectedDisplay(_ status: WorkspaceConnectionStatus) -> String? {
        switch status {
        case .changed(let ids), .unavailable(let ids): ids.sorted().first
        default: nil
        }
    }

    private func recoveryMessage(_ state: WorkspaceRecoveryState) -> String {
        (state.pendingDisplayIDs.sorted().map { strings.workspacePendingDisplay(model.displayName(for: $0)) }
        + state.unavailableDisplayIDs.sorted().map { strings.workspaceUnavailableDisplay(model.displayName(for: $0)) }
        + state.invalidDisplayIDs.sorted().map { strings.workspaceInvalidDisplay(model.displayName(for: $0)) })
        .joined(separator: "\n")
    }

    private func displayNames(_ ids: Set<String>) -> String { ids.sorted().map { model.displayName(for: $0) }.joined(separator: ", ") }
    private func contextName(_ id: String?) -> String {
        model.settings.contextPlan.contexts.first { $0.id == id }?.name ?? strings.workspaceUnavailableName
    }
}
