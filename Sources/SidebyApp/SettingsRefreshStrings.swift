import SidebyCore

struct SettingsRefreshStrings {
    let language: AppLanguage
    func text(_ english: String, _ korean: String) -> String { language == .korean ? korean : english }
    func pane(_ pane: ProductSettingsPane) -> String {
        switch pane {
        case .workspaces: text("Manage Setups", "구성 관리")
        case .input: text("Input", "조작 방법")
        case .permissions: text("Permissions", "권한")
        case .general: text("General", "일반")
        }
    }
    func paneSymbol(_ pane: ProductSettingsPane) -> String {
        switch pane {
        case .workspaces: "rectangle.on.rectangle"
        case .input: "keyboard"
        case .permissions: "hand.raised"
        case .general: "gearshape"
        }
    }
    var subtitle: String { text("Prepare the desktops you want to return to together.", "함께 돌아갈 데스크탑을 구성별로 준비합니다.") }
    var displayHeading: String { text("Displays that move together", "함께 움직일 화면") }
    var selectAll: String { text("Select connected displays", "연결된 화면 모두 선택") }
    var noDisplays: String { text("No connected displays are available. Check again.", "사용할 수 있는 연결 화면이 없습니다. 다시 확인해 주세요.") }
    var rememberedDisplays: String { text("Remembered displays", "기억하고 있는 화면") }
    var showDisconnectedAssignments: String { text("Show disconnected displays", "연결 끊긴 화면 보기") }
    var hideDisconnectedAssignments: String { text("Show connected displays only", "현재 연결된 화면만 보기") }
    var offlineSelected: String { text("Disconnected · selection remembered · excluded from this move", "연결 안 됨 · 이전 선택 기억됨 · 이번 이동 제외") }
    var offlineExcluded: String { text("Disconnected · exclusion remembered", "연결 안 됨 · 이전 제외 선택 기억됨") }
    func rememberedCount(_ count: Int) -> String { text("Remembered displays (\(count))", "기억하고 있는 화면 \(count)개") }
    var compactAutoSave: String { text("Changes save automatically. Confirm to check the current desktop connections.", "변경은 자동 저장됩니다. 배정 확인으로 현재 데스크탑 연결을 검토하세요.") }
    var compactBuiltin: String { text("built-in", "내장") }
    var compactExternal: String { text("external", "외부") }
    var builtin: String { text("Built-in display · connected", "내장 디스플레이 · 연결됨") }
    var external: String { text("External display · connected", "외부 디스플레이 · 연결됨") }
    func selectionCount(_ count: Int) -> String {
        count == 0 ? text("Select at least one display to move.", "함께 움직일 화면을 하나 이상 선택해 주세요.")
        : text("\(count) selected displays will move together.", "선택한 화면 \(count)개가 함께 이동합니다.")
    }
    var workspaceName: String { text("Setup name", "구성 이름") }
    var workspaces: String { text("Setups", "구성") }
    var missingTarget: String { text("The requested setup is no longer available. Showing an available setup instead.", "요청한 구성이 더 이상 없습니다. 남아 있는 구성을 표시합니다.") }
    var missingDisplay: String { text("The requested display is no longer in this setup. Its saved information may be shown under remembered displays.", "요청한 화면이 이 구성에 없습니다. 저장된 정보는 기억하고 있는 화면에서 확인할 수 있습니다.") }
    var noAssignment: String { text("Not assigned", "배정 안 됨") }
    var unavailableAssignment: String { text("Current desktops could not be checked. Saved assignment is retained.", "현재 데스크탑을 확인하지 못했습니다. 저장된 배정은 유지됩니다.") }
    var invalidAssignment: String { text("The saved desktop is not currently available.", "저장한 데스크탑을 현재 사용할 수 없습니다.") }
    func desktop(_ index: Int) -> String { text("Desktop \(index + 1)", "데스크탑 \(index + 1)") }
    func assignmentLabel(_ name: String) -> String { text("Desktop for \(name)", "\(name)의 데스크탑") }
    func screenNumber(_ index: Int) -> String {
        let marks = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧"]
        return marks.indices.contains(index) ? marks[index] : text("Display \(index + 1)", "화면 \(index + 1)")
    }
    var geometryUnavailable: String { text("Display positions unavailable; select by name.", "배치를 확인할 수 없어 이름으로 표시합니다.") }
    var primaryDisplaySuffix: String { text(" · main", " · 주 화면") }
    var excluded: String { text("Excluded from this move", "이번 이동 제외") }
    var offline: String { text("Disconnected · saved", "연결 안 됨 · 저장 배정") }
    var readFailure: String { text("Could not check", "확인 불가") }
    var invalidDesktop: String { text("Desktop unavailable", "데스크탑 사용 불가") }
    var currentWorkspace: String { text("Current setup", "현재 구성") }
    var reorderBefore: String { text("Move column before", "화면 열 앞으로 이동") }
    var tableHeading: String { text("Desktop assignments by setup", "구성별 데스크탑 배정") }
    var savedAssignment: String { text("Saved assignment", "저장 배정") }
    var assignmentTable: String { text("Show all assignments", "전체 배정 보기") }
    var autoSave: String { text("Name and assignment changes are saved automatically. Confirming assignments checks how saved setup names relate to the current desktops on each display.", "이름과 배정 변경은 자동으로 저장됩니다. 배정 확인은 저장한 구성 이름과 현재 디스플레이별 데스크탑의 연결을 검토하는 단계입니다.") }
    var confirmAssignments: String { text("Confirm assignments", "화면 배정 확인") }
    var confirmReturnDaily: String { text("Confirm and open setup chooser", "확인하고 구성 선택으로") }
    var confirmReturnGuide: String { text("Confirm and return to guide", "확인하고 안내로 돌아가기") }
    var confirmed: String { text("Current desktop layout loaded", "현재 데스크탑 구성을 읽었습니다") }
    var usableAssignmentsConfirmed: String { text("Available setups are connected", "사용 가능한 구성이 연결되어 있습니다") }
    var missingDesktopHelp: String { text("Reassign missing desktops or add them in Mission Control.", "없는 데스크탑은 배정을 바꾸거나 다시 추가해 주세요.") }
    var openMissionControl: String { text("Open Mission Control", "Mission Control 열기") }
    var capture: String { text("Read desktop arrangement", "데스크탑 구성 가져오기") }
    var captureImpact: String { text("Reads desktop changes while keeping setup names and custom assignments.", "데스크탑 변경 사항을 읽고 구성 이름과 직접 구성한 배정을 유지합니다.") }
    var empty: String { text("Read your desktop arrangement to prepare setups.", "데스크탑 구성을 가져와 돌아갈 구성을 준비하세요.") }
    var addWorkspace: String { text("Add setup", "구성 추가") }
    var deleteWorkspace: String { text("Delete setup", "구성 삭제") }
    var gesturePractice: String { text("Try the gesture", "제스처 연습") }
    var finishPractice: String { text("End practice", "연습 마치기") }
    var permissionBeforePractice: String { text("Allow Accessibility before starting gesture practice.", "제스처를 연습하려면 먼저 손쉬운 사용을 허용해 주세요.") }
    var inputDescription: String { text("Choose how to move between the setups you prepared.", "준비한 구성을 오갈 조작 방법을 선택합니다.") }
    var replay: String { text("Open setup guide again", "시작 안내 다시 보기") }
    var generalDescription: String { text("Language, startup, and updates.", "언어, 시작 방식과 업데이트를 관리합니다.") }
}
