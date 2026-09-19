import SidebyCore
import SidebyUI
import SwiftUI

/// The menu and Settings expose the same explicit rebuild/undo operation.
struct WorkspaceRebuildControls: View {
    @ObservedObject var model: SidebyAppModel
    @State private var proposal: WorkspaceRebuildProposal?
    @State private var message: String?
    private var copy: WorkspaceRebuildStrings { .init(language: model.settings.language) }
    private var isBusy: Bool { !model.canAddContext || model.pendingContextCaptureAlignment != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button(copy.rebuild) {
                    proposal = model.prepareWorkspaceRebuild()
                    if proposal == nil { message = copy.unavailable }
                }
                .pointingHandCursor().disabled(isBusy || model.selectedDisplayIDs.isEmpty)
                .accessibilityIdentifier("workspace-rebuild")
                Spacer(minLength: 0)
                if model.workspaceRebuildBackup != nil {
                    Button(copy.undo) {
                        message = model.restoreWorkspaceRebuildBackup() ? copy.restored : copy.restoreFailed
                    }
                    .pointingHandCursor().disabled(isBusy)
                    .accessibilityIdentifier("workspace-rebuild-undo")
                }
            }
            Text(message ?? copy.automatic).font(.system(size: 12))
                .foregroundStyle(NativeSurfaceStyle.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(copy.confirmTitle(proposal?.count ?? 0), isPresented: Binding(
            get: { proposal != nil }, set: { if !$0 { proposal = nil } }
        ), titleVisibility: .visible, presenting: proposal) { accepted in
            Button(copy.confirm, role: .destructive) {
                message = model.rebuildWorkspaces(accepted) ? copy.rebuilt(accepted.count) : copy.changed
                proposal = nil
            }
            Button(model.strings.cancel, role: .cancel) { proposal = nil }
        } message: { _ in Text(copy.impact) }
    }
}

struct WorkspaceRebuildStrings {
    let language: AppLanguage
    private func text(_ en: String, _ ko: String) -> String { language == .korean ? ko : en }
    var rebuild: String { text("Rebuild from current desktops…", "현재 데스크탑으로 다시 구성…") }
    var confirm: String { text("Rebuild workspaces", "다시 구성") }
    var undo: String { text("Restore previous setup", "이전 구성으로 되돌리기") }
    var automatic: String { text("Desktop changes update automatically. Rebuild only to start over in the current desktop order.", "데스크탑 변경은 자동으로 반영됩니다. 현재 순서로 새로 시작할 때만 다시 구성하세요.") }
    var impact: String { text("Creates workspaces in the current desktop order on your selected displays. Their existing names, custom assignments and shared desktops will be replaced. Other displays are kept, and you can restore the previous setup.", "선택한 화면의 현재 데스크탑 순서로 작업을 만듭니다. 기존 작업 이름·수동 배정·함께 사용 관계가 새 구성으로 바뀝니다. 다른 화면의 배정은 보관하며, 이전 구성으로 되돌릴 수 있습니다.") }
    func confirmTitle(_ count: Int) -> String { text("Rebuild \(count) workspaces?", "작업 \(count)개를 다시 구성할까요?") }
    func rebuilt(_ count: Int) -> String { text("Created \(count) workspaces in desktop order. Previous setup saved.", "데스크탑 순서로 작업 \(count)개를 만들었습니다. 이전 구성은 보관했습니다.") }
    var restored: String { text("Previous workspace setup restored.", "이전 작업 구성을 복원했습니다.") }
    var unavailable: String { text("Could not read all selected displays. Check their connection and try again.", "선택한 화면의 데스크탑을 모두 읽지 못했습니다. 연결 상태를 확인해 주세요.") }
    var changed: String { text("The desktop arrangement changed. Open Rebuild again to review the latest setup.", "데스크탑 구성이 바뀌었습니다. 다시 구성 버튼을 눌러 최신 구성을 확인해 주세요.") }
    var restoreFailed: String { text("A desktop needed for restoration is missing or unreadable. Your backup is still saved.", "복원에 필요한 데스크탑이 없거나 읽을 수 없습니다. 이전 구성은 계속 보관 중입니다.") }
}
