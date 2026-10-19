import AppKit
import SidebyCore
import SidebyUI
import SwiftUI
import UniformTypeIdentifiers

/// Settings, the menu, and the shortcut editor share this live connection table.
struct CurrentConnectionsView: View {
    @ObservedObject var model: SidebyAppModel
    var showsDesktopSources = false
    var isQuickEditor = false
    var availableHeight: CGFloat = 600
    var select: ((String) -> Void)?
    var keepOpen: () -> Void = {}
    var close: (() -> Void)?
    var copyRequested: () -> Bool = { NSEvent.modifierFlags.contains(.option) }
    @State private var sourceOffsets: [String: CGFloat] = [:]
    @State private var observation: WorkspaceLayoutObservation?
    @State private var picker: String?
    @State private var showsDisplays = false
    @State private var showsOffline = false
    @State private var session = UUID()
    @State private var drag: WorkspaceComposerDrag?
    @State private var dropCell: String?
    @State private var dropColumn: String?
    @State private var dropAfter = false
    @State private var addRequest = 0
    @State private var highlightsNewColumn = false
    @State private var dropOperation: DropOperation = .copy
    @State private var selectedDesktop: WorkspaceDesktopReference?
    @State private var deletionProposal: ConnectionRemovalProposal?
    @State private var confirmsClearAll = false
    @State private var isSelectingConnections = false
    @State private var selectedConnectionIDs: Set<String> = []
    @State private var renaming: ContextDefinition?
    private let rowHeight: CGFloat = 72
    private let columnWidth: CGFloat = 178
    private var copy: CurrentConnectionStrings { model.connectionCopy }
    private var contexts: [ContextDefinition] { model.settings.contextPlan.contexts.sorted { $0.order < $1.order } }
    private var displayIDs: [String] {
        WorkspaceTablePresentation.displayIDs(connected: model.connectedWorkspaceDisplayIDs, remembered: [],
            assigned: contexts.flatMap(\.displayIDs), order: model.settings.displayRowOrder, includeDisconnected: showsOffline)
    }
    private var connected: Set<String> { Set(model.connectedWorkspaceDisplayIDs) }
    private var compact: Bool { showsDesktopSources && availableHeight < 580 }
    private var activeDisplayID: String? { drag?.desktop?.displayID ?? selectedDesktop?.displayID }
    private var canUndo: Bool { model.settings.savedWorkspaces.undo != nil }


    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isSelectingConnections ? copy.selectConnections : copy.title).font(.system(size: 17, weight: .semibold))
                    .accessibilityIdentifier("connections-title")
                Spacer()
                if isSelectingConnections {
                    Button(copy.removeSelected(selectedConnectionIDs.count)) {
                        confirmRemoval(.connections(selectedConnectionIDs))
                    }.controlSize(.small).pointingHandCursor()
                        .disabled(selectedConnectionIDs.isEmpty || !model.canChangeSavedWorkspaces)
                        .accessibilityIdentifier("connections-remove-selected")
                    Button(copy.finishSelection) { finishSelectingConnections() }
                        .controlSize(.small).pointingHandCursor()
                        .accessibilityIdentifier("connections-finish-selection")
                } else {
                if !contexts.isEmpty {
                    Button { keepOpen(); highlightsNewColumn = true; addRequest += 1 } label: { Label(copy.add, systemImage: "plus") }
                        .controlSize(.small).pointingHandCursor().help(copy.add).accessibilityLabel(copy.add)
                        .disabled(!model.canChangeSavedWorkspaces).accessibilityIdentifier("connections-add")
                }
                    Button(copy.clearAll) {
                        confirmRemoval(.all)
                    }.controlSize(.small).pointingHandCursor()
                        .disabled(!model.canDeleteAllSavedWorkspaces)
                        .accessibilityIdentifier("connections-clear-all")
                Button(copy.displays) { keepOpen(); showsDisplays = true }.pointingHandCursor()
                    .accessibilityIdentifier("connections-displays")
                    .popover(isPresented: $showsDisplays) {
                        ScrollView {
                            NativeDisplaySelector(displays: model.displayLayout.displays, selectedIDs: model.selectedDisplayIDs,
                                language: model.settings.language, isEnabled: model.canChangeSavedWorkspaces,
                                setSelected: { model.setDisplayTarget($0, isSelected: $1); readObservation() })
                        }.frame(width: 340, height: min(260, max(100, CGFloat(model.displayLayout.displays.count) * 34 + 100))).padding(16)
                    }
                }
                if let close {
                    Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).pointingHandCursor()
                        .accessibilityLabel(model.saveCopy.close)
                }
            }
            if isSelectingConnections {
                Text(copy.selectionHint).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            } else if !compact {
                Text(showsDesktopSources
                    ? copy.text("Place a Space in a cell for the same display. Use Go together to switch.", "Space를 같은 모니터의 칸에 놓으세요. 화면 이동은 ‘함께 이동’을 누르세요.") : copy.hint)
                    .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            }
            if showsDesktopSources && !isSelectingConnections { desktopSources }
            if !connected.isEmpty && (observation == nil || connected.contains(where: { keys($0) == nil })) {
                HStack {
                    Text(copy.readUnavailable).foregroundStyle(.orange)
                    Button(copy.readAgain) { refresh() }.pointingHandCursor()
                        .disabled(!model.canSaveWorkspace).accessibilityIdentifier("connections-retry")
                }.font(.system(size: 12))
            }
            if model.settingsStore.hasUnreadableSettings {
                Text(model.saveCopy.settingsUnreadable).font(.system(size: 12)).foregroundStyle(.orange)
            } else if contexts.isEmpty && displayIDs.isEmpty {
                empty
            } else {
                table
            }
            if !contexts.isEmpty, Set(contexts.flatMap(\.displayIDs)).subtracting(connected).isEmpty == false {
                Toggle(copy.text("Show disconnected displays", "연결 해제된 모니터 보기"), isOn: $showsOffline)
                    .toggleStyle(.checkbox).font(.system(size: 11)).pointingHandCursor()
            }
            if model.hasWorkspaceComposerChanges {
                HStack {
                    Text(copy.text("Finish your open draft before changing connections here.", "열어 둔 편집을 먼저 저장하거나 취소한 뒤 연결을 바꿔 주세요."))
                    Button(copy.text("Continue draft", "기존 편집 계속")) {
                        if let id = model.workspaceComposerDraft?.state.entries.first?.id { model.openWorkspaceEditor?(id) }
                    }.pointingHandCursor().accessibilityIdentifier("workspace-resume-editing")
                }.font(.system(size: 11)).accessibilityElement(children: .contain).accessibilityIdentifier("workspace-unsaved-edit-notice")
            }
            if !isQuickEditor, let message = model.workspaceSaveMessage { feedback(message) }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if (isQuickEditor || !contexts.isEmpty) && !isSelectingConnections {
                        Text(copy.dragHint).font(.system(size: 11))
                            .accessibilityIdentifier("connections-drag-hint")
                    }
                    if !isQuickEditor {
                        Text(copy.scope).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                            .accessibilityIdentifier("connections-scope")
                    }
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !isQuickEditor && model.workspaceSaveMessage == nil { undoButton }
            }
            if isQuickEditor { quickEditorStatus }

        }
        .foregroundStyle(NativeSurfaceStyle.primaryText).tint(NativeSurfaceStyle.accent)
        .background(CurrentConnectionsKeyboardCommands(model: model))
        .background(CurrentConnectionsLiveRefresh(model: model,
            paused: drag != nil || selectedDesktop != nil || picker != nil || showsDisplays || confirmsClearAll || isSelectingConnections || renaming != nil,
            didRefresh: { readObservation() }))
        .background(WorkspaceDragCompletion(dragID: drag?.id) { drag = nil; dropCell = nil; dropColumn = nil })
        .onAppear { model.refreshWorkspaceStatus(); readObservation() }
        .alert(removalTitle, isPresented: $confirmsClearAll) {
            Button(model.saveCopy.cancel, role: .cancel) { deletionProposal = nil }
            Button(isSelectedRemoval ? copy.removeSelectedAction : copy.clearAllAction, role: .destructive) {
                if let proposal = deletionProposal {
                    if model.removeConnections(proposal), case .connections = proposal.scope { finishSelectingConnections() }
                }
                deletionProposal = nil; selectedDesktop = nil; picker = nil; readObservation()
            }.accessibilityIdentifier("connections-confirm-clear-all")
        } message: { Text(removalMessage) }
        .task(id: addRequest) {
            guard addRequest > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { highlightsNewColumn = false }
        }
        .onReceive(model.$workspaceObservedDisplays) { _ in readObservation() }
        .onChange(of: model.displayLayout) { _, _ in readObservation(); picker = nil; drag = nil; selectedDesktop = nil }
        .onChange(of: model.settings.contextPlan.contexts) { _, _ in
            readObservation()
            selectedConnectionIDs.formIntersection(contexts.map(\.id))
            if let renaming, !contexts.contains(where: { $0.id == renaming.id }) { self.renaming = nil }
            if contexts.isEmpty { finishSelectingConnections() }
        }
        .onChange(of: model.isSwitching) { _, busy in if !busy { readObservation() } }
        .onExitCommand {
            if renaming != nil { renaming = nil; return }
            if isSelectingConnections && !confirmsClearAll { finishSelectingConnections(); return }
            if picker == nil && drag == nil && selectedDesktop == nil && !showsDisplays && !confirmsClearAll { close?() }
            picker = nil; drag = nil; dropCell = nil; selectedDesktop = nil; showsDisplays = false
        }
    }

    private func startSelectingConnections() {
        keepOpen(); selectedDesktop = nil; picker = nil; drag = nil; dropCell = nil
        renaming = nil
        selectedConnectionIDs.removeAll(); isSelectingConnections = true
    }

    private func finishSelectingConnections() {
        isSelectingConnections = false; selectedConnectionIDs.removeAll()
    }

    private func toggleConnectionSelection(_ id: String) {
        keepOpen()
        if !selectedConnectionIDs.insert(id).inserted { selectedConnectionIDs.remove(id) }
    }

    private var isSelectedRemoval: Bool {
        if case .connections = deletionProposal?.scope { return true }
        return false
    }

    private var removalMessage: String {
        let detail = copy.removalMessage(deletionProposal?.scope ?? .all)
        guard let proposal = deletionProposal, case .connections(let ids) = proposal.scope else { return detail }
        let names = proposal.snapshot.contexts.filter { ids.contains($0.id) }.map(\.name)
        let more = names.count > 5 ? copy.text(" and \(names.count - 5) more", " 외 \(names.count - 5)개") : ""
        return names.prefix(5).joined(separator: ", ") + more + "\n\n" + detail
    }

    private var removalTitle: String {
        guard let proposal = deletionProposal else { return copy.clearAll }
        let name: String
        if case .display(let id) = proposal.scope { name = model.displayName(for: id) } else { name = "" }
        return copy.removalTitle(proposal, displayName: name)
    }

    private func confirmRemoval(_ scope: ConnectionRemovalScope) {
        guard let proposal = model.prepareConnectionRemoval(scope) else { return }
        keepOpen(); selectedDesktop = nil; picker = nil
        if case .connections(let ids) = scope, ids.count == 1 {
            if model.removeConnections(proposal) { finishSelectingConnections() }
            readObservation()
            return
        }
        deletionProposal = proposal; confirmsClearAll = true
    }

    private var undoButton: some View {
        Button { keepOpen(); _ = model.undoSavedWorkspaceChange(); readObservation() } label: {
            Label(copy.text("Undo", "되돌리기"), systemImage: "arrow.uturn.backward")
        }.font(.system(size: 12)).pointingHandCursor()
            .disabled(!model.canChangeSavedWorkspaces || !canUndo)
            .help((model.settings.savedWorkspaces.undo?.label ?? copy.undo) + " (⌘Z)\n" + copy.undoHistoryHint)
            .accessibilityLabel(copy.undo).accessibilityIdentifier("connections-undo")
    }

    // The quick editor fits its window to the content. Reuse its scope notice
    // for edit results so the first assignment, clear, undo, and dismiss do not
    // insert/remove a row underneath a pointer or drag. Long errors may grow.
    private var quickEditorStatus: some View {
        VStack(spacing: 0) {
            if let message = model.workspaceSaveMessage {
                feedback(message, minimumTextHeight: 32)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(copy.scope).font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .accessibilityIdentifier("connections-scope")
                    undoButton
                }.foregroundStyle(NativeSurfaceStyle.secondaryText).padding(9)
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("connections-status")
    }

    private func feedback(_ message: String, minimumTextHeight: CGFloat = 0) -> some View {
        let failed = model.workspaceSaveFeedbackKind == .failure
        let success = model.workspaceSaveFeedbackKind == .success
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: failed ? "exclamationmark.triangle.fill" : success ? "checkmark.circle.fill" : "info.circle")
                .foregroundStyle(failed ? Color.orange : NativeSurfaceStyle.accent)
            VStack(alignment: .leading, spacing: 2) {
                if failed { Text(copy.notApplied).fontWeight(.semibold) }
                Text(message).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: minimumTextHeight, alignment: .leading)
            undoButton
            Button { model.workspaceSaveMessage = nil } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                .buttonStyle(.plain).pointingHandCursor().accessibilityLabel(model.saveCopy.close)
                .accessibilityIdentifier("connections-dismiss-feedback")
        }.padding(9)
            .background(failed ? Color.orange.opacity(0.10) : NativeSurfaceStyle.selectionBackground,
                        in: RoundedRectangle(cornerRadius: 7))
            .id("connections-feedback")
            .accessibilityElement(children: .contain).accessibilityIdentifier("connections-feedback")
    }

    @ViewBuilder private func displayBadge(_ id: String) -> some View {
        if !connected.contains(id) || !model.selectedDisplayIDs.contains(id) {
            Label(!connected.contains(id) ? copy.text("Disconnected", "연결 해제") : copy.text("Not switching", "전환 제외"),
                  systemImage: !connected.contains(id) ? "cable.connector.slash" : "pause.circle")
                .font(.system(size: 11, weight: .medium)).lineLimit(2)
                .padding(.horizontal, 5).padding(.vertical, 3)
                .background(NativeSurfaceStyle.windowBackground, in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private var desktopSources: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(copy.text("Spaces on your displays", "모니터별 Space")).font(.system(size: 13, weight: .semibold))
                if activeDisplayID == nil, model.connectedWorkspaceDisplayIDs.count > (compact ? 1 : 2) {
                    Text(copy.text("\(model.connectedWorkspaceDisplayIDs.count) displays · scroll for more", "모니터 \(model.connectedWorkspaceDisplayIDs.count)개 · 스크롤로 더 보기"))
                        .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                }
                Spacer()
                if let id = activeDisplayID {
                    Text(copy.text("Place in the \(model.displayName(for: id)) row", "\(model.displayName(for: id)) 행에 놓기"))
                        .font(.system(size: 11, weight: .medium)).lineLimit(1).help(model.displayName(for: id))
                        .accessibilityIdentifier("connection-active-display")
                }
                if selectedDesktop != nil {
                    Button(copy.text("Cancel selection", "선택 취소")) { selectedDesktop = nil }
                        .buttonStyle(.plain).pointingHandCursor().font(.system(size: 11))
                }
            }
            ScrollView(.vertical) {
                VStack(spacing: 4) {
                    ForEach(model.connectedWorkspaceDisplayIDs, id: \.self) { id in
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName(for: id)).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                if let count = keys(id)?.count {
                                    Text(copy.text("\(count) Spaces", "Space \(count)개"))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(NativeSurfaceStyle.accent)
                                        .accessibilityIdentifier("connection-space-count-" + id)
                                }
                                displayBadge(id)
                            }.padding(.horizontal, 10).frame(width: 132, height: 76, alignment: .leading)
                                .background(activeDisplayID == id ? NativeSurfaceStyle.selectionBackground : .clear)
                            if let keys = keys(id) {
                                GeometryReader { viewport in
                                    ScrollViewReader { scroll in
                                        ScrollView(.horizontal) {
                                            HStack(spacing: 6) {
                                                ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                                                    desktopSource(displayID: id, key: key, index: index).id(key)
                                                }
                                            }.padding(.vertical, 3)
                                                .background(GeometryReader { content in
                                                    Color.clear.preference(key: ConnectionSourceOffset.self,
                                                        value: [id: content.frame(in: .named("sources-" + id)).minX])
                                                })
                                        }.coordinateSpace(name: "sources-" + id).scrollIndicators(.visible)
                                            .onPreferenceChange(ConnectionSourceOffset.self) { values in
                                                if let offset = values[id] { sourceOffsets[id] = offset }
                                            }
                                            .overlay(alignment: .trailing) {
                                                let total = CGFloat(keys.count) * 180 - 6
                                                if total + (sourceOffsets[id] ?? 0) > viewport.size.width + 2,
                                                   !keys.isEmpty {
                                                    Button {
                                                        let first = max(0, Int(-(sourceOffsets[id] ?? 0) / 180))
                                                        let next = min(keys.count - 1, first + max(1, Int(viewport.size.width / 180)))
                                                        withAnimation { scroll.scrollTo(keys[next], anchor: .leading) }
                                                    } label: {
                                                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                                            .frame(width: 26, height: 48)
                                                            .background(NativeSurfaceStyle.controlBackground, in: Capsule())
                                                            .overlay(Capsule().strokeBorder(NativeSurfaceStyle.itemBorder))
                                                    }.buttonStyle(.plain).pointingHandCursor()
                                                        .help(copy.text("More Spaces to the right", "오른쪽에 Space 더 보기"))
                                                        .accessibilityLabel(copy.text("More Spaces to the right", "오른쪽에 Space 더 보기"))
                                                        .accessibilityIdentifier("connection-more-spaces-" + id)
                                                        .padding(.trailing, 4)
                                                }
                                            }
                                    }
                                }
                            } else {
                                Text(copy.readUnavailable).font(.system(size: 11)).foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.frame(height: 76)
                    }
                }
            }.frame(height: CGFloat(min(max(1, model.connectedWorkspaceDisplayIDs.count), compact ? 1 : 2)) * 80)
                .background(NativeSurfaceStyle.headerBackground, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityIdentifier("connection-desktop-sources")
        }
    }

    private func desktopSource(displayID: String, key: String, index: Int) -> some View {
        let desktop = WorkspaceDesktopReference(displayID: displayID, key: key)
        let title = model.workspaceDesktopName(displayID: displayID, spaceIndex: index) ?? copy.spacePosition(index)
        let current = observation?.displays.first(where: { $0.displayID == displayID })?.currentSpaceIndex == index
        let selected = selectedDesktop == desktop
        return WorkspaceDesktopDragSource(enabled: model.canChangeSavedWorkspaces,
            label: model.displayName(for: displayID) + " · " + copy.spacePosition(index) + " · " + title
                + (current ? copy.text(" · On screen", " · 지금 보고 있음") : ""),
            identifier: "connection-source-" + displayID + "-\(index)",
            accessibilityState: selected ? copy.text("Selected. Click a cell for this display.", "선택됨. 같은 모니터의 칸을 누르세요.") : nil,
            click: { keepOpen(); selectedDesktop = selected ? nil : desktop; picker = nil }, beginDrag: {
                keepOpen()
                selectedDesktop = desktop
                let payload = WorkspaceComposerDrag(session: session, desktop: desktop)
                drag = payload
                return payload.rawValue
            }, endDrag: { drag = nil; dropCell = nil }) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in Circle().fill(NativeSurfaceStyle.secondaryText.opacity(0.45)).frame(width: 4, height: 4) }
                        Spacer()
                        Text(copy.spacePosition(index)).font(.system(size: 9)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    }.padding(.horizontal, 7).frame(height: 17)
                        .background(NativeSurfaceStyle.headerBackground)
                    HStack(alignment: .top, spacing: 4) {
                        Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(NativeSurfaceStyle.accent) }
                    }.padding(.horizontal, 7).padding(.top, 5).padding(.bottom, 3)
                    HStack(spacing: 5) {
                        if current { Text(copy.text("On screen", "현재")).fontWeight(.medium).foregroundStyle(NativeSurfaceStyle.accent) }
                    }.font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText).padding(.horizontal, 7)
                    Spacer(minLength: 2)
                }.frame(width: 174, height: 70, alignment: .leading)
                    .background(selected ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.inputBackground,
                                in: RoundedRectangle(cornerRadius: 7))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.accentColor : NativeSurfaceStyle.itemBorder, lineWidth: selected ? 2 : 1))
            }.frame(width: 174, height: 70).help(title)
    }

    private var empty: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(displayIDs.isEmpty ? copy.text("Connect a display to begin.", "모니터를 연결하면 시작할 수 있어요.")
                : showsDesktopSources ? copy.emptyDragHint : copy.emptyDirectHint)
                .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            startByOrderButton
        }
    }

    private var startByOrderButton: some View {
        Button(copy.text("Pair by order", "순서대로 연결")) { keepOpen(); _ = model.connectCurrentDesktopOrder(); readObservation() }
            .controlSize(.small).pointingHandCursor().help(copy.emptyDetail)
            .disabled(!model.canChangeSavedWorkspaces || model.selectedDisplayIDs.isEmpty || observation == nil)
            .accessibilityLabel(copy.start)
            .accessibilityIdentifier("connections-start")
    }

    private var table: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(copy.text("Connections →", "Space 연결 →")).font(.system(size: 11, weight: .medium))
                        if isSelectingConnections {
                            Toggle(copy.selectAll, isOn: Binding(get: {
                                !contexts.isEmpty && selectedConnectionIDs == Set(contexts.map(\.id))
                            }, set: { selectedConnectionIDs = $0 ? Set(contexts.map(\.id)) : []; keepOpen() }))
                                .toggleStyle(.checkbox).font(.system(size: 11)).pointingHandCursor()
                                .disabled(!model.canChangeSavedWorkspaces)
                                .accessibilityIdentifier("connections-select-all")
                        } else if !contexts.isEmpty {
                            Button(copy.selectConnections) { startSelectingConnections() }
                                .controlSize(.small).font(.system(size: 11)).pointingHandCursor()
                                .disabled(!model.canChangeSavedWorkspaces)
                                .accessibilityIdentifier("connections-select")
                        } else {
                            // Keep the first-drop target and Space sources in place.
                            // Starting by order shares the existing table header instead
                            // of adding a row that disappears after the first connection.
                            startByOrderButton.font(.system(size: 11))
                        }
                    }.frame(height: 64).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(displayIDs, id: \.self) { id in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 2) {
                                Text(model.displayName(for: id)).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                Spacer(minLength: 0)
                                if !isSelectingConnections { Menu { displayActions(id) } label: {
                                    Image(systemName: "ellipsis").frame(width: 20, height: 20)
                                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                    .accessibilityLabel(model.displayName(for: id) + " · " + copy.text("Connection actions", "연결 관리"))
                                    .accessibilityIdentifier("connection-display-actions-" + id)
                                }
                            }
                            displayBadge(id)
                            if activeDisplayID == id {
                                Label(copy.text("Place here", "이 행에 놓기"), systemImage: "arrow.right")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(NativeSurfaceStyle.accent)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: rowHeight)
                            .background(activeDisplayID == id ? NativeSurfaceStyle.selectionBackground : .clear)
                            .help(model.displayName(for: id))
                            .contextMenu { if !isSelectingConnections { displayActions(id) } }
                    }
                }.padding(.horizontal, 10).frame(width: 132).background(NativeSurfaceStyle.headerBackground)
                ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(contexts.enumerated()), id: \.element.id) { index, context in
                            VStack(spacing: 0) {
                                header(context, position: index + 1)
                                ForEach(displayIDs, id: \.self) { id in cell(context, displayID: id) }
                            }.frame(width: columnWidth)
                                .overlay {
                                    if isSelectingConnections && selectedConnectionIDs.contains(context.id) {
                                        RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: 2)
                                            .allowsHitTesting(false)
                                    }
                                }.id(context.id)
                        }
                        if !isSelectingConnections {
                        VStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(copy.add).font(.system(size: 12, weight: .medium))
                                Text(showsDesktopSources ? copy.createByDropping : copy.text("Choose a Space to create", "Space를 고르면 새 연결이 생겨요")).font(.system(size: 11))
                                    .foregroundStyle(NativeSurfaceStyle.secondaryText).fixedSize(horizontal: false, vertical: true)
                            }.padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading).frame(height: 64)
                                .accessibilityElement(children: .combine).accessibilityIdentifier("connection-new-hint")
                            ForEach(displayIDs, id: \.self) { id in cell(nil, displayID: id) }
                        }.frame(width: columnWidth)
                            .background(highlightsNewColumn ? NativeSurfaceStyle.selectionBackground : .clear).id("new")
                        }
                    }
                }.frame(height: 64 + CGFloat(displayIDs.count) * rowHeight)
                    .onChange(of: addRequest) { _, _ in scroll.scrollTo("new", anchor: .trailing) }
                    .onChange(of: contexts.map(\.id)) { old, ids in
                        if !isSelectingConnections, ids.count > old.count, let last = ids.last { scroll.scrollTo(last, anchor: .trailing) }
                    }
                }
            }
        }
        .frame(height: min(showsDesktopSources ? (compact ? 64 + rowHeight * 2 + 12 : 310) : 340,
                           64 + CGFloat(max(1, displayIDs.count)) * rowHeight + 12))
        .scrollIndicators(.visible)
        .background(NativeSurfaceStyle.tableBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(NativeSurfaceStyle.frameBorder))
        .accessibilityIdentifier("current-connections-table")
    }

    private func displayActions(_ id: String) -> some View {
        Button(copy.clearDisplay, role: .destructive) { confirmRemoval(.display(id)) }
            .disabled(!model.canChangeSavedWorkspaces || !contexts.contains { $0.displayIDs.contains(id) })
            .accessibilityIdentifier("connection-clear-display-" + id)
    }

    @ViewBuilder private func header(_ context: ContextDefinition, position: Int) -> some View {
        if isSelectingConnections {
            Toggle(isOn: Binding(get: { selectedConnectionIDs.contains(context.id) }, set: { selected in
                keepOpen()
                if selected { selectedConnectionIDs.insert(context.id) } else { selectedConnectionIDs.remove(context.id) }
            })) {
                Text(context.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.checkbox).pointingHandCursor().padding(.horizontal, 9).frame(height: 64)
                .disabled(!model.canChangeSavedWorkspaces)
                .background(selectedConnectionIDs.contains(context.id) ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.headerBackground)
                .help(context.name).accessibilityIdentifier("connection-select-" + context.id)
        } else {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                WorkspaceDesktopDragSource(enabled: model.canChangeSavedWorkspaces,
                    label: context.name + " · " + copy.rename,
                    identifier: "connection-rename-" + context.id, allowsMove: true,
                    click: { beginRenaming(context) }, beginDrag: {
                        keepOpen(); renaming = nil; picker = nil; selectedDesktop = nil
                        let payload = WorkspaceComposerDrag(session: session, contextID: context.id)
                        drag = payload
                        return payload.rawValue
                    }, endDrag: { drag = nil; dropColumn = nil }) {
                    HStack(spacing: 3) {
                        Text(context.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    }
                }.frame(minHeight: 30)
                    .help(context.name + " · " + copy.text("Click to rename · Drag to reorder", "클릭해 이름 수정 · 끌어서 순서 변경"))
                    .accessibilityLabel(context.name + " · " + copy.rename)
                    .accessibilityIdentifier("connection-rename-" + context.id)
                    .popover(isPresented: Binding(get: { renaming?.id == context.id }, set: { if !$0 { renaming = nil } })) {
                        if let target = renaming {
                            ConnectionNameEditor(model: model, target: target, close: { renaming = nil })
                        }
                    }
                Spacer(minLength: 0)
                Menu { connectionActions(context, position: position) } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 20)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(copy.text("Connection actions", "연결 관리"))
                    .accessibilityLabel(context.name + " · " + copy.text("Connection actions", "연결 관리"))
                    .accessibilityIdentifier("connection-actions-" + context.id)
            }
            HStack(spacing: 4) {
                if model.verifiedCurrentWorkspaceID == context.id {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                        .foregroundStyle(NativeSurfaceStyle.accent)
                        .help(copy.text("Current", "현재"))
                        .accessibilityLabel(copy.text("Current", "현재"))
                }
                Text(model.workspaceShortcut(context.id) ?? copy.connection(position))
                    .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                Button {
                    if let select { select(context.id) } else { model.activateContext(contextID: context.id) }
                } label: { Label(copy.moveTogether, systemImage: "arrow.right.circle").font(.system(size: 11)) }
                    .controlSize(.small).fixedSize().pointingHandCursor()
                    .disabled(!model.canActivateContext || !model.isWorkspaceAssignmentAvailable(contextID: context.id))
                    .help(copy.move).accessibilityLabel(context.name + " · " + copy.moveTogether)
                    .accessibilityIdentifier("connection-go-" + context.id)
            }
        }.padding(.horizontal, 9).frame(height: 64)
            .background(model.verifiedCurrentWorkspaceID == context.id ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.headerBackground)
            .contextMenu { connectionActions(context, position: position) }
            .overlay(alignment: dropAfter ? .trailing : .leading) {
                if dropColumn == context.id { Rectangle().fill(Color.accentColor).frame(width: 3).allowsHitTesting(false) }
            }
            .onDrop(of: [UTType.plainText], delegate: WorkspaceComposerDropDelegate(session: session, active: drag,
                contextID: context.id, displayID: nil,
                enabled: model.canChangeSavedWorkspaces && drag?.contextID != nil && !isSelectingConnections,
                midpoint: columnWidth / 2,
                hover: { inside, after in dropColumn = inside ? context.id : nil; dropAfter = after },
                receive: { payload, after, _ in
                    if let id = payload.contextID { _ = model.reorderSavedWorkspace(id, relativeTo: context.id, after: after) }
                    drag = nil; dropColumn = nil
                }))
        }
    }

    @ViewBuilder private func connectionActions(_ context: ContextDefinition, position: Int) -> some View {
        Button(copy.rename) { beginRenaming(context) }.disabled(!model.canChangeSavedWorkspaces)
        Divider()
        Button(copy.text("Move left", "왼쪽으로 이동")) {
            keepOpen()
            if position > 1 { _ = model.reorderSavedWorkspace(context.id, relativeTo: contexts[position - 2].id, after: false) }
        }.disabled(position == 1 || !model.canChangeSavedWorkspaces)
        Button(copy.text("Move right", "오른쪽으로 이동")) {
            keepOpen()
            if position < contexts.count { _ = model.reorderSavedWorkspace(context.id, relativeTo: contexts[position].id, after: true) }
        }.disabled(position == contexts.count || !model.canChangeSavedWorkspaces)
        Divider()
        Button(copy.text("Remove connection · Keep Spaces", "연결 삭제 · Space는 유지"), role: .destructive) {
            keepOpen(); _ = model.deleteSavedWorkspace(context.id)
        }.disabled(!model.canChangeSavedWorkspaces)
    }

    private func beginRenaming(_ context: ContextDefinition) {
        keepOpen(); selectedDesktop = nil; picker = nil; drag = nil; dropCell = nil
        renaming = context
    }

    private func cell(_ context: ContextDefinition?, displayID: String) -> some View {
        let cellID = (context?.id ?? "new") + "-" + displayID
        let key = context.flatMap { model.settings.savedWorkspaces.bookmarks[$0.id]?[displayID] }
        let index = key.flatMap { keys(displayID)?.firstIndex(of: $0) } ?? (key == nil ? context?.spaceIndex(for: displayID) : nil)
        let assigned = context?.spaceIndex(for: displayID) != nil
        let missing = assigned && connected.contains(displayID) && keys(displayID) != nil && (key == nil || index == nil)
        let unreadable = assigned && connected.contains(displayID) && keys(displayID) == nil
        let title = assigned && !connected.contains(displayID) ? copy.offline : unreadable ? copy.text("Couldn't read · Retry", "읽기 실패 · 다시 확인") : missing ? copy.repair : index.map { model.workspaceDesktopName(displayID: displayID, spaceIndex: $0) ?? copy.spacePosition($0) }
            ?? (isSelectingConnections ? copy.keep : showsDesktopSources ? copy.dropHere : copy.choose)
        let enabled = model.canChangeSavedWorkspaces && (isSelectingConnections || connected.contains(displayID) || assigned)
        let hovering = dropCell == cellID
        let preview = dropPreview(context, assigned: assigned)
        let isSelected = context.map { selectedConnectionIDs.contains($0.id) } ?? false
        return WorkspaceDesktopDragSource(enabled: enabled, label: (isSelectingConnections ? (context?.name ?? "") + " · " : "") + model.displayName(for: displayID) + " · " + title,
            identifier: "connection-cell-" + cellID,
            isDraggable: !isSelectingConnections && connected.contains(displayID) && assigned && !missing && !unreadable && key != nil,
            accessibilityState: isSelectingConnections ? copy.selectedState(isSelected) : hovering ? preview : assigned ? copy.text("Connected", "연결됨") : copy.text("Empty. Click to connect a Space.", "빈 칸. 눌러서 Space를 연결하세요."),
            allowsMove: true,
            click: {
                keepOpen()
                if isSelectingConnections {
                    if let context { toggleConnectionSelection(context.id) }
                    return
                }
                if let selectedDesktop {
                    guard selectedDesktop.displayID == displayID else { return }
                    if model.setCurrentConnection(displayID: displayID, key: selectedDesktop.key, contextID: context?.id) {
                        self.selectedDesktop = nil
                    }
                    readObservation()
                } else { picker = cellID }
            }, beginDrag: {
                guard let key, !missing, keys(displayID)?.contains(key) == true else { return "" }
                keepOpen()
                selectedDesktop = nil
                let payload = WorkspaceComposerDrag(session: session, desktop: .init(displayID: displayID, key: key),
                    sourceContextID: context?.id)
                drag = payload
                return payload.rawValue
            }, endDrag: { drag = nil; dropCell = nil }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if assigned && !missing && !unreadable && !isSelectingConnections {
                            Image(systemName: "link").font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.accent)
                        }
                        if !assigned && !isSelectingConnections { Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(NativeSurfaceStyle.secondaryText) }
                        Text(title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        Spacer(minLength: 0)
                        if assigned && !isSelectingConnections { Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(NativeSurfaceStyle.secondaryText) }
                    }
                    if hovering {
                        Text(preview).font(.system(size: 11, weight: .medium)).foregroundStyle(NativeSurfaceStyle.accent)
                    } else if let index, title != copy.spacePosition(index) {
                        Text(copy.spacePosition(index)).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    } else if !assigned && !isSelectingConnections {
                        Text(showsDesktopSources ? copy.orChoose : copy.text("Click to connect", "눌러서 연결하기"))
                            .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    }
                }.padding(9).frame(maxWidth: .infinity, alignment: .leading).frame(height: rowHeight - 8)
                    .background(hovering || (isSelectingConnections && isSelected) ? NativeSurfaceStyle.selectionBackground : assigned ? NativeSurfaceStyle.selectionBackground.opacity(0.65) : NativeSurfaceStyle.windowBackground,
                                in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(missing || unreadable ? Color.orange : hovering || selectedDesktop?.displayID == displayID ? Color.accentColor : NativeSurfaceStyle.itemBorder,
                        style: StrokeStyle(lineWidth: hovering ? 2 : 1, dash: assigned ? [] : [4, 4])))
            }
            .padding(.horizontal, 5).frame(height: rowHeight).help(title)
            .screenBoundedPopover(isPresented: Binding(get: { picker == cellID }, set: { if !$0 { picker = nil } }), width: 290) {
                ConnectionSpacePicker(model: model, context: context, displayID: displayID) {
                    picker = nil; readObservation()
                }
            }
            .onDrop(of: [UTType.plainText], delegate: WorkspaceComposerDropDelegate(session: session, active: drag,
                contextID: context?.id ?? "new", displayID: displayID, enabled: enabled && !isSelectingConnections && connected.contains(displayID), midpoint: columnWidth / 2,
                desktopOperation: {
                    let operation: DropOperation = drag?.sourceContextID != nil && !copyRequested() ? .move : .copy
                    if dropOperation != operation { dropOperation = operation }
                    return operation
                },
                hover: { inside, _ in
                    if inside { dropCell = cellID }
                    else if dropCell == cellID { dropCell = nil }
                }, receive: { payload, _, operation in
                    if let source = payload.desktop, source.displayID == displayID {
                        if let sourceID = payload.sourceContextID {
                            _ = model.transferCurrentConnection(source, from: sourceID, to: context?.id,
                                expectedDestinationKey: key, copying: operation == .copy)
                        } else {
                            _ = model.setCurrentConnection(displayID: displayID, key: source.key, contextID: context?.id)
                        }
                    }
                    drag = nil; dropCell = nil; selectedDesktop = nil; readObservation()
                }))
    }

    private func dropPreview(_ context: ContextDefinition?, assigned: Bool) -> String {
        guard let sourceID = drag?.sourceContextID else {
            return copy.text("Release to connect", "놓으면 연결")
        }
        if sourceID == context?.id { return copy.text("Already connected here", "이미 연결된 칸") }
        if dropOperation == .copy { return copy.text("Release to copy · Keep source", "놓으면 복사 · 원래 칸 유지") }
        return assigned ? copy.text("Release to swap", "놓으면 자리 바꾸기") : copy.text("Release to move", "놓으면 이동")
    }

    private func keys(_ id: String) -> [String]? { model.composerKeys(id, observation: observation) }
    private func readObservation() { observation = model.workspaceObservation(includingUnselectedDisplays: true) }
    private func refresh() {
        Task { await model.refreshVisibleConnections(force: true); readObservation() }
    }
}

/// Shared picker for normal editing and repairing an unavailable quick-switch cell.
struct ConnectionSpacePicker: View {
    @ObservedObject var model: SidebyAppModel
    let context: ContextDefinition?
    let displayID: String
    var close: () -> Void
    @State private var observation: WorkspaceLayoutObservation?
    @FocusState private var focusedKey: String?
    private var copy: CurrentConnectionStrings { model.connectionCopy }
    private var connected: Set<String> { Set(model.connectedWorkspaceDisplayIDs) }
    private var currentKey: String? { context.flatMap { model.settings.savedWorkspaces.bookmarks[$0.id]?[displayID] } }
    private var missing: Bool {
        guard context?.spaceIndex(for: displayID) != nil, let keys = keys(displayID) else { return false }
        return currentKey.map { !keys.contains($0) } ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.displayName(for: displayID)).font(.system(size: 13, weight: .semibold))
            if missing {
                Text(copy.repairHint).font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("connection-repair-hint")
            }
            if !model.selectedDisplayIDs.contains(displayID) {
                Text(copy.excluded).font(.system(size: 11)).foregroundStyle(.orange)
            }
            if !connected.contains(displayID) {
                Text(copy.offline).font(.system(size: 12))
            } else if let keys = keys(displayID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                            spaceChoice(index: index, key: key)
                        }
                    }.padding(2)
                }.frame(height: min(260, CGFloat(keys.count) * 48 + CGFloat(max(0, keys.count - 1)) * 6 + 4))
            } else {
                Text(copy.readUnavailable).font(.system(size: 12))
                Button(copy.readAgain) { refresh() }.pointingHandCursor()
            }
            if let context, context.spaceIndex(for: displayID) != nil {
                Divider()
                Button(role: .destructive) {
                    if model.setCurrentConnection(displayID: displayID, key: nil, contextID: context.id) { close() }
                } label: {
                    Label(copy.clearCell, systemImage: "minus.circle")
                        .foregroundStyle(.red).padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).pointingHandCursor().accessibilityIdentifier("connection-clear")
            }
        }.padding(14).font(.system(size: 12))
            .onAppear { readObservation() }
            .onExitCommand { close() }
    }

    private func spaceChoice(index: Int, key: String) -> some View {
        let name = model.workspaceDesktopName(displayID: displayID, spaceIndex: index)
        let position = copy.spacePosition(index)
        let selected = currentKey == key
        let accessibleName = name.map { $0 + " · " + position } ?? position
        return Button {
            if model.setCurrentConnection(displayID: displayID, key: key, contextID: context?.id) { close() }
            readObservation()
        } label: {
            spaceChoiceLabel(name: name, position: position, selected: selected)
        }
        .buttonStyle(ConnectionSpaceChoiceStyle(selected: selected, focused: focusedKey == key))
        .focused($focusedKey, equals: key).pointingHandCursor()
        .disabled(!model.canChangeSavedWorkspaces)
        .help(accessibleName)
        .accessibilityLabel(accessibleName)
        .accessibilityValue(selected ? copy.text("Connected", "연결됨") : "")
        .accessibilityIdentifier("connection-choice-" + displayID + "-\(index)")
    }

    private func spaceChoiceLabel(name: String?, position: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 15)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            VStack(alignment: .leading, spacing: 3) {
                Text(name ?? position)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let name, name != position {
                    Text(position).font(.system(size: 10))
                        .foregroundStyle(NativeSurfaceStyle.secondaryText)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                .font(.system(size: selected ? 14 : 10, weight: .semibold))
                .foregroundStyle(selected ? NativeSurfaceStyle.accent : NativeSurfaceStyle.secondaryText)
        }
        .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 48)
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    private func keys(_ id: String) -> [String]? { model.composerKeys(id, observation: observation) }
    private func readObservation() { observation = model.workspaceObservation(includingUnselectedDisplays: true) }
    private func refresh() {
        Task { await model.refreshVisibleConnections(force: true); readObservation() }
    }
}

private struct ConnectionSpaceChoiceStyle: ButtonStyle {
    let selected: Bool
    let focused: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = isEnabled && (hovered || configuration.isPressed)
        return configuration.label
            .foregroundStyle(NativeSurfaceStyle.primaryText)
            .background(configuration.isPressed || selected ? NativeSurfaceStyle.selectionBackground
                : highlighted ? NativeSurfaceStyle.hoverBackground : NativeSurfaceStyle.controlBackground,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(selected || focused || highlighted ? NativeSurfaceStyle.accent : NativeSurfaceStyle.controlBorder,
                              lineWidth: selected || focused ? 2 : 1)
                .allowsHitTesting(false))
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { hovered = $0 }
    }
}

private struct CurrentConnectionsKeyboardCommands: NSViewRepresentable {
    let model: SidebyAppModel
    func makeNSView(context: Context) -> Commands { let view = Commands(); view.model = model; return view }
    func updateNSView(_ view: Commands, context: Context) { view.model = model }
    final class Commands: NSView {
        weak var model: SidebyAppModel?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard let window, window.isKeyWindow, window.attachedSheet == nil, NSApp.modalWindow == nil,
                  !(window.firstResponder is NSTextView), event.type == .keyDown,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command],
                  event.charactersIgnoringModifiers?.lowercased() == "z", let model,
                  model.canChangeSavedWorkspaces, model.settings.savedWorkspaces.undo != nil else { return false }
            return model.undoSavedWorkspaceChange()
        }
    }
}

private struct ConnectionSourceOffset: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
