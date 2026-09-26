import Foundation
import AppKit
import UniformTypeIdentifiers
import SidebyCore

enum WorkspaceMatrixDrag: Equatable {
    case desktop(WorkspaceSpaceDragPayload)
    case display(String)
}

struct WorkspaceSpaceDragPayload: Codable, Equatable, Sendable {
    let sourceContextID: String
    let displayID: String
    let spaceIndex: Int
    // Use the same native text transport as display-row drags. An undeclared
    // custom UTI registered with ownProcess never reached SwiftUI's drop target.
    static let typeIdentifier = UTType.plainText.identifier
    private static let prefix = "sideby-workspace-desktop|"

    init(sourceContextID: String, displayID: String, spaceIndex: Int) {
        self.sourceContextID = sourceContextID
        self.displayID = displayID
        self.spaceIndex = spaceIndex
    }

    init?(rawValue: String) {
        guard rawValue.hasPrefix(Self.prefix),
              let data = String(rawValue.dropFirst(Self.prefix.count)).data(using: .utf8),
              let payload = try? JSONDecoder().decode(Self.self, from: data),
              !payload.sourceContextID.isEmpty, !payload.displayID.isEmpty, payload.spaceIndex >= 0
        else { return nil }
        self = payload
    }

    var itemProvider: NSItemProvider {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return NSItemProvider(object: (Self.prefix + String(decoding: data, as: UTF8.self)) as NSString)
    }
}

extension SidebyAppModel {
    func canEditWorkspaceDisplay(_ id: String) -> Bool {
        canAddContext && pendingContextCaptureAlignment == nil && !workspaceIdentityBlockedDisplayIDs.contains(id)
            && displayLayout.displays.contains { $0.id == id }
    }

    func workspaceDesktopChoices(displayID: String) -> [WorkspaceAssignmentChoice] {
        guard displayLayout.displays.contains(where: { $0.id == displayID }) else { return [] }
        if let count = workspaceObservedDisplays?.first(where: { $0.displayID == displayID })?.spaceCount {
            return WorkspaceAssignmentChoices.options(plan: settings.contextPlan, displayID: displayID, observedSpaceCount: count)
        }
        // Reading failed or this display is excluded from switching. Saved assignments remain editable.
        let indices = Set(settings.contextPlan.contexts.compactMap { $0.spaceIndex(for: displayID) }).sorted()
        return indices.map { index in
            let contexts = settings.contextPlan.contexts.filter { $0.spaceIndex(for: displayID) == index }
            return .init(sourceContextID: contexts.first?.id ?? "", spaceIndex: index, name: contexts.map(\.name).joined(separator: ", "))
        }
    }

    @discardableResult
    func assignWorkspaceDesktop(displayID: String, spaceIndex: Int?, toContextID: String) -> Bool {
        let previousLayout = workspaceLastObservedSpaceIDs
        refreshWorkspaceStatus()
        guard previousLayout.isEmpty || previousLayout == workspaceLastObservedSpaceIDs else { return false }
        guard canEditWorkspaceDisplay(displayID),
              spaceIndex == nil || workspaceDesktopChoices(displayID: displayID).contains(where: { $0.spaceIndex == spaceIndex })
        else { return false }
        var changed = false
        updateContextPlan { plan in
            changed = plan.assignDisplaySpace(displayID: displayID, spaceIndex: spaceIndex, toContextID: toContextID)
        }
        if changed {
            applyWorkspaceObservation(workspaceObservation())
            updateAutomaticWorkspaceNames()
        }
        return changed
    }

    @discardableResult
    func dropWorkspaceDesktop(_ payload: WorkspaceSpaceDragPayload, targetDisplayID: String,
                              targetContextID: String, copying: Bool) -> Bool {
        refreshWorkspaceStatus()
        guard payload.displayID == targetDisplayID, payload.sourceContextID != targetContextID,
              canEditWorkspaceDisplay(targetDisplayID),
              settings.contextPlan.contexts.first(where: { $0.id == payload.sourceContextID })?.spaceIndex(for: targetDisplayID) == payload.spaceIndex
        else { return false }
        var changed = false
        updateContextPlan { plan in
            if copying {
                changed = plan.assignDisplaySpace(displayID: targetDisplayID, spaceIndex: payload.spaceIndex, toContextID: targetContextID)
            } else {
                changed = plan.moveDisplaySpace(displayID: targetDisplayID, spaceIndex: payload.spaceIndex,
                                                fromContextID: payload.sourceContextID, toContextID: targetContextID)
            }
        }
        if changed {
            applyWorkspaceObservation(workspaceObservation())
            updateAutomaticWorkspaceNames()
        }
        return changed
    }
}

struct WorkspaceMatrixStrings {
    let language: AppLanguage
    private func text(_ en: String, _ ko: String) -> String { language == .korean ? ko : en }
    var title: String { text("Workspace matrix", "작업 매트릭스") }
    var current: String { text("Current", "현재") }
    var moving: String { text("Switching…", "이동 중…") }
    var help: String { text("Drag to move or swap · Option-drag to share · Rename desktops in the cell menu", "드래그로 이동·맞교환 · ⌥ 드래그로 함께 사용 · 칸 메뉴에서 이름 변경") }
    var displays: String { text("Displays ↓", "화면 ↓") }
    var workspaces: String { text("Workspaces →", "작업 →") }
    var assign: String { text("Choose desktop", "데스크탑 선택") }
    var share: String { text("Also use in…", "다른 작업에도 사용") }
    var move: String { text("Move to…", "다른 작업으로 이동·교환") }
    var clear: String { text("Remove this assignment", "이 작업에서 배정 해제") }
    var shared: String { text("Shared", "함께 사용") }
    var dropMove: String { text("Move here", "여기로 이동") }
    var dropSwap: String { text("Swap desktops", "서로 교환") }
    var dropCopy: String { text("Also use here", "여기서도 사용") }
    var resize: String { text("Drag to resize display names", "드래그하여 화면 이름 너비 조절") }
    var reorder: String { text("Move display before…", "화면 행 앞으로 이동") }
    var back: String { text("Back to workspaces", "작업 선택으로") }
    var moreSettings: String { text("All settings…", "전체 설정…") }
}
