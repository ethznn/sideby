import AppKit
import SidebyCore
import SidebyUI
import SwiftUI
import UniformTypeIdentifiers

/// The same editor is used in Settings and in the menu panel.
struct WorkspaceMatrixView: View {
    @ObservedObject var model: SidebyAppModel
    var compact = false
    var showsDisconnected = false
    var focusContextID: String?
    var focusDisplayID: String?
    @State private var nameMessage: String?
    @State private var displayWidth: CGFloat = 150
    @State private var resizeStart: CGFloat?
    @State private var activeDrag: WorkspaceMatrixDrag?
    @State private var pendingDeletionID: String?
    @State private var hoveredDisplayID: String?
    @FocusState private var focusedName: String?
    private var copy: WorkspaceMatrixStrings { .init(language: model.settings.language) }
    private var strings: SettingsRefreshStrings { .init(language: model.settings.language) }
    private let rowHeight: CGFloat = 48
    private let headerHeight: CGFloat = 74
    private var columnWidth: CGFloat { compact ? 156 : 184 }
    private var connectedIDs: Set<String> { Set(model.displayLayout.displays.map(\.id)) }
    private var contexts: [ContextDefinition] {
        showsDisconnected ? model.settings.contextPlan.contexts.sorted { $0.order < $1.order }
            : WorkspaceContextVisibility.contexts(in: model.settings.contextPlan, connectedDisplayIDs: connectedIDs)
    }
    private var displayIDs: [String] {
        WorkspaceTablePresentation.displayIDs(connected: model.displayLayout.displays.map(\.id),
            remembered: Array(model.settings.displaySelection.knownDisplayNames.keys),
            assigned: model.settings.contextPlan.contexts.flatMap(\.displayIDs), order: model.settings.displayRowOrder,
            includeDisconnected: showsDisconnected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(copy.title).fontWeight(.semibold).accessibilityAddTraits(.isHeader)
                if model.isSwitching || model.contextCaptureSession != nil || model.pendingContextCaptureAlignment != nil {
                    ProgressView().controlSize(.small)
                    Text(model.isSwitching ? copy.moving : DailyRefreshStrings(language: model.settings.language).busy)
                        .font(.system(size: NativeSurfaceStyle.metadataSize))
                        .foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1)
                        .help(model.workspaceSwitchTargetName.map(model.strings.workspaceMovingTo)
                              ?? DailyRefreshStrings(language: model.settings.language).busy)
                }
                Spacer(minLength: 4)
                Button { model.addEmptyContext() } label: { Label(strings.addWorkspace, systemImage: "plus") }
                    .pointingHandCursor().disabled(!model.canAddContext)
            }
            Text(copy.help).font(.system(size: NativeSurfaceStyle.descriptionSize)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if model.heldMatrixConfiguration.isEnabled, model.heldMatrixShortcutError == nil {
                Text(HeldMatrixStrings(language: model.settings.language).discover(
                    KeyboardShortcutFormatter.shortcutText(model.heldMatrixConfiguration.shortcut)))
                    .font(.system(size: NativeSurfaceStyle.metadataSize)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let nameMessage {
                Text(nameMessage).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollViewReader { verticalProxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(copy.workspaces)
                                Text(copy.displays)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NativeSurfaceStyle.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(height: headerHeight)
                            ForEach(displayIDs, id: \.self) { id in displayLabel(id).id("display-" + id) }
                        }
                        .frame(width: displayWidth)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(NativeSurfaceStyle.separator).frame(width: 2)
                                .padding(.vertical, 4).frame(width: 10).contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if resizeStart == nil { resizeStart = displayWidth }
                                        displayWidth = min(260, max(100, (resizeStart ?? displayWidth) + value.translation.width))
                                    }.onEnded { _ in resizeStart = nil })
                                .interactionCursor(.resizeLeftRight)
                                .help(copy.resize).offset(x: 6)
                        }
                        ScrollViewReader { horizontalProxy in
                            ScrollView(.horizontal) {
                                HStack(alignment: .top, spacing: 8) {
                                    ForEach(contexts) { context in
                                        VStack(spacing: 8) {
                                            contextHeader(context).frame(height: headerHeight).id("context-" + context.id)
                                            ForEach(displayIDs, id: \.self) { id in cell(context, displayID: id) }
                                        }.frame(width: columnWidth)
                                    }
                                }.padding(.bottom, 8)
                            }
                            .onAppear { revealContext(horizontalProxy) }
                            .onChange(of: focusContextID) { _, _ in revealContext(horizontalProxy) }
                        }
                    }.padding(8)
                }
                .onAppear { revealDisplay(verticalProxy) }
                .onChange(of: focusDisplayID) { _, _ in revealDisplay(verticalProxy) }
            }
            .background(NativeSurfaceStyle.tableBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NativeSurfaceStyle.frameBorder, lineWidth: 1))
            .accessibilityIdentifier("workspace-assignment-table")
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText)
        .font(.system(size: 13))
        .onAppear { model.loadWorkspaceNamesIfNeeded() }
        .task {
            // Only while an editor is presented. Mission Control can reorder a
            // non-current Space without sending an active-Space notification.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
                guard model.canAddContext, model.pendingContextCaptureAlignment == nil else { continue }
                let previous = model.workspaceLastObservedSpaceIDs
                model.refreshWorkspaceStatus()
                if previous != model.workspaceLastObservedSpaceIDs { model.loadWorkspaceNamesIfNeeded() }
            }
        }
        .confirmationDialog(model.strings.deleteContextConfirmationTitle(deletionName), isPresented: Binding(
            get: { pendingDeletionID != nil }, set: { if !$0 { pendingDeletionID = nil } }
        )) {
            Button(strings.deleteWorkspace, role: .destructive) {
                if let id = pendingDeletionID { _ = model.deleteContext(contextID: id) }
                pendingDeletionID = nil
            }
            Button(model.strings.cancel, role: .cancel) { pendingDeletionID = nil }
        } message: { Text(model.strings.deleteContextConfirmationMessage) }
    }

    private func displayLabel(_ id: String) -> some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName(for: id)).fontWeight(.medium).lineLimit(2)
                if !connectedIDs.contains(id) { Text(strings.offline).font(.system(size: 11)).foregroundStyle(.secondary) }
                else if !model.selectedDisplayIDs.contains(id) { Text(strings.excluded).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 6).frame(height: rowHeight)
        .background(hoveredDisplayID == id ? NativeSurfaceStyle.hoverBackground : .clear,
                    in: RoundedRectangle(cornerRadius: NativeSurfaceStyle.rowCornerRadius))
        .contentShape(Rectangle())
        .onHover { hoveredDisplayID = $0 && model.canEditWorkspaceDisplay(id) ? id : nil }
        .interactionCursor(.openHand, isEnabled: model.canEditWorkspaceDisplay(id))
        .help(copy.reorder + " · " + model.displayName(for: id))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.displayName(for: id))
        .accessibilityActions { displayReorderCommands(id) }
        .contextMenu { displayReorderCommands(id) }
        .onDrag {
            guard model.canEditWorkspaceDisplay(id) else { return NSItemProvider() }
            activeDrag = .display(id)
            return NSItemProvider(object: ("display-row|" + id) as NSString)
        }
        .onDrop(of: [UTType.plainText], delegate: WorkspaceDisplayRowDropDelegate(
            model: model, displayID: id, activeDrag: $activeDrag))
    }

    @ViewBuilder private func displayReorderCommands(_ id: String) -> some View {
        ForEach(displayIDs.filter { $0 != id && connectedIDs.contains($0) }, id: \.self) { target in
            Button(copy.reorder + " · " + model.displayName(for: target)) {
                model.moveContextDisplayRow(displayID: id, to: target)
            }.disabled(!model.canEditWorkspaceDisplay(id))
        }
    }

    private func contextHeader(_ context: ContextDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NativeInlineNameField(identity: context.id, value: context.name, label: strings.workspaceName, compact: true) {
                model.setContextName(contextID: context.id, name: $0)
            }.focused($focusedName, equals: context.id).disabled(!model.canAddContext)
            HStack(spacing: 4) {
                Button { model.activateContext(contextID: context.id) } label: {
                    HStack(spacing: 5) {
                        Text(model.strings.goToContext)
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered).controlSize(.small).fixedSize()
                .accessibilityLabel(model.strings.workspaceGoTo(context.name))
                .pointingHandCursor().disabled(!model.canActivateContext || !model.isWorkspaceAssignmentAvailable(contextID: context.id))
                Spacer(minLength: 2)
                if model.verifiedCurrentWorkspaceID == context.id {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        Text(copy.current)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NativeSurfaceStyle.primaryText).fixedSize()
                    .help(strings.currentWorkspace)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(strings.currentWorkspace)
                }
                Menu {
                    if let shortcut = model.workspaceRows.first(where: { $0.id == context.id })?.shortcut { Text(shortcut) }
                    Button(DailyRefreshStrings(language: model.settings.language).useDesktopName) {
                        let copy = DailyRefreshStrings(language: model.settings.language)
                        if model.useDesktopContentName(contextID: context.id),
                           let updated = model.settings.contextPlan.contexts.first(where: { $0.id == context.id }) {
                            nameMessage = copy.workspaceNamed(updated.name)
                        } else { nameMessage = copy.desktopNameUnavailable }
                    }.disabled(!model.canAddContext || model.pendingContextCaptureAlignment != nil)
                    Button(strings.deleteWorkspace, role: .destructive) {
                        if model.contextDeletionRequiresConfirmation(contextID: context.id) { pendingDeletionID = context.id }
                        else { _ = model.deleteContext(contextID: context.id) }
                    }.disabled(!model.canDeleteContext)
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel(context.name + " · " + strings.workspaces)
                .help(context.name + " · " + strings.workspaces)
                .pointingHandCursor()
            }.font(.system(size: 12)).frame(height: 24)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.verifiedCurrentWorkspaceID == context.id ? NativeSurfaceStyle.selectionBackground : .clear,
                    in: RoundedRectangle(cornerRadius: NativeSurfaceStyle.rowCornerRadius))
    }

    private func cell(_ context: ContextDefinition, displayID: String) -> some View {
        WorkspaceMatrixCell(model: model, context: context, displayID: displayID, activeDrag: $activeDrag)
            .frame(height: rowHeight)
    }
    private var deletionName: String { contexts.first { $0.id == pendingDeletionID }?.name ?? "" }
    private func revealContext(_ proxy: ScrollViewProxy) {
        guard let id = focusContextID else { return }
        DispatchQueue.main.async { proxy.scrollTo("context-" + id, anchor: .center); focusedName = id }
    }
    private func revealDisplay(_ proxy: ScrollViewProxy) {
        guard let id = focusDisplayID else { return }
        DispatchQueue.main.async { proxy.scrollTo("display-" + id, anchor: .center) }
    }
}

private struct WorkspaceMatrixCell: View {
    @ObservedObject var model: SidebyAppModel
    let context: ContextDefinition
    let displayID: String
    @Binding var activeDrag: WorkspaceMatrixDrag?
    @State private var isDropTarget = false
    @State private var isHovered = false
    @State private var nameEditTarget: DesktopNameEditTarget?
    @State private var nameError: String?
    private var nameCopy: DesktopNameStrings { .init(language: model.settings.language) }
    private var copy: WorkspaceMatrixStrings { .init(language: model.settings.language) }
    private var strings: SettingsRefreshStrings { .init(language: model.settings.language) }
    private var index: Int? { context.spaceIndex(for: displayID) }
    private var enabled: Bool { model.canEditWorkspaceDisplay(displayID) }
    private var desktopLabel: String { index.map(strings.desktop) ?? strings.noAssignment }
    private var spaceName: String? { index.flatMap { model.workspaceDesktopName(displayID: displayID, spaceIndex: $0) } }
    private var title: String { spaceName ?? desktopLabel }
    private var fullLabel: String { spaceName.map { $0 + " · " + desktopLabel } ?? desktopLabel }
    private var sharedCount: Int { index.map { i in model.settings.contextPlan.contexts.filter { $0.spaceIndex(for: displayID) == i }.count } ?? 0 }
    private var payload: WorkspaceSpaceDragPayload? { index.map { .init(sourceContextID: context.id, displayID: displayID, spaceIndex: $0) } }

    var body: some View {
        HStack(spacing: 0) {
            if let payload, enabled {
                face.onDrag {
                    activeDrag = .desktop(payload)
                    return payload.itemProvider
                }
            } else { face }
            Menu { commands } label: { Image(systemName: "chevron.down").frame(width: 24, height: 34) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().pointingHandCursor().disabled(!enabled)
                .accessibilityLabel(context.name + " · " + model.displayName(for: displayID) + " · " + nameCopy.actions)
                .accessibilityValue(fullLabel)
        }
        .background(isDropTarget ? NativeSurfaceStyle.selectionBackground :
                    isHovered && enabled ? NativeSurfaceStyle.hoverBackground :
                    index == nil ? NativeSurfaceStyle.inputBackground : NativeSurfaceStyle.itemBackground,
                    in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isDropTarget ? Color.accentColor : NativeSurfaceStyle.itemBorder,
                                                               lineWidth: isDropTarget ? 2 : 1))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrop(of: [WorkspaceSpaceDragPayload.typeIdentifier], delegate: WorkspaceMatrixDropDelegate(
            model: model, contextID: context.id, displayID: displayID, activeDrag: $activeDrag, isTargeted: $isDropTarget))
        .contextMenu { commands }
        .popover(item: $nameEditTarget, arrowEdge: .bottom) { target in
            DesktopNameEditor(model: model, target: target) { nameEditTarget = nil }.id(target.id)
        }
        .alert(nameCopy.title, isPresented: Binding(get: { nameError != nil }, set: { if !$0 { nameError = nil } })) {
            Button("OK") { nameError = nil }
        } message: { Text(nameError ?? "") }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isDropTarget ? (NSEvent.modifierFlags.contains(.option) ? copy.dropCopy : index == nil ? copy.dropMove : copy.dropSwap) : title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(index == nil && !isDropTarget ? NativeSurfaceStyle.secondaryText : NativeSurfaceStyle.primaryText)
                .lineLimit(1)
            HStack(spacing: 4) {
                if spaceName != nil { Text(desktopLabel) }
                if let index, let count = model.workspaceObservedDisplays?.first(where: { $0.displayID == displayID })?.spaceCount,
                   index >= count { Text(strings.invalidDesktop) }
                else if sharedCount > 1 { Label(copy.shared, systemImage: "link") }
            }.font(.system(size: NativeSurfaceStyle.metadataSize)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1)
        }
        .padding(.leading, 10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(context.name + " · " + model.displayName(for: displayID) + " · " + fullLabel)
        .help(fullLabel)
        .interactionCursor(.openHand, isEnabled: enabled && index != nil)
    }

    private func desktopChoiceLabel(_ choice: WorkspaceAssignmentChoice) -> String {
        let name = model.workspaceDesktopName(displayID: displayID, spaceIndex: choice.spaceIndex) ?? ""
        return name.isEmpty ? strings.desktop(choice.spaceIndex) : strings.desktop(choice.spaceIndex) + " · " + name
    }

    @ViewBuilder private var commands: some View {
        if let index {
            Button(nameCopy.rename) {
                if let target = model.prepareDesktopNameEdit(displayID: displayID, spaceIndex: index) {
                    nameEditTarget = target
                } else { nameError = nameCopy.unavailable }
            }.disabled(!enabled)
            if model.desktopAlias(displayID: displayID, spaceIndex: index) != nil {
                Button(nameCopy.automatic) {
                    guard let target = model.prepareDesktopNameEdit(displayID: displayID, spaceIndex: index) else {
                        nameError = nameCopy.unavailable
                        return
                    }
                    nameError = nameCopy.failure(model.saveDesktopName(nil, target: target))
                }.disabled(!enabled)
            }
            Divider()
        }
        Text(copy.assign)
        ForEach(model.workspaceDesktopChoices(displayID: displayID)) { choice in
            Button(desktopChoiceLabel(choice)) {
                model.assignWorkspaceDesktop(displayID: displayID, spaceIndex: choice.spaceIndex, toContextID: context.id)
            }.disabled(!enabled || choice.spaceIndex == index)
        }
        if let payload {
            Divider()
            Menu(copy.share) {
                ForEach(model.settings.contextPlan.contexts.filter { $0.id != context.id }) { target in
                    Button(target.name) {
                        model.dropWorkspaceDesktop(payload, targetDisplayID: displayID, targetContextID: target.id, copying: true)
                    }.disabled(!enabled || target.spaceIndex(for: displayID) == index)
                }
            }
            Menu(copy.move) {
                ForEach(model.settings.contextPlan.contexts.filter { $0.id != context.id }) { target in
                    Button(target.name) {
                        model.dropWorkspaceDesktop(payload, targetDisplayID: displayID, targetContextID: target.id, copying: false)
                    }.disabled(!enabled || target.spaceIndex(for: displayID) == index)
                }
            }
            Button(copy.clear) { model.assignWorkspaceDesktop(displayID: displayID, spaceIndex: nil, toContextID: context.id) }
                .disabled(!enabled)
        }
    }
}

private struct WorkspaceMatrixDropDelegate: DropDelegate {
    let model: SidebyAppModel
    let contextID: String
    let displayID: String
    @Binding var activeDrag: WorkspaceMatrixDrag?
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard case let .desktop(drag)? = activeDrag else { return false }
        return drag.displayID == displayID && drag.sourceContextID != contextID && model.canEditWorkspaceDisplay(displayID)
            && info.hasItemsConforming(to: [WorkspaceSpaceDragPayload.typeIdentifier])
    }
    func dropEntered(info: DropInfo) { isTargeted = validateDrop(info: info) }
    func dropExited(info: DropInfo) { isTargeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? (NSEvent.modifierFlags.contains(.option) ? .copy : .move) : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        defer { isTargeted = false; activeDrag = nil }
        guard validateDrop(info: info), case let .desktop(drag)? = activeDrag else { return false }
        guard let provider = info.itemProviders(for: [WorkspaceSpaceDragPayload.typeIdentifier]).first else { return false }
        let copying = NSEvent.modifierFlags.contains(.option)
        // Read the actual drag item as well as the local preview state. A canceled
        // drag must not let a subsequent text or display-row drop reuse its source.
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, let payload = WorkspaceSpaceDragPayload(rawValue: raw), payload == drag else { return }
            Task { @MainActor in
                model.dropWorkspaceDesktop(payload, targetDisplayID: displayID, targetContextID: contextID, copying: copying)
            }
        }
        return true
    }
}

/// Row reordering always moves. Closure-based onDrop uses the default copy
/// proposal, which incorrectly adds a + badge even without the Option key.
private struct WorkspaceDisplayRowDropDelegate: DropDelegate {
    let model: SidebyAppModel
    let displayID: String
    @Binding var activeDrag: WorkspaceMatrixDrag?

    func validateDrop(info: DropInfo) -> Bool {
        guard case let .display(source)? = activeDrag else { return false }
        return model.canEditWorkspaceDisplay(source) && model.canEditWorkspaceDisplay(displayID)
            && info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { activeDrag = nil }
        guard validateDrop(info: info), case let .display(source)? = activeDrag, source != displayID,
              let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, raw == "display-row|" + source else { return }
            Task { @MainActor in
                if model.canEditWorkspaceDisplay(source), model.canEditWorkspaceDisplay(displayID) {
                    model.moveContextDisplayRow(displayID: source, to: displayID)
                }
            }
        }
        return true
    }
}
