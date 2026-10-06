import SidebyCore
import SidebyUI
import SwiftUI

struct HeldMatrixStrings {
    let language: AppLanguage
    private func text(_ en: String, _ ko: String) -> String { language == .korean ? ko : en }
    var title: String { text("Switch Spaces together", "Space 함께 이동") }
    var hint: String { text("Click anywhere in a column to move your displays together.", "열의 어느 곳이든 누르면 연결된 Space로 함께 이동합니다.") }
    var editConnections: String { text("Edit connections", "연결 수정") }
    var backToSwitching: String { text("Back to switching", "이동 화면으로") }
    var together: String { text("Move together", "함께 전환") }
    var releaseHint: String { text("Release the shortcut to close · Esc to cancel", "단축키를 놓으면 닫힘 · Esc로 취소") }
    var pinnedHint: String { text("Click a column to move · Esc to close", "열을 눌러 이동 · Esc로 닫기") }
    var current: String { text("Current", "현재") }
    var moving: String { text("Switching…", "이동 중…") }
    var changed: String { text("Assignments changed. Reopen to update.", "배정이 바뀌었습니다. 다시 열어 확인해 주세요.") }
    var unavailable: String { text("Check Space connection", "Space 연결 확인 필요") }
    var off: String { text("Turn on Sideby from the menu bar to switch setups.", "메뉴바에서 Sideby를 켜 주세요.") }
    var permission: String { text("Check switching access in Settings.", "설정에서 전환 권한을 확인해 주세요.") }
    var noDisplays: String { text("Choose participating displays in Edit connections.", "연결 수정에서 함께 움직일 모니터를 선택해 주세요.") }
    var empty: String { text("Choose Edit connections to connect your Spaces.", "연결 수정을 눌러 현재 Space를 연결해 주세요.") }
    var busy: String { text("Finishing the current operation…", "진행 중인 동작을 마무리하고 있습니다…") }
    var failed: String { text("Switch incomplete. Click the column to retry.", "일부 모니터가 이동하지 못했습니다. 열을 눌러 다시 시도하세요.") }
    var previous: String { text("Show earlier setups", "앞쪽 구성 보기") }
    var next: String { text("Show later setups", "뒤쪽 구성 보기") }
    var setting: String { text("Show the quick matrix while holding a shortcut", "단축키를 누르는 동안 Space 연결표 보기") }
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
    @State private var isEditing = false
    @State private var hasEnteredEditing = false
    @State private var hoveredID: String?
    private var copy: HeldMatrixStrings { .init(language: model.settings.language) }
    private var live: HeldWorkspaceSnapshot { .init(model: model, previousColumnID: snapshot.initialColumnID) }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                if isEditing {
                    HStack {
                        Label(copy.editConnections, systemImage: "pencil").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(copy.backToSwitching) { setEditing(false) }
                            .pointingHandCursor().accessibilityIdentifier("held-finish-editing")
                    }
                    ScrollView {
                        CurrentConnectionsView(model: model, showsDesktopSources: true,
                            availableHeight: max(280, geometry.size.height - 80),
                            select: { id in if let column = live.columns.first(where: { $0.id == id }) { select(column) } },
                            keepOpen: keepOpen, close: close)
                    }
                } else {
                    HStack {
                        Text(copy.title).font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Button(copy.editConnections) { setEditing(true) }
                            .pointingHandCursor().disabled(model.isSwitching)
                            .accessibilityIdentifier("held-edit-connections")
                        Button(action: close) { Image(systemName: "xmark") }
                            .buttonStyle(.plain).pointingHandCursor().accessibilityLabel(model.saveCopy.close)
                    }
                    Text(copy.hint).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    if live.columns.isEmpty || live.displayIDs.isEmpty {
                        Text(live.columns.isEmpty ? copy.empty : copy.noDisplays)
                            .font(.system(size: 13)).frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                    } else {
                        quickTable(live, maxHeight: max(120, geometry.size.height - (statusMessage == nil ? 130 : 172)))
                    }
                    if let statusMessage {
                        Text(statusMessage).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(persistent || hasEnteredEditing ? copy.pinnedHint : copy.releaseHint)
                        .font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                }
            }
            .padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText)
        .background(NativeSurfaceStyle.windowBackground, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(NativeSurfaceStyle.frameBorder))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("held-workspace-matrix")
        .onAppear { model.refreshWorkspaceStatus(); model.refreshCurrentDesktopContents() }
    }

    private func setEditing(_ editing: Bool) {
        if editing { keepOpen(); hasEnteredEditing = true }
        isEditing = editing
        editingChanged(editing)
    }

    private func quickTable(_ snapshot: HeldWorkspaceSnapshot, maxHeight: CGFloat) -> some View {
        let contentHeight = HeldMatrixPanelLayout.headerHeight + CGFloat(snapshot.displayIDs.count) * HeldMatrixPanelLayout.rowHeight
        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 6) {
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
                }
            }
        }
        .frame(height: min(maxHeight, contentHeight + 14))
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

    private func columnButton(_ column: HeldWorkspaceColumn, snapshot: HeldWorkspaceSnapshot) -> some View {
        let current = model.verifiedCurrentWorkspaceID == column.id && !model.isSwitching
        let enabled = model.heldMatrixCanActivate(column, displayIDs: snapshot.displayIDs)
        let context = model.settings.contextPlan.contexts.first { $0.id == column.id }
        let missing = context.map { model.unresolvedWorkspaceMembers($0) } ?? []
        return Button {
            rememberColumn(column.id)
            select(column)
        } label: {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(column.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    HStack(spacing: 6) {
                        if current { Label(copy.current, systemImage: "checkmark.circle.fill") }
                        else if model.isSwitching && model.workspaceSwitchTargetName == column.name { Text(copy.moving) }
                        else if !enabled, statusMessage == nil { Text(copy.unavailable).lineLimit(1) }
                        else if let shortcut = model.workspaceShortcut(column.id) { Text(shortcut) }
                    }.font(.system(size: 10)).foregroundStyle(current ? Color.accentColor : NativeSurfaceStyle.secondaryText)
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: HeldMatrixPanelLayout.headerHeight)
                ForEach(snapshot.displayIDs, id: \.self) { id in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(missing.contains(id) ? copy.unavailable : column.cells[id] ?? model.connectionCopy.keep)
                            .font(.system(size: 12, weight: .medium)).lineLimit(2)
                        if !missing.contains(id), let label = column.desktopLabels[id], column.cells[id] != label {
                            Text(label).font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).frame(height: HeldMatrixPanelLayout.rowHeight)
                        .overlay(alignment: .top) { Rectangle().fill(NativeSurfaceStyle.frameBorder).frame(height: 0.5).allowsHitTesting(false) }
                }
            }
            .padding(.horizontal, 10).frame(width: HeldMatrixPanelLayout.columnWidth)
            .background(current ? NativeSurfaceStyle.selectionBackground : hoveredID == column.id && enabled ? NativeSurfaceStyle.hoverBackground : NativeSurfaceStyle.tableBackground,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(current ? Color.accentColor : NativeSurfaceStyle.itemBorder, lineWidth: current ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .onHover { hoveredID = $0 ? column.id : nil }.pointingHandCursor(enabled)
        .help(copy.move(column.name) + "\n" + summary(column, snapshot: snapshot))
        .accessibilityLabel(copy.move(column.name))
        .accessibilityValue((current ? copy.current + " · " : "") + summary(column, snapshot: snapshot))
        .accessibilityIdentifier("held-workspace-" + column.id)
    }

    private func summary(_ column: HeldWorkspaceColumn, snapshot: HeldWorkspaceSnapshot) -> String {
        snapshot.displayIDs.map { (snapshot.displayNames[$0] ?? "") + ": " + (column.cells[$0] ?? model.connectionCopy.keep) }.joined(separator: " · ")
    }
}
