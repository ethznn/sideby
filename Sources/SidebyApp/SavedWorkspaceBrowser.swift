import SwiftUI
import SidebyCore
import SidebyUI

struct SavedWorkspaceBrowser: View {
    @ObservedObject var model: SidebyAppModel
    var showsBrand = true
    var isQuick = false
    var isPersistent = true
    var save: (() -> Void)?
    var edit: ((String) -> Void)?
    var select: ((String) -> Void)?
    var close: (() -> Void)?
    var keepOpen: (() -> Void)?
    @State private var deletionProposal: WorkspaceDeleteAllProposal?
    @State private var confirmsDeleteAll = false
    @State private var pinnedForConfirmation = false
    @AppStorage("sideby.workspace-view") private var viewMode = "matrix"
    private var copy: WorkspaceSaveStrings { model.saveCopy }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if showsBrand { HStack {
                Label("sideby", systemImage: "rectangle.on.rectangle")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(NativeSurfaceStyle.accent)
                Spacer()
                if model.isSwitching { ProgressView().controlSize(.small); Text(copy.moving).font(.system(size: 11)) }
                else {
                    Text(model.isEnabled ? copy.text("On", "사용 중") : copy.text("Off", "꺼짐"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                }
                if let close, isPersistent || pinnedForConfirmation {
                    Button(action: close) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                        .buttonStyle(.plain).accessibilityLabel(copy.close).pointingHandCursor()
                        .keyboardShortcut(.cancelAction)
                }
            }
            }
            if isQuick && (!model.isEnabled || !model.hasSwitchingAccess) {
                Text(!model.isEnabled ? HeldMatrixStrings(language: model.settings.language).off : HeldMatrixStrings(language: model.settings.language).permission)
                    .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(model.verifiedCurrentWorkspaceID.flatMap { id in model.settings.contextPlan.contexts.first { $0.id == id }?.name } ?? copy.currentSetup)
                    .font(.system(size: 13, weight: .semibold))
                Text(currentSummary).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Button { if let save { save() } else { model.showWorkspaceSave() } } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus").foregroundStyle(NativeSurfaceStyle.accent)
                    Text(copy.saveConfiguration).fontWeight(.medium)
                    Spacer()
                    Image(systemName: "arrow.right").foregroundStyle(NativeSurfaceStyle.secondaryText)
                }.padding(12).contentShape(Rectangle())
            }
            .buttonStyle(.plain).font(.system(size: 13)).pointingHandCursor().disabled(!model.canSaveWorkspace)
            .background(NativeSurfaceStyle.tableBackground, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(NativeSurfaceStyle.frameBorder))
            .accessibilityIdentifier("save-current-workspace")
            HStack {
                Text(copy.savedWorkspaces + " · \(model.settings.contextPlan.contexts.count)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                Spacer()
                if !isQuick {
                    Picker(copy.savedWorkspaces, selection: $viewMode) {
                        Text(copy.matrix).tag("matrix")
                        Text(copy.list).tag("list")
                    }.pickerStyle(.segmented).frame(width: 192).labelsHidden()
                }
                if !model.settings.contextPlan.contexts.isEmpty {
                    Button {
                        guard let proposal = model.prepareDeleteAllSavedWorkspaces() else { return }
                        deletionProposal = proposal
                        if isQuick { keepOpen?(); pinnedForConfirmation = true }
                        confirmsDeleteAll = true
                    } label: { Label(copy.deleteAll, systemImage: "trash") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .disabled(!model.canDeleteAllSavedWorkspaces).pointingHandCursor()
                    .accessibilityIdentifier("workspace-delete-all")
                }
            }
            if model.settingsStore.hasUnreadableSettings {
                Label(copy.settingsUnreadable, systemImage: "exclamationmark.triangle").font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true).padding(18)
            } else if model.settings.contextPlan.contexts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 28)).foregroundStyle(NativeSurfaceStyle.accent)
                    Text(copy.emptyTitle).font(.system(size: 14, weight: .semibold))
                    Text(copy.emptyMessage).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                        .multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity).accessibilityIdentifier("workspace-empty-state")
            } else if isQuick || viewMode == "matrix" {
                SavedWorkspaceMatrix(model: model, select: select, edit: edit)
                    .frame(minHeight: 170, maxHeight: .infinity)
            } else {
                SavedWorkspaceList(model: model, select: select, edit: edit)
                    .frame(minHeight: 170, maxHeight: .infinity)
            }
            if let message = model.workspaceSaveMessage {
                HStack(alignment: .top) {
                    Text(message).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { model.workspaceSaveMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel(copy.close)
                }.padding(10).background(NativeSurfaceStyle.selectionBackground, in: RoundedRectangle(cornerRadius: 8))
            }
            if let previous = model.workspaceHistory.previousContextID,
               previous != model.verifiedCurrentWorkspaceID,
               let context = model.settings.contextPlan.contexts.first(where: { $0.id == previous }) {
                Button { if let select { select(previous) } else { model.activateContext(contextID: previous) } } label: {
                    HStack { Label(copy.returnTo(context.name), systemImage: "arrow.uturn.backward"); Spacer(); Text("⌥⇧Tab") }
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.accent)
                    .disabled(!model.canActivateContext || !model.isWorkspaceAssignmentAvailable(contextID: previous)).pointingHandCursor()
            }
            Divider()
            HStack(spacing: 12) {
                Text(isQuick && !isPersistent && !pinnedForConfirmation ? copy.holdHint : copy.chooseHint)
                    .font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(2)
                Spacer(minLength: 0)
                Button { _ = model.undoSavedWorkspaceChange() } label: { Label(copy.undo, systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .disabled(!model.canSaveWorkspace || model.settings.savedWorkspaces.undo == nil).pointingHandCursor()
                    .help(model.settings.savedWorkspaces.undo?.label ?? copy.undo)
                    .accessibilityIdentifier("workspace-undo")
            }
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText)
        .tint(NativeSurfaceStyle.accent)
        .alert(copy.deleteAllTitle(deletionProposal?.contexts.count ?? 0), isPresented: $confirmsDeleteAll) {
            Button(copy.cancel, role: .cancel) { deletionProposal = nil }.keyboardShortcut(.defaultAction)
            Button(copy.deleteAllAction, role: .destructive) {
                if let proposal = deletionProposal { _ = model.deleteAllSavedWorkspaces(proposal) }
                deletionProposal = nil
            }
        } message: { Text(copy.deleteAllMessage) }
    }

    private var currentSummary: String {
        let displays = model.workspaceObservedDisplays ?? []
        if displays.isEmpty { return copy.readUnavailable }
        return displays.map { model.displayName(for: $0.displayID) + " · " + copy.desktop($0.currentSpaceIndex) }.joined(separator: "   ")
    }
}

struct SavedWorkspaceMatrix: View {
    @ObservedObject var model: SidebyAppModel
    var select: ((String) -> Void)?
    var edit: ((String) -> Void)?
    @State private var deleting: ContextDefinition?
    private var copy: WorkspaceSaveStrings { model.saveCopy }
    private let columnWidth: CGFloat = 154
    private let rowHeight: CGFloat = 68
    private let headerHeight: CGFloat = 85
    private var contexts: [ContextDefinition] { model.settings.contextPlan.contexts.sorted { $0.order < $1.order } }
    var displayIDs: [String] { model.connectedWorkspaceDisplayIDs }

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(copy.text("Setups →", "구성 →")); Text(copy.text("Displays ↓", "화면 ↓"))
                    }.font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading).frame(height: headerHeight).padding(.horizontal, 12)
                        .background(NativeSurfaceStyle.headerBackground)
                    ForEach(displayIDs, id: \.self) { id in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(model.displayName(for: id), systemImage: model.displayLayout.displays.first { $0.id == id }?.isBuiltin == true ? "laptopcomputer" : "display")
                                .font(.system(size: 11, weight: .medium)).lineLimit(2)
                            Text(model.workspaceObservedDisplays?.first { $0.displayID == id }.map { copy.desktop($0.currentSpaceIndex) }
                                 ?? (model.displayLayout.displays.contains { $0.id == id } ? copy.excluded : copy.offline))
                                .font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: rowHeight).padding(.horizontal, 12)
                            .overlay(alignment: .top) { Rectangle().fill(NativeSurfaceStyle.frameBorder).frame(height: 0.5) }
                    }
                }.frame(width: 132).background(NativeSurfaceStyle.windowBackground)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(contexts) { context in column(context).id(context.id) }
                        }
                    }
                    .onAppear { if let id = model.workspaceSavedFocusID ?? model.verifiedCurrentWorkspaceID { proxy.scrollTo(id, anchor: .center) } }
                    .onChange(of: model.workspaceSavedFocusID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
        .background(NativeSurfaceStyle.tableBackground, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NativeSurfaceStyle.frameBorder))
        .accessibilityIdentifier("workspace-assignment-table")
        .confirmationDialog(deleting.map { copy.deleteTitle($0.name) } ?? copy.delete,
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(copy.delete, role: .destructive) { if let id = deleting?.id { _ = model.deleteSavedWorkspace(id) }; deleting = nil }
                Button(copy.cancel, role: .cancel) { deleting = nil }
            } message: { Text(copy.deleteMessage) }
    }

    private func column(_ context: ContextDefinition) -> some View {
        let current = model.verifiedCurrentWorkspaceID == context.id
        let available = model.isWorkspaceAssignmentAvailable(contextID: context.id)
        let move = { if let select { select(context.id) } else { model.activateContext(contextID: context.id) } }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: move) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.stack").foregroundStyle(NativeSurfaceStyle.accent)
                        Text(context.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!model.canActivateContext || !available).pointingHandCursor()
                    .accessibilityIdentifier("workspace-select-" + context.id)
                HStack {
                    Text(model.workspaceShortcut(context.id) ?? "").font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    Spacer(minLength: 0)
                    Button(copy.edit) { if let edit { edit(context.id) } else { model.showWorkspaceSave(editingID: context.id) } }
                        .font(.system(size: 10)).buttonStyle(.bordered).controlSize(.mini)
                        .disabled(!model.canSaveWorkspace).pointingHandCursor().accessibilityLabel(context.name + " · " + copy.edit)
                }
                HStack(spacing: 3) {
                    if current { Image(systemName: "checkmark") }
                    Text(current ? copy.current : available ? copy.text("Choose to return", "선택해 돌아가기") : copy.offlineOrMissing(context, model: model))
                }.font(.system(size: 10)).foregroundStyle(current ? NativeSurfaceStyle.accent : NativeSurfaceStyle.secondaryText).lineLimit(1)
            }.padding(.horizontal, 11).frame(height: headerHeight)
                .background(current ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.headerBackground)
            Button(action: move) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(displayIDs, id: \.self) { id in cell(context, id: id) }
                }.frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!model.canActivateContext || !available).pointingHandCursor()
                .accessibilityLabel(context.name + " · " + copy.chooseHint)
        }
        .frame(width: columnWidth)
        .background(current ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.tableBackground)
        .overlay(alignment: .leading) { Rectangle().fill(NativeSurfaceStyle.frameBorder).frame(width: 0.5) }
        .contextMenu {
            Button(copy.edit) { if let edit { edit(context.id) } else { model.showWorkspaceSave(editingID: context.id) } }
            Button(copy.delete, role: .destructive) { deleting = context }
        }
    }

    private func cell(_ context: ContextDefinition, id: String) -> some View {
        let connected = model.displayLayout.displays.contains { $0.id == id }
        let unresolved = model.unresolvedWorkspaceMembers(context).contains(id)
        return VStack(alignment: .leading, spacing: 5) {
            if let index = context.spaceIndex(for: id) {
                Text(unresolved ? copy.text("Check desktop", "데스크탑 확인 필요") : model.workspaceDesktopName(displayID: id, spaceIndex: index) ?? copy.desktop(index))
                    .font(.system(size: 11, weight: .medium)).lineLimit(2)
                HStack(spacing: 4) {
                    Text(connected ? copy.desktop(index) : copy.remembered)
                    if let key = model.settings.savedWorkspaces.bookmarks[context.id]?[id],
                       contexts.filter({ model.settings.savedWorkspaces.bookmarks[$0.id]?[id] == key }).count > 1 {
                        Image(systemName: "link").accessibilityLabel(copy.text("Shared", "함께 사용"))
                    }
                }.font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1)
            } else {
                Text(copy.keep).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: rowHeight).padding(.horizontal, 11)
            .overlay(alignment: .top) { Rectangle().fill(NativeSurfaceStyle.frameBorder).frame(height: 0.5) }
    }
}

private extension WorkspaceSaveStrings {
    @MainActor func offlineOrMissing(_ context: ContextDefinition, model: SidebyAppModel) -> String {
        !Set(context.displayIDs).isDisjoint(with: model.selectedDisplayIDs) ? text("Check connection", "연결 확인 필요") : offline
    }
}

struct SavedWorkspaceList: View {
    @ObservedObject var model: SidebyAppModel
    var select: ((String) -> Void)?
    var edit: ((String) -> Void)?
    @State private var deleting: ContextDefinition?
    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(model.settings.contextPlan.contexts.sorted { $0.order < $1.order }) { context in
                    HStack(spacing: 8) {
                        Button { if let select { select(context.id) } else { model.activateContext(contextID: context.id) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "rectangle.stack").foregroundStyle(NativeSurfaceStyle.accent)
                                    .frame(width: 32, height: 32).background(NativeSurfaceStyle.selectionBackground, in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(context.name).font(.system(size: 14, weight: .semibold))
                                    Text(model.isWorkspaceAssignmentAvailable(contextID: context.id)
                                        ? model.connectedWorkspaceDisplayIDs.filter { context.displayIDs.contains($0) }.map { model.displayName(for: $0) }.joined(separator: " · ")
                                        : model.saveCopy.offlineOrMissing(context, model: model))
                                        .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1)
                                }
                                Spacer()
                                if model.verifiedCurrentWorkspaceID == context.id { Image(systemName: "checkmark").foregroundStyle(NativeSurfaceStyle.accent) }
                                Text(model.workspaceShortcut(context.id) ?? "").font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                            }.padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!model.canActivateContext || !model.isWorkspaceAssignmentAvailable(contextID: context.id)).pointingHandCursor()
                        Menu {
                            Button(model.saveCopy.edit) { if let edit { edit(context.id) } else { model.showWorkspaceSave(editingID: context.id) } }
                            Button(model.saveCopy.delete, role: .destructive) { deleting = context }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).padding(.trailing, 8)
                    }.background(model.verifiedCurrentWorkspaceID == context.id ? NativeSurfaceStyle.selectionBackground : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }.confirmationDialog(deleting.map { model.saveCopy.deleteTitle($0.name) } ?? model.saveCopy.delete,
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(model.saveCopy.delete, role: .destructive) { if let id = deleting?.id { _ = model.deleteSavedWorkspace(id) }; deleting = nil }
                Button(model.saveCopy.cancel, role: .cancel) { deleting = nil }
            } message: { Text(model.saveCopy.deleteMessage) }
    }
}
