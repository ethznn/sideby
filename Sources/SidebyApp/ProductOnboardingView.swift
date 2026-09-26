import AppKit
import SwiftUI
import SidebyCore
import SidebyUI

struct ProductOnboardingActions {
    var close: () -> Void
    var finishToDaily: () -> Void
    var openInputSettings: () -> Void
    var openWorkspaceSettings: (String?, String?) -> Void
}

struct ProductOnboardingView: View {
    @ObservedObject var model: SidebyAppModel
    @ObservedObject var presentation: ProductOnboardingPresentation
    let preferences: any ProductUIPreferences
    let actions: ProductOnboardingActions
    @FocusState private var focusedStage: ProductOnboardingStage?
    @AccessibilityFocusState private var accessibleStage: ProductOnboardingStage?
    @ScaledMetric(relativeTo: .title) private var titleSize = 27.0
    @ScaledMetric(relativeTo: .body) private var bodySize = 13.0
    @ScaledMetric(relativeTo: .caption) private var detailSize = 12.0
    @State private var didRequestCapture = false
    @State private var didOpenMissionControl = false
    @State private var observation = ProductOnboardingObservationState()

    init(model: SidebyAppModel, presentation: ProductOnboardingPresentation,
         preferences: any ProductUIPreferences, actions: ProductOnboardingActions) {
        self.model = model
        self.presentation = presentation
        self.preferences = preferences
        self.actions = actions
    }

    private var strings: OnboardingRefreshStrings { .init(language: model.settings.language) }
    private var stage: ProductOnboardingStage { presentation.state.stage }
    private var connectedIDs: Set<String> { Set(model.displayLayout.displays.map(\.id)) }
    private var selectedIDs: Set<String> { model.selectedDisplayIDs.intersection(connectedIDs) }
    private var contexts: [ContextDefinition] {
        model.settings.contextPlan.contexts.sorted { $0.order < $1.order }
            .filter { !Set($0.displayIDs).isDisjoint(with: selectedIDs) }
    }
    private var availableContexts: [ContextDefinition] {
        contexts.filter { model.isWorkspaceAssignmentAvailable(contextID: $0.id) }
    }
    private var facts: ProductOnboardingFacts {
        ProductOnboardingFacts(
            hasAccessibilityPermission: model.permissionState == .granted,
            hasSwitchingAccess: model.hasSwitchingAccess,
            selectedDisplayCount: selectedIDs.count,
            participatingContextIDs: availableContexts.map(\.id),
            connectionStatus: model.workspaceConnectionStatus,
            isBusy: model.isSwitching || model.contextCaptureSession != nil || model.pendingContextCaptureAlignment != nil,
            isEnabled: model.isEnabled, progress: model.firstWorkProgress)
    }
    private var hasPermissions: Bool { facts.hasAccessibilityPermission && facts.hasSwitchingAccess }
    private var hasSavedAssignments: Bool {
        model.settings.contextPlan.contexts.contains { !$0.displayIDs.isEmpty }
    }
    private var unreadable: Bool {
        if case .unavailable = model.workspaceConnectionStatus { return true }
        return observation.isUnavailable
    }
    private var workspaceReadUnavailable: Bool {
        observation.isUnavailable || (unreadable && (hasSavedAssignments || didRequestCapture))
    }
    private var hasObservedShortage: Bool {
        !unreadable && observation.hasShortage(
            hasReadOrSavedAssignments: didRequestCapture || hasSavedAssignments)
    }
    private var nextContextID: String? {
        let progress = model.firstWorkProgress
        if progress.awayContextID != nil { return progress.originContextID }
        if let origin = progress.originContextID { return availableContexts.first { $0.id != origin }?.id }
        return availableContexts.first?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(strings.stage(stage))
                                .font(.system(size: detailSize, weight: .medium))
                                .foregroundStyle(NativeSurfaceStyle.secondaryText)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(NativeSurfaceStyle.tableBackground, in: Capsule())
                                .padding(.bottom, 4)
                            Text(stage == .workspaces && !hasSavedAssignments ? strings.captureTitle : strings.title(stage))
                                .font(.system(size: titleSize, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                                .focusable()
                                .focused($focusedStage, equals: stage)
                                .accessibilityFocused($accessibleStage, equals: stage)
                                .id(stage)
                            Text(strings.subtitle(stage))
                                .foregroundStyle(NativeSurfaceStyle.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        stageContent
                        if facts.isBusy { Text(strings.waiting).foregroundStyle(NativeSurfaceStyle.secondaryText) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
                .onChange(of: stage) { _, newStage in
                    proxy.scrollTo(newStage, anchor: .top)
                    focusedStage = newStage
                    accessibleStage = newStage
                    refreshWorkspaceObservationIfNeeded()
                }
            }
            Divider()
            footer
        }
        .font(.system(size: bodySize))
        .foregroundStyle(NativeSurfaceStyle.primaryText)
        .background(NativeSurfaceStyle.windowBackground)
        .onAppear {
            focusedStage = stage
            accessibleStage = stage
            refreshWorkspaceObservationIfNeeded()
        }
        .onReceive(model.$workspaceConnectionStatus) { _ in
            // Do not deduplicate equal values: key/return and Space refreshes can
            // republish the same status while the observed desktop count changes.
            refreshWorkspaceObservationIfNeeded()
        }
        .onChange(of: facts.isBusy) { _, _ in
            // Status can publish before an operation finishes. Discard while busy,
            // then reread on completion (including alignment choice/cancellation).
            refreshWorkspaceObservationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Returning from system settings/Mission Control refreshes facts, never advances or captures.
            model.refresh()
            refreshWorkspaceObservationIfNeeded()
        }
    }

    @ViewBuilder private var stageContent: some View {
        switch stage {
        case .preparation: preparationContent
        case .displays: displaysContent
        case .workspaces: workspacesContent
        case .roundTrip: roundTripContent
        }
    }

    private var preparationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativePermissionRow(name: model.strings.accessibility,
                reason: model.strings.permissionAccessibilitySubtitle,
                status: facts.hasAccessibilityPermission ? model.strings.granted : model.strings.notGranted) {
                if !facts.hasAccessibilityPermission {
                    Button(model.strings.openAccessibilitySettingsButton) { model.openSystemSettingsAccessibility() }
                        .disabled(facts.isBusy)
                }
            }
            NativePermissionRow(name: model.strings.switchingAccess,
                reason: model.strings.permissionSwitchingAccessSubtitle,
                status: facts.hasSwitchingAccess ? model.strings.granted : model.strings.notGranted) {
                if !facts.hasSwitchingAccess {
                    Button(model.strings.checkSwitchingAccess) { model.requestSwitchingAccess() }
                        .disabled(facts.isBusy)
                }
            }
            if let feedback = model.permissionRequestFeedback {
                NativeStatusSection(tone: .warning, title: model.strings.permissions,
                                    message: model.strings.permissionRequestFeedback(feedback)) {
                    if let action = feedback.action {
                        Button(model.strings.permissionRequestActionTitle(action)) { model.openAccessibilitySettings() }
                    }
                }
            }
            DisclosureGroup(strings.permissionDetails) {
                Text(model.strings.inputPrivacyNote).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            Text(hasPermissions ? strings.accessReady : strings.permissionsNeeded)
                .foregroundStyle(NativeSurfaceStyle.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displaysContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !hasPermissions {
                Text(strings.permissionsNeeded).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.displayLayout.displays.isEmpty {
                NativeStatusSection(tone: .warning, title: strings.noDisplays, message: strings.selectedDisplays(0)) {}
            }
            NativeDisplaySelector(displays: model.displayLayout.displays, selectedIDs: selectedIDs,
                language: model.settings.language, isEnabled: !facts.isBusy,
                setSelected: { model.setDisplayTarget($0, isSelected: $1) })
            Text(strings.selectedDisplays(selectedIDs.count)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            let rememberedIDs = Set(model.settings.displaySelection.knownDisplayNames.keys)
                .union(model.settings.contextPlan.contexts.flatMap(\.displayIDs)).subtracting(connectedIDs)
            if !rememberedIDs.isEmpty {
                Text(strings.rememberedDisplays).fontWeight(.medium).padding(.top, 8)
                ForEach(rememberedIDs.sorted(), id: \.self) { id in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.displayName(for: id))
                        Text(strings.offline(selected: model.settings.displaySelection.selectedDisplayIDs.contains(id)))
                            .font(.system(size: detailSize)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var workspacesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !hasSavedAssignments { Text(strings.captureExplanation).foregroundStyle(NativeSurfaceStyle.secondaryText) }
            ForEach(Array(contexts.prefix(2).enumerated()), id: \.element.id) { index, context in
                VStack(alignment: .leading, spacing: 10) {
                    Text(index == 0 ? model.strings.workspaceGuideFirstName : model.strings.workspaceGuideSecondName)
                        .font(.system(size: detailSize)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    NativeInlineNameField(identity: context.id, value: context.name,
                        label: index == 0 ? model.strings.workspaceGuideFirstName : model.strings.workspaceGuideSecondName) {
                        model.setContextName(contextID: context.id, name: $0)
                    }
                    .disabled(facts.isBusy)
                    assignmentSummary(context)
                }
                .padding(14)
                .background(NativeSurfaceStyle.tableBackground, in: RoundedRectangle(cornerRadius: 8))
            }
            if hasSavedAssignments {
                Text(strings.autosave).font(.system(size: detailSize)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                Button(strings.review) { openAssignments() }.disabled(facts.isBusy)
            }
            if workspaceReadUnavailable {
                NativeStatusSection(tone: .warning, title: model.strings.workspaceLayoutUnavailable, message: strings.unavailable) {}
            } else if hasObservedShortage {
                NativeStatusSection(tone: .warning, title: strings.shortage, message: strings.returnedFromMissionControl) {}
            } else if hasSavedAssignments {
                connectionContent
            }
            if let status = model.contextCaptureStatus {
                Text(status).font(.system(size: detailSize)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let request = model.pendingContextCaptureAlignment {
                ContextCaptureAlignmentPicker(request: request, strings: model.strings,
                    choose: { model.chooseContextCaptureAlignment(contextID: $0) },
                    cancel: { model.cancelContextCaptureAlignment() })
            }
            if hasSavedAssignments || didRequestCapture {
                Text(strings.recaptureExplanation).font(.system(size: detailSize)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !hasObservedShortage {
                    Button(strings.recapture) { capture() }.disabled(!canCapture)
                }
                Button(strings.missionControl) { openMissionControl() }.disabled(facts.isBusy)
            }
        }
    }

    private func assignmentSummary(_ context: ContextDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(context.displayIDs.sorted(), id: \.self) { id in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.displayName(for: id))
                        if !connectedIDs.contains(id) {
                            Text(strings.offline(selected: model.settings.displaySelection.selectedDisplayIDs.contains(id)))
                        } else if !selectedIDs.contains(id) {
                            Text(strings.excluded)
                        }
                    }
                    Spacer(minLength: 8)
                    if let index = context.spaceIndex(for: id), index >= 0 {
                        VStack(alignment: .trailing, spacing: 3) {
                            if let name = model.workspaceDesktopName(displayID: id, spaceIndex: index) {
                                Text(name).foregroundStyle(.primary).fontWeight(.medium).lineLimit(2)
                            }
                            Text(strings.desktop(index))
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Text(model.strings.workspaceInvalidDisplay(model.displayName(for: id)))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: detailSize)).foregroundStyle(NativeSurfaceStyle.secondaryText)
    }

    @ViewBuilder private var connectionContent: some View {
        switch model.workspaceConnectionStatus {
        case .ready: EmptyView()
        case .unconfirmed:
            NativeStatusSection(tone: .neutral, title: model.strings.workspaceNeedsConfirmation,
                                message: model.strings.workspaceConnectionReviewMessage) {}
        case .changed(let ids):
            NativeStatusSection(tone: .warning, title: model.strings.workspaceConnectionsChanged,
                                message: displayNames(ids)) {}
        case .unavailable(let ids):
            NativeStatusSection(tone: .warning, title: model.strings.workspaceLayoutUnavailable,
                                message: displayNames(ids)) {}
        }
    }

    private var roundTripContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            let progress = model.firstWorkProgress
            if progress.isComplete, let a = progress.originContextID, let b = progress.awayContextID {
                NativeStatusSection(tone: .neutral, title: strings.roundTripComplete,
                                    message: strings.complete(contextName(a), contextName(b))) {}
                Text(strings.menuHint).foregroundStyle(NativeSurfaceStyle.secondaryText).fixedSize(horizontal: false, vertical: true)
                Text(strings.previousShortcutHint).fixedSize(horizontal: false, vertical: true)
                if model.heldMatrixConfiguration.isEnabled, model.heldMatrixShortcutError == nil {
                    Text(HeldMatrixStrings(language: model.settings.language).discover(
                        KeyboardShortcutFormatter.shortcutText(model.heldMatrixConfiguration.shortcut)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(strings.optionalInput, action: actions.openInputSettings)
            } else {
                if let a = progress.originContextID {
                    Label(contextName(a), systemImage: "checkmark.circle")
                    if let b = progress.awayContextID { Label(contextName(b), systemImage: "checkmark.circle") }
                } else if let first = contexts.first {
                    Text(strings.firstMove(first.name)).fixedSize(horizontal: false, vertical: true)
                    assignmentSummary(first)
                }
                if !hasPermissions {
                    Text(strings.permissionsNeeded).foregroundStyle(NativeSurfaceStyle.secondaryText)
                } else if !model.isEnabled {
                    Text(model.strings.workspaceTurnOnToMove).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    Text(model.inputStatus).font(.system(size: detailSize)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                }
                connectionContent
                if let recovery = model.workspaceRecoveryState, !recovery.isResolved {
                    recoveryContent(recovery)
                } else if let targetID = model.workspaceRecoveryTargetID {
                    NativeStatusSection(tone: .warning,
                        title: model.strings.workspaceTransitionFailed(contextName(targetID)),
                        message: model.lastSwitchResult) {}
                }
                if contexts.count < 2 { Text(strings.shortage).foregroundStyle(NativeSurfaceStyle.secondaryText) }
            }
        }
    }

    private func recoveryContent(_ recovery: WorkspaceRecoveryState) -> some View {
        NativeStatusSection(tone: .warning,
            title: model.strings.workspaceTransitionFailed(contextName(model.workspaceRecoveryTargetID ?? "")),
            message: model.lastSwitchResult) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(recovery.pendingDisplayIDs.sorted(), id: \.self) { Text(model.strings.workspacePendingDisplay(model.displayName(for: $0))) }
                ForEach(recovery.unavailableDisplayIDs.sorted(), id: \.self) { Text(model.strings.workspaceUnavailableDisplay(model.displayName(for: $0))) }
                ForEach(recovery.invalidDisplayIDs.sorted(), id: \.self) { Text(model.strings.workspaceInvalidDisplay(model.displayName(for: $0))) }
                ForEach(recovery.alignedDisplayIDs.sorted(), id: \.self) { Text(model.strings.workspaceAlignedDisplay(model.displayName(for: $0))) }
            }
        }
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                laterButton
                Spacer(minLength: 8)
                backButton
                primaryButton
            }
            VStack(alignment: .trailing, spacing: 12) {
                primaryButton
                HStack { laterButton; Spacer(); backButton }
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 15)
        .frame(minHeight: 62)
        .background(NativeSurfaceStyle.tableBackground)
    }
    private var laterButton: some View {
        Button(strings.later) { dismiss(); actions.close() }.keyboardShortcut(.cancelAction)
    }
    @ViewBuilder private var backButton: some View {
        if stage != .preparation {
            Button(strings.back) { presentation.goBack() }.disabled(facts.isBusy)
        }
    }

    private enum PrimaryAction {
        case advance, requestAccessibility, requestSwitching, refresh, capture, missionControl
        case confirm, permissions, turnOn, review, move, retry, finish
    }
    private var primaryAction: PrimaryAction {
        switch stage {
        case .preparation:
            if !facts.hasAccessibilityPermission { return .requestAccessibility }
            if !facts.hasSwitchingAccess { return .requestSwitching }
            return .advance
        case .displays:
            switch ProductOnboardingDisplayAction.resolve(hasRequiredPermissions: hasPermissions,
                                                          connectedDisplayCount: model.displayLayout.displays.count) {
            case .permissions: return .permissions
            case .refresh: return .refresh
            case .advance: return .advance
            }
        case .workspaces:
            if !hasPermissions { return .permissions }
            if selectedIDs.isEmpty { return .review }
            if workspaceReadUnavailable { return .refresh }
            if hasObservedShortage { return didOpenMissionControl ? .capture : .missionControl }
            if !hasSavedAssignments || contexts.isEmpty { return .capture }
            if contexts.count < 2 || (model.workspaceObservedDisplays != nil && availableContexts.count < 2) {
                return observation.didCheckObservation ? .capture : .refresh
            }
            return .confirm
        case .roundTrip:
            if model.firstWorkProgress.isComplete { return .finish }
            if !hasPermissions { return .permissions }
            if !model.isEnabled { return .turnOn }
            if unreadable { return .refresh }
            if model.workspaceConnectionStatus != .ready || availableContexts.count < 2 { return .review }
            if let recovery = model.workspaceRecoveryState, !recovery.isResolved {
                if recovery.canRetry { return .retry }
                return recovery.invalidDisplayIDs.isEmpty ? .refresh : .review
            }
            return .move
        }
    }
    private var primaryTitle: String {
        switch primaryAction {
        case .advance: return stage == .preparation ? strings.chooseDisplays : strings.prepareWorkspaces
        case .requestAccessibility: return model.strings.openAccessibilitySettingsButton
        case .requestSwitching: return model.strings.checkSwitchingAccess
        case .refresh: return model.strings.workspaceCheckAgain
        case .capture: return hasSavedAssignments || didRequestCapture ? strings.recapture : strings.capture
        case .missionControl: return strings.missionControl
        case .confirm: return strings.confirm
        case .permissions: return strings.reviewPermissions
        case .turnOn: return strings.turnOn
        case .review: return strings.review
        case .move:
            let name = contextName(nextContextID ?? "")
            return model.firstWorkProgress.awayContextID == nil ? strings.move(name) : strings.returnTo(name)
        case .retry:
            return model.strings.workspaceRetryDisplays(displayNames(model.workspaceRecoveryState?.pendingDisplayIDs ?? []))
        case .finish: return strings.openChooser
        }
    }
    private var canCapture: Bool { hasPermissions && !selectedIDs.isEmpty && !facts.isBusy }
    private var primaryEnabled: Bool {
        guard !facts.isBusy else { return false }
        switch primaryAction {
        case .advance, .finish: return presentation.state.canContinue(using: facts)
        case .capture: return canCapture
        case .confirm: return hasPermissions && contexts.count >= 2 && !selectedIDs.isEmpty
        case .move:
            guard hasPermissions, model.canActivateContext, model.workspaceConnectionStatus == .ready,
                  let id = nextContextID else { return false }
            return model.workspaceRows.first { $0.id == id }?.hasMoveTargets == true
        case .retry:
            return hasPermissions && model.canActivateContext && model.workspaceConnectionStatus == .ready
                && model.workspaceRecoveryState?.canRetry == true
        default: return true
        }
    }
    private var primaryButton: some View {
        Button(action: performPrimaryAction) {
            Text(primaryTitle).fixedSize(horizontal: false, vertical: true).frame(minHeight: 24)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .keyboardShortcut(.defaultAction).disabled(!primaryEnabled)
    }

    private func performPrimaryAction() {
        guard primaryEnabled else { return }
        switch primaryAction {
        case .advance:
            if stage == .preparation { model.prepareFirstWorkspaceGuideIfNeeded(preferences: preferences) }
            _ = presentation.continueIfAllowed(using: facts)
        case .requestAccessibility: model.openSystemSettingsAccessibility()
        case .requestSwitching: model.requestSwitchingAccess()
        case .refresh: model.refresh(); checkObservation()
        case .capture: capture()
        case .missionControl: openMissionControl()
        case .confirm:
            if model.confirmWorkspaceConnections() { _ = presentation.continueIfAllowed(using: facts) }
        case .permissions:
            while presentation.state.stage != .preparation { presentation.goBack() }
        case .turnOn: model.setSidebyEnabled(true)
        case .review:
            if stage == .roundTrip { presentation.goBack() }
            openAssignments()
        case .move:
            model.showFirstWorkGuide()
            if model.firstWorkProgress.originContextID == nil {
                model.beginFirstWorkRoundTrip()
            } else if let id = nextContextID {
                model.activateContext(contextID: id)
            }
        case .retry:
            model.prepareFirstWorkspaceGuideRetry()
            model.retryWorkspaceTransition()
        case .finish:
            dismiss()
            actions.finishToDaily()
        }
    }
    private func dismiss() {
        preferences.didDismissOnboarding = true
        model.dismissFirstWorkGuide()
    }
    private func capture() {
        guard canCapture else { return }
        didRequestCapture = true
        didOpenMissionControl = false
        model.startContextCapture()
        checkObservation()
    }
    private func checkObservation() {
        observation.refresh(isBusy: facts.isBusy) {
            ProductInstantContextCaptureStartPolicy.plan(
                for: model.workspaceObservation()?.displays, selectedDisplayIDs: selectedIDs)?.contexts.count
        }
    }
    private func refreshWorkspaceObservationIfNeeded() {
        if stage == .workspaces {
            checkObservation()
            model.loadWorkspaceNamesIfNeeded()
        } else {
            observation.invalidate()
        }
    }
    private func openMissionControl() {
        didOpenMissionControl = true
        model.openMissionControl()
    }
    private func openAssignments() {
        let target = model.workspaceRecoveryTargetID ?? contexts.first?.id
        let displayID: String?
        switch model.workspaceConnectionStatus {
        case .changed(let ids), .unavailable(let ids): displayID = ids.sorted().first
        default: displayID = model.workspaceRecoveryState?.invalidDisplayIDs.sorted().first
        }
        actions.openWorkspaceSettings(target, displayID)
    }
    private func contextName(_ id: String) -> String {
        model.settings.contextPlan.contexts.first { $0.id == id }?.name ?? model.strings.workspaceNeedsConfirmation
    }
    private func displayNames(_ ids: Set<String>) -> String { ids.sorted().map { model.displayName(for: $0) }.joined(separator: ", ") }
}
