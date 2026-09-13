public extension SBSStrings {
    private func workspaceText(_ english: String, _ korean: String) -> String {
        switch language {
        case .english: english
        case .korean: korean
        }
    }

    var workspaces: String { workspaceText("Workspaces", "작업 공간") }
    var workspaceCurrent: String { workspaceText("Current workspace", "현재 작업") }
    var workspaceEdit: String { workspaceText("Edit Workspaces", "작업 구성 편집") }
    var workspaceBackToList: String { workspaceText("Done Editing", "편집 마치기") }
    var workspaceScreenAssignments: String { workspaceText("Screen Assignments", "화면 연결 설정") }
    var workspaceConfirmConnections: String {
        workspaceText("Confirm These Assignments", "현재 연결 확인")
    }
    var workspaceConnectionReviewMessage: String {
        workspaceText(
            "Review which desktop each workspace uses on each display, then confirm the assignments.",
            "각 작업이 디스플레이별로 어느 데스크탑에 연결되어 있는지 검토한 뒤 현재 연결을 확인해 주세요."
        )
    }
    var workspaceConnectionsChanged: String {
        workspaceText("Desktop order has changed. Review the assignments.", "데스크탑 순서가 바뀌었습니다. 화면 연결 설정을 검토해 주세요.")
    }
    var workspaceLayoutUnavailable: String {
        workspaceText("The current desktop arrangement could not be checked.", "현재 데스크탑 구성을 확인하지 못했습니다.")
    }
    var workspaceNotAligned: String {
        workspaceText("The selected displays are not at a verified workspace.", "선택한 화면이 확인된 작업 위치에 있지 않습니다.")
    }
    var workspaceNeedsConfirmation: String {
        workspaceText("Confirm the desktop assignments before switching.", "이동하기 전에 데스크탑 연결을 확인해 주세요.")
    }
    var workspaceRetry: String { workspaceText("Try Again", "다시 맞추기") }
    var workspaceCheckAgain: String { workspaceText("Check Again", "다시 확인") }
    var workspaceStartSetup: String { workspaceText("Set Up Workspaces", "작업 구성 시작") }
    var workspaceEmptyMessage: String {
        workspaceText("Save where each task belongs so you can return to it in one action.", "작업별 화면 위치를 저장하면 한 번에 돌아갈 수 있습니다.")
    }
    var workspaceNoMoveTargets: String {
        workspaceText("No selected, connected displays belong to this workspace.", "이 작업에 포함된 화면 중 연결되어 있고 이동 대상으로 선택된 화면이 없습니다.")
    }
    var workspaceTurnOnToMove: String {
        workspaceText("Turn on Sideby to move between workspaces.", "작업을 이동하려면 Sideby를 켜 주세요.")
    }
    var workspaceWaitForSwitch: String {
        workspaceText("Wait for the current move to finish.", "현재 이동을 마칠 때까지 기다려 주세요.")
    }
    var workspaceWaitForCapture: String {
        workspaceText("Wait for capture to finish, or stop capture in Edit Workspaces.", "캡처가 끝날 때까지 기다리거나 작업 구성 편집에서 캡처를 중지해 주세요.")
    }
    var workspaceMoveUnavailable: String {
        workspaceText("Workspace switching is not available yet.", "아직 작업을 이동할 수 없습니다.")
    }
    var workspaceUnavailableName: String { workspaceText("Workspace", "작업") }

    func workspaceGoTo(_ name: String) -> String {
        workspaceText("Go to \(name)", "‘\(name)’ 작업으로 이동")
    }
    func workspaceMovingTo(_ name: String) -> String {
        workspaceText("Moving to \(name)…", "‘\(name)’ 작업으로 이동 중…")
    }
    func workspaceMovedTo(_ name: String) -> String {
        workspaceText("Moved to \(name)", "\(name)에 도착했습니다")
    }
    func workspaceTransitionFailed(_ name: String) -> String {
        workspaceText("Could not finish moving to \(name).", "‘\(name)’ 작업으로 이동을 마치지 못했습니다.")
    }
    func workspaceKeptOffline(_ name: String) -> String {
        workspaceText("\(name) is disconnected. Its assignments are saved.", "\(name): 연결이 끊겨 있어 설정을 유지합니다.")
    }
    func workspaceDisplayCounts(connected: Int, total: Int, moving: Int) -> String {
        workspaceText(
            "\(connected) of \(total) displays connected · \(moving) selected to move",
            "화면 \(total)개 중 \(connected)개 연결됨 · 선택한 화면 \(moving)개 이동"
        )
    }
    func workspaceDisconnectedDisplays(_ names: String) -> String {
        workspaceText("Disconnected: \(names)", "연결되지 않은 화면: \(names)")
    }
    func workspacePendingDisplay(_ name: String) -> String {
        workspaceText("\(name): not at the destination yet", "\(name): 아직 목적지에 도착하지 않았습니다")
    }
    func workspaceUnavailableDisplay(_ name: String) -> String {
        workspaceText("\(name): current position could not be checked", "\(name): 현재 위치를 확인하지 못했습니다")
    }
    func workspaceInvalidDisplay(_ name: String) -> String {
        workspaceText("\(name): the assigned desktop is unavailable", "\(name): 연결된 데스크탑을 사용할 수 없습니다")
    }
    func workspaceAlignedDisplay(_ name: String) -> String {
        workspaceText("\(name): destination verified", "\(name): 목적지 도착을 확인했습니다")
    }
    func workspaceRetryDisplays(_ names: String) -> String {
        workspaceText("Realign \(names)", "\(names) 다시 맞추기")
    }
    func workspacePrevious(_ name: String) -> String {
        workspaceText("Return to \(name)", "‘\(name)’ 작업으로 돌아가기")
    }

    var workspaceStartGuide: String { workspaceText("Try Your First Round Trip", "첫 작업 왕복해 보기") }
    var workspaceGuideFinished: String { workspaceText("You’re Back at Your Work", "원래 작업으로 돌아왔습니다") }
    var workspaceGuideLater: String { workspaceText("Continue Later", "나중에 계속하기") }
    var workspaceGuideDone: String { workspaceText("Done", "마치기") }
    var workspaceGuideTitle: String { workspaceText("Get Back to Your Work", "내 작업으로 돌아오기") }
    var workspaceGuideNameMessage: String {
        workspaceText("Name two saved workspaces, then move there and back to try them out.", "저장된 작업 두 개에 이름을 붙이고, 서로 오가며 사용해 보세요.")
    }
    var workspaceGuideFirstName: String { workspaceText("First workspace", "첫 번째 작업") }
    var workspaceGuideSecondName: String { workspaceText("Second workspace", "두 번째 작업") }
    var workspaceGuideChooseDisplays: String {
        workspaceText("Choose Displays and Capture", "화면 선택 및 작업 캡처")
    }
    var workspaceGuideNeedsTwo: String {
        workspaceText(
            "You need two saved workspaces to try a round trip. Add a desktop in Mission Control if needed, then choose the displays that should move together and capture their positions.",
            "왕복하려면 저장된 작업이 두 개 필요합니다. 필요하면 Mission Control에서 데스크탑을 추가한 뒤, 함께 움직일 화면을 선택하고 작업 위치를 캡처해 주세요."
        )
    }
    var workspaceOpenMissionControl: String { workspaceText("Open Mission Control", "Mission Control 열기") }
    var workspaceGuideRecoveryFirst: String {
        workspaceText("Finish the move below, then continue the round trip.", "아래에서 이동을 마친 뒤 왕복을 계속해 주세요.")
    }
    func workspaceGuideVisitNext(origin: String, destination: String) -> String {
        workspaceText("\(origin) is verified. Visit \(destination) next.", "‘\(origin)’에 도착한 것을 확인했습니다. 이제 ‘\(destination)’ 작업으로 이동해 보세요.")
    }
    func workspaceGuideReturn(origin: String, destination: String) -> String {
        workspaceText("You reached \(destination). Return to \(origin) to finish.", "‘\(destination)’에 도착했습니다. ‘\(origin)’ 작업으로 돌아오면 왕복이 끝납니다.")
    }
    func workspaceGuideCompleted(origin: String, destination: String) -> String {
        workspaceText("\(origin) → \(destination) → \(origin). Both moves were verified.", "\(origin) → \(destination) → \(origin). 이동과 복귀를 모두 확인했습니다.")
    }
}
