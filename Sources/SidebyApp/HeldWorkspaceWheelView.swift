import AppKit
import SidebyCore
import SidebyUI
import SwiftUI
import UniformTypeIdentifiers

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

/// A quick destination chooser with connection reordering. Space assignments use the shared table.
struct HeldWorkspaceWheelView: View {
    @ObservedObject var model: SidebyAppModel
    let select: (HeldWorkspaceColumn) -> Void
    var keepOpen: () -> Void = {}
    var close: () -> Void = {}
    var edit: (ConnectionEditorRevealRequest?) -> Void = { _ in }
    var persistent = false
    var diameter: CGFloat?
    var displayCount: Int?
    var snapshot: HeldWorkspaceSnapshot?
    var animateEntrance = true
    var isActive = true
    var body: some View {
        HeldWorkspaceWheelContent(model: model, select: select, keepOpen: keepOpen, close: close,
            edit: edit, persistent: persistent, diameter: diameter, displayCount: displayCount,
            live: snapshot ?? HeldWorkspaceSnapshot(model: model), animateEntrance: animateEntrance, isActive: isActive)
            .task { if snapshot == nil { await model.refreshVisibleConnections() } }
    }
}

private struct HeldWorkspaceWheelContent: View {
    @ObservedObject var model: SidebyAppModel
    let select: (HeldWorkspaceColumn) -> Void
    var keepOpen: () -> Void = {}
    var close: () -> Void = {}
    var edit: (ConnectionEditorRevealRequest?) -> Void = { _ in }
    var persistent = false
    var diameter: CGFloat?
    var displayCount: Int?
    let live: HeldWorkspaceSnapshot
    var animateEntrance = true
    var isActive = true
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
    @State private var dragSession = UUID()
    @State private var draggedConnection: WorkspaceComposerDrag?
    @State private var dropIndex: Int?
    @State private var pageHoverTask: Task<Void, Never>?
    @FocusState private var focused: String?
    @FocusState private var cancelFocused: Bool
    private var copy: HeldMatrixStrings { .init(language: model.settings.language) }
    private var geometry: HeldWorkspaceWheelGeometry {
        .init(displayCount: openingDisplayCount ?? displayCount ?? live.displayIDs.count)
    }
    private var renderedDiameter: CGFloat { diameter ?? geometry.diameter }
    private var ringScale: CGFloat { renderedDiameter / geometry.diameter }
    private var compactRing: Bool { ringScale < 0.9 }
    private func ringFont(_ preferred: CGFloat, minimum: CGFloat = 11) -> CGFloat {
        HeldWorkspaceWheelLayout.fontSize(preferred, minimum: minimum, scale: ringScale)
    }
    private var columns: [HeldWorkspaceColumn] { Array(live.columns[HeldWorkspaceWheelLayout.pageRange(page, count: live.columns.count)]) }
    private func text(_ en: String, _ ko: String) -> String { model.connectionCopy.text(en, ko) }
    private var activeID: String? {
        if case let .connection(id) = interactionTarget { return id }
        return nil
    }
    private var previewColumn: HeldWorkspaceColumn? {
        columns.first { $0.id == activeID }
    }
    private var visibleToolIndices: Set<Int> {
        guard draggedConnection == nil, renaming == nil, clearing == nil else { return [] }
        return Set(columns.indices.filter { index in
            let id = columns[index].id
            return activeID == id || focused == "rename-" + id || focused == "delete-" + id
        })
    }
    private var centerHighlighted: Bool {
        model.canChangeSavedWorkspaces && interactionTarget == .center
    }
    private var centerActionTitle: String {
        text("Add current setup", "현재 상태 추가하기")
    }
    private var recovery: HeldWorkspaceRecoveryPresentation? { model.heldWorkspaceRecovery }
    private func recoveryDescription(_ recovery: HeldWorkspaceRecoveryPresentation) -> String {
        recovery.name + "\n" + recovery.message(language: model.settings.language,
            displayNames: recovery.displayIDs.map { model.displayName(for: $0) })
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
        .background(WheelEscapeHandler(isEnabled: isActive) {
            if draggedConnection != nil { finishDrag(); return true }
            if clearing != nil { clearing = nil; return true }
            if renaming != nil {
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
                renaming = nil; return true
            }
            return false
        })
        .foregroundStyle(NativeSurfaceStyle.primaryText).tint(NativeSurfaceStyle.accent)
        .scaleEffect(appeared || reduceMotion || !animateEntrance ? 1 : 0.86)
        .opacity(appeared || !animateEntrance ? 1 : 0)
        .onAppear {
            if openingDisplayCount == nil { openingDisplayCount = displayCount ?? live.displayIDs.count }
            if let id = model.verifiedCurrentWorkspaceID, let index = live.columns.firstIndex(where: { $0.id == id }) {
                page = index / HeldWorkspaceWheelLayout.pageSize
            }
            if animateEntrance {
                withAnimation(reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.4, dampingFraction: 0.8)) { appeared = true }
            } else { appeared = true }
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
            dropIndex = nil
            if let source = draggedConnection?.contextID, !ids.contains(source) { finishDrag() }
            if let renaming, !ids.contains(renaming.id) { self.renaming = nil }
            if let activeID, !ids.contains(activeID) { interactionTarget = nil }
            if let focused, focused != "save", !columns.contains(where: {
                focused == $0.id || focused == "rename-" + $0.id || focused == "delete-" + $0.id
            }) { self.focused = nil }
        }
        .onChange(of: page) { _, _ in focused = nil }
        .onExitCommand {
            if clearing != nil { clearing = nil }
            else if renaming != nil { renaming = nil }
            else { close() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("held-workspace-wheel")
        .onDisappear { pageHoverTask?.cancel() }
        .onChange(of: isActive) { _, active in
            if active {
                if let id = model.verifiedCurrentWorkspaceID, let index = live.columns.firstIndex(where: { $0.id == id }) {
                    page = index / HeldWorkspaceWheelLayout.pageSize
                }
            } else { renaming = nil; clearing = nil; focused = nil; finishDrag() }
        }
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
        let columns = columns
        return ZStack {
            if columns.isEmpty {
                emptyRing
            }
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                sector(column, index: index)
            }
            Button {
                pin()
                if let id = model.addCurrentConnection(), let index = model.settings.contextPlan.contexts.sorted(by: { $0.order < $1.order }).firstIndex(where: { $0.id == id }) {
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
                        .font(.system(size: ringFont(14, minimum: 12), weight: .semibold)).multilineTextAlignment(.center)
                    Text(text("Save the Spaces\non your displays", "지금 보고 있는 Space를\n새 연결로 저장합니다"))
                        .font(.system(size: ringFont(11, minimum: 10))).foregroundStyle(NativeSurfaceStyle.secondaryText).multilineTextAlignment(.center)
                  }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "cursorarrow").font(.system(size: 20))
                        Text(text("Choose a connection", "연결을 골라 주세요"))
                            .font(.system(size: ringFont(13, minimum: 12), weight: .semibold))
                        Text(text("Hover a sector\nto see its Spaces", "칸에 마우스를 올려\n화면 내용을 확인하세요"))
                            .font(.system(size: ringFont(11, minimum: 10))).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    }.multilineTextAlignment(.center)
                }
              }.frame(width: max(140, geometry.previewWidth))
                    .frame(width: geometry.centerRadius * 2, height: geometry.centerRadius * 2)
                    .background(centerHighlighted ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.tableBackground, in: Circle())
                    .overlay(Circle().strokeBorder(centerHighlighted ? NativeSurfaceStyle.accent : NativeSurfaceStyle.itemBorder,
                        lineWidth: centerHighlighted ? 2.5 : 1))
                    .overlay {
                        if focused == "save" {
                            Circle().inset(by: 5).strokeBorder(NativeSurfaceStyle.primaryText, lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                    }
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
            WheelInteractionSurface(count: columns.count, geometry: geometry,
                enabled: Set(columns.enumerated().compactMap { index, column in
                    canChoose(column) ? index : nil
                }), centerEnabled: model.canChangeSavedWorkspaces,
                visibleToolIndices: visibleToolIndices,
                canReorder: model.canChangeSavedWorkspaces && live.columns.count > 1,
                activeDrag: draggedConnection, session: dragSession,
                columnIDs: columns.map(\.id), orderedIDs: live.columns.map(\.id), names: columns.map(\.name),
                hovered: { index, isCenter in
                    let target: InteractionTarget? = isCenter ? .center
                        : index.flatMap { columns.indices.contains($0) ? .connection(columns[$0].id) : nil }
                    if interactionTarget != target { interactionTarget = target }
                }, click: { index in
                    guard columns.indices.contains(index) else { return }
                    choose(columns[index])
                }, beginDrag: { index in
                    guard columns.indices.contains(index), model.canChangeSavedWorkspaces else { return nil }
                    pin(); focused = nil; interactionTarget = nil; showsFeedback = false
                    let payload = WorkspaceComposerDrag(session: dragSession, contextID: columns[index].id)
                    draggedConnection = payload
                    return payload
                }, endDrag: finishDrag,
                dropHovered: { dropIndex = $0 },
                receive: { source, target, after in
                    let changed = model.reorderSavedWorkspace(source, relativeTo: target, after: after)
                    showsFeedback = true
                    return changed
                })
        }

    }

    private func connectionPreview(_ column: HeldWorkspaceColumn) -> some View {
        let displays = live.displayIDs.filter { column.cells[$0] != nil }
        return VStack(spacing: 7) {
            if displays.isEmpty {
                Text(text("No Spaces connected", "연결된 Space가 없어요"))
                    .font(.system(size: ringFont(13, minimum: 12))).foregroundStyle(NativeSurfaceStyle.secondaryText)
            } else {
                ForEach(displays, id: \.self) { id in
                    VStack(spacing: 2) {
                        HStack(spacing: 3) {
                            Text(live.displayNames[id] ?? id)
                                .lineLimit(1).truncationMode(.middle)
                            if let position = column.desktopLabels[id] {
                                Text("· " + position).lineLimit(1).fixedSize()
                            }
                        }.font(.system(size: ringFont(10, minimum: 10)))
                            .foregroundStyle(NativeSurfaceStyle.secondaryText)
                            .frame(width: geometry.previewWidth - 12)
                        Text(previewSpaceTitle(column, displayID: id))
                            .font(.system(size: ringFont(14, minimum: 12), weight: .semibold))
                            .lineLimit(displays.count > 2 || (compactRing && displays.count > 1) ? 1 : displays.count == 1 ? 3 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }.multilineTextAlignment(.center)
                }
            }
            Text(needsSpaceSelection(column) ? text("Choose Spaces in this sector", "칸을 눌러 Space 확인")
                : model.verifiedCurrentWorkspaceID == column.id ? copy.current
                : text("Click the sector to switch", "칸을 눌러 이동"))
                .font(.system(size: ringFont(10, minimum: 10))).foregroundStyle(needsSpaceSelection(column) ? Color.orange : NativeSurfaceStyle.secondaryText)
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
                    .font(.system(size: ringFont(14, minimum: 12), weight: .semibold))
                Text(text("Save the Spaces you are using\nto return to them together.", "지금 쓰는 Space를 저장해 두면\n한 번에 돌아올 수 있어요."))
                    .font(.system(size: ringFont(11))).foregroundStyle(NativeSurfaceStyle.secondaryText)
            }.multilineTextAlignment(.center).frame(width: 250).position(x: geometry.midpoint, y: 74)
                .accessibilityIdentifier("wheel-empty-guidance")
            VStack(spacing: 7) {
                if live.displayIDs.isEmpty {
                    Text(copy.noDisplays).font(.system(size: ringFont(11))).multilineTextAlignment(.center)
                } else {
                    ForEach(Array(live.displayIDs.prefix(2)), id: \.self) { id in
                        VStack(spacing: 2) {
                            Text(live.displayNames[id] ?? id).font(.system(size: ringFont(10, minimum: 10)))
                                .foregroundStyle(NativeSurfaceStyle.secondaryText)
                            Text(currentSpaceTitle(id)).font(.system(size: ringFont(12), weight: .medium))
                        }.lineLimit(1).help((live.displayNames[id] ?? id) + " · " + currentSpaceTitle(id))
                            .accessibilityIdentifier("wheel-empty-space-" + id)
                    }
                    if live.displayIDs.count > 2 {
                        Text(text("and \(live.displayIDs.count - 2) more displays", "외 모니터 \(live.displayIDs.count - 2)대"))
                            .font(.system(size: ringFont(10, minimum: 10))).foregroundStyle(NativeSurfaceStyle.secondaryText)
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
        let button = Button { choose(column) } label: { surface }
        let accessibilityName = column.name + " · " + connectionSummary(column)
        return ZStack {
            button.buttonStyle(.plain).focusEffectDisabled().disabled(!enabled)
                .focused($focused, equals: column.id)
                .help(column.name + "\n" + connectionSummary(column))
                .accessibilityLabel(accessibilityName)
                .accessibilityIdentifier("wheel-go-" + column.id)
                .opacity(draggedConnection?.contextID == column.id ? 0.45 : 1)
            if focused == column.id {
                shape.stroke(NativeSurfaceStyle.primaryText, style: StrokeStyle(lineWidth: 4, dash: [3, 3]))
                    .clipShape(shape).allowsHitTesting(false)
            }
            if dropIndex == index {
                shape.stroke(NativeSurfaceStyle.accent, style: StrokeStyle(lineWidth: 5, dash: [5, 3]))
                    .clipShape(shape).allowsHitTesting(false)
            }
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
                .opacity(visibleToolIndices.contains(index) ? 1 : 0).allowsHitTesting(visibleToolIndices.contains(index))
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
        return VStack(spacing: compactRing ? 2 : 4) {
            Text(column.name)
                .font(.system(size: ringFont(HeldWorkspaceWheelLayout.nameFontSize(count: columns.count), minimum: 13), weight: .semibold))
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
        }.font(.system(size: ringFont(11, minimum: 10))).lineLimit(1)
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
            .overlay {
                if focused == id {
                    RoundedRectangle(cornerRadius: 4).inset(by: 2)
                        .strokeBorder(NativeSurfaceStyle.primaryText, lineWidth: 2).allowsHitTesting(false)
                }
            }
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
                        .onDrop(of: [UTType.plainText], delegate: pageDrop(-1))
                    Text(text("\(live.columns.count) connections", "연결 \(live.columns.count)개") + " · \(page + 1)/\(HeldWorkspaceWheelLayout.pageCount(live.columns.count))")
                    Button { changePage(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 22) }
                        .disabled(page == HeldWorkspaceWheelLayout.pageCount(live.columns.count) - 1)
                        .accessibilityLabel(copy.next).accessibilityIdentifier("wheel-next-page")
                        .onDrop(of: [UTType.plainText], delegate: pageDrop(1))
                }.buttonStyle(.plain).pointingHandCursor().font(.system(size: 11))
                    .padding(.horizontal, 9).background(NativeSurfaceStyle.windowBackground, in: Capsule())
            }
            HStack(spacing: 8) {
              Group {
                if draggedConnection != nil {
                    Text(dropIndex.flatMap { columns.indices.contains($0) ? columns[$0] : nil }
                        .map { text("Move to \($0.name)’s position", "\($0.name) 위치로 순서 변경") }
                        ?? text("Drag onto another sector · Esc to cancel", "다른 칸에 놓아 순서 변경 · Esc로 취소"))
                        .foregroundStyle(NativeSurfaceStyle.primaryText)
                } else if let recovery {
                    VStack(spacing: 1) {
                        Text(recovery.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                        Text(recovery.message(language: model.settings.language,
                            displayNames: recovery.displayIDs.map { model.displayName(for: $0) })).lineLimit(1)
                    }.foregroundStyle(.orange).help(recoveryDescription(recovery))
                        .accessibilityElement(children: .ignore).accessibilityLabel(recoveryDescription(recovery))
                        .accessibilityIdentifier("wheel-recovery-message")
                } else if showsFeedback, let message = model.workspaceSaveMessage {
                    Text(message).foregroundStyle(model.workspaceSaveFeedbackKind == .failure ? Color.orange : NativeSurfaceStyle.secondaryText)
                        .accessibilityIdentifier("held-add-feedback")
                } else if let status {
                    Text(status).foregroundStyle(.orange)
                } else if let column = columns.first(where: { $0.id == activeID }) {
                    VStack(spacing: 1) {
                        Text(column.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                        Text(connectionSummary(column).components(separatedBy: "\n").first ?? "").lineLimit(1)
                    }.help(column.name + "\n" + connectionSummary(column))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(column.name + "\n" + connectionSummary(column))
                        .accessibilityIdentifier("wheel-connection-summary")
                } else {
                    Text(idleGuidance)
                        .foregroundStyle(NativeSurfaceStyle.secondaryText)
                        .accessibilityIdentifier("wheel-idle-guidance")
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
                Button { pin(); edit(nil) } label: {
                    Label(text("Edit connections", "연결 편집"), systemImage: "slider.horizontal.3")
                        .padding(.horizontal, 8).frame(height: 28)
                        .background(NativeSurfaceStyle.windowBackground, in: Capsule())
                }.disabled(model.isSwitching).accessibilityIdentifier("held-edit-connections")
                if let recovery {
                    Button(recovery.actionTitle(language: model.settings.language)) {
                        pin(); showsFeedback = false
                        model.performHeldWorkspaceRecovery(recovery, select: select, edit: { edit($0) })
                    }.padding(.horizontal, 8).frame(height: 28)
                        .background(NativeSurfaceStyle.windowBackground, in: Capsule())
                        .help(recoveryDescription(recovery))
                        .accessibilityLabel(recovery.actionTitle(language: model.settings.language) + " · " + recovery.name)
                        .accessibilityIdentifier("wheel-recovery-action")
                } else {
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
                }
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
        if model.isSwitching || model.contextCaptureSession != nil || model.pendingContextCaptureAlignment != nil { return copy.busy }
        if model.permissionState != .granted || !model.hasSwitchingAccess { return copy.permission }
        if live.displayIDs.isEmpty { return copy.noDisplays }
        return nil
    }

    private var idleGuidance: String {
        if live.columns.isEmpty {
            return text("Start with Add current setup in the center.", "가운데 ‘현재 상태 추가하기’로 첫 연결을 만드세요.")
        }
        if live.columns.count == 1, let column = live.columns.first {
            if needsSpaceSelection(column) { return text("Choose this connection to check its Spaces.", "이 연결을 눌러 Space를 확인하세요.") }
            if spacesAlreadyVisible(column) { return text("Choose this connection to return after working elsewhere.", "다른 Space에서 작업한 뒤 이 연결로 돌아오세요.") }
            return text("Choose this connection to move its assigned displays together.", "이 연결을 누르면 배정한 모니터가 함께 이동합니다.")
        }
        return text("Click to switch · Drag sectors to reorder", "클릭으로 이동 · 칸을 드래그해 순서 변경")
    }

    private func choose(_ column: HeldWorkspaceColumn) {
        guard draggedConnection == nil, canChoose(column) else { return }
        if model.verifiedCurrentWorkspaceID == column.id { close() }
        else if needsSpaceSelection(column) {
            guard model.canChangeSavedWorkspaces,
                  let context = model.settings.contextPlan.contexts.first(where: { $0.id == column.id }) else { return }
            let missing = model.unresolvedWorkspaceMembers(context)
            let displayID = live.displayIDs.first { missing.contains($0) }
            pin(); edit(ConnectionEditorRevealRequest(contextID: column.id, displayID: displayID))
        }
        else { select(column) }
    }

    private func finishDrag() {
        pageHoverTask?.cancel(); pageHoverTask = nil
        draggedConnection = nil; dropIndex = nil; interactionTarget = nil
    }

    private func pageDrop(_ offset: Int) -> WheelPageDropDelegate {
        WheelPageDropDelegate(enabled: draggedConnection?.session == dragSession && model.canChangeSavedWorkspaces
            && (offset < 0 ? page > 0 : page < HeldWorkspaceWheelLayout.pageCount(live.columns.count) - 1),
            entered: {
                pageHoverTask?.cancel()
                let id = draggedConnection?.id
                pageHoverTask = Task { @MainActor in
                    do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                    guard draggedConnection?.id == id, id != nil else { return }
                    dropIndex = nil; changePage(offset)
                }
            }, exited: { pageHoverTask?.cancel(); pageHoverTask = nil })
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

/// NSPanel handles cancelOperation before the SwiftUI root when a button owns
/// keyboard focus. Give an open dialog first refusal, then close the panel.
private struct WheelEscapeHandler: NSViewRepresentable {
    var isEnabled = true
    let cancel: () -> Bool
    func makeNSView(context: Context) -> HandlerView { HandlerView() }
    func updateNSView(_ view: HandlerView, context: Context) { view.cancel = cancel; view.isEnabled = isEnabled; view.install() }
    static func dismantleNSView(_ view: HandlerView, coordinator: ()) {
        if let panel = view.window as? HeldMatrixPanel, panel.cancelContentOwner === view {
            panel.cancelContent = nil; panel.cancelContentOwner = nil
        }
    }
    final class HandlerView: NSView {
        var isEnabled = true
        var cancel: (() -> Bool)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); install() }
        func install() {
            guard let panel = window as? HeldMatrixPanel else { return }
            guard isEnabled else {
                if panel.cancelContentOwner === self { panel.cancelContent = nil; panel.cancelContentOwner = nil }
                return
            }
            panel.cancelContentOwner = self
            panel.cancelContent = { [weak self] in self?.cancel?() ?? false }
        }
    }
}

private struct WheelPageDropDelegate: DropDelegate {
    let enabled: Bool
    let entered: () -> Void
    let exited: () -> Void
    func validateDrop(info: DropInfo) -> Bool { enabled && info.hasItemsConforming(to: [UTType.plainText]) }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { entered() } }
    func dropExited(info: DropInfo) { exited() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: enabled ? .move : .forbidden) }
    func performDrop(info: DropInfo) -> Bool { exited(); return false }
}
