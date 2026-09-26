import SidebyCore

struct DailyRefreshStrings {
    let language: AppLanguage
    private func text(_ english: String, _ korean: String) -> String { language == .korean ? korean : english }
    var title: String { text("Workspaces", "작업 선택") }
    var emptyTitle: String { text("Prepare a workspace to return to", "돌아갈 작업을 준비하세요") }
    var emptyMessage: String { text("Choose the displays and desktops you want to move together, then give the workspaces a name.", "함께 움직일 화면과 데스크탑을 선택하고 작업에 이름을 붙여 주세요.") }
    var busy: String { text("Finishing the current operation…", "진행 중인 작업을 마무리하고 있습니다…") }
    var offTitle: String { text("Sideby is off", "Sideby가 꺼져 있습니다") }
    var turnOn: String { text("Turn on Sideby", "Sideby 켜기") }
    var permissionTitle: String { text("Access is needed to switch", "화면 전환에 필요한 접근을 확인해 주세요") }
    var permissions: String { text("Review permissions", "권한 확인") }
    var review: String { text("Review assignments", "화면 배정 확인") }
    var repairAssignment: String { text("Fix assignment", "배정 수정") }
    var savedDesktopMissing: String { text("A saved desktop is no longer available on this display", "이 화면에 저장된 데스크탑이 없습니다") }
    var reviewTitle: String { text("Check the workspaces you saved", "저장한 작업의 연결을 확인해 주세요") }
    var resume: String { text("Continue first-work guide", "첫 작업 안내 계속하기") }
    var settings: String { text("Settings…", "설정…") }
    var edit: String { text("Edit workspaces", "작업 구성 편집") }
    var rename: String { text("Rename", "이름 수정") }
    var finishRenaming: String { text("Done", "완료") }
    var useVisibleName: String { text("Use name from current screen", "현재 화면에서 이름 가져오기") }
    var nameUnavailable: String { text("Could not find a window name. Enter a name directly.", "창 이름을 찾지 못했습니다. 직접 이름을 입력해 주세요.") }
    var useDesktopName: String { text("Use desktop names for workspace", "데스크탑 이름을 작업 이름으로 사용") }
    var desktopNameUnavailable: String { text("Could not read the desktop names. Check the display connection or enter a workspace name directly.", "데스크탑 이름을 읽을 수 없습니다. 화면 연결을 확인하거나 작업 이름을 직접 입력해 주세요.") }
    func workspaceNamed(_ name: String) -> String { text("Workspace named “\(name)”.", "작업 이름을 변경했습니다: \(name)") }
    var nameHelp: String { text("Desktop names are suggested from window content. Your own workspace names stay unchanged.", "각 데스크탑의 창 내용으로 이름을 제안합니다. 직접 수정한 작업 이름은 유지됩니다.") }
    func refreshResult(updatedNames: Int, detectedNames: Int) -> String {
        if detectedNames == 0 { return text("No window names were available; existing names were kept.", "창 이름을 읽지 못해 기존 이름을 유지했습니다.") }
        return text("\(detectedNames) desktop names found, \(updatedNames) workspace names updated", "데스크탑 이름 \(detectedNames)개 확인, 작업 이름 \(updatedNames)개 반영")
    }
    var quit: String { text("Quit Sideby", "Sideby 종료") }
    func movingDisplays(_ count: Int) -> String { text("\(count) displays move together", "화면 \(count)개 함께 이동") }
}
