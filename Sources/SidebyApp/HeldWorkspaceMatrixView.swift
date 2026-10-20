import AppKit
import UniformTypeIdentifiers
import SidebyCore
import SidebyUI
import SwiftUI

private struct HeldMatrixContentSize: Equatable {
    var size: CGSize = .zero
    var editing = false
}

struct HeldMatrixStrings {
    let language: AppLanguage
    private func text(_ en: String, _ ko: String) -> String { language == .korean ? ko : en }
    var title: String { text("Switch Spaces together", "Space 함께 이동") }
    var hint: String { text("Click a name or Space to switch · Pencil to rename · Drag to edit.", "이름·Space 클릭으로 이동 · 연필로 이름 수정 · 드래그로 연결·순서 변경") }
    var editConnections: String { text("Edit connections", "연결 수정") }
    var backToSwitching: String { text("Back to switching", "이동 화면으로") }
    var together: String { text("Move together", "함께 전환") }
    var releaseHint: String { text("Release the shortcut to close · Esc to cancel", "단축키를 놓으면 닫힘 · Esc로 취소") }
    var pinnedHint: String { text("Release the shortcut to edit · Option-drag to copy · Esc to close", "단축키를 놓고 편집하세요 · Option 드래그로 복사 · Esc로 닫기") }
    var current: String { text("Current", "현재") }
    var moving: String { text("Switching…", "이동 중…") }
    var changed: String { text("Assignments changed. Reopen to update.", "배정이 바뀌었습니다. 다시 열어 확인해 주세요.") }
    var chooseAgain: String { text("Choose Space again", "Space 다시 선택") }
    var missingHint: String { text("Saved Space not found", "저장한 Space를 찾을 수 없음") }
    var repairHint: String { text("Click to choose a Space or disconnect this cell. Option-drag a Space from the same display to copy it here.", "눌러서 Space를 다시 선택하거나 이 칸의 연결을 해제하세요. 같은 모니터의 Space를 Option 드래그로 복사해 넣을 수도 있습니다.") }
    var off: String { text("Turn on Sideby from the menu bar to switch setups.", "메뉴바에서 Sideby를 켜 주세요.") }
    var permission: String { text("Check switching access in Settings.", "설정에서 전환 권한을 확인해 주세요.") }
    var noDisplays: String { text("Choose participating displays in Edit connections.", "연결 수정에서 함께 움직일 모니터를 선택해 주세요.") }
    var empty: String { text("Connect the Spaces on screen now, or choose Edit connections to pick others.", "지금 화면을 연결로 추가하거나, 연결 수정에서 다른 Space를 골라 주세요.") }
    var busy: String { text("Finishing the current operation…", "진행 중인 동작을 마무리하고 있습니다…") }
    var failed: String { text("Switch incomplete. Click the column to retry.", "일부 모니터가 이동하지 못했습니다. 열을 눌러 다시 시도하세요.") }
    var previous: String { text("Show earlier setups", "앞쪽 구성 보기") }
    var next: String { text("Show later setups", "뒤쪽 구성 보기") }
    var setting: String { text("Show the Space switcher while holding a shortcut", "단축키를 누르는 동안 Space 빠른 이동 보기") }
    var record: String { text("Change shortcut…", "단축키 변경…") }
    var recording: String { text("Press a shortcut · Esc to cancel", "단축키를 누르세요 · Esc로 취소") }
    var invalidShortcut: String { text("Use Option, Control or Command with a key. Avoid Sideby shortcuts, reserved system shortcuts and Esc.", "Option·Control·Command 중 하나와 키를 조합해 주세요. 기존 Sideby·시스템 단축키 및 Esc는 사용할 수 없습니다.") }
    var registrationFailed: String { text("This shortcut could not be registered. Choose another combination.", "단축키를 등록할 수 없습니다. 다른 조합을 선택해 주세요.") }
    func move(_ name: String) -> String { text("Switch all assigned displays to \(name)", "배정된 모니터를 모두 \(name) 연결로 전환") }
    func discover(_ shortcut: String) -> String { text("Hold \(shortcut) to choose where your displays move together.", "\(shortcut)를 누른 채 함께 이동할 Space를 고르세요.") }
}

struct HeldWorkspaceMatrixView: View {
    @ObservedObject var model: SidebyAppModel
    let snapshot: HeldWorkspaceSnapshot
    let select: (HeldWorkspaceColumn) -> Void
    var rememberColumn: (String?) -> Void = { _ in }
    var persistent = false
    var close: () -> Void = {}
    var keepOpen: () -> Void = {}
    var editingChanged: (Bool) -> Void = { _ in }
    var copyRequested: () -> Bool = { NSEvent.modifierFlags.contains(.option) }
    var availableHeight: CGFloat = 900
    var contentMeasured: (CGSize, Bool) -> Void = { _, _ in }
    var usesRadial = false
    var wheelDiameter: CGFloat?
    var presentationChanged: (HeldSwitcherPresentation) -> Void = { _ in }
    @State private var showsTable = false
    @State private var renaming: ContextDefinition?
    @State private var repairingCell: String?
    @State private var dragSession = UUID()
    @State private var drag: WorkspaceComposerDrag?
    @State private var dropCell: String?
    @State private var dropColumn: String?
    @State private var dropAfter = false
    @State private var dragCopies = false
    @State private var isEditing = false
    @State private var hasEnteredEditing = false
    @State private var hoveredID: String?
    @State private var hoveredRenameID: String?
    @State private var hoveredActionsID: String?
    @State private var showsFeedback = false
    @State private var revealedConnectionID: String?
    private var copy: HeldMatrixStrings { .init(language: model.settings.language) }
    private var live: HeldWorkspaceSnapshot { .init(model: model, previousColumnID: snapshot.initialColumnID) }

    var body: some View {
        Group {
            if usesRadial && !isEditing && !showsTable {
                HeldWorkspaceWheelView(model: model, select: { column in
                    rememberColumn(column.id); select(column)
                }, keepOpen: keepOpen, close: close, edit: { setEditing(true) },
                    showTable: { showsTable = true; presentationChanged(.table) },
                    persistent: persistent || hasEnteredEditing, diameter: wheelDiameter, displayCount: snapshot.displayIDs.count)
            } else { matrixBody }
        }
    }

    private var matrixBody: some View {
        ScrollViewReader { scroll in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    if isEditing {
                        HStack {
                            Label(copy.editConnections, systemImage: "pencil").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button(copy.backToSwitching) { setEditing(false) }
                                .pointingHandCursor().accessibilityIdentifier("held-finish-editing")
                        }
                        Text(copy.pinnedHint).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                        CurrentConnectionsView(model: model, showsDesktopSources: true, isQuickEditor: true,
                            availableHeight: max(280, availableHeight - 80),
                            select: { id in if let column = live.columns.first(where: { $0.id == id }) { select(column) } },
                            keepOpen: keepOpen, close: close, copyRequested: copyRequested)
                    } else {
                        HStack {
                            Text(copy.title).font(.system(size: 17, weight: .semibold))
                            Spacer()
                            if usesRadial {
                                Button(model.connectionCopy.text("Circle", "원형으로 보기")) {
                                    showsTable = false; presentationChanged(.wheel)
                                }.pointingHandCursor().accessibilityIdentifier("held-show-wheel")
                            }
                            Button(copy.editConnections) { setEditing(true) }
                                .pointingHandCursor().disabled(model.isSwitching)
                                .accessibilityIdentifier("held-edit-connections")
                            Button(action: close) { Image(systemName: "xmark") }
                                .buttonStyle(.plain).pointingHandCursor().accessibilityLabel(model.saveCopy.close)
                        }
                        Text(copy.hint).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                        Button {
                            keepOpen(); hasEnteredEditing = true
                            revealedConnectionID = model.addCurrentConnection()
                            showsFeedback = true
                        } label: {
                            Label(model.connectionCopy.addCurrent, systemImage: "plus.circle")
                        }
                        .pointingHandCursor().disabled(!model.canChangeSavedWorkspaces)
                        .help(model.connectionCopy.addCurrentHint)
                        .accessibilityIdentifier("held-add-current-connection")
                        if live.columns.isEmpty || live.displayIDs.isEmpty {
                            Text(live.displayIDs.isEmpty ? copy.noDisplays : copy.empty)
                                .font(.system(size: 13)).frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                        } else {
                            quickTable(live)
                        }
                        if showsFeedback, let message = model.workspaceSaveMessage {
                            HStack {
                                Text(message).font(.system(size: 12))
                                    .foregroundStyle(model.workspaceSaveFeedbackKind == .failure ? Color.orange : NativeSurfaceStyle.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("held-add-feedback")
                                    .id("held-add-feedback")
                                Spacer(minLength: 8)
                                if model.settings.savedWorkspaces.undo != nil {
                                    Button(model.connectionCopy.text("Undo", "되돌리기")) {
                                        keepOpen()
                                        _ = model.undoSavedWorkspaceChange()
                                    }.pointingHandCursor().disabled(!model.canChangeSavedWorkspaces)
                                        .keyboardShortcut("z", modifiers: .command)
                                        .accessibilityIdentifier("held-undo-connection")
                                }
                            }
                        }
                        if let statusMessage {
                            Text(statusMessage).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(persistent || hasEnteredEditing ? copy.pinnedHint : copy.releaseHint)
                            .font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("held-footer")
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .topLeading)
                .background(GeometryReader { geometry in
                    Color.clear.onChange(of: HeldMatrixContentSize(size: geometry.size, editing: isEditing), initial: true) { _, measurement in
                        contentMeasured(measurement.size, measurement.editing)
                    }
                })
            }
            .onChange(of: model.workspaceSaveMessage) { _, message in
                // Routine editor feedback replaces a row in place. Scrolling
                // to it would pull the Space sources away during a drag.
                if message != nil && (!isEditing || model.workspaceSaveFeedbackKind == .failure) {
                    scroll.scrollTo(isEditing ? "connections-feedback" : "held-add-feedback", anchor: .bottom)
                }
            }
            .onChange(of: repairingCell) { _, id in
                if let id { scroll.scrollTo(id, anchor: .center) }
            }
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText)
        .background(NativeSurfaceStyle.windowBackground, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(NativeSurfaceStyle.frameBorder))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("held-workspace-matrix")
        .onAppear { model.refreshWorkspaceStatus(); model.refreshCurrentDesktopContents() }
        .background(WorkspaceDragCompletion(dragID: drag?.id, finished: finishDrag))
        .onChange(of: model.settings.savedWorkspaces.undo) { _, _ in
            if hasEnteredEditing { showsFeedback = true }
        }
    }

    private func setEditing(_ editing: Bool) {
        if editing { keepOpen(); hasEnteredEditing = true }
        isEditing = editing
        editingChanged(editing)
        presentationChanged(editing ? .editor : usesRadial && !showsTable ? .wheel : .table)
    }

    private func quickTable(_ snapshot: HeldWorkspaceSnapshot) -> some View {
        let contentHeight = HeldMatrixPanelLayout.headerHeight + CGFloat(snapshot.displayIDs.count) * HeldMatrixPanelLayout.rowHeight
        return HStack(alignment: .top, spacing: 6) {
            VStack(spacing: 0) {
                Text(copy.together).font(.system(size: 11, weight: .medium))
                    .frame(height: HeldMatrixPanelLayout.headerHeight)
                ForEach(snapshot.displayIDs, id: \.self) { id in
                    Text(snapshot.displayNames[id] ?? id).font(.system(size: 11, weight: .medium))
                        .lineLimit(2).help(snapshot.displayNames[id] ?? id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: HeldMatrixPanelLayout.rowHeight)
                }
            }.padding(.horizontal, 10).frame(width: HeldMatrixPanelLayout.labelWidth)
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(snapshot.columns) { column in
                            columnButton(column, snapshot: snapshot).id(column.id)
                        }
                    }.padding(2)
                }.frame(height: contentHeight + 14)
                    .task {
                        // Wait for the native scroll view to have its content size.
                        await Task.yield()
                        if let id = snapshot.initialColumnID { scroll.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: model.verifiedCurrentWorkspaceID) { _, id in
                        if let id { scroll.scrollTo(id, anchor: .center) }
                    }
                    .task(id: revealedConnectionID) {
                        guard let id = revealedConnectionID else { return }
                        await Task.yield()
                        scroll.scrollTo(id, anchor: .center)
                    }
            }
        }
        .frame(height: contentHeight + 14)
        .scrollIndicators(.visible)
        .background(NativeSurfaceStyle.tableBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(NativeSurfaceStyle.frameBorder))
        .accessibilityIdentifier("held-switch-table")
    }

    private var statusMessage: String? {
        if model.settingsStore.hasUnreadableSettings { return model.saveCopy.settingsUnreadable }
        if !model.isEnabled { return copy.off }
        if model.isSwitching || model.contextCaptureSession != nil || model.pendingContextCaptureAlignment != nil { return copy.busy }
        if !model.hasSwitchingAccess { return copy.permission }
        if model.workspaceRecoveryTargetID != nil, let recovery = model.workspaceRecoveryState, !recovery.isResolved {
            let message = recovery.pendingDisplayIDs.sorted().map { model.strings.workspacePendingDisplay(model.displayName(for: $0)) }.joined(separator: " · ")
            return message.isEmpty ? copy.failed : message
        }
        return nil
    }

    private func pinForEditing() {
        keepOpen()
        hasEnteredEditing = true
    }

    private func finishDrag() {
        drag = nil; dropCell = nil; dropColumn = nil
    }

    private func columnButton(_ column: HeldWorkspaceColumn, snapshot: HeldWorkspaceSnapshot) -> some View {
        let current = model.verifiedCurrentWorkspaceID == column.id && !model.isSwitching
        let enabled = model.heldMatrixCanActivate(column, displayIDs: snapshot.displayIDs)
        let actionable = enabled || repairDisplayID(column) != nil
        let switchHovered = hoveredID == column.id && hoveredRenameID != column.id
            && hoveredActionsID != column.id && actionable && drag == nil
        return VStack(spacing: 0) {
            columnHeader(column, current: current, enabled: enabled)
            ForEach(snapshot.displayIDs, id: \.self) { displayID in
                quickCell(column, displayID: displayID, canSwitch: enabled)
            }
        }
        .frame(width: HeldMatrixPanelLayout.columnWidth)
        .background(current ? NativeSurfaceStyle.selectionBackground : switchHovered ? NativeSurfaceStyle.hoverBackground : NativeSurfaceStyle.tableBackground,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(current ? Color.accentColor : switchHovered ? NativeSurfaceStyle.controlBorder : NativeSurfaceStyle.itemBorder, lineWidth: current || switchHovered ? 2 : 1).allowsHitTesting(false))
        .onHover { hoveredID = $0 ? column.id : nil }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(column.name)
        .accessibilityIdentifier("held-workspace-" + column.id)
    }

    private func columnHeader(_ column: HeldWorkspaceColumn, current: Bool, enabled: Bool) -> some View {
        let repairable = repairDisplayID(column) != nil
        let actionLabel = repairable ? column.name + " · " + copy.repairHint : copy.move(column.name)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                WorkspaceDesktopDragSource(enabled: enabled || model.canChangeSavedWorkspaces,
                    label: actionLabel, identifier: "held-title-" + column.id,
                    isDraggable: model.canChangeSavedWorkspaces, allowsMove: true, usesPointingHand: true,
                    click: { switchTo(column, enabled: enabled) }, beginDrag: {
                        pinForEditing(); renaming = nil
                        let payload = WorkspaceComposerDrag(session: dragSession, contextID: column.id)
                        drag = payload
                        return payload.rawValue
                    }, endDrag: finishDrag) {
                        Text(column.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    }
                    .help(actionLabel + " · " + model.connectionCopy.text("Drag to reorder", "끌어서 순서 변경"))
                    .pointingHandCursor(enabled || model.canChangeSavedWorkspaces)
                Button {
                    pinForEditing()
                    renaming = model.settings.contextPlan.contexts.first { $0.id == column.id }
                } label: {
                    Image(systemName: "pencil").font(.system(size: 11))
                        .foregroundStyle(hoveredRenameID == column.id ? Color.accentColor : NativeSurfaceStyle.secondaryText)
                        .frame(width: 24, height: 28).contentShape(Rectangle())
                        .background(hoveredRenameID == column.id ? NativeSurfaceStyle.hoverBackground : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain).disabled(!model.canChangeSavedWorkspaces)
                .pointingHandCursor(model.canChangeSavedWorkspaces)
                .onHover { hoveredRenameID = $0 && model.canChangeSavedWorkspaces ? column.id : nil }
                .help(model.connectionCopy.rename)
                .accessibilityLabel(column.name + " · " + model.connectionCopy.rename)
                .accessibilityIdentifier("held-rename-" + column.id)
                .popover(isPresented: Binding(get: { renaming?.id == column.id }, set: { if !$0 { renaming = nil } })) {
                    if let target = renaming { ConnectionNameEditor(model: model, target: target, close: { renaming = nil }) }
                }
            }
            HStack(spacing: 4) {
                if current { Label(copy.current, systemImage: "checkmark.circle.fill") }
                else if model.isSwitching && model.workspaceSwitchTargetName == column.name { Text(copy.moving) }
                else if let shortcut = model.workspaceShortcut(column.id) { Text(shortcut) }
                Spacer(minLength: 0)
                HeldConnectionActionsMenu(
                    label: column.name + " · " + model.connectionCopy.text("Connection actions", "연결 관리"),
                    removeTitle: model.connectionCopy.text("Remove connection · Keep Spaces", "연결 삭제 · Space는 유지"),
                    identifier: "held-actions-" + column.id,
                    enabled: model.canChangeSavedWorkspaces,
                    willOpen: {
                        pinForEditing(); renaming = nil; repairingCell = nil
                    }, remove: {
                        pinForEditing()
                        _ = model.deleteSavedWorkspace(column.id)
                        showsFeedback = true
                    })
                    .frame(width: 24, height: 22)
                    .disabled(!model.canChangeSavedWorkspaces)
                    .background(hoveredActionsID == column.id ? NativeSurfaceStyle.hoverBackground : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                    .pointingHandCursor(model.canChangeSavedWorkspaces)
                    .onHover { hoveredActionsID = $0 && model.canChangeSavedWorkspaces ? column.id : nil }
                    .accessibilityLabel(column.name + " · " + model.connectionCopy.text("Connection actions", "연결 관리"))
                    .accessibilityIdentifier("held-actions-" + column.id)
                Button { switchTo(column, enabled: enabled) } label: {
                    Image(systemName: repairable ? "exclamationmark.circle" : "arrow.right.circle")
                        .foregroundStyle(repairable ? Color.orange : current ? Color.accentColor : NativeSurfaceStyle.secondaryText)
                }
                    .buttonStyle(.plain).disabled(!enabled && !repairable).pointingHandCursor(enabled || repairable)
                    .help(actionLabel).accessibilityLabel(actionLabel)
                    .accessibilityIdentifier("held-go-" + column.id)
            }.font(.system(size: 10)).foregroundStyle(current ? Color.accentColor : NativeSurfaceStyle.secondaryText)
        }
        .padding(.horizontal, 10).frame(height: HeldMatrixPanelLayout.headerHeight)
        .overlay(alignment: dropAfter ? .trailing : .leading) {
            if dropColumn == column.id { Rectangle().fill(Color.accentColor).frame(width: 3).allowsHitTesting(false) }
        }
        .onDrop(of: [UTType.plainText], delegate: WorkspaceComposerDropDelegate(session: dragSession, active: drag,
            contextID: column.id, displayID: nil, enabled: model.canChangeSavedWorkspaces && drag?.contextID != nil,
            midpoint: HeldMatrixPanelLayout.columnWidth / 2,
            hover: { inside, after in dropColumn = inside ? column.id : nil; dropAfter = after },
            receive: { payload, after, _ in
                if let id = payload.contextID { _ = model.reorderSavedWorkspace(id, relativeTo: column.id, after: after) }
                finishDrag()
            }))
    }

    private func switchTo(_ column: HeldWorkspaceColumn, enabled: Bool) {
        guard enabled else { repair(column); return }
        rememberColumn(column.id)
        select(column)
    }

    private func repairDisplayID(_ column: HeldWorkspaceColumn) -> String? {
        guard model.canChangeSavedWorkspaces,
              let context = model.settings.contextPlan.contexts.first(where: { $0.id == column.id }) else { return nil }
        let missing = model.unresolvedWorkspaceMembers(context)
        return live.displayIDs.first { missing.contains($0) }
    }

    private func repair(_ column: HeldWorkspaceColumn, displayID: String? = nil) {
        guard let firstMissing = repairDisplayID(column) else { return }
        pinForEditing(); renaming = nil
        repairingCell = column.id + "-" + (displayID ?? firstMissing)
    }

    private func quickCell(_ column: HeldWorkspaceColumn, displayID: String, canSwitch: Bool) -> some View {
        let key = model.settings.savedWorkspaces.bookmarks[column.id]?[displayID]
        let context = model.settings.contextPlan.contexts.first { $0.id == column.id }
        let missing = context.map { model.unresolvedWorkspaceMembers($0).contains(displayID) } ?? true
        let canRepair = repairDisplayID(column) != nil
        let canDrag = model.canChangeSavedWorkspaces && !missing && key.map { model.workspaceLastObservedSpaceKeys[displayID]?.contains($0) == true } == true
        let cellID = column.id + "-" + displayID
        let title = missing ? copy.chooseAgain : column.cells[displayID] ?? model.connectionCopy.keep
        let hovering = dropCell == cellID
        let hint = dragCopies ? model.connectionCopy.text("Release to copy", "놓으면 복사") : missing
            ? model.connectionCopy.text("Hold Option to copy here", "Option을 누르면 여기에 복사")
            : model.connectionCopy.text("Release to move / swap", "놓으면 이동·자리 바꾸기")
        return WorkspaceDesktopDragSource(enabled: canSwitch || canDrag || canRepair,
            label: model.displayName(for: displayID) + " · " + title,
            identifier: "held-cell-" + cellID, isDraggable: canDrag,
            accessibilityState: hovering ? hint : title, allowsMove: true, usesPointingHand: true,
            click: {
                if missing { repair(column, displayID: displayID) }
                else { switchTo(column, enabled: canSwitch) }
            }, beginDrag: {
                guard let key, canDrag else { return "" }
                pinForEditing()
                let payload = WorkspaceComposerDrag(session: dragSession, desktop: .init(displayID: displayID, key: key), sourceContextID: column.id)
                drag = payload
                return payload.rawValue
            }, endDrag: finishDrag) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        .foregroundStyle(missing ? Color.orange : NativeSurfaceStyle.primaryText)
                    if hovering { Text(hint).font(.system(size: 10)).foregroundStyle(Color.accentColor) }
                    else if missing { Text(copy.missingHint).font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1) }
                    else if !missing, let label = column.desktopLabels[displayID], column.cells[displayID] != label {
                        Text(label).font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1)
                    }
                }.padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading).frame(height: HeldMatrixPanelLayout.rowHeight)
                    .background(hovering ? NativeSurfaceStyle.selectionBackground : .clear)
                    .overlay(alignment: .top) { Rectangle().fill(NativeSurfaceStyle.frameBorder).frame(height: 0.5).allowsHitTesting(false) }
                    .overlay { if hovering { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2) } }
            }
            .help(canRepair ? copy.repairHint : copy.move(column.name) + " · " + model.connectionCopy.text("Drag to change connection", "끌어서 연결 변경"))
            .pointingHandCursor(canSwitch || canDrag || canRepair)
            .id(cellID)
            .screenBoundedPopover(isPresented: Binding(get: { repairingCell == cellID }, set: { if !$0 { repairingCell = nil } }), width: 290) {
                ConnectionSpacePicker(model: model, context: context, displayID: displayID) { repairingCell = nil }
            }
            .onDrop(of: [UTType.plainText], delegate: WorkspaceComposerDropDelegate(session: dragSession, active: drag,
                contextID: column.id, displayID: displayID, enabled: model.canChangeSavedWorkspaces,
                desktopOperation: {
                    let copying = copyRequested()
                    if dragCopies != copying { dragCopies = copying }
                    return copying ? .copy : .move
                }, hover: { inside, _ in dropCell = inside ? cellID : nil },
                receive: { payload, _, operation in
                    if let desktop = payload.desktop, let source = payload.sourceContextID {
                        _ = model.transferCurrentConnection(desktop, from: source, to: column.id, expectedDestinationKey: key, copying: operation == .copy)
                    }
                    finishDrag()
                }))
    }

    private func summary(_ column: HeldWorkspaceColumn, snapshot: HeldWorkspaceSnapshot) -> String {
        snapshot.displayIDs.map { (snapshot.displayNames[$0] ?? "") + ": " + (column.cells[$0] ?? model.connectionCopy.keep) }.joined(separator: " · ")
    }
}
