import SidebyCore

struct OnboardingRefreshStrings {
    let language: AppLanguage
    private func text(_ english: String, _ korean: String) -> String {
        language == .korean ? korean : english
    }

    func stage(_ stage: ProductOnboardingStage) -> String {
        switch stage {
        case .preparation: text("1 · Preparation", "1 · 전환 준비")
        case .displays: text("2 · Displays", "2 · 화면 선택")
        case .workspaces: text("3 · Setups", "3 · 구성 준비")
        case .roundTrip: text("4 · Round trip", "4 · 직접 왕복")
        }
    }
    func title(_ stage: ProductOnboardingStage) -> String {
        switch stage {
        case .preparation: text("Back to your work, in one action.", "하던 일로 한 번에 돌아오세요.")
        case .displays: text("Which displays should move together?", "어떤 화면을 함께 움직일까요?")
        case .workspaces: text("Name the work you’ll return to", "돌아갈 구성에 이름을 붙이세요")
        case .roundTrip: text("Go there. Then come back.", "다른 구성으로 갔다가 돌아오세요")
        }
    }
    func subtitle(_ stage: ProductOnboardingStage) -> String {
        switch stage {
        case .preparation: text("Switch the desktops you prepared for development and review together, by setup name.", "개발과 리뷰에 쓰도록 준비한 데스크탑을 구성 이름으로 함께 오가세요.")
        case .displays: text("Choose one or more displays. Sideby also works with just your Mac’s screen.", "함께 전환할 화면을 선택하세요. Mac 화면 하나만으로도 사용할 수 있습니다.")
        case .workspaces: text("Review the names and desktop assignments on each display.", "이름과 디스플레이별 데스크탑 배정을 확인하세요.")
        case .roundTrip: text("Try the two setups you prepared. Return to the first one to finish setup.", "준비한 두 구성을 직접 오가 보세요. 처음 구성으로 돌아오면 준비가 끝납니다.")
        }
    }
    var later: String { text("Continue later", "나중에 계속하기") }
    var back: String { text("Back", "뒤로") }
    var chooseDisplays: String { text("Choose displays", "함께 움직일 화면 선택") }
    var prepareWorkspaces: String { text("Prepare setups", "구성 준비") }
    var permissionsNeeded: String { text("Allow both required accesses to continue.", "두 가지 필수 접근을 허용하면 계속할 수 있습니다.") }
    var permissionDetails: String { text("How Sideby handles input", "Sideby의 입력 처리 방식") }
    var accessReady: String { text("The required access is ready. Now choose the displays that should move together.", "필요한 접근을 확인했습니다. 이제 함께 움직일 화면을 선택하세요.") }
    var noDisplays: String { text("Could not identify connected displays.", "연결된 화면을 확인하지 못했습니다.") }
    var rememberedDisplays: String { text("Remembered displays", "기억하고 있는 화면") }
    func displayDescription(builtin: Bool, primary: Bool) -> String {
        let kind = builtin ? text("Built-in display", "내장 디스플레이") : text("External display", "외부 디스플레이")
        return kind + (primary ? text(" · Main display · Connected", " · 주 디스플레이 · 연결됨") : text(" · Connected", " · 연결됨"))
    }
    func offline(selected: Bool) -> String {
        selected
            ? text("Disconnected · Previous selection remembered. Excluded from this move.", "연결 안 됨 · 이전 선택 기억됨. 이번 이동에는 포함되지 않습니다.")
            : text("Disconnected · Assignments preserved. Excluded from this move.", "연결 안 됨 · 배정 보존 중. 이번 이동에는 포함되지 않습니다.")
    }
    func selectedDisplays(_ count: Int) -> String {
        count == 0
            ? text("Select at least one connected display to continue.", "함께 움직일 화면을 하나 이상 선택해 주세요.")
            : count == 1
                ? text("Switch between desktops on this display.", "이 화면의 데스크탑을 구성별로 전환합니다.")
                : text("\(count) selected displays will move together.", "선택한 화면 \(count)개가 함께 이동합니다.")
    }
    var captureTitle: String { text("First, read your desktop layout", "먼저 데스크탑 구성을 가져옵니다") }
    var captureExplanation: String { text("Read the desktop positions on your selected displays and group them into setups. This does not take screenshots or save window contents.", "선택한 화면의 데스크탑 위치를 읽어 구성별로 묶습니다. 화면 이미지를 촬영하거나 창 내용을 저장하지 않습니다.") }
    var capture: String { text("Read desktop layout", "데스크탑 구성 가져오기") }
    var recapture: String { text("Read layout again", "구성 다시 가져오기") }
    var recaptureExplanation: String { text("Reading again updates assignments on selected displays, preserves names and assignments on other displays, and restarts session confirmation and round-trip progress.", "다시 가져오면 선택한 화면의 배정을 갱신합니다. 이름과 비선택 화면의 배정은 보존하며, 세션 확인과 왕복 진행은 다시 시작합니다.") }
    var autosave: String { text("Names and assignment changes save automatically. Confirm the assignments, then choose the first move on the next screen.", "이름과 배정 변경은 자동으로 저장됩니다. 배정을 확인하고 계속한 뒤, 다음 단계에서 직접 첫 구성으로 이동하세요.") }
    var confirm: String { text("Confirm assignments and continue", "배정 확인하고 계속") }
    var shortage: String { text("You need two setups for a round trip.", "왕복하려면 구성 두 개가 필요합니다.") }
    var unavailable: String { text("Could not read the current desktop layout. Your saved names and assignments are preserved.", "현재 데스크탑 구성을 확인하지 못했습니다. 저장된 이름과 배정은 유지됩니다.") }
    var review: String { text("Review assignments", "배정 자세히 보기") }
    var missionControl: String { text("Open Mission Control", "Mission Control 열기") }
    var returnedFromMissionControl: String { text("After adding a desktop, read the layout again. Sideby does not create desktops.", "데스크탑을 추가한 뒤 구성을 다시 가져오세요. Sideby가 데스크탑을 만들지는 않습니다.") }
    func desktop(_ index: Int) -> String { text("Desktop \(index + 1)", "데스크탑 \(index + 1)") }
    var savedAssignment: String { text("Saved assignment", "저장된 배정") }
    var excluded: String { text("Excluded from this move", "이번 이동 제외") }
    func firstMove(_ name: String) -> String { text("First, go to the desktops assigned to \(name). If you are already there, Sideby checks that position before you start.", "먼저 ‘\(name)’에 지정된 데스크탑으로 이동합니다. 이미 그 위치에 있다면 현재 위치를 확인한 뒤 시작합니다.") }
    func move(_ name: String) -> String { text("Go to \(name)", "‘\(name)’ 구성으로 이동") }
    func returnTo(_ name: String) -> String { text("Return to \(name)", "‘\(name)’ 구성으로 돌아가기") }
    func complete(_ first: String, _ second: String) -> String { text("\(first) → \(second) → \(first). Both the move and the return were verified.", "\(first) → \(second) → \(first). 이동과 복귀를 모두 확인했습니다.") }
    var roundTripComplete: String { text("You’re back. Ready for your next task.", "돌아왔습니다. 이제 하던 일을 이어가세요.") }
    var openChooser: String { text("Open Sideby menu", "메뉴에서 시작하기") }
    var menuHint: String { text("Open Sideby in the menu bar to switch setups or edit desktop assignments right in the matrix.", "메뉴 막대의 Sideby를 열어 구성을 전환하거나 매트릭스에서 데스크탑 배정을 바로 바꾸세요.") }
    var previousShortcutHint: String { text("Press ⌥⇧Tab to return to your previous setup. Use the same shortcut to go back and forth.", "⌥⇧Tab을 누르면 직전 구성으로 돌아갑니다. 같은 단축키로 두 구성을 계속 오갈 수 있습니다.") }
    var optionalInput: String { text("Learn gestures and shortcuts", "제스처와 단축키 알아보기") }
    var turnOn: String { text("Turn on Sideby", "Sideby 켜기") }
    var reviewPermissions: String { text("Review required access", "필수 접근 확인") }
    var waiting: String { text("Waiting for the current operation…", "현재 동작이 끝나기를 기다리는 중…") }
}
