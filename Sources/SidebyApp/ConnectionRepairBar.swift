import SidebyCore
import SidebyUI
import SwiftUI

/// Pinned above the editor's scroll view; a user click anchors the existing picker here.
struct ConnectionRepairBar: View {
    @ObservedObject var model: SidebyAppModel
    let request: ConnectionEditorRevealRequest
    @Binding var isPickerPresented: Bool
    let dismiss: () -> Void
    @State private var observation: WorkspaceLayoutObservation?
    @State private var refreshing = false
    @State private var refreshTask: Task<Void, Never>?
    private var context: ContextDefinition? { model.settings.contextPlan.contexts.first { $0.id == request.contextID } }
    private func text(_ en: String, _ ko: String) -> String { model.connectionCopy.text(en, ko) }
    private var resolution: ConnectionEditorRevealRequest.Resolution {
        request.resolve(context: context, connectedIDs: Set(model.connectedWorkspaceDisplayIDs),
            readableIDs: Set(request.displayID.map { model.composerKeys($0, observation: observation)?.isEmpty == false ? [$0] : [] } ?? []),
            canEdit: model.canChangeSavedWorkspaces)
    }
    private var message: String {
        switch resolution.kind {
        case .missingContext: text("This connection is no longer available.", "이 연결은 더 이상 없습니다.")
        case .connectionOnly: text("Choose a cell in this connection's column to review its Spaces.", "연결표에서 이 연결의 칸을 골라 Space를 확인하세요.")
        case .offlineDisplay: text("Reconnect this display, or review participation using Displays below.", "모니터를 다시 연결하거나 아래 ‘참여 모니터’에서 선택을 확인하세요.")
        case .unreadableDisplay: text("Couldn't read this display. Check again before choosing a Space.", "모니터를 읽지 못했습니다. 다시 확인한 뒤 Space를 골라 주세요.")
        case .pickableDisplay: model.canChangeSavedWorkspaces
            ? text("Choose a Space to repair this connection. Editing does not move your displays.", "이 연결의 Space를 골라 주세요. 편집만으로 화면이 이동하지는 않습니다.")
            : text("Finish the current operation or open draft before editing.", "진행 중인 작업이나 열어 둔 편집을 마친 뒤 수정하세요.")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let context {
                    Text(context.name).font(.system(size: 13, weight: .semibold)).lineLimit(2).help(context.name)
                    if let id = request.displayID {
                        Text(model.displayName(for: id)).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    }
                }
                Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if resolution.kind == .pickableDisplay {
                Button(text("Choose Space", "Space 선택")) {
                    // Revalidate on the explicit action, not only when the bar first appeared.
                    readObservation()
                    if resolution.canOpenPicker { isPickerPresented = true }
                }.disabled(!resolution.canOpenPicker).pointingHandCursor()
                    .accessibilityIdentifier("connection-repair-choose")
                    .screenBoundedPopover(isPresented: $isPickerPresented, width: 290) {
                        if let context, let id = request.displayID {
                            ConnectionSpacePicker(model: model, context: context, displayID: id) { isPickerPresented = false }
                        }
                    }
            } else if resolution.kind == .unreadableDisplay {
                Button(text("Check again", "다시 확인")) {
                    refreshing = true
                    refreshTask = Task { @MainActor in
                        _ = await model.refreshVisibleConnections(force: true)
                        guard !Task.isCancelled else { return }
                        readObservation(); refreshing = false
                    }
                }.disabled(refreshing || !model.canSaveWorkspace).pointingHandCursor()
                    .accessibilityIdentifier("connection-repair-refresh")
            }
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain).pointingHandCursor().accessibilityLabel(text("Dismiss repair guidance", "복구 안내 닫기"))
                .accessibilityIdentifier("connection-repair-dismiss")
        }
        .padding(12).background(NativeSurfaceStyle.headerBackground, in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain).accessibilityIdentifier("connection-repair-bar")
        .onAppear { readObservation() }
        .onChange(of: model.workspaceLatestObservation) { _, _ in readObservation() }
        .onChange(of: model.displayLayout) { _, _ in readObservation() }
        .onChange(of: resolution) { _, value in if !value.canOpenPicker { isPickerPresented = false } }
        .onDisappear { refreshTask?.cancel() }
    }

    private func readObservation() {
        observation = model.workspaceObservation(includingUnselectedDisplays: true)
    }
}
