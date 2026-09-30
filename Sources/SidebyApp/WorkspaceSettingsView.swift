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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.saveCopy.savedWorkspaces).font(.system(size: 23, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text(model.saveCopy.text("Review your saved setups. Edit one setup at a time.", "저장한 구성을 살펴보고 구성 하나씩 수정하세요."))
                        .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                }
                Spacer()
                Button { model.showWorkspaceSave() } label: { Label(model.saveCopy.saveConfiguration, systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(NativeSurfaceStyle.accent).disabled(!model.canSaveWorkspace).pointingHandCursor()
            }
            WorkspaceMatrixView(model: model, showsDisconnected: true,
                focusContextID: navigation.settingsRoute.contextID, focusDisplayID: navigation.settingsRoute.displayID)
            HStack {
                if let message = model.workspaceSaveMessage { Text(message).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.accent) }
                Spacer()
                Button { _ = model.undoSavedWorkspaceChange() } label: { Label(model.saveCopy.undo, systemImage: "arrow.uturn.backward") }
                    .disabled(model.settings.savedWorkspaces.undo == nil || !model.canSaveWorkspace).pointingHandCursor()
            }
            DisclosureGroup(model.saveCopy.text("Display participation", "함께 움직일 화면 설정")) {
                NativeDisplaySelector(displays: model.displayLayout.displays, selectedIDs: model.selectedDisplayIDs,
                    language: model.settings.language, isEnabled: model.canSaveWorkspace,
                    setSelected: { model.setDisplayTarget($0, isSelected: $1) }).padding(.top, 10)
            }.font(.system(size: 12))
            if model.workspaceRebuildBackup != nil {
                WorkspaceRebuildControls(model: model)
            }
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText).tint(NativeSurfaceStyle.accent)
        .onAppear { model.refreshWorkspaceStatus(); revealRoute(navigation.settingsRoute) }
        .onReceive(navigation.$settingsRoute) { revealRoute($0) }
        .onChange(of: model.settings.contextPlan.contexts.map(\.id)) { _, ids in selection.reconcile(contextIDs: ids, preferredID: nil) }
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
    private var copy: WorkspaceSaveStrings { model.saveCopy }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.text("Save changes in each setup’s editor.", "구성 편집창에서 변경사항을 저장하세요."))
                if model.workspaceObservedDisplays == nil {
                    Text(copy.readUnavailable).foregroundStyle(NativeSurfaceStyle.secondaryText)
                } else {
                    Text(copy.text("Checking desktops keeps your saved setups intact.", "데스크탑 상태를 다시 확인해도 저장한 구성은 유지됩니다."))
                        .foregroundStyle(NativeSurfaceStyle.secondaryText)
                }
            }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(copy.text("Check desktops", "데스크탑 확인")) { model.refreshWorkspaceStatus() }
                .disabled(!model.canSaveWorkspace).pointingHandCursor()
            if navigation.settingsRoute.returnTo != nil {
                Button(copy.text("Done", "완료"), action: finishAssignmentReview)
                    .buttonStyle(.borderedProminent).tint(NativeSurfaceStyle.accent).pointingHandCursor()
            }
        }
    }
}
