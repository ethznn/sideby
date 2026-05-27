import SidebyCore

public struct SBSStrings: Sendable {
    public let language: AppLanguage

    public init(language: AppLanguage) {
        self.language = language
    }

    private func text(_ english: String, _ korean: String) -> String {
        switch language {
        case .english:
            english
        case .korean:
            korean
        }
    }

    public func languageName(_ language: AppLanguage) -> String {
        switch (self.language, language) {
        case (.english, .english):
            "English"
        case (.english, .korean):
            "Korean"
        case (.korean, .english):
            "영어"
        case (.korean, .korean):
            "한국어"
        }
    }

    public var languageTitle: String { text("Language", "언어") }
    public var languageHelp: String { text("Changes the app UI language immediately.", "앱 UI 언어가 즉시 변경됩니다.") }
    public var settings: String { text("Settings", "설정") }
    public var overview: String { text("Overview", "개요") }
    public var general: String { text("General", "일반") }
    public var input: String { text("Input", "입력") }
    public var permissions: String { text("Permissions", "권한") }
    public var advanced: String { text("Advanced", "고급") }
    public var labs: String { text("Labs", "실험실") }
    public var refresh: String { text("Refresh", "새로고침") }
    public var quit: String { text("Quit", "종료") }
    public var on: String { text("On", "켬") }
    public var off: String { text("Off", "끔") }
    public var back: String { text("Back", "뒤로") }
    public var `continue`: String { text("Continue", "계속") }
    public var openSystemSettings: String { text("Open System Settings…", "시스템 설정 열기…") }
    public var openMenuBar: String { text("Open menu bar", "메뉴바 열기") }
    public var openSettings: String { text("Open Settings", "설정 열기") }
    public var onboardingCompletionActionTitle: String { openSettings }
    public var replayOnboarding: String { text("Replay Onboarding", "온보딩 다시 보기") }
    public var customizeShortcuts: String { text("Customize Shortcuts", "단축키 설정") }
    public var sideby: String { SidebyCore.productName }
    public var slogan: String { SidebyCore.slogan }

    public var settingsSubtitle: String {
        text("Screen Switching is ready for selected displays.", "선택한 디스플레이에서 화면 전환을 사용할 준비가 됐습니다.")
    }
    public var overviewSubtitle: String {
        text("Check Sideby status and run a quick switch test.", "Sideby 상태를 확인하고 전환을 빠르게 테스트합니다.")
    }
    public var displaysSubtitle: String {
        text("Choose which displays move together.", "함께 이동할 디스플레이를 선택합니다.")
    }
    public var inputSubtitle: String {
        text("Set the gesture modifier and keyboard shortcuts.", "제스처 보조 키와 키보드 단축키를 설정합니다.")
    }
    public var permissionsSubtitle: String {
        text("Review the permissions used for gesture detection and switching.", "제스처 감지와 전환에 필요한 권한을 확인합니다.")
    }
    public var generalSubtitle: String {
        text("Set app language, launch behavior, and onboarding.", "앱 언어, 실행 방식, 온보딩을 설정합니다.")
    }
    public var advancedSubtitle: String {
        text("Experimental input paths for testing only.", "테스트용 실험 입력 경로입니다.")
    }

    public var setupTitle: String { text("Set Up Sideby", "Sideby 설정") }
    public var setupSubtitle: String {
        text("Move selected displays with one action.", "선택한 디스플레이를 한 번에 함께 이동합니다.")
    }
    public var setupStatus: String { text("Setup Status", "설정 상태") }
    public var completeSetup: String { text("Complete Setup", "설정 완료") }

    public var moveTargets: String { text("Move Targets", "이동 대상") }
    public var allDisplaysButton: String { text("All Displays", "전체 디스플레이") }
    public var primaryDisplayTag: String { text("primary", "주 디스플레이") }
    public var builtInDisplayTag: String { text("built-in", "내장") }
    public var contextPlanner: String { text("Contexts", "컨텍스트") }
    public var currentContext: String { text("Current Context", "현재 컨텍스트") }
    public var addContext: String { text("Add Context", "컨텍스트 추가") }
    public var setCurrent: String { text("Set Current", "현재 위치로 맞춤") }
    public var deleteContext: String { text("Delete", "삭제") }
    public var contextLabelPlaceholder: String { text("Label", "라벨") }
    public var scanCurrentDisplays: String { text("Scan Current Displays", "현재 디스플레이 스캔") }
    public var scanCurrentSpace: String { text("Scan Current Space", "현재 화면 스캔") }
    public var captureContexts: String { text("Capture Contexts", "컨텍스트 캡처") }
    public var displaySpaces: String { text("Display Spaces", "디스플레이별 화면") }
    public var captureSpaces: String { text("Capture Spaces", "화면 캡처") }
    public var stopCapture: String { text("Stop", "중지") }
    public var useApp: String { text("Use App", "앱 사용") }
    public var useTitle: String { text("Use Title", "제목 사용") }
    public var noCurrentContext: String { text("No current Context", "현재 컨텍스트 없음") }
    public var contextPlannerHelp: String {
        text(
            "Labels are written by you. Sideby moves only Previous or Next and updates the current Context after a successful switch.",
            "라벨은 사용자가 직접 입력합니다. Sideby는 이전/다음으로만 이동하고 전환 성공 후 현재 컨텍스트를 갱신합니다."
        )
    }
    public var displaySpacesHelp: String {
        text(
            "Each connected display is a Context. Add labels for the Spaces you move through on that display.",
            "연결된 디스플레이 하나가 컨텍스트입니다. 각 디스플레이에서 이동할 화면별 라벨을 입력합니다."
        )
    }

    public func spacesToCapture(_ count: Int) -> String {
        if count == 1 {
            return text("Capture 1 Space", "1개 화면 캡처")
        }
        return text("Capture \(count) Spaces", "\(count)개 화면 캡처")
    }

    public func spaceName(_ order: Int) -> String {
        text("Space \(order)", "화면 \(order)")
    }

    public var spaceLabelPlaceholder: String { text("App or title", "앱 또는 제목") }

    public func detectedApp(_ label: String) -> String {
        text("Detected: \(label)", "감지됨: \(label)")
    }

    public func capturingContext(current: Int, total: Int, name: String) -> String {
        text("Capturing Context \(current) of \(total): \(name)", "컨텍스트 \(current)/\(total) 캡처 중: \(name)")
    }

    public func capturingSpace(current: Int, total: Int) -> String {
        text("Capturing Space \(current) of \(total)", "화면 \(current)/\(total) 캡처 중")
    }

    public func selectedDisplaySummary(selected: Int, total: Int) -> String {
        if total == 0 {
            return text("No displays", "디스플레이 없음")
        }
        if selected == 0 {
            return text("No displays selected", "선택된 디스플레이 없음")
        }
        if selected == total {
            return text("All \(total) displays", "디스플레이 \(total)개 모두 선택됨")
        }
        return text("\(selected)/\(total) displays selected", "디스플레이 \(selected)/\(total)개 선택됨")
    }

    public var privacyPermissions: String { text("Privacy & Permissions", "개인정보 및 권한") }
    public var accessibility: String { text("Accessibility", "손쉬운 사용") }
    public var postEvents: String { text("Post Events", "이벤트 전송") }
    public var switchingAccess: String { text("Screen Switching", "화면 전환") }
    public var granted: String { text("granted", "허용됨") }
    public var notGranted: String { text("not granted", "허용 안 됨") }
    public var inputPrivacyNote: String {
        text("Input is used only while Sideby is on. Raw input is not stored.", "입력은 Sideby가 켜져 있을 때만 사용되며 원본 입력은 저장하지 않습니다.")
    }
    public var enablePermissions: String { text("Enable Permissions", "권한 허용") }
    public var enableAccessibility: String { text("Enable Accessibility", "손쉬운 사용 허용") }
    public var checkSwitchingAccess: String { text("Check Switching Access", "화면 전환 권한 확인") }
    public var enablePostEvents: String { checkSwitchingAccess }
    public var openAccessibilitySettingsButton: String {
        text("Open Accessibility Settings", "손쉬운 사용 설정 열기")
    }
    public var accessibilitySettings: String { text("Accessibility Settings", "손쉬운 사용 설정") }
    public var automationSettings: String { text("Automation Settings", "자동화 설정") }

    public var screenSwitching: String { text("Screen Switching", "화면 전환") }
    public var switchSection: String { text("Switch", "전환") }
    public var previous: String { text("Previous", "이전") }
    public var next: String { text("Next", "다음") }
    public var targets: String { text("Targets", "대상") }
    public var lastSwitch: String { text("Last switch", "마지막 전환") }
    public var testButtonsUseActivePath: String {
        text("Test buttons use the active Sideby path.", "테스트 버튼은 현재 Sideby 전환 경로를 사용합니다.")
    }
    public var turnOnForTestButtons: String {
        text("Turn on Sideby to enable test buttons.", "테스트 버튼을 사용하려면 Sideby를 켜세요.")
    }

    public var startAtLogin: String { text("Start at login", "로그인 시 시작") }
    public func startAtLoginStatus(isEnabled: Bool) -> String {
        if isEnabled {
            return text("Start at login on", "로그인 시 시작 켜짐")
        }
        return text("Start at login off", "로그인 시 시작 꺼짐")
    }
    public var startAtLoginCouldNotChange: String {
        text("Start at login could not be changed", "로그인 시 시작 설정을 변경할 수 없습니다.")
    }

    public var status: String { text("Status", "상태") }
    public var displays: String { text("Displays", "디스플레이") }
    public var mainDisplay: String { text("Main", "메인") }
    public var selected: String { text("Selected", "선택됨") }
    public var notSelected: String { text("Not selected", "선택 안 됨") }
    public var noDiagnostics: String { text("No diagnostics", "진단 없음") }
    public var swipe: String { text("Swipe", "스와이프") }
    public var command: String { text("Command", "명령") }
    public var lastInput: String { text("Last input", "마지막 입력") }

    public func permissionState(_ state: PermissionState) -> String {
        switch state {
        case .granted:
            text("granted", "허용됨")
        case .denied:
            text("denied", "거부됨")
        case .notDetermined:
            text("not determined", "확인 필요")
        }
    }

    public var sidebyOff: String { text("Sideby off", "Sideby 꺼짐") }
    public var sidebyPaused: String { text("Sideby paused", "Sideby 일시 정지됨") }
    public var inputCooldown: String { text("Input cooldown", "입력 대기 중") }
    public var noSwitchAttempted: String { text("No switch attempted", "아직 전환하지 않음") }
    public var releaseGestureModifier: String { text("Release gesture modifier to switch", "전환하려면 제스처 보조 키를 떼세요") }
    public var releaseShortcutModifier: String { text("Release shortcut modifier to switch", "전환하려면 단축키 보조 키를 떼세요") }
    public var noMoveTargetsStatus: String { text("Sideby on; no move targets selected", "Sideby 켜짐; 이동 대상이 선택되지 않았습니다") }
    public var shortcutSettingsNotSaved: String { text("Shortcut settings were not saved", "단축키 설정이 저장되지 않았습니다") }
    public var sidebyIsOffInputEvent: String { text("Sideby is off", "Sideby가 꺼져 있습니다") }
    public var couldNotStartInput: String {
        text("Sideby could not start; grant Accessibility and try again", "Sideby를 시작할 수 없습니다. 손쉬운 사용 권한을 허용한 뒤 다시 시도하세요")
    }
    public var keyboardListenerFailed: String { text("Keyboard command listener failed to start", "키보드 명령 감지를 시작하지 못했습니다") }
    public var swipeListenerFailed: String { text("Swipe listener failed to start", "스와이프 감지를 시작하지 못했습니다") }

    public func sidebyOnTargets(_ summary: String) -> String {
        text("Sideby on; targets \(summary)", "Sideby 켜짐; 대상 \(summary)")
    }

    public func gestureTestListeningTargets(_ summary: String) -> String {
        text("Gesture test listening; targets \(summary)", "제스처 테스트 감지 중; 대상 \(summary)")
    }

    public func useInputHint(gesture: String, keyboard: String) -> String {
        text("Use \(gesture), or \(keyboard).", "\(gesture) 또는 \(keyboard)을 사용하세요.")
    }
    public func useGestureHint(gesture: String) -> String {
        text("Use \(gesture).", "\(gesture)을 사용하세요.")
    }

    public func inputSettingsSaved(gesture: String, keyboard: String) -> String {
        text("Input settings saved: \(gesture), \(keyboard)", "입력 설정 저장됨: \(gesture), \(keyboard)")
    }

    public func inputSettingsUpdated(gesture: String, keyboard: String) -> String {
        text("Input settings updated: \(gesture), \(keyboard)", "입력 설정 업데이트됨: \(gesture), \(keyboard)")
    }

    public func horizontalScrollGesture(_ modifiers: ModifierFlags) -> String {
        text("\(modifierText(modifiers)) + horizontal scroll", "\(modifierText(modifiers)) + 가로 스크롤")
    }

    public func commandName(_ command: SwitchCommand) -> String {
        switch command {
        case .previous:
            previous
        case .next:
            next
        }
    }

    public func queuedSwitch(command: SwitchCommand, summary: String) -> String {
        text("Queued \(commandName(command)): \(summary)", "\(commandName(command)) 전환 대기 중: \(summary)")
    }

    public func postedSwitch(label: String, command: SwitchCommand) -> String {
        text("Posted \(label) \(commandName(command))", "\(label) \(commandName(command)) 전환 실행됨")
    }

    public func blockedSwitch(label: String, command: SwitchCommand, reason: String) -> String {
        text("Blocked \(label) \(commandName(command)): \(reason)", "\(label) \(commandName(command)) 차단됨: \(reason)")
    }

    public func ignoredSwitchAlreadyRunning(label: String? = nil, command: SwitchCommand) -> String {
        if let label {
            return text("Ignored \(label) \(commandName(command)): switch already running", "\(label) \(commandName(command)) 무시됨: 이미 전환 중")
        }
        return text("Ignored \(commandName(command)): switch already running", "\(commandName(command)) 무시됨: 이미 전환 중")
    }

    public func acceptedCommand(command: SwitchCommand, modifiers: String) -> String {
        text("Accepted \(commandName(command)); release \(modifiers)", "\(commandName(command)) 입력됨; \(modifiers)를 떼세요")
    }

    public func switchingFromSwipe(command: SwitchCommand, modifiers: String) -> String {
        text("Switching \(commandName(command)) from \(modifiers) swipe", "\(modifiers) 스와이프로 \(commandName(command)) 전환 중")
    }

    public func switchingFromShortcut(command: SwitchCommand, modifiers: String) -> String {
        text("Switching \(commandName(command)) from \(modifiers) shortcut", "\(modifiers) 단축키로 \(commandName(command)) 전환 중")
    }

    public func switchingInputPaused(command: SwitchCommand) -> String {
        text("Switching \(commandName(command)); input paused", "\(commandName(command)) 전환 중; 입력 일시 정지")
    }

    public func modifiersStatus(_ modifiers: String) -> String {
        text("Modifiers \(modifiers)", "보조 키 \(modifiers)")
    }

    public func scrollStatus(dx: Int, dy: Int) -> String {
        text("Scroll dx=\(dx) dy=\(dy)", "스크롤 dx=\(dx) dy=\(dy)")
    }

    public var spaceCommandNotAcceptedTitle: String { text("Space command was not accepted", "Space 전환 명령이 처리되지 않았습니다") }
    public var spaceCommandNotAcceptedMessage: String {
        text(
            "The selected-display Control+Arrow command was not accepted. Check Accessibility, Post Events, and System Events Automation permissions, then try again.",
            "선택한 디스플레이의 Control+화살표 명령이 처리되지 않았습니다. 손쉬운 사용, 이벤트 전송, System Events 자동화 권한을 확인한 뒤 다시 시도하세요."
        )
    }
    public var noMoveTargetsTitle: String { text("No move targets selected", "이동 대상이 선택되지 않았습니다") }
    public var noMoveTargetsMessage: String { text("Select at least one display before switching.", "전환하기 전에 디스플레이를 하나 이상 선택하세요.") }
    public var sidebyOffTitle: String { text("Sideby is off", "Sideby가 꺼져 있습니다") }
    public var sidebyOffMessage: String { text("Turn on Sideby before testing a switch.", "전환을 테스트하기 전에 Sideby를 켜세요.") }
    public var postEventsOffTitle: String { text("Post Events permission is off", "이벤트 전송 권한이 꺼져 있습니다") }
    public var postEventsOffMessage: String {
        text("Use Check Switching Access, then follow any macOS permission prompt.", "화면 전환 권한 확인을 누른 뒤 macOS 권한 안내가 뜨면 따르세요.")
    }
    public func permissionRequestFeedback(_ feedback: PermissionRequestFeedback) -> String {
        switch feedback.kind {
        case .postEventsRequesting:
            text(
                "Check the macOS Post Events prompt. If nothing appears, wait a moment and use the fallback action that appears here.",
                "macOS 이벤트 전송 권한 안내를 확인하세요. 아무 창도 뜨지 않으면 잠시 뒤 여기에 표시되는 대체 동작을 사용하세요."
            )
        case .switchingAccessRequesting:
            text(
                "Check any macOS permission prompts for Screen Switching. If nothing appears, wait a moment and use the fallback action that appears here.",
                "화면 전환 권한을 위한 macOS 안내를 확인하세요. 아무 창도 뜨지 않으면 잠시 뒤 여기에 표시되는 대체 동작을 사용하세요."
            )
        case .postEventsDenied:
            text(
                "macOS did not grant Post Events. If no prompt appears, open Accessibility Settings and re-enable Sideby.",
                "macOS가 이벤트 전송 권한을 허용하지 않았습니다. 안내 창이 뜨지 않으면 손쉬운 사용 설정에서 Sideby를 다시 허용하세요."
            )
        case .automationDenied:
            text(
                "macOS did not grant System Events Automation. Open Automation Settings and allow Sideby to control System Events.",
                "macOS가 System Events 자동화를 허용하지 않았습니다. 자동화 설정에서 Sideby가 System Events를 제어하도록 허용하세요."
            )
        case .automationNotRegistered:
            text(
                "macOS did not register the System Events permission request. Try Check Switching Access again; if the prompt still does not appear, quit and reopen Sideby.",
                "macOS가 System Events 권한 요청을 등록하지 않았습니다. 화면 전환 권한 확인을 다시 누르세요. 안내가 계속 뜨지 않으면 Sideby를 종료한 뒤 다시 여세요."
            )
        }
    }

    public func permissionRequestActionTitle(_ action: PermissionRequestAction) -> String {
        switch action {
        case .openAccessibilitySettings:
            accessibilitySettings
        case .openAutomationSettings:
            automationSettings
        }
    }
    public var noMoveTargetsReason: String { text("no move targets", "이동 대상 없음") }
    public var sidebyOffReason: String { text("Sideby is off", "Sideby 꺼짐") }
    public var postEventsOffReason: String { text("Post Events permission off", "이벤트 전송 권한 꺼짐") }
    public var systemEventsFailedReason: String { text("System Events Space command failed", "System Events Space 명령 실패") }
    public func contextBoundaryReason(command: SwitchCommand) -> String {
        switch command {
        case .previous:
            text("No previous Context", "이전 컨텍스트 없음")
        case .next:
            text("No next Context", "다음 컨텍스트 없음")
        }
    }

    public func localizedDiagnosticTitle(_ title: String) -> String {
        switch title {
        case "Accessibility permission is off":
            text("Accessibility permission is off", "손쉬운 사용 권한이 꺼져 있습니다")
        case "Only one Space is available":
            text("Only one Space is available", "사용 가능한 Space가 하나뿐입니다")
        case "Single Display Mode":
            text("Single Display Mode", "단일 디스플레이 모드")
        case "Advanced mode is experimental":
            text("Advanced mode is experimental", "고급 모드는 실험 기능입니다")
        case "No previous Context":
            text("No previous Context", "이전 컨텍스트 없음")
        case "No next Context":
            text("No next Context", "다음 컨텍스트 없음")
        default:
            title
        }
    }

    public func localizedDiagnosticMessage(_ message: String) -> String {
        switch message {
        case "Enable permission to detect swipes while a key is held.":
            text("Enable permission to detect swipes while a key is held.", "보조 키를 누른 상태의 스와이프를 감지하려면 권한을 허용하세요.")
        case "Add another Desktop in Mission Control before switching contexts.":
            text("Add another Desktop in Mission Control before switching contexts.", "컨텍스트를 전환하기 전에 Mission Control에서 데스크탑을 하나 더 추가하세요.")
        case "External display features will activate when another display is connected.":
            text("External display features will activate when another display is connected.", "다른 디스플레이가 연결되면 외부 디스플레이 기능이 활성화됩니다.")
        case "Separate display Spaces may not stay perfectly synchronized on every macOS setup.":
            text("Separate display Spaces may not stay perfectly synchronized on every macOS setup.", "모든 macOS 설정에서 디스플레이별 Space가 완벽하게 동기화되지는 않을 수 있습니다.")
        case "The current Context is already first.":
            text("The current Context is already first.", "현재 컨텍스트가 첫 번째입니다.")
        case "The current Context is already last.":
            text("The current Context is already last.", "현재 컨텍스트가 마지막입니다.")
        default:
            message
        }
    }

    public func localizedActionLabel(_ actionLabel: String?) -> String? {
        switch actionLabel {
        case "Open System Settings":
            openSystemSettings
        case "Add Desktop":
            text("Add Desktop", "데스크탑 추가")
        case "Open Accessibility Settings":
            accessibilitySettings
        case .some(let label):
            label
        case nil:
            nil
        }
    }

    public var onboardingPermissionTitle: String { text("Allow input and switching", "입력 감지와 화면 전환 허용") }
    public var onboardingPermissionSubtitle: String {
        text("Used to detect ⌥⇧ swipes and send the requested Space switch. Keystrokes are never read.", "⌥⇧ 스와이프를 감지하고 요청한 화면 전환을 보내는 데만 사용합니다. 키 입력 내용은 읽지 않습니다.")
    }
    public var permissionAccessibilitySubtitle: String {
        text("Required to observe ⌥⇧-held swipes.", "⌥⇧를 누른 스와이프를 감지하는 데 필요합니다.")
    }
    public var permissionPostEventsSubtitle: String {
        text("Required to send the requested Space switch.", "요청한 화면 전환 명령을 보내는 데 필요합니다.")
    }
    public var permissionSwitchingAccessSubtitle: String {
        text("Required to send the requested Space switch.", "요청한 화면 전환 명령을 보내는 데 필요합니다.")
    }
    public var grantedChip: String { text("Granted", "허용됨") }
    public var notGrantedChip: String { text("Not granted", "허용 안 됨") }
    public var holdOptionShiftAndSwipe: String { text("Hold Option + Shift and swipe", "Option + Shift를 누르고 스와이프") }
    public var keyboardShortcutsLater: String {
        text("Keyboard shortcuts can be turned on later in Input settings.", "키보드 단축키는 나중에 입력 설정에서 켤 수 있습니다.")
    }
    public var hold: String { text("Hold", "누른 채") }
    public var swipeVerb: String { text("Swipe", "스와이프") }
    public func displayCountChip(_ count: Int) -> String { text("\(count) displays", "디스플레이 \(count)개") }
    public var accessibilityOn: String { text("Accessibility on", "손쉬운 사용 켜짐") }
    public var detected: String { text("Detected", "감지됨") }
    public var listening: String { text("Listening…", "감지 중…") }
    public var skipTest: String { text("Skip test", "테스트 건너뛰기") }
    public var onboardingDoneTitle: String { text("You're set.", "준비됐습니다.") }
    public var onboardingDoneBody: String {
        text(
            "Sideby now lives in your menu bar. Click the icon to choose which displays move together.",
            "Sideby가 메뉴바에 표시됩니다. 아이콘을 눌러 함께 이동할 디스플레이를 선택하세요."
        )
    }
    public func stepAccessibilityLabel(current: Int, total: Int) -> String {
        text("Step \(current) of \(total)", "\(total)단계 중 \(current)단계")
    }

    public var gestureModifier: String { text("Gesture Modifier", "제스처 보조 키") }
    public var inputExperiment: String { text("Input Experiment", "입력 실험") }
    public var execution: String { text("Execution", "실행 방식") }
    public var controlSwipe: String { text("Control Swipe", "Control 스와이프") }
    public var defaultGesturePreset: String { text("Option Shift", "Option Shift") }
    public var keyboardShortcuts: String { text("Keyboard Shortcuts", "키보드 단축키") }
    public var keyboardShortcutsOn: String { text("Keyboard shortcuts on", "키보드 단축키 켜짐") }
    public var keyboardShortcutsOff: String { text("Keyboard shortcuts off", "키보드 단축키 꺼짐") }
    public var enableKeyboardShortcuts: String { text("Enable keyboard shortcuts", "키보드 단축키 사용") }
    public var keyboardShortcutsOptionalHint: String {
        text("Optional fallback for users who prefer Left/Right key commands.", "왼쪽/오른쪽 키 명령을 선호하는 사용자를 위한 선택 입력입니다.")
    }
    public var resetDefaults: String { text("Reset Defaults", "기본값 복원") }
    public var pressKeys: String { text("Press keys…", "키를 누르세요…") }
    public var change: String { text("Change", "변경") }
    public var none: String { text("None", "없음") }

    public func modifierText(_ modifiers: ModifierFlags) -> String {
        let caps = KeyboardShortcutFormatter.modifierCaps(modifiers)
        return caps.isEmpty ? none : caps.joined()
    }

    public func modifierChoiceTitle(_ modifier: ModifierFlags) -> String {
        if modifier == .option {
            return text("Option", "Option")
        }
        if modifier == .control {
            return text("Control", "Control")
        }
        if modifier == .command {
            return text("Command", "Command")
        }
        if modifier == .shift {
            return text("Shift", "Shift")
        }
        return modifierText(modifier)
    }

    public func pressNewShortcut(_ title: String) -> String {
        text("Press a new \(title.lowercased()) shortcut.", "새 \(title) 단축키를 누르세요.")
    }

    public func gestureModifierSaved(_ modifiers: String) -> String {
        text("Gesture modifier saved: \(modifiers).", "제스처 보조 키 저장됨: \(modifiers).")
    }

    public func shortcutSaved(role: KeyboardShortcutRole, shortcut: String) -> String {
        text("\(roleTitle(role)) shortcut saved: \(shortcut).", "\(roleTitle(role)) 단축키 저장됨: \(shortcut).")
    }

    public var shortcutSettingsReset: String { text("Shortcut settings reset to defaults.", "단축키 설정을 기본값으로 복원했습니다.") }

    public func inputExperimentSaved(_ strategy: InputExecutionStrategy) -> String {
        text("Input experiment saved: \(strategyTitle(strategy)).", "입력 실험 저장됨: \(strategyTitle(strategy)).")
    }

    public func issueMessage(_ issue: KeyboardShortcutValidationIssue) -> String {
        switch issue {
        case .missingPrimaryModifier(let role):
            text("\(roleTitle(role)) needs Control, Option, or Command.", "\(roleTitle(role))에는 Control, Option, Command 중 하나가 필요합니다.")
        case .duplicatePreviousAndNext:
            text("Previous and Next cannot use the same shortcut.", "이전과 다음은 같은 단축키를 사용할 수 없습니다.")
        case .reservedSystemShortcut(let role):
            text("\(roleTitle(role)) uses a reserved macOS shortcut.", "\(roleTitle(role))에 macOS 예약 단축키가 사용되었습니다.")
        case .emptyGestureModifier:
            text("Choose at least one gesture modifier.", "제스처 보조 키를 하나 이상 선택하세요.")
        }
    }

    public func roleTitle(_ role: KeyboardShortcutRole) -> String {
        switch role {
        case .previous:
            previous
        case .next:
            next
        }
    }

    public func strategyTitle(_ strategy: InputExecutionStrategy) -> String {
        text("Release", "키를 뗄 때")
    }

    public func strategySummary(_ strategy: InputExecutionStrategy) -> String {
        text("Runs after the trigger modifier is released.", "트리거 보조 키를 뗀 뒤 실행합니다.")
    }

    public func setupViewTitle(_ title: String) -> String {
        switch title {
        case "No displays detected":
            text("No displays detected", "감지된 디스플레이 없음")
        case "Permission needed":
            text("Permission needed", "권한 필요")
        case "Ready to turn on":
            text("Ready to turn on", "켤 준비 완료")
        case "Sideby is on":
            text("Sideby is on", "Sideby 켜짐")
        default:
            title.replacingOccurrences(of: "displays detected", with: text("displays detected", "개 디스플레이 감지됨"))
        }
    }

    public func setupViewStatus(_ status: String) -> String {
        switch status {
        case "Connect a display or refresh before setting up Sideby.":
            text("Connect a display or refresh before setting up Sideby.", "Sideby를 설정하기 전에 디스플레이를 연결하거나 새로고침하세요.")
        case "Select at least one display to move.":
            text("Select at least one display to move.", "이동할 디스플레이를 하나 이상 선택하세요.")
        case "Input is used only while Sideby is on. Raw input is not stored.":
            inputPrivacyNote
        case "Turn on Sideby to enable swipe gestures and test buttons.":
            text("Turn on Sideby to enable swipe gestures and test buttons.", "스와이프 제스처와 테스트 버튼을 사용하려면 Sideby를 켜세요.")
        case "Use Option + Shift + horizontal scroll. Keyboard shortcuts can be enabled in Input settings.":
            text("Use Option + Shift + horizontal scroll. Keyboard shortcuts can be enabled in Input settings.", "Option + Shift + 가로 스크롤을 사용하세요. 키보드 단축키는 입력 설정에서 켤 수 있습니다.")
        default:
            status
        }
    }
}
