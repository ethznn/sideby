import SidebyCore
import SidebyUI
import SwiftUI

/// Previously created rebuild backups remain accessible; everyday work never rebuilds the library.
struct WorkspaceRebuildControls: View {
    @ObservedObject var model: SidebyAppModel
    @State private var confirming = false
    @State private var message: String?
    private var copy: WorkspaceRebuildStrings { .init(language: model.settings.language) }

    var body: some View {
        if let backup = model.workspaceRebuildBackup {
            VStack(alignment: .leading, spacing: 8) {
                Button(model.saveCopy.text("Restore previous setup…", "이전 화면 구성 복원…")) { confirming = true }
                    .disabled(!model.canSaveWorkspace).pointingHandCursor().accessibilityIdentifier("workspace-rebuild-undo")
                if let message { Text(message).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText) }
            }
            .confirmationDialog(model.saveCopy.text("Restore \(backup.plan.contexts.count) saved setups?", "이전 구성 \(backup.plan.contexts.count)개를 복원할까요?"), isPresented: $confirming) {
                Button(model.saveCopy.text("Restore setup", "구성 복원")) {
                    message = model.restoreWorkspaceRebuildBackup() ? copy.restored : copy.restoreFailed
                }
                Button(model.saveCopy.cancel, role: .cancel) {}
            } message: {
                Text(model.saveCopy.text("This replaces the current saved setup definitions. Desktops don't move, and the change can be undone.", "현재 저장된 구성 정의를 이전 구성으로 바꿉니다. 실제 데스크탑은 이동하지 않으며 최근 변경으로 되돌릴 수 있습니다."))
            }
        }
    }
}

struct WorkspaceRebuildStrings {
    let language: AppLanguage
    private func text(_ en: String, _ ko: String) -> String { language == .korean ? ko : en }
    var rebuild: String { text("Rebuild from current desktops…", "현재 데스크탑으로 다시 구성…") }
    var confirm: String { text("Rebuild setups", "다시 구성") }
    var undo: String { text("Undo", "실행 취소") }
    var automatic: String { text("Changes update automatically. Rebuild to start over in desktop order.", "변경은 자동 반영됩니다. 데스크탑 순서로 새로 시작하려면 다시 구성하세요.") }
    var impact: String { text("Creates setups in the current desktop order on your selected displays. Their existing names, custom assignments and shared desktops will be replaced. Other displays are kept, and you can restore the previous setup.", "선택한 화면의 현재 데스크탑 순서로 구성을 만듭니다. 기존 구성 이름·수동 배정·함께 사용 관계가 새 구성으로 바뀝니다. 다른 화면의 배정은 보관하며, 이전 구성으로 되돌릴 수 있습니다.") }
    func confirmTitle(_ count: Int) -> String { text("Rebuild \(count) setups?", "구성 \(count)개를 다시 구성할까요?") }
    func rebuilt(_ count: Int) -> String { text("Created \(count) setups in desktop order.", "데스크탑 순서로 구성 \(count)개를 만들었습니다.") }
    var restored: String { text("Previous setup restored.", "이전 화면 구성을 복원했습니다.") }
    var unavailable: String { text("Could not read all selected displays. Check their connection and try again.", "선택한 화면의 데스크탑을 모두 읽지 못했습니다. 연결 상태를 확인해 주세요.") }
    var changed: String { text("The desktop arrangement changed. Open Rebuild again to review the latest setup.", "데스크탑 구성이 바뀌었습니다. 다시 구성 버튼을 눌러 최신 구성을 확인해 주세요.") }
    var restoreFailed: String { text("A desktop needed for restoration is missing or unreadable. Your backup is still saved.", "복원에 필요한 데스크탑이 없거나 읽을 수 없습니다. 이전 구성은 계속 보관 중입니다.") }
}
