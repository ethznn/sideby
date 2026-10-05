import AppKit
import SidebyCore
import SidebyUI
import SwiftUI

/// Saved work is a primary destination; app preferences have their own window.
struct WorkspaceLibraryView: View {
    @ObservedObject var model: SidebyAppModel
    @ObservedObject var navigation: ProductUINavigation
    var startsInOverview = false
    let finish: () -> Void
    var openPermissions: () -> Void = {}
    @State private var selectedID: String?
    @State private var showsOverview = false
    @State private var hostingWindow: NSWindow?
    @State private var selection = WorkspaceSettingsSelection()
    @State private var showsDisplayParticipation = false
    private var copy: WorkspaceSaveStrings { model.saveCopy }
    private var entries: [WorkspaceComposerEntry] { model.workspaceComposerDraft?.state.entries ?? [] }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                toolbar(compact: geometry.size.height < 640)
                    .padding(.horizontal, 20).padding(.vertical, geometry.size.height < 640 ? 10 : 20)
                status
                Divider()
                HStack(spacing: 0) {
                    if !showsOverview {
                        sidebar.frame(width: geometry.size.width < 900 ? 180 : 210)
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                    if selection.missingContextID != nil {
                        Text(SettingsRefreshStrings(language: model.settings.language).missingTarget)
                            .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                            .padding(.horizontal, 20).padding(.top, 16)
                            .accessibilityIdentifier("library-missing-target")
                    }
                    WorkspaceSettingsView(model: model, navigation: navigation,
                        layout: .init(windowWidth: geometry.size.width, displayCount: model.displayLayout.displays.count),
                        selection: $selection, showsDisplayParticipation: $showsDisplayParticipation,
                        isOverview: showsOverview, compactLayout: geometry.size.height < 640, selectedContextID: selectedID,
                        selectContext: { choose($0); showsOverview = false }, didAddContext: { choose($0) })
                        .padding(.horizontal, 20).padding(.vertical, geometry.size.height < 640 ? 10 : 20)
                    }
                }.frame(maxHeight: .infinity)
                Divider()
                WorkspaceAssignmentReviewFooter(model: model, navigation: navigation, finishAssignmentReview: finish,
                    showDisplayParticipation: { showsDisplayParticipation = true })
                    .padding(.horizontal, 20).padding(.vertical, geometry.size.height < 640 ? 10 : 14)
            }
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText)
        .background(NativeSurfaceStyle.windowBackground).tint(NativeSurfaceStyle.accent)
        .background(ProductSettingsWindowReader { hostingWindow = $0; $0?.title = copy.savedWorkspaces + " — Sideby" })
        .background(WorkspaceComposerKeyboardCommands(model: model))
        .onChange(of: model.settings.language) { _, _ in hostingWindow?.title = copy.savedWorkspaces + " — Sideby" }
        .onAppear {
            model.beginWorkspaceComposer()
            showsOverview = startsInOverview
            reveal(navigation.workspaceRoute)
        }
        .onReceive(navigation.$workspaceRoute) { reveal($0) }
        .onChange(of: entries.map(\.id)) { previous, ids in
            if let selectedID, !ids.contains(selectedID), let index = previous.firstIndex(of: selectedID) {
                // Removing an item while editing is expected: stay at its nearest neighbor.
                selection = WorkspaceSettingsSelection(selectedContextID: ids.isEmpty ? nil : ids[min(index, ids.count - 1)])
            } else {
                selection.reconcile(contextIDs: ids, preferredID: nil)
            }
            selectedID = selection.selectedContextID
        }
        .onChange(of: model.workspaceSavedFocusID) { _, id in
            if let id { model.refreshWorkspaceComposer(); choose(id) }
        }
    }

    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.savedWorkspaces).font(.system(size: 22, weight: .semibold)).accessibilityAddTraits(.isHeader)
                if !compact { Text(showsOverview
                    ? copy.text("Drag desktops down to arrange several setups together.", "화면별 데스크탑을 아래로 끌어 여러 구성을 함께 정리하세요.")
                    : copy.text("Choose a setup to review or change its desktops.", "구성을 골라 돌아갈 데스크탑을 확인하고 수정하세요."))
                    .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText) }
            }
            Spacer(minLength: 8)
            Button {
                showsOverview.toggle()
            } label: {
                Label(showsOverview ? copy.text("One setup", "구성별 보기") : copy.text("Edit all setups", "전체 구성 편집"),
                      systemImage: showsOverview ? "sidebar.left" : "rectangle.split.3x3")
            }.pointingHandCursor().accessibilityIdentifier("library-overview")
            Button(copy.saveConfiguration) {
                model.resolveWorkspaceComposerBeforeLeaving(window: hostingWindow) {
                    model.showWorkspaceSave {
                        model.refreshWorkspaceComposer()
                    }
                }
            }.buttonStyle(.borderedProminent).pointingHandCursor().disabled(!model.canSaveWorkspace)
                .accessibilityIdentifier("library-save-current")
        }
    }

    @ViewBuilder private var status: some View {
        if model.permissionState != .granted || !model.hasSwitchingAccess {
            HStack {
                Label(copy.text("Allow access to read and switch desktops.", "데스크탑을 확인하고 전환하려면 접근을 허용해 주세요."), systemImage: "lock")
                Spacer()
                Button(copy.text("Open permissions", "권한 설정 열기"), action: openPermissions).pointingHandCursor()
                    .accessibilityIdentifier("library-permissions")
            }.font(.system(size: 12)).padding(.horizontal, 20).padding(.bottom, 12)
        } else if !model.isEnabled {
            HStack {
                Text(copy.text("Sideby is off. Saved setups can still be edited.", "Sideby가 꺼져 있어요. 저장한 구성은 편집할 수 있습니다."))
                Spacer()
                Button(copy.text("Turn on Sideby", "Sideby 켜기")) { model.setSidebyEnabled(true) }.pointingHandCursor()
            }.font(.system(size: 12)).padding(.horizontal, 20).padding(.bottom, 12)
        } else if model.isSwitching {
            HStack { ProgressView().controlSize(.small); Text(copy.moving); Spacer() }
                .font(.system(size: 12)).padding(.horizontal, 20).padding(.bottom, 12)
        } else if model.workspaceRecoveryTargetID != nil {
            Label(model.lastSwitchResult, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.text("\(entries.count) saved", "저장한 구성 \(entries.count)개"))
                .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText).padding(.horizontal, 12)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(entries) { entry in
                        Button { choose(entry.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                HStack(spacing: 4) {
                                    if model.workspaceComposerEntryIsCurrent(entry) {
                                        Image(systemName: "checkmark")
                                        Text(copy.current)
                                    } else {
                                        Text(copy.text("\(entry.members.count) displays", "화면 \(entry.members.count)개"))
                                    }
                                    Spacer(minLength: 0)
                                    if entry != model.workspaceComposerDraft?.baseline.entries.first(where: { $0.id == entry.id }) {
                                        Image(systemName: "pencil").accessibilityLabel(copy.text("Unsaved edit", "저장 전 변경"))
                                    }
                                }.font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).pointingHandCursor()
                            .help(entry.name)
                            .background(selectedID == entry.id ? NativeSurfaceStyle.selectionBackground : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityAddTraits(selectedID == entry.id ? .isSelected : [])
                            .accessibilityIdentifier("library-setup-" + entry.id)
                    }
                }
            }
            if let selectedID, entries.contains(where: { $0.id == selectedID }),
               model.settings.contextPlan.contexts.contains(where: { $0.id == selectedID }) {
                Divider()
                Button(copy.text("Go to this setup", "이 구성으로 이동")) {
                    model.resolveWorkspaceComposerBeforeLeaving(window: hostingWindow) {
                        model.activateContext(contextID: selectedID)
                    }
                }.frame(maxWidth: .infinity).pointingHandCursor()
                    .disabled(!model.canActivateContext || !model.isWorkspaceAssignmentAvailable(contextID: selectedID))
                    .accessibilityIdentifier("library-activate")
            }
        }.padding(12).background(NativeSurfaceStyle.sidebarBackground)
    }

    private func reveal(_ route: ProductSettingsRoute) {
        if let id = route.contextID { choose(id); showsOverview = false }
        else if selectedID == nil { selectedID = entries.first?.id }
    }
    private func choose(_ id: String) {
        selection.reconcile(contextIDs: entries.map(\.id), preferredID: id)
        selectedID = selection.selectedContextID
    }
}
