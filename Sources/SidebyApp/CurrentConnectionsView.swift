import AppKit
import SidebyCore
import SidebyUI
import SwiftUI
import UniformTypeIdentifiers

/// Settings, the menu, and the shortcut editor share this live connection table.
struct CurrentConnectionsView: View {
    @ObservedObject var model: SidebyAppModel
    var showsDesktopSources = false
    var availableHeight: CGFloat = 600
    var select: ((String) -> Void)?
    var keepOpen: () -> Void = {}
    var close: (() -> Void)?
    @State private var observation: WorkspaceLayoutObservation?
    @State private var picker: String?
    @State private var showsDisplays = false
    @State private var showsOffline = false
    @State private var session = UUID()
    @State private var drag: WorkspaceComposerDrag?
    @State private var dropCell: String?
    @State private var addRequest = 0
    @State private var highlightsNewColumn = false
    @State private var dropOperation: DropOperation = .copy
    @State private var selectedDesktop: WorkspaceDesktopReference?
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
                Text(contexts.isEmpty ? copy.title : copy.editing).font(.system(size: 17, weight: .semibold))
                Spacer()
                if !contexts.isEmpty {
                    Button { keepOpen(); highlightsNewColumn = true; addRequest += 1 } label: { Label(copy.add, systemImage: "plus") }
                        .controlSize(.small).pointingHandCursor().help(copy.add).accessibilityLabel(copy.add)
                        .disabled(!model.canChangeSavedWorkspaces).accessibilityIdentifier("connections-add")
                }
                Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).pointingHandCursor().help(model.saveCopy.readAgain)
                    .disabled(!model.canSaveWorkspace).accessibilityIdentifier("connections-refresh")
                Button(copy.displays) { keepOpen(); showsDisplays = true }.pointingHandCursor()
                    .accessibilityIdentifier("connections-displays")
                    .popover(isPresented: $showsDisplays) {
                        ScrollView {
                            NativeDisplaySelector(displays: model.displayLayout.displays, selectedIDs: model.selectedDisplayIDs,
                                language: model.settings.language, isEnabled: model.canChangeSavedWorkspaces,
                                setSelected: { model.setDisplayTarget($0, isSelected: $1); readObservation() })
                        }.frame(width: 340, height: min(260, max(100, CGFloat(model.displayLayout.displays.count) * 34 + 100))).padding(16)
                    }
                if let close {
                    Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).pointingHandCursor()
                        .accessibilityLabel(model.saveCopy.close)
                }
            }
            if !contexts.isEmpty && !compact {
                Text(showsDesktopSources
                    ? copy.text("Place a Space in a cell for the same display. Use Move together to switch.", "Space를 같은 모니터의 칸에 놓으세요. 화면 이동은 ‘함께 이동’을 누르세요.") : copy.hint)
                    .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            }
            if showsDesktopSources { desktopSources }
            if model.settingsStore.hasUnreadableSettings {
                Text(model.saveCopy.settingsUnreadable).font(.system(size: 12)).foregroundStyle(.orange)
            } else if contexts.isEmpty {
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
            if let message = model.workspaceSaveMessage { feedback(message) }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if !contexts.isEmpty {
                        Text(copy.dragHint).font(.system(size: 11))
                            .accessibilityIdentifier("connections-drag-hint")
                    }
                    Text(copy.scope).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if canUndo && model.workspaceSaveMessage == nil { undoButton }
            }

        }
        .foregroundStyle(NativeSurfaceStyle.primaryText).tint(NativeSurfaceStyle.accent)
        .background(CurrentConnectionsKeyboardCommands(model: model))
        .background(WorkspaceDragCompletion(dragID: drag?.id) { drag = nil; dropCell = nil })
        .onAppear { refresh() }
        .task(id: addRequest) {
            guard addRequest > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { highlightsNewColumn = false }
        }
        .onReceive(model.$workspaceObservedDisplays) { _ in readObservation() }
        .onChange(of: model.displayLayout) { _, _ in readObservation(); picker = nil; drag = nil; selectedDesktop = nil }
        .onChange(of: model.settings.contextPlan.contexts) { _, _ in readObservation() }
        .onChange(of: model.isSwitching) { _, busy in if !busy { refresh() } }
        .onExitCommand {
            if picker == nil && drag == nil && selectedDesktop == nil && !showsDisplays { close?() }
            picker = nil; drag = nil; dropCell = nil; selectedDesktop = nil; showsDisplays = false
        }
    }

    private var undoButton: some View {
        Button { keepOpen(); _ = model.undoSavedWorkspaceChange(); readObservation() } label: {
            Label(copy.text("Undo", "되돌리기"), systemImage: "arrow.uturn.backward")
        }.font(.system(size: 12)).pointingHandCursor()
            .disabled(!model.canChangeSavedWorkspaces || !canUndo)
            .help((model.settings.savedWorkspaces.undo?.label ?? copy.undo) + " (⌘Z)")
            .accessibilityLabel(copy.undo).accessibilityIdentifier("connections-undo")
    }

    private func feedback(_ message: String) -> some View {
        let failed = model.workspaceSaveFeedbackKind == .failure
        let success = model.workspaceSaveFeedbackKind == .success
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: failed ? "exclamationmark.triangle.fill" : success ? "checkmark.circle.fill" : "info.circle")
                .foregroundStyle(failed ? Color.orange : NativeSurfaceStyle.accent)
            VStack(alignment: .leading, spacing: 2) {
                if failed { Text(copy.notApplied).fontWeight(.semibold) }
                Text(message).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            if canUndo { undoButton }
            Button { model.workspaceSaveMessage = nil } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }
                .buttonStyle(.plain).pointingHandCursor().accessibilityLabel(model.saveCopy.close)
        }.padding(9)
            .background(failed ? Color.orange.opacity(0.10) : NativeSurfaceStyle.selectionBackground,
                        in: RoundedRectangle(cornerRadius: 7))
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
                                displayBadge(id)
                            }.padding(.horizontal, 10).frame(width: 132, height: 76, alignment: .leading)
                                .background(activeDisplayID == id ? NativeSurfaceStyle.selectionBackground : .clear)
                            if let keys = keys(id) {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 6) {
                                        ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                                            desktopSource(displayID: id, key: key, index: index)
                                        }
                                    }.padding(.vertical, 3)
                                }.scrollIndicators(.visible)
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 4) {
                        Text(title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(NativeSurfaceStyle.accent) }
                    }
                    HStack(spacing: 5) {
                        if title != copy.spacePosition(index) { Text(copy.text("Position \(index + 1)", "\(index + 1)번째 Space")) }
                        if current { Text(copy.text("On screen", "현재")).fontWeight(.medium).foregroundStyle(NativeSurfaceStyle.accent) }
                    }.font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                }.padding(8).frame(width: 174, height: 70, alignment: .leading)
                    .background(selected ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.inputBackground,
                                in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.accentColor : NativeSurfaceStyle.controlBorder))
            }.frame(width: 174, height: 70).help(title)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.empty).font(.system(size: 15, weight: .medium))
            Text(copy.emptyDetail).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            ForEach(model.connectedWorkspaceDisplayIDs, id: \.self) { id in
                HStack {
                    Text(model.displayName(for: id)).lineLimit(1).help(model.displayName(for: id))
                    Spacer()
                    Text(!model.selectedDisplayIDs.contains(id) ? copy.excluded
                        : keys(id).map { copy.text("\($0.count) Spaces", "Space \($0.count)개") } ?? copy.readUnavailable)
                }.font(.system(size: 11))
            }
            Button(copy.start) { keepOpen(); _ = model.connectCurrentDesktopOrder(); readObservation() }
                .buttonStyle(.borderedProminent).pointingHandCursor()
                .disabled(!model.canChangeSavedWorkspaces || model.selectedDisplayIDs.isEmpty || observation == nil)
                .accessibilityIdentifier("connections-start")
            if model.selectedDisplayIDs.isEmpty {
                Text(copy.text("Choose the displays above to begin.", "위에서 함께 움직일 모니터를 선택하세요.")).font(.system(size: 11))
            } else if observation == nil {
                Text(copy.readUnavailable).font(.system(size: 11)).foregroundStyle(.orange)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeSurfaceStyle.headerBackground, in: RoundedRectangle(cornerRadius: 9))
    }

    private var table: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text(copy.text("Connections →", "Space 연결 →")).font(.system(size: 11, weight: .medium))
                        .frame(height: 64).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(displayIDs, id: \.self) { id in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName(for: id)).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            displayBadge(id)
                            if activeDisplayID == id {
                                Label(copy.text("Place here", "이 행에 놓기"), systemImage: "arrow.right")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(NativeSurfaceStyle.accent)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).frame(height: rowHeight)
                            .background(activeDisplayID == id ? NativeSurfaceStyle.selectionBackground : .clear)
                            .help(model.displayName(for: id))
                    }
                }.padding(.horizontal, 10).frame(width: 132).background(NativeSurfaceStyle.headerBackground)
                ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(contexts.enumerated()), id: \.element.id) { index, context in
                            VStack(spacing: 0) {
                                header(context, position: index + 1)
                                ForEach(displayIDs, id: \.self) { id in cell(context, displayID: id) }
                            }.frame(width: columnWidth).id(context.id)
                        }
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
                }.frame(height: 64 + CGFloat(displayIDs.count) * rowHeight)
                    .onChange(of: addRequest) { _, _ in scroll.scrollTo("new", anchor: .trailing) }
                    .onChange(of: contexts.map(\.id)) { old, ids in
                        if ids.count > old.count, let last = ids.last { scroll.scrollTo(last, anchor: .trailing) }
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

    private func header(_ context: ContextDefinition, position: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(context.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(context.name)
                Spacer(minLength: 0)
                if model.verifiedCurrentWorkspaceID == context.id {
                    Text("✓ " + copy.text("Current", "현재")).font(.system(size: 11))
                        .foregroundStyle(NativeSurfaceStyle.accent).fixedSize()
                }
                Menu { connectionActions(context, position: position) } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 20)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(copy.text("Connection actions", "연결 관리"))
                    .accessibilityLabel(context.name + " · " + copy.text("Connection actions", "연결 관리"))
                    .accessibilityIdentifier("connection-actions-" + context.id)
            }
            HStack(spacing: 4) {
                Text(model.workspaceShortcut(context.id) ?? copy.connection(position))
                    .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1)
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
    }

    @ViewBuilder private func connectionActions(_ context: ContextDefinition, position: Int) -> some View {
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

    private func cell(_ context: ContextDefinition?, displayID: String) -> some View {
        let cellID = (context?.id ?? "new") + "-" + displayID
        let key = context.flatMap { model.settings.savedWorkspaces.bookmarks[$0.id]?[displayID] }
        let index = key.flatMap { keys(displayID)?.firstIndex(of: $0) } ?? (key == nil ? context?.spaceIndex(for: displayID) : nil)
        let assigned = context?.spaceIndex(for: displayID) != nil
        let missing = assigned && connected.contains(displayID) && keys(displayID) != nil && (key == nil || index == nil)
        let unreadable = assigned && connected.contains(displayID) && keys(displayID) == nil
        let title = unreadable ? copy.text("Couldn't read · Retry", "읽기 실패 · 다시 확인") : missing ? copy.repair : index.map { model.workspaceDesktopName(displayID: displayID, spaceIndex: $0) ?? copy.spacePosition($0) }
            ?? (showsDesktopSources ? copy.dropHere : copy.choose)
        let enabled = model.canChangeSavedWorkspaces && connected.contains(displayID)
        let hovering = dropCell == cellID
        let preview = dropPreview(context, assigned: assigned)
        return WorkspaceDesktopDragSource(enabled: enabled, label: model.displayName(for: displayID) + " · " + title,
            identifier: "connection-cell-" + cellID,
            isDraggable: assigned && !missing && !unreadable && key != nil,
            accessibilityState: hovering ? preview : assigned ? copy.text("Connected", "연결됨") : copy.text("Empty. Click to connect a Space.", "빈 칸. 눌러서 Space를 연결하세요."),
            allowsMove: true,
            click: {
                keepOpen()
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
                        if !assigned { Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(NativeSurfaceStyle.secondaryText) }
                        Text(title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        Spacer(minLength: 0)
                        if assigned { Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(NativeSurfaceStyle.secondaryText) }
                    }
                    if hovering {
                        Text(preview).font(.system(size: 11, weight: .medium)).foregroundStyle(NativeSurfaceStyle.accent)
                    } else if let index, title != copy.spacePosition(index) {
                        Text(copy.text("Position \(index + 1)", "\(index + 1)번째 Space")).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    } else if !assigned {
                        Text(showsDesktopSources ? copy.orChoose : copy.text("Click to connect", "눌러서 연결하기"))
                            .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    }
                }.padding(9).frame(maxWidth: .infinity, alignment: .leading).frame(height: rowHeight - 8)
                    .background(hovering ? NativeSurfaceStyle.selectionBackground : assigned ? NativeSurfaceStyle.inputBackground : NativeSurfaceStyle.tableBackground,
                                in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(missing || unreadable ? Color.orange : hovering || selectedDesktop?.displayID == displayID ? Color.accentColor : NativeSurfaceStyle.controlBorder,
                        style: StrokeStyle(lineWidth: hovering ? 2 : 1, dash: assigned ? [] : [4, 3])))
            }
            .padding(.horizontal, 5).frame(height: rowHeight).help(title)
            .popover(isPresented: Binding(get: { picker == cellID }, set: { if !$0 { picker = nil } })) {
                choices(context, displayID: displayID, currentKey: key)
            }
            .onDrop(of: [UTType.plainText], delegate: WorkspaceComposerDropDelegate(session: session, active: drag,
                contextID: context?.id ?? "new", displayID: displayID, enabled: enabled, midpoint: columnWidth / 2,
                desktopOperation: {
                    let operation: DropOperation = drag?.sourceContextID != nil && !NSEvent.modifierFlags.contains(.option) ? .move : .copy
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

    private func choices(_ context: ContextDefinition?, displayID: String, currentKey: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.displayName(for: displayID)).font(.system(size: 13, weight: .semibold))
            if !model.selectedDisplayIDs.contains(displayID) {
                Text(copy.excluded).font(.system(size: 11)).foregroundStyle(.orange)
            }
            if let keys = keys(displayID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                            Button {
                                if model.setCurrentConnection(displayID: displayID, key: key, contextID: context?.id) { picker = nil }
                                readObservation()
                            } label: {
                                HStack {
                                    Text(model.workspaceDesktopName(displayID: displayID, spaceIndex: index).map { $0 + " · " + copy.spacePosition(index) } ?? copy.spacePosition(index))
                                        .lineLimit(2)
                                    Spacer()
                                    if currentKey == key { Image(systemName: "checkmark") }
                                }.padding(7).contentShape(Rectangle())
                            }.buttonStyle(.plain).pointingHandCursor()
                                .accessibilityIdentifier("connection-choice-" + displayID + "-\(index)")
                        }
                    }
                }.frame(maxHeight: 260)
            } else {
                Text(copy.readUnavailable).font(.system(size: 12))
                Button(model.saveCopy.readAgain) { refresh() }.pointingHandCursor()
            }
            if let context, context.spaceIndex(for: displayID) != nil {
                Divider()
                Button(copy.keep) {
                    if model.setCurrentConnection(displayID: displayID, key: nil, contextID: context.id) { picker = nil }
                }.pointingHandCursor().accessibilityIdentifier("connection-clear")
            }
        }.padding(14).frame(width: 290).font(.system(size: 12))
    }

    private func keys(_ id: String) -> [String]? { model.composerKeys(id, observation: observation) }
    private func readObservation() { observation = model.workspaceObservation(includingUnselectedDisplays: true) }
    private func refresh() { model.refreshWorkspaceStatus(); model.refreshCurrentDesktopContents(); readObservation() }
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
