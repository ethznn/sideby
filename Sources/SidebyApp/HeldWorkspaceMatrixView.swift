import SidebyCore
import SidebyUI
import SwiftUI

struct HeldMatrixStrings {
    let language: AppLanguage
    private func text(_ en: String, _ ko: String) -> String { language == .korean ? ko : en }
    var title: String { text("Quick setup matrix", "빠른 구성 매트릭스") }
    var hint: String { text("Hold the shortcut and click a setup. Release to close.", "누른 채 구성을 클릭하세요. 키를 놓으면 닫힙니다.") }
    var current: String { text("Current", "현재") }
    var moving: String { text("Switching…", "이동 중…") }
    var changed: String { text("Assignments changed. Reopen to update.", "배정이 바뀌었습니다. 다시 열어 확인해 주세요.") }
    var unavailable: String { text("Check desktop connection", "데스크탑 연결 확인 필요") }
    var off: String { text("Turn on Sideby from the menu bar to switch setups.", "메뉴바에서 Sideby를 켜 주세요.") }
    var permission: String { text("Check switching access in Settings.", "설정에서 전환 권한을 확인해 주세요.") }
    var noDisplays: String { text("Choose the displays to switch from the menu bar.", "메뉴바에서 함께 움직일 화면을 선택해 주세요.") }
    var empty: String { text("Create your first setup from the menu bar.", "메뉴바에서 첫 구성을 구성해 주세요.") }
    var busy: String { text("Finishing the current operation…", "진행 중인 동작을 마무리하고 있습니다…") }
    var failed: String { text("Switch incomplete. Click the setup to retry.", "일부 화면이 이동하지 못했습니다. 구성을 눌러 다시 시도하세요.") }
    var previous: String { text("Show earlier setups", "앞쪽 구성 보기") }
    var next: String { text("Show later setups", "뒤쪽 구성 보기") }
    var setting: String { text("Show the quick matrix while holding a shortcut", "단축키를 누르는 동안 빠른 구성 매트릭스 보기") }
    var record: String { text("Change shortcut…", "단축키 변경…") }
    var recording: String { text("Press a shortcut · Esc to cancel", "단축키를 누르세요 · Esc로 취소") }
    var invalidShortcut: String { text("Use Option, Control or Command with a key. Avoid Sideby shortcuts, reserved system shortcuts and Esc.", "Option·Control·Command 중 하나와 키를 조합해 주세요. 기존 Sideby·시스템 단축키 및 Esc는 사용할 수 없습니다.") }
    var registrationFailed: String { text("This shortcut could not be registered. Choose another combination.", "단축키를 등록할 수 없습니다. 다른 조합을 선택해 주세요.") }
    func move(_ name: String) -> String { text("Switch all assigned displays to \(name)", "배정된 화면을 모두 \(name) 구성으로 전환") }
    func discover(_ shortcut: String) -> String { text("Hold \(shortcut) to choose a setup quickly.", "\(shortcut)를 누른 채 구성을 빠르게 선택할 수 있습니다.") }
}

struct HeldWorkspaceMatrixView: View {
    @ObservedObject var model: SidebyAppModel
    let snapshot: HeldWorkspaceSnapshot
    let select: (HeldWorkspaceColumn) -> Void
    var rememberColumn: (String?) -> Void = { _ in }
    @State private var leadingID: String?
    @State private var hoveredID: String?
    private var copy: HeldMatrixStrings { .init(language: model.settings.language) }
    private var strings: SettingsRefreshStrings { .init(language: model.settings.language) }
    private var leadingIndex: Int { snapshot.columns.firstIndex { $0.id == leadingID } ?? 0 }

    var save: () -> Void = {}
    var edit: (String) -> Void = { _ in }
    var persistent = false
    var close: () -> Void = {}
    var keepOpen: () -> Void = {}

    var body: some View {
        let liveSnapshot = HeldWorkspaceSnapshot(model: model)
        SavedWorkspaceBrowser(model: model, isQuick: true, isPersistent: persistent, save: save, edit: edit,
            select: { id in if let column = liveSnapshot.columns.first(where: { $0.id == id }) { select(column) } }, close: close, keepOpen: keepOpen)
            .padding(18)
            .background(NativeSurfaceStyle.windowBackground, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(NativeSurfaceStyle.frameBorder))
            .accessibilityIdentifier("held-workspace-matrix")
    }

    private var statusMessage: String? {
        if !model.isEnabled { return copy.off }
        if model.isSwitching || model.contextCaptureSession != nil || model.pendingContextCaptureAlignment != nil { return copy.busy }
        if !model.hasSwitchingAccess { return copy.permission }
        if model.workspaceRecoveryTargetID != nil, let recovery = model.workspaceRecoveryState, !recovery.isResolved {
            return recovery.pendingDisplayIDs.sorted().map { model.strings.workspacePendingDisplay(model.displayName(for: $0)) }.joined(separator: " · ")
                .nonEmpty ?? copy.failed
        }
        return nil
    }

    private func columnButton(_ column: HeldWorkspaceColumn) -> some View {
        let current = model.verifiedCurrentWorkspaceID == column.id && !model.isSwitching
        let enabled = model.heldMatrixCanActivate(column, displayIDs: snapshot.displayIDs)
        let matches = column.stillMatches(model: model, displayIDs: snapshot.displayIDs)
        return Button { select(column) } label: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(column.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    if current {
                        Label { Text(copy.current).foregroundStyle(NativeSurfaceStyle.primaryText) }
                            icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    }
                    else if model.isSwitching && model.workspaceSwitchTargetName == column.name { Text(copy.moving) }
                    else if !matches { Text(copy.changed).lineLimit(1) }
                    else if !enabled, statusMessage == nil { Text(copy.unavailable).lineLimit(1) }
                }.font(.system(size: 11)).frame(height: HeldMatrixPanelLayout.headerHeight, alignment: .top)
                ForEach(snapshot.displayIDs, id: \.self) { id in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(column.cells[id] ?? strings.noAssignment).font(.system(size: 12, weight: .medium)).lineLimit(2)
                        if let label = column.desktopLabels[id], column.cells[id] != label {
                            Text(label).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).frame(height: HeldMatrixPanelLayout.rowHeight)
                    .overlay(alignment: .top) {
                        Rectangle().fill(NativeSurfaceStyle.frameBorder).frame(height: 0.5).allowsHitTesting(false)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .frame(width: HeldMatrixPanelLayout.columnWidth, alignment: .leading)
            .background(current ? NativeSurfaceStyle.selectionBackground : hoveredID == column.id && enabled ? NativeSurfaceStyle.hoverBackground : NativeSurfaceStyle.tableBackground,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(current ? Color.accentColor : NativeSurfaceStyle.itemBorder, lineWidth: current ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .onHover { hoveredID = $0 ? column.id : nil }.pointingHandCursor(enabled)
        .help(copy.move(column.name) + "\n" + summary(column))
        .accessibilityLabel(copy.move(column.name))
        .accessibilityValue((current ? copy.current + " · " : "") + summary(column))
        .accessibilityIdentifier("held-workspace-" + column.id)
    }

    private func summary(_ column: HeldWorkspaceColumn) -> String {
        snapshot.displayIDs.map { (snapshot.displayNames[$0] ?? "") + ": " + (column.cells[$0] ?? strings.noAssignment) }.joined(separator: " · ")
    }

    private func scroll(_ offset: Int) {
        let index = min(max(0, leadingIndex + offset), snapshot.columns.count - 1)
        guard snapshot.columns.indices.contains(index) else { return }
        leadingID = snapshot.columns[index].id
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
