import SidebyCore

struct WorkspaceSaveStrings {
    let language: AppLanguage
    func text(_ en: String, _ ko: String) -> String { language == .korean ? ko : en }
    var saveConfiguration: String { text("Save this setup", "이 구성 저장") }
    var currentSetup: String { text("Current setup", "지금 화면") }
    var savedWorkspaces: String { text("Saved setups", "저장한 구성") }
    var matrix: String { text("By display", "화면별 보기") }
    var list: String { text("List", "목록 보기") }
    var emptyTitle: String { text("Keep the setup you're using.", "지금 쓰는 구성을 기억해 두세요.") }
    var emptyMessage: String { text("Save it above, then choose it here whenever you want to return.", "위에서 구성을 저장하면\n다음에도 여기에서 다시 고를 수 있어요.") }
    var edit: String { text("Edit", "편집") }
    var delete: String { text("Delete setup…", "구성 삭제…") }
    var deleteAll: String { text("Delete all saved setups…", "저장한 구성 모두 삭제…") }
    var deleteAllAction: String { text("Delete all", "모두 삭제") }
    func deleteAllTitle(_ count: Int) -> String { text("Delete all \(count) saved setups?", "저장한 구성 \(count)개를 모두 삭제할까요?") }
    var deleteAllMessage: String { text("Includes setups on disconnected displays. Your desktops, apps and other settings stay as they are. You can undo this until your next setup change.", "연결되지 않은 화면의 구성도 함께 삭제합니다. 실제 데스크탑·열려 있는 앱·다른 설정은 그대로 유지돼요. 다음에 구성을 추가하거나 수정하기 전까지 ‘최근 변경 되돌리기’로 복구할 수 있어요.") }
    var deleteAllChanged: String { text("The saved setups changed. Review the list before deleting all.", "저장한 구성이 변경됐어요. 목록을 확인한 뒤 다시 삭제해 주세요.") }
    func deletedAll(_ count: Int) -> String { text("Deleted \(count) saved setups. You can undo this.", "저장한 구성 \(count)개를 모두 삭제했어요. 최근 변경을 되돌릴 수 있어요.") }
    var cancel: String { text("Cancel", "취소") }
    var save: String { text("Save setup", "구성 저장") }
    var saveChanges: String { text("Save changes", "변경 저장") }
    var name: String { text("Setup name", "구성 이름") }
    var included: String { text("Displays to remember", "함께 기억할 화면") }
    var scope: String { text("Remembers desktop connections. Apps, documents and window positions aren't saved.", "데스크탑 연결을 기억합니다. 앱·문서·창 위치는 저장하지 않습니다.") }
    var preserve: String { text("Your other setups stay as they are.", "기존 구성은 그대로 유지됩니다.") }
    var preserveEdit: String { text("Only this setup will change.", "이 구성만 변경됩니다.") }
    var keep: String { text("Keep as is", "그대로 유지") }
    var notIncluded: String { text("Not included", "포함 안 함") }
    var offline: String { text("Not connected", "연결 안 됨") }
    var excluded: String { text("Excluded in display settings", "화면 설정에서 제외됨") }
    var remembered: String { text("Saved connection kept", "저장된 연결 유지") }
    var missingDesktop: String { text("Desktop needs review. Edit this setup to reconnect it.", "연결할 데스크탑을 확인해 주세요. 이 구성의 편집에서 다시 지정할 수 있어요.") }
    var changed: String { text("The setup changed. Read the current setup again before saving.", "화면 구성이 바뀌었어요. 현재 화면을 다시 읽어 확인해 주세요.") }
    var readAgain: String { text("Read current setup again", "현재 화면 다시 읽기") }
    var useCurrent: String { text("Use current setup", "현재 화면으로 바꾸기") }
    var readUnavailable: String { text("Couldn't read the desktop connections. Check the displays and try again.", "데스크탑 연결을 읽지 못했어요. 화면 연결을 확인하고 다시 시도해 주세요.") }
    var invalidNameOrSelection: String { text("Enter a name up to 60 characters and select at least one display.", "60자 이내의 이름과 포함할 화면을 하나 이상 선택해 주세요.") }
    var conflict: String { text("This setup changed elsewhere. Reopen it to review the latest setup.", "다른 곳에서 구성이 변경됐어요. 다시 열어 최신 구성을 확인해 주세요.") }
    var saveFailed: String { text("Couldn't save. Your existing setups are unchanged. Please try again.", "저장하지 못했어요. 기존 구성은 유지됩니다. 다시 시도해 주세요.") }
    var settingsUnreadable: String { text("Saved settings couldn't be read. They have been kept without overwriting. Restore the original settings to continue.", "저장된 설정을 읽지 못했어요. 원본을 덮어쓰지 않고 보존했습니다. 설정을 복구한 뒤 다시 열어 주세요.") }
    var undo: String { text("Undo last change", "최근 변경 되돌리기") }
    var undone: String { text("Last setup change undone.", "최근 변경을 되돌렸어요.") }
    var current: String { text("Current", "현재 구성") }
    var moving: String { text("Switching…", "이동 중…") }
    var close: String { text("Close", "닫기") }
    var chooseHint: String { text("Choose a setup to move its included displays.", "구성을 고르면 포함한 화면만 함께 이동해요.") }
    var holdHint: String { text("Hold to choose · Release to close", "누른 채 선택 · 키를 놓으면 닫기") }
    var releaseHint: String { text("Release the shortcut keys to enter a name.", "단축키에서 손을 떼고 이름을 입력하세요.") }
    var showExisting: String { text("Show saved setup", "저장된 구성 보기") }
    var changes: String { text("Changes", "변경 내용") }
    func defaultName(_ n: Int) -> String { text("Setup \(n)", "구성 \(n)") }
    func desktop(_ n: Int) -> String { text("Desktop \(n + 1)", "데스크탑 \(n + 1)") }
    func saved(_ name: String) -> String { text("Saved ‘\(name)’.", "‘\(name)’을 저장했어요.") }
    func edited(_ name: String) -> String { text("Updated ‘\(name)’.", "‘\(name)’을 수정했어요.") }
    func deleted(_ name: String) -> String { text("Deleted ‘\(name)’.", "‘\(name)’을 삭제했어요.") }
    func duplicate(_ name: String) -> String { text("This setup is already saved as ‘\(name)’.", "이 구성은 이미 ‘\(name)’로 저장되어 있어요.") }
    func returnTo(_ name: String) -> String { text("Return to \(name)", "\(name)로 돌아가기") }
    func deleteTitle(_ name: String) -> String { text("Delete ‘\(name)’?", "‘\(name)’ 구성을 삭제할까요?") }
    var deleteMessage: String { text("Only the saved setup is removed. Your desktops and apps stay open. You can undo this change.", "저장된 구성만 삭제합니다. 데스크탑과 앱은 그대로 남고, 최근 변경을 되돌릴 수 있어요.") }
}
