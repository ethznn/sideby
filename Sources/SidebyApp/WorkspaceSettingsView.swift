import AppKit
import SidebyCore
import SidebyUI
import SwiftUI

struct WorkspaceSettingsView: View {
    @ObservedObject var model: SidebyAppModel
    @ObservedObject var navigation: ProductUINavigation
    let layout: WorkspaceTablePresentation
    @Binding var selection: WorkspaceSettingsSelection
    @State private var showsDisconnectedAssignments = false
    private var strings: SettingsRefreshStrings { .init(language: model.settings.language) }
    private var connectedIDs: Set<String> { Set(model.displayLayout.displays.map(\.id)) }
    private var hasDisconnectedAssignments: Bool {
        !Set(model.settings.contextPlan.contexts.flatMap(\.displayIDs)
             + Array(model.settings.displaySelection.knownDisplayNames.keys)).subtracting(connectedIDs).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(strings.pane(.workspaces)).font(.system(size: 22, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
            }
            WorkspaceRebuildControls(model: model)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(strings.displayHeading).fontWeight(.semibold)
                    Spacer(minLength: 4)
                    Button(strings.selectAll) { model.selectAllDisplayTargets() }.pointingHandCursor().disabled(!model.canAddContext || connectedIDs.isEmpty)
                }
                NativeDisplaySelector(displays: model.displayLayout.displays, selectedIDs: model.selectedDisplayIDs,
                    language: model.settings.language, isEnabled: model.canAddContext,
                    setSelected: { model.setDisplayTarget($0, isSelected: $1) })
                if connectedIDs.isEmpty { Text(strings.noDisplays).foregroundStyle(NativeSurfaceStyle.secondaryText) }
                if hasDisconnectedAssignments {
                    Button(showsDisconnectedAssignments ? strings.hideDisconnectedAssignments : strings.showDisconnectedAssignments) {
                        showsDisconnectedAssignments.toggle()
                    }.buttonStyle(.link).pointingHandCursor()
                }
            }
            WorkspaceMatrixView(model: model, showsDisconnected: showsDisconnectedAssignments,
                focusContextID: navigation.settingsRoute.contextID, focusDisplayID: navigation.settingsRoute.displayID)
            if selection.missingContextID != nil { Text(strings.missingTarget).foregroundStyle(NativeSurfaceStyle.secondaryText) }
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText)
        .onAppear { model.refreshWorkspaceStatus(); revealRoute(navigation.settingsRoute) }
        .onReceive(navigation.$settingsRoute) { revealRoute($0) }
        .onChange(of: model.settings.contextPlan.contexts.map(\.id)) { _, ids in
            selection.reconcile(contextIDs: ids, preferredID: nil)
        }
        .sheet(isPresented: Binding(get: { model.pendingContextCaptureAlignment != nil },
                                   set: { if !$0 { model.cancelContextCaptureAlignment() } })) {
            if let request = model.pendingContextCaptureAlignment {
                ContextCaptureAlignmentPicker(request: request, strings: model.strings,
                    choose: { model.chooseContextCaptureAlignment(contextID: $0) }, cancel: { model.cancelContextCaptureAlignment() })
            }
        }
    }

    private func revealRoute(_ route: ProductSettingsRoute) {
        selection.reconcile(contextIDs: model.settings.contextPlan.contexts.map(\.id), preferredID: route.contextID)
        if let id = route.displayID, !connectedIDs.contains(id) { showsDisconnectedAssignments = true }
        if let id = route.contextID, let context = model.settings.contextPlan.contexts.first(where: { $0.id == id }),
           !context.displayIDs.isEmpty, Set(context.displayIDs).isDisjoint(with: connectedIDs) { showsDisconnectedAssignments = true }
    }
}

struct WorkspaceAssignmentReviewFooter: View {
    @ObservedObject var model: SidebyAppModel
    @ObservedObject var navigation: ProductUINavigation
    let finishAssignmentReview: () -> Void
    private var strings: SettingsRefreshStrings { .init(language: model.settings.language) }
    private var hasInvalidAssignments: Bool {
        model.settings.contextPlan.contexts.contains {
            !(model.workspaceAssignmentReadiness(contextID: $0.id)?.invalidDisplayIDs.isEmpty ?? true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.compactAutoSave).foregroundStyle(NativeSurfaceStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if hasInvalidAssignments {
                VStack(alignment: .leading, spacing: 4) {
                    Text(strings.missingDesktopHelp).fixedSize(horizontal: false, vertical: true)
                    Button(strings.openMissionControl) { model.openMissionControl() }.pointingHandCursor()
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { status; Spacer(minLength: 0); confirmation }
                VStack(alignment: .leading, spacing: 8) { status; confirmation }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch model.workspaceConnectionStatus {
        case .ready: Label(hasInvalidAssignments ? strings.usableAssignmentsConfirmed : strings.confirmed,
                           systemImage: "checkmark.circle")
        case .unconfirmed: Text(model.strings.workspaceNeedsConfirmation)
        case .changed: Text(model.strings.workspaceConnectionsChanged)
        case .unavailable:
            VStack(alignment: .leading, spacing: 4) {
                Text(model.strings.workspaceLayoutUnavailable)
                Button(model.strings.workspaceCheckAgain) { model.refreshWorkspaceStatus() }.pointingHandCursor()
            }
        }
    }

    private var confirmation: some View {
        Button {
            if model.confirmWorkspaceConnections() { finishAssignmentReview() }
        } label: {
            Text(confirmTitle).fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderedProminent).pointingHandCursor().controlSize(.large)
        .disabled(!model.canAddContext || model.selectedDisplayIDs.isEmpty)
    }

    private var confirmTitle: String {
        switch navigation.settingsRoute.returnTo {
        case .daily: strings.confirmReturnDaily
        case .onboarding: strings.confirmReturnGuide
        case nil: strings.confirmAssignments
        }
    }
}
