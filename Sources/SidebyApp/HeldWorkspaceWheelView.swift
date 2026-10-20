import AppKit
import SidebyCore
import SidebyUI
import SwiftUI

struct ConnectionSector: Shape {
    let index: Int
    let count: Int
    var geometry = HeldWorkspaceWheelGeometry()
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let step = 360.0 / Double(max(1, count))
        let start = -90 - step / 2 + Double(index) * step
        let end = start + step
        let outer = geometry.outerRadius
        let inner = geometry.innerRadius
        // Offset both straight edges by half the same point distance. Angular
        // spacing would taper toward the center; these edges stay parallel.
        let halfGap = count == 1 ? 0 : HeldWorkspaceWheelLayout.gap / 2
        let outerInset = asin(halfGap / outer) * 180 / .pi
        let innerInset = asin(halfGap / inner) * 180 / .pi
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .degrees(start + outerInset), endAngle: .degrees(end - outerInset), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: .degrees(end - innerInset), endAngle: .degrees(start + innerInset), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// A quick destination chooser. Detailed drag/link editing stays in the shared table.
struct HeldWorkspaceWheelView: View {
    @ObservedObject var model: SidebyAppModel
    let select: (HeldWorkspaceColumn) -> Void
    var keepOpen: () -> Void = {}
    var close: () -> Void = {}
    var edit: () -> Void = {}
    var showTable: () -> Void = {}
    var persistent = false
    var diameter: CGFloat?
    var displayCount: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var pinned = false
    @State private var page = 0
    @State private var openingDisplayCount: Int?
    private enum InteractionTarget: Equatable {
        case connection(String)
        case center
    }
    // One target owns the highlight and center contents. Pointer exit must clear
    // it, rather than falling back to a previously focused/clicked connection.
    @State private var interactionTarget: InteractionTarget?
    @State private var renaming: ContextDefinition?
    @State private var clearing: WorkspaceDeleteAllProposal?
    @State private var showsFeedback = false
    @FocusState private var focused: String?
    @FocusState private var cancelFocused: Bool
    private var copy: HeldMatrixStrings { .init(language: model.settings.language) }
    private var live: HeldWorkspaceSnapshot { .init(model: model) }
    private var geometry: HeldWorkspaceWheelGeometry {
        .init(displayCount: openingDisplayCount ?? displayCount ?? live.displayIDs.count)
    }
    private var renderedDiameter: CGFloat { diameter ?? geometry.diameter }
    private var columns: [HeldWorkspaceColumn] { Array(live.columns[HeldWorkspaceWheelLayout.pageRange(page, count: live.columns.count)]) }
    private func text(_ en: String, _ ko: String) -> String { model.connectionCopy.text(en, ko) }
    private var activeID: String? {
        if case let .connection(id) = interactionTarget { return id }
        return nil
    }
    private var previewColumn: HeldWorkspaceColumn? {
        columns.first { $0.id == activeID }
    }
    private var centerHighlighted: Bool {
        model.canChangeSavedWorkspaces && interactionTarget == .center
    }
    private var centerActionTitle: String {
        text("Add current setup", "현재 상태 추가하기")
    }

    var body: some View {
        ZStack {
            content
                .disabled(clearing != nil || renaming != nil)
                .opacity(clearing != nil || renaming != nil ? 0.45 : 1)
                .accessibilityHidden(clearing != nil || renaming != nil)
            if let proposal = clearing {
                Color.clear.contentShape(Rectangle()).onTapGesture { }
                clearAllConfirmation(proposal)
            }
            if let target = renaming {
                Color.clear.contentShape(Rectangle()).onTapGesture { }
                ConnectionNameEditor(model: model, target: target, close: { renaming = nil })
                    .background(NativeSurfaceStyle.windowBackground, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NativeSurfaceStyle.frameBorder))
                    .shadow(radius: 16, y: 6)
            }
        }
        .background(WheelEscapeHandler {
            if clearing != nil { clearing = nil; return true }
            if renaming != nil {
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
                renaming = nil; return true
            }
            return false
        })
        .foregroundStyle(NativeSurfaceStyle.primaryText).tint(NativeSurfaceStyle.accent)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            model.refreshWorkspaceStatus(); model.refreshCurrentDesktopContents()
            if openingDisplayCount == nil { openingDisplayCount = displayCount ?? live.displayIDs.count }
            if let id = model.verifiedCurrentWorkspaceID, let index = live.columns.firstIndex(where: { $0.id == id }) {
                page = index / HeldWorkspaceWheelLayout.pageSize
            }
            withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.4, dampingFraction: 0.8)) { appeared = true }
        }
        .onChange(of: clearing != nil) { _, presented in cancelFocused = presented }
        .onChange(of: focused) { _, value in
            if value == "save" { interactionTarget = .center }
            else {
                interactionTarget = columns.first {
                    value == $0.id || value == "rename-" + $0.id || value == "delete-" + $0.id
                }.map { .connection($0.id) }
            }
        }
        .onChange(of: model.settings.savedWorkspaces.undo) { _, _ in
            if pinned { showsFeedback = true }
        }
        .onChange(of: live.columns.map(\.id)) { _, ids in
            page = min(page, HeldWorkspaceWheelLayout.pageCount(ids.count) - 1)
            if let renaming, !ids.contains(renaming.id) { self.renaming = nil }
            if let activeID, !ids.contains(activeID) { interactionTarget = nil }
        }
        .onExitCommand {
            if clearing != nil { clearing = nil }
            else if renaming != nil { renaming = nil }
            else { close() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("held-workspace-wheel")
    }

    private var content: some View {
        VStack(spacing: 0) {
            ring.frame(width: geometry.diameter, height: geometry.diameter)
                .scaleEffect(renderedDiameter / geometry.diameter)
                .frame(width: renderedDiameter, height: renderedDiameter).padding(.top, 8)
            footer.frame(height: 120).padding(.horizontal, 12)
        }.frame(width: renderedDiameter + 32, height: renderedDiameter + HeldWorkspaceWheelLayout.chromeHeight)
    }

    private var ring: some View {
        ZStack {
            if columns.isEmpty {
                emptyRing
            }
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                sector(column, index: index)
            }
            Button {
                pin()
                if let id = model.addCurrentConnection(), let index = live.columns.firstIndex(where: { $0.id == id }) {
                    page = index / HeldWorkspaceWheelLayout.pageSize
                }
                showsFeedback = true
            } label: {
              Group {
                if let column = previewColumn {
                    connectionPreview(column)
                } else if interactionTarget == .center || columns.isEmpty {
                  VStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 23)).foregroundStyle(NativeSurfaceStyle.accent)
                    Text(centerActionTitle)
                        .font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center)
                    Text(text("Save the Spaces\non your displays", "지금 보고 있는 Space를\n새 연결로 저장합니다"))
                        .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText).multilineTextAlignment(.center)
                  }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "cursorarrow").font(.system(size: 20))
                        Text(text("Choose a connection", "연결을 골라 주세요"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(text("Hover a sector\nto see its Spaces", "칸에 마우스를 올려\n화면 내용을 확인하세요"))
                            .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    }.multilineTextAlignment(.center)
                }
              }.frame(width: max(140, geometry.previewWidth))
                    .frame(width: geometry.centerRadius * 2, height: geometry.centerRadius * 2)
                    .background(centerHighlighted ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.tableBackground, in: Circle())
                    .overlay(Circle().strokeBorder(centerHighlighted ? NativeSurfaceStyle.accent : NativeSurfaceStyle.itemBorder,
                        lineWidth: centerHighlighted ? 2.5 : 1))
                    .contentShape(Circle())
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: centerHighlighted)
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .disabled(!model.canChangeSavedWorkspaces).focused($focused, equals: "save")
            // This remains a save action even while displaying a sector preview.
            .accessibilityLabel(centerActionTitle)
            .accessibilityValue(previewColumn.map(connectionPreviewDescription)
                ?? (centerHighlighted ? text("Save the Spaces currently on your displays", "지금 보고 있는 Space를 저장합니다") : ""))
            .help(model.connectionCopy.addCurrentHint).accessibilityIdentifier("held-add-current-connection")
        }
        .overlay {
            WheelCursorRegion(count: columns.count, geometry: geometry,
                enabled: Set(columns.enumerated().compactMap { index, column in
                    canChoose(column) ? index : nil
                }), centerEnabled: model.canChangeSavedWorkspaces,
                hovered: { index, isCenter in
                    interactionTarget = isCenter ? .center
                        : index.flatMap { columns.indices.contains($0) ? .connection(columns[$0].id) : nil }
                })
        }

    }

    private func connectionPreview(_ column: HeldWorkspaceColumn) -> some View {
        let displays = live.displayIDs.filter { column.cells[$0] != nil }
        return VStack(spacing: 7) {
            if displays.isEmpty {
                Text(text("No Spaces connected", "연결된 Space가 없어요"))
                    .font(.system(size: 13)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            } else {
                ForEach(displays, id: \.self) { id in
                    VStack(spacing: 2) {
                        Text((live.displayNames[id] ?? id) + " · " + (column.desktopLabels[id] ?? ""))
                            .font(.system(size: 10))
                            .foregroundStyle(NativeSurfaceStyle.secondaryText)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(width: geometry.previewWidth - 12)
                        Text(previewSpaceTitle(column, displayID: id))
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(displays.count > 2 ? 1 : displays.count == 1 ? 3 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }.multilineTextAlignment(.center)
                }
            }
            Text(needsSpaceSelection(column) ? text("Choose Spaces in this sector", "칸을 눌러 Space 확인")
                : model.verifiedCurrentWorkspaceID == column.id ? copy.current
                : text("Click the sector to switch", "칸을 눌러 이동"))
                .font(.system(size: 10)).foregroundStyle(needsSpaceSelection(column) ? Color.orange : NativeSurfaceStyle.secondaryText)
                .lineLimit(1)
        }.frame(width: geometry.previewWidth).accessibilityHidden(true)
    }

    private func previewSpaceTitle(_ column: HeldWorkspaceColumn, displayID: String) -> String {
        if let context = model.settings.contextPlan.contexts.first(where: { $0.id == column.id }),
           model.unresolvedWorkspaceMembers(context).contains(displayID) {
            return text("Space not found", "Space를 찾을 수 없어요")
        }
        return column.cells[displayID] ?? ""
    }

    private func connectionPreviewDescription(_ column: HeldWorkspaceColumn) -> String {
        let spaces = live.displayIDs.filter { column.cells[$0] != nil }.map {
            (live.displayNames[$0] ?? $0) + " · " + (column.desktopLabels[$0] ?? "")
                + ": " + previewSpaceTitle(column, displayID: $0)
        }
        return ([column.name] + spaces + [connectionSummary(column)]).joined(separator: "\n")
    }

    private var emptyRing: some View {
        ZStack {
            let shape = ConnectionSector(index: 0, count: 1, geometry: geometry)
            shape.fill(NativeSurfaceStyle.tableBackground)
                .overlay {
                    Circle().stroke(NativeSurfaceStyle.itemBorder, lineWidth: 2).padding(2)
                    Circle().stroke(NativeSurfaceStyle.itemBorder, lineWidth: 2)
                        .frame(width: geometry.innerRadius * 2, height: geometry.innerRadius * 2)
                }.clipShape(shape)
            VStack(spacing: 6) {
                Text(text("No saved connections yet", "아직 저장된 연결이 없어요"))
                    .font(.system(size: 14, weight: .semibold))
                Text(text("Save the Spaces you are using\nto return to them together.", "지금 쓰는 Space를 저장해 두면\n한 번에 돌아올 수 있어요."))
                    .font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            }.multilineTextAlignment(.center).frame(width: 250).position(x: geometry.midpoint, y: 74)
                .accessibilityIdentifier("wheel-empty-guidance")
            VStack(spacing: 7) {
                if live.displayIDs.isEmpty {
                    Text(copy.noDisplays).font(.system(size: 11)).multilineTextAlignment(.center)
                } else {
                    ForEach(Array(live.displayIDs.prefix(2)), id: \.self) { id in
                        VStack(spacing: 2) {
                            Text(live.displayNames[id] ?? id).font(.system(size: 10))
                                .foregroundStyle(NativeSurfaceStyle.secondaryText)
                            Text(currentSpaceTitle(id)).font(.system(size: 12, weight: .medium))
                        }.lineLimit(1).help((live.displayNames[id] ?? id) + " · " + currentSpaceTitle(id))
                            .accessibilityIdentifier("wheel-empty-space-" + id)
                    }
                    if live.displayIDs.count > 2 {
                        Text(text("and \(live.displayIDs.count - 2) more displays", "외 모니터 \(live.displayIDs.count - 2)대"))
                            .font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    }
                }
            }.frame(width: 220).position(x: geometry.midpoint, y: 354 + geometry.expansion * 2)
        }.allowsHitTesting(false)
    }

    private func currentSpaceTitle(_ displayID: String) -> String {
        guard let index = model.workspaceObservedDisplays?.first(where: { $0.displayID == displayID })?.currentSpaceIndex else {
            return text("Current Space unavailable", "현재 Space 확인 필요")
        }
        return model.workspaceDesktopName(displayID: displayID, spaceIndex: index) ?? model.connectionCopy.spacePosition(index)
    }

    private func sector(_ column: HeldWorkspaceColumn, index: Int) -> some View {
        let shape = ConnectionSector(index: index, count: columns.count, geometry: geometry)
        let active = activeID == column.id
        let current = model.verifiedCurrentWorkspaceID == column.id && !model.isSwitching
        let enabled = canChoose(column)
        let missing = needsSpaceSelection(column)
        let aligned = spacesAlreadyVisible(column)
        let position = HeldWorkspaceWheelLayout.labelPoint(index: index, count: columns.count, geometry: geometry)
        let labelFrame = HeldWorkspaceWheelLayout.labelFrame(index: index, count: columns.count, geometry: geometry)
        let label = sectorLabel(column, current: current, aligned: aligned, missing: missing)
            .frame(width: labelFrame.width, height: labelFrame.height)
            .position(x: labelFrame.midX, y: labelFrame.midY)
            .allowsHitTesting(false)
        let surface = sectorSurface(shape, active: active).overlay(label).contentShape(shape)
        let button = Button {
            if current { close() }
            else if missing { pin(); edit() }
            else { select(column) }
        } label: { surface }
        let accessibilityName = column.name + " · " + connectionSummary(column)
        return ZStack {
            button.buttonStyle(.plain).focusEffectDisabled().disabled(!enabled)
                .focused($focused, equals: column.id)
                .help(column.name + "\n" + connectionSummary(column))
                .accessibilityLabel(accessibilityName)
                .accessibilityIdentifier("wheel-go-" + column.id)
            HStack(spacing: 6) {
                tool("pencil", label: model.connectionCopy.rename, id: "rename-" + column.id) {
                    pin(); focused = nil; cancelFocused = false
                    renaming = model.settings.contextPlan.contexts.first { $0.id == column.id }
                }
                tool("trash", label: text("Delete connection", "연결 삭제"), id: "delete-" + column.id) {
                    pin(); focused = nil
                    _ = model.deleteSavedWorkspace(column.id)
                    interactionTarget = nil; showsFeedback = true
                }
            }.position(x: position.x, y: position.y + HeldWorkspaceWheelLayout.toolsOffset(count: columns.count))
                .opacity(active ? 1 : 0).allowsHitTesting(active)
                // Keep tools in the keyboard/VoiceOver order even when visually hidden.
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: active)
    }

    private func sectorSurface(_ shape: ConnectionSector, active: Bool) -> some View {
        // Current location is a label, not a second selection. Only the pointer
        // or keyboard target receives the same fill and outline as the center.
        let fill = active ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.tableBackground
        let border = active ? NativeSurfaceStyle.accent : NativeSurfaceStyle.itemBorder
        let width: CGFloat = active ? 2.5 : 1
        return shape.fill(fill).overlay(shape.stroke(border, lineWidth: width * 2).clipShape(shape))
    }

    private func sectorLabel(_ column: HeldWorkspaceColumn, current: Bool, aligned: Bool, missing: Bool) -> some View {
        let count = column.cells.count
        let coverage = text("\(count) display\(count == 1 ? "" : "s")", "모니터 \(count)대")
        let partial = count < live.displayIDs.count
        return VStack(spacing: 4) {
            Text(column.name)
                .font(.system(size: HeldWorkspaceWheelLayout.nameFontSize(count: columns.count), weight: .semibold))
                .foregroundStyle(NativeSurfaceStyle.primaryText)
                .lineLimit(2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if current {
                Label(copy.current + (partial ? " · \(count)/\(live.displayIDs.count)" : ""), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(NativeSurfaceStyle.secondaryText)
            } else if aligned {
                Text(text("Already here", "이미 현재 Space") + (partial ? text(" · \(count)", " · \(count)대") : ""))
                    .foregroundStyle(NativeSurfaceStyle.secondaryText)
            } else if missing {
                Label(column.bookmarks.isEmpty ? text("Choose Space", "Space 연결 필요") : text("Check Space", "Space 확인"),
                      systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            } else {
                Text(partial ? coverage : model.workspaceShortcut(column.id) ?? " ").foregroundStyle(NativeSurfaceStyle.secondaryText)
            }
        }.font(.system(size: 11)).lineLimit(1)
    }

    private func needsSpaceSelection(_ column: HeldWorkspaceColumn) -> Bool {
        guard let context = model.settings.contextPlan.contexts.first(where: { $0.id == column.id }) else { return false }
        return column.bookmarks.isEmpty || !model.unresolvedWorkspaceMembers(context).isEmpty
    }

    private func spacesAlreadyVisible(_ column: HeldWorkspaceColumn) -> Bool {
        !model.isSwitching && model.isWorkspaceAssignmentAvailable(contextID: column.id)
            && model.workspaceAssignmentReadiness(contextID: column.id)?.isResolved == true
    }

    private func canChoose(_ column: HeldWorkspaceColumn) -> Bool {
        if model.isSwitching { return false }
        return model.verifiedCurrentWorkspaceID == column.id
            || model.heldMatrixCanActivate(column, displayIDs: live.displayIDs)
            || (model.canChangeSavedWorkspaces && needsSpaceSelection(column))
    }

    private func connectionSummary(_ column: HeldWorkspaceColumn) -> String {
        let included = live.displayIDs.filter { column.cells[$0] != nil }
        if included.isEmpty { return text("No participating display is connected. Click to choose Spaces.", "연결된 참여 모니터가 없습니다. 눌러서 Space를 연결하세요.") }
        if needsSpaceSelection(column) { return copy.missingHint + " · " + copy.chooseAgain }
        let names = included.map { live.displayNames[$0] ?? $0 }.joined(separator: ", ")
        let coverage = included.count < live.displayIDs.count
            ? text("Only \(names) · Other displays stay unchanged", "\(names)만 연결 · 다른 모니터는 유지")
            : text("\(included.count) displays connected", "모니터 \(included.count)대 연결")
        if model.verifiedCurrentWorkspaceID == column.id {
            return text("Already on these Spaces · Click to close", "이미 현재 Space입니다 · 누르면 닫기") + "\n" + coverage
        }
        if spacesAlreadyVisible(column) {
            return text("These Spaces are already on screen", "연결한 Space가 이미 화면에 떠 있습니다") + "\n" + coverage
        }
        return coverage + "\n" + included.map { column.cells[$0] ?? "" }.joined(separator: " / ")
    }

    private func tool(_ image: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).font(.system(size: 12))
            .frame(width: 28, height: 26).background(NativeSurfaceStyle.controlBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NativeSurfaceStyle.itemBorder))
        }.buttonStyle(.plain).focusEffectDisabled().pointingHandCursor().disabled(!model.canChangeSavedWorkspaces)
            .focused($focused, equals: id).help(label).accessibilityLabel(label)
            .accessibilityIdentifier("wheel-" + id)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if HeldWorkspaceWheelLayout.pageCount(live.columns.count) > 1 {
                HStack {
                    Button { changePage(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 22) }
                        .disabled(page == 0).accessibilityLabel(copy.previous).accessibilityIdentifier("wheel-previous-page")
                    Text(text("\(live.columns.count) connections", "연결 \(live.columns.count)개") + " · \(page + 1)/\(HeldWorkspaceWheelLayout.pageCount(live.columns.count))")
                    Button { changePage(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 22) }
                        .disabled(page == HeldWorkspaceWheelLayout.pageCount(live.columns.count) - 1)
                        .accessibilityLabel(copy.next).accessibilityIdentifier("wheel-next-page")
                }.buttonStyle(.plain).pointingHandCursor().font(.system(size: 11))
                    .padding(.horizontal, 9).background(NativeSurfaceStyle.windowBackground, in: Capsule())
            }
            HStack(spacing: 8) {
              Group {
                if showsFeedback, let message = model.workspaceSaveMessage {
                    Text(message).foregroundStyle(model.workspaceSaveFeedbackKind == .failure ? Color.orange : NativeSurfaceStyle.secondaryText)
                        .accessibilityIdentifier("held-add-feedback")
                } else if let status {
                    Text(status).foregroundStyle(.orange)
                } else if let column = columns.first(where: { $0.id == activeID }) {
                    Text(connectionSummary(column)).help(connectionSummary(column))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wheel-connection-summary")
                }
              }.font(.system(size: 11)).lineLimit(2)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(NativeSurfaceStyle.windowBackground, in: Capsule())
              Button { pin(); _ = model.undoSavedWorkspaceChange(); showsFeedback = true } label: {
                  Label(text("Undo", "되돌리기"), systemImage: "arrow.uturn.backward")
                      .padding(.horizontal, 10).frame(height: 28)
                      .background(NativeSurfaceStyle.windowBackground, in: Capsule())
              }.buttonStyle(.plain).pointingHandCursor().font(.system(size: 11)).fixedSize()
                  .disabled(!model.canChangeSavedWorkspaces || model.settings.savedWorkspaces.undo == nil)
                  .help((model.settings.savedWorkspaces.undo?.label ?? model.connectionCopy.undo) + " (⌘Z)\n" + model.connectionCopy.undoHistoryHint)
                  .keyboardShortcut("z", modifiers: .command).accessibilityIdentifier("held-undo-connection")
            }.frame(height: 40)
            HStack(spacing: 6) {
                Button { pin(); edit() } label: {
                    Label(text("Edit connections", "연결 편집"), systemImage: "slider.horizontal.3")
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(NativeSurfaceStyle.windowBackground, in: Capsule())
                }.disabled(model.isSwitching).accessibilityIdentifier("held-edit-connections")
                Button { pin(); showTable() } label: {
                    Label(text("Table", "표로 보기"), systemImage: "rectangle.split.3x3")
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(NativeSurfaceStyle.windowBackground, in: Capsule())
                }.accessibilityIdentifier("wheel-show-table")
                Button {
                    pin(); focused = nil
                    clearing = model.prepareDeleteAllSavedWorkspaces()
                } label: {
                    Text(text("Clear all…", "모두 비우기…"))
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(NativeSurfaceStyle.windowBackground, in: Capsule())
                }.disabled(!model.canDeleteAllSavedWorkspaces)
                    .help(model.connectionCopy.clearAllMessage).accessibilityLabel(model.connectionCopy.clearAll)
                    .accessibilityIdentifier("wheel-clear-all")
                Button(action: close) {
                    Image(systemName: "xmark").frame(width: 28, height: 28)
                        .background(NativeSurfaceStyle.windowBackground, in: Circle())
                }.accessibilityLabel(model.saveCopy.close)
            }.buttonStyle(.plain).pointingHandCursor().font(.system(size: 11))
                .help(persistent || pinned ? text("Esc to close", "Esc로 닫기") : copy.releaseHint)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("held-footer")
        }.frame(maxWidth: .infinity)
    }

    private var status: String? {
        if model.settingsStore.hasUnreadableSettings { return model.saveCopy.settingsUnreadable }
        if !model.isEnabled { return copy.off }
        if model.isSwitching { return copy.moving }
        if !model.hasSwitchingAccess { return copy.permission }
        if live.displayIDs.isEmpty { return copy.noDisplays }
        if model.workspaceRecoveryTargetID != nil { return copy.failed }
        return nil
    }

    private func pin() { pinned = true; keepOpen() }
    private func changePage(_ offset: Int) {
        pin(); interactionTarget = nil; showsFeedback = false
        page = max(0, min(page + offset, HeldWorkspaceWheelLayout.pageCount(live.columns.count) - 1))
    }

    private func clearAllConfirmation(_ proposal: WorkspaceDeleteAllProposal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.connectionCopy.clearAllTitle(proposal.contexts.count)).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.connectionCopy.clearAllMessage)
                .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if model.workspaceSaveFeedbackKind == .failure, let message = model.workspaceSaveMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button(model.saveCopy.cancel) { clearing = nil }
                    .pointingHandCursor().focused($cancelFocused).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("wheel-cancel-clear-all")
                Button(model.connectionCopy.clearAllAction, role: .destructive) {
                    if model.deleteAllSavedWorkspaces(proposal, label: model.connectionCopy.clearedAll(proposal.contexts.count)) { clearing = nil }
                    showsFeedback = true
                }.pointingHandCursor().tint(.red).disabled(!model.canChangeSavedWorkspaces)
                    .accessibilityIdentifier("wheel-confirm-clear-all")
            }
        }.padding(20).frame(width: 300)
            .background(NativeSurfaceStyle.windowBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(NativeSurfaceStyle.frameBorder))
            .shadow(radius: 16, y: 6).accessibilityElement(children: .contain)
            .accessibilityIdentifier("wheel-clear-all-confirmation")
    }
}

/// Curved destinations must not install rectangular hand-cursor regions over
/// the entire ring. Use the same geometry for hover cursors and sector hit tests.
private struct WheelCursorRegion: NSViewRepresentable {
    let count: Int
    let geometry: HeldWorkspaceWheelGeometry
    let enabled: Set<Int>
    let centerEnabled: Bool
    let hovered: (Int?, Bool) -> Void
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ view: CursorView, context: Context) {
        view.count = count; view.enabled = enabled; view.centerEnabled = centerEnabled; view.hovered = hovered
        view.geometry = geometry
    }
    final class CursorView: NSView {
        var count = 0
        var geometry = HeldWorkspaceWheelGeometry()
        var enabled: Set<Int> = []
        var centerEnabled = false
        var hovered: ((Int?, Bool) -> Void)?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self))
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
            window?.acceptsMouseMovedEvents = true
        }
        override func mouseMoved(with event: NSEvent) { updateCursor(event) }
        override func mouseEntered(with event: NSEvent) { updateCursor(event) }
        override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
        override func mouseExited(with event: NSEvent) {
            hovered?(nil, false)
            if window?.isVisible == true { NSCursor.arrow.set() }
        }
        private func updateCursor(_ event: NSEvent) {
            let raw = convert(event.locationInWindow, from: nil)
            let point = CGPoint(x: raw.x * geometry.diameter / max(1, bounds.width), y: raw.y * geometry.diameter / max(1, bounds.height))
            let isCenter = hypot(point.x - geometry.midpoint, point.y - geometry.midpoint) <= geometry.centerRadius
            let index = HeldWorkspaceWheelLayout.sector(at: point, count: count, geometry: geometry)
            hovered?(index, isCenter)
            // Hidden/offscreen views can be rendered and exercised without
            // taking over the user's system cursor.
            guard window?.isVisible == true else { return }
            let actionable = (isCenter && centerEnabled) || index.map { enabled.contains($0) } == true
            (actionable ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }
}

/// NSPanel handles cancelOperation before the SwiftUI root when a button owns
/// keyboard focus. Give an open dialog first refusal, then close the panel.
private struct WheelEscapeHandler: NSViewRepresentable {
    let cancel: () -> Bool
    func makeNSView(context: Context) -> HandlerView { HandlerView() }
    func updateNSView(_ view: HandlerView, context: Context) { view.cancel = cancel; view.install() }
    static func dismantleNSView(_ view: HandlerView, coordinator: ()) {
        if let panel = view.window as? HeldMatrixPanel, panel.cancelContentOwner === view {
            panel.cancelContent = nil; panel.cancelContentOwner = nil
        }
    }
    final class HandlerView: NSView {
        var cancel: (() -> Bool)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); install() }
        func install() {
            guard let panel = window as? HeldMatrixPanel else { return }
            panel.cancelContentOwner = self
            panel.cancelContent = { [weak self] in self?.cancel?() ?? false }
        }
    }
}
