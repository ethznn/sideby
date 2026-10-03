import AppKit
import SidebyCore
import SidebyUI
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceSettingsView: View {
    @ObservedObject var model: SidebyAppModel
    @ObservedObject var navigation: ProductUINavigation
    let layout: WorkspaceTablePresentation
    @Binding var selection: WorkspaceSettingsSelection
    @State private var showsDisconnected = false
    @State private var selectedDesktop: WorkspaceDesktopReference?
    @State private var drag: WorkspaceComposerDrag?
    @State private var dropContext: String?
    @State private var dropDisplay: String?
    @State private var dropAfter = false
    @State private var horizontalOffset: CGFloat = 0
    @State private var focusID: String?
    @State private var picking: String?
    @State private var naming: ComposerNameRequest?
    @State private var deleting: WorkspaceComposerEntry?
    @State private var session = UUID()
    private let labelWidth: CGFloat = 140
    private let columnWidth: CGFloat = 174
    private let sourceHeight: CGFloat = 64
    private let rowHeight: CGFloat = 76
    private let headerHeight: CGFloat = 64
    private var copy: WorkspaceSaveStrings { model.saveCopy }
    private var entries: [WorkspaceComposerEntry] { model.workspaceComposerDraft?.state.entries ?? [] }
    private var sourceIDs: [String] { model.connectedWorkspaceDisplayIDs }
    private var displayIDs: [String] {
        WorkspaceTablePresentation.displayIDs(connected: sourceIDs, remembered: [],
            assigned: entries.flatMap { $0.members.keys }, order: model.settings.displayRowOrder,
            includeDisconnected: showsDisconnected)
    }
    private var activeDesktop: WorkspaceDesktopReference? { drag?.desktop ?? selectedDesktop }
    private var observation: WorkspaceLayoutObservation? { model.workspaceComposerDraft?.observation }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 8) {
                intro
                sectionTitle(copy.text("Desktops by display", "화면별 데스크탑"), count: sourceIDs.count) {
                    Button { model.refreshWorkspaceStatus(); model.refreshWorkspaceComposer(); model.loadWorkspaceNamesIfNeeded(); model.refreshWorkspaceComposerNames() } label: {
                        Image(systemName: "arrow.clockwise")
                    }.buttonStyle(.plain).pointingHandCursor().help(copy.readAgain)
                }
                sources.frame(height: min(CGFloat(max(1, sourceIDs.count)) * sourceHeight + 2, max(64, min(208, geometry.size.height - 364))))
                Text(hint).font(.system(size: 11)).foregroundStyle(activeDesktop == nil ? NativeSurfaceStyle.secondaryText : NativeSurfaceStyle.accent)
                    .lineLimit(2).frame(minHeight: 26, alignment: .leading).accessibilityIdentifier("composer-hint")
                sectionTitle(copy.savedWorkspaces, count: entries.count) {
                    Button { naming = .init(contextID: nil, name: nextName, useCurrent: false) } label: {
                        Label(copy.text("New setup", "새 구성"), systemImage: "plus")
                    }.controlSize(.small).disabled(!model.canEditWorkspaceComposer).pointingHandCursor()
                        .accessibilityIdentifier("composer-add")
                }
                matrix.frame(minHeight: 140, maxHeight: .infinity)
                HStack {
                    Toggle(copy.text("Show saved connections on disconnected displays", "연결되지 않은 화면의 저장 정보 보기"), isOn: $showsDisconnected)
                        .toggleStyle(.checkbox).pointingHandCursor().font(.system(size: 10))
                    Spacer(minLength: 0)
                    Text(copy.text("Shortcuts stay with their setups.", "순서를 바꿔도 숫자 단축키는 유지됩니다."))
                        .font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(2)
                }
                DisclosureGroup(copy.text("Display participation", "함께 움직일 화면 설정")) {
                    NativeDisplaySelector(displays: model.displayLayout.displays, selectedIDs: model.selectedDisplayIDs,
                        language: model.settings.language, isEnabled: model.canEditWorkspaceComposer && !model.hasWorkspaceComposerChanges,
                        setSelected: { model.setDisplayTarget($0, isSelected: $1) })
                    if model.hasWorkspaceComposerChanges { Text(copy.text("Save or cancel the draft before changing participating displays.", "편집을 저장하거나 취소한 뒤 함께 움직일 화면을 변경하세요.")).font(.system(size: 11)) }
                }.font(.system(size: 11))
            }
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText).tint(NativeSurfaceStyle.accent)
        .background(WorkspaceDragCompletion(dragID: drag?.id) { drag = nil; dropContext = nil; dropDisplay = nil })
        .onAppear { model.beginWorkspaceComposer(); revealRoute(navigation.settingsRoute) }
        .onReceive(navigation.$settingsRoute) { revealRoute($0) }
        .onChange(of: model.settings.contextPlan.contexts) { _, _ in model.refreshWorkspaceComposer() }
        .onChange(of: model.workspaceObservedDisplays) { _, _ in model.refreshWorkspaceComposer() }
        .onChange(of: model.displayLayout) { _, _ in model.refreshWorkspaceComposer(); selectedDesktop = nil; drag = nil }
        .onExitCommand { selectedDesktop = nil; drag = nil; dropContext = nil }
        .sheet(item: $naming) { request in
            ComposerNameSheet(copy: copy, request: request) { name in
                if let id = request.contextID {
                    model.editWorkspaceComposer { state in
                        if let i = state.entries.firstIndex(where: { $0.id == id }) { state.entries[i].name = name }
                    }
                } else { focusID = model.addWorkspaceComposer(name: name, useCurrent: request.useCurrent) }
                naming = nil
            } cancel: { naming = nil }
        }
        .confirmationDialog(deleting.map { copy.deleteTitle($0.name) } ?? copy.delete,
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(copy.delete, role: .destructive) {
                    if let id = deleting?.id { model.editWorkspaceComposer { state in state.entries.removeAll { $0.id == id }; state.slots.removeValue(forKey: id) } }
                    deleting = nil
                }
                Button(copy.cancel, role: .cancel) { deleting = nil }
            } message: { Text(copy.text("This setup will be removed when you save changes. Desktops and apps remain open.", "변경사항을 저장하면 이 구성이 삭제됩니다. 데스크탑과 앱은 그대로 유지됩니다.")) }
    }

    private var intro: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.text("Manage setups", "구성 관리")).font(.system(size: 23, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text(copy.text("Connect desktops above to setups below.", "위에서 데스크탑을 골라 아래 구성에 연결하세요."))
                    .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            }
            Spacer(minLength: 0)
            Button { naming = .init(contextID: nil, name: nextName, useCurrent: true) } label: {
                Label(copy.text("Add current setup", "현재 화면으로 구성 추가"), systemImage: "plus")
            }.font(.system(size: 11)).disabled(!model.canEditWorkspaceComposer).pointingHandCursor()
                .accessibilityIdentifier("composer-capture")
        }.padding(.bottom, 6)
    }

    private func sectionTitle<T: View>(_ title: String, count: Int, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text("· \(count)").font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            Spacer()
            trailing()
        }.frame(minHeight: 23)
    }

    private var sources: some View {
        ScrollView(.vertical) {
            if sourceIDs.isEmpty {
                Text(copy.readUnavailable).font(.system(size: 12)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(sourceIDs, id: \.self) { id in
                            displayLabel(id, subtitle: composerKeys(id).map { copy.text("\($0.count) desktops", "데스크탑 \($0.count)개") } ?? copy.text("Unable to read", "읽기 실패"))
                                .frame(height: sourceHeight).rowDivider()
                        }
                    }.frame(width: labelWidth)
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(sourceIDs, id: \.self) { id in
                                HStack(spacing: 7) {
                                    if let keys = composerKeys(id) {
                                        ForEach(Array(keys.enumerated()), id: \.element) { index, key in sourceCard(id, index: index, key: key) }
                                    } else {
                                        Text(copy.readUnavailable).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                                    }
                                }.padding(.horizontal, 10).frame(height: sourceHeight).frame(maxWidth: .infinity, alignment: .leading).rowDivider()
                            }
                        }
                    }
                }
            }
        }
        .background(NativeSurfaceStyle.headerBackground).composerBorder()
        .accessibilityIdentifier("composer-desktop-sources")
    }

    private func sourceCard(_ id: String, index: Int, key: String) -> some View {
        let reference = WorkspaceDesktopReference(displayID: id, key: key)
        let name = model.workspaceComposerDesktopName(displayID: id, spaceIndex: index)
        let current = observation?.displays.first { $0.displayID == id }?.currentSpaceIndex == index
        let chosen = activeDesktop == reference
        return Button { selectedDesktop = selectedDesktop == reference ? nil : reference; drag = nil } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(name ?? copy.desktop(index))
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(copy.desktop(index) + (current ? " · " + copy.current : ""))
                    .font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1)
            }.frame(width: 98, alignment: .leading).padding(.horizontal, 9).frame(height: 49)
                .background(chosen ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.tableBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(chosen ? NativeSurfaceStyle.accent : NativeSurfaceStyle.itemBorder))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!model.canEditWorkspaceComposer).interactionCursor(.openHand)
            .help([model.displayName(for: id), copy.desktop(index), name].compactMap { $0 }.joined(separator: " · "))
            .accessibilityLabel([model.displayName(for: id), copy.desktop(index), name].compactMap { $0 }.joined(separator: " · "))
            .accessibilityIdentifier("composer-source-\(id)-\(index)")
            .onDrag {
                let payload = WorkspaceComposerDrag(session: session, desktop: reference)
                drag = payload; selectedDesktop = nil
                return NSItemProvider(object: payload.rawValue as NSString)
            }
    }

    private var matrix: some View {
        GeometryReader { geometry in
            ScrollViewReader { vertical in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            if entries.isEmpty {
                                Text(copy.text("Add a setup, then connect desktops from above.", "새 구성을 추가한 뒤 위의 데스크탑을 연결하세요."))
                                    .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText).padding(28)
                                    .frame(maxWidth: .infinity)
                            } else {
                                HStack(alignment: .top, spacing: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(displayIDs, id: \.self) { id in
                                            displayLabel(id, subtitle: sourceIDs.contains(id)
                                                ? (model.selectedDisplayIDs.contains(id) ? copy.text("Connected", "연결됨") : copy.excluded) : copy.offline)
                                                .frame(height: rowHeight).rowDivider().id("composer-display-" + id)
                                        }
                                    }.frame(width: labelWidth)
                                    ScrollViewReader { horizontal in
                                        ScrollView(.horizontal) {
                                            HStack(alignment: .top, spacing: 0) {
                                                ForEach(entries) { entry in
                                                    VStack(spacing: 0) {
                                                        ForEach(displayIDs, id: \.self) { id in targetCell(entry, displayID: id) }
                                                    }.frame(width: columnWidth).id(entry.id)
                                                }
                                            }.background(WorkspaceHorizontalScrollOffset { horizontalOffset = $0 })
                                        }
                                            .onChange(of: focusID) { _, id in if let id { horizontal.scrollTo(id, anchor: .center) } }
                                            .onAppear { if let id = focusID { horizontal.scrollTo(id, anchor: .center) } }
                                    }
                                }
                            }
                        } header: {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(copy.text("Setups →", "구성 →")); Text(copy.text("Displays ↓", "화면 ↓"))
                                }.font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                                    .frame(width: labelWidth - 24, alignment: .leading).padding(.horizontal, 12).frame(height: headerHeight)
                                HStack(spacing: 0) {
                                    ForEach(entries) { entry in
                                        contextHeader(entry) { id in vertical.scrollTo("composer-display-" + id, anchor: .center) }
                                    }
                                }.offset(x: horizontalOffset).frame(width: max(0, geometry.size.width - labelWidth), alignment: .leading).clipped()
                            }.background(NativeSurfaceStyle.headerBackground)
                        }
                    }
                }
            }
        }
        .background(NativeSurfaceStyle.tableBackground).composerBorder().accessibilityIdentifier("workspace-assignment-table")
    }

    private func contextHeader(_ entry: WorkspaceComposerEntry, reveal: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                WorkspaceReorderHandle(name: entry.name, copy: copy, enabled: model.canEditWorkspaceComposer,
                    moveLeft: neighbor(entry.id, offset: -1).map { target in { move(entry.id, relativeTo: target, after: false) } },
                    moveRight: neighbor(entry.id, offset: 1).map { target in { move(entry.id, relativeTo: target, after: true) } },
                    startDrag: {
                        let payload = WorkspaceComposerDrag(session: session, contextID: entry.id)
                        drag = payload; selectedDesktop = nil
                        return NSItemProvider(object: payload.rawValue as NSString)
                    }).accessibilityIdentifier("composer-reorder-" + entry.id)
                Button { if let selectedDesktop { assign(selectedDesktop, to: entry.id) } else { naming = .init(contextID: entry.id, name: entry.name, useCurrent: false) } } label: {
                    Text(entry.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }.buttonStyle(.plain).pointingHandCursor().help(entry.name).disabled(!model.canEditWorkspaceComposer)
                Spacer(minLength: 0)
                Menu { contextMenu(entry) } label: { Image(systemName: "ellipsis").frame(width: 16, height: 20) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().pointingHandCursor()
                    .disabled(!model.canEditWorkspaceComposer).accessibilityLabel(entry.name + " · " + copy.edit)
            }
            HStack {
                Text(model.workspaceComposerDraft?.state.slots[entry.id].map { "⌥⇧\($0 == 10 ? 0 : $0)" } ?? copy.text("No shortcut", "단축키 없음"))
                Spacer(minLength: 0)
                if model.verifiedCurrentWorkspaceID == entry.id { Text("✓ " + copy.current).foregroundStyle(NativeSurfaceStyle.accent) }
            }.font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText)
        }.padding(.horizontal, 10).frame(width: columnWidth, height: headerHeight)
            .background(dropContext == entry.id ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.headerBackground)
            .overlay(alignment: .leading) { Rectangle().fill(NativeSurfaceStyle.frameBorder).frame(width: 0.5) }
            .overlay(alignment: dropAfter ? .trailing : .leading) {
                if dropContext == entry.id && drag?.contextID != nil { Rectangle().fill(NativeSurfaceStyle.accent).frame(width: 2) }
            }
            .onDrop(of: [UTType.plainText], delegate: dropDelegate(contextID: entry.id, displayID: nil, reveal: reveal))
            .onDrag {
                let payload = WorkspaceComposerDrag(session: session, contextID: entry.id)
                drag = payload; selectedDesktop = nil
                return NSItemProvider(object: payload.rawValue as NSString)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("composer-header-" + entry.id)
    }

    @ViewBuilder private func contextMenu(_ entry: WorkspaceComposerEntry) -> some View {
        Button(copy.text("Rename…", "이름 변경…")) { naming = .init(contextID: entry.id, name: entry.name, useCurrent: false) }
        let left = neighbor(entry.id, offset: -1), right = neighbor(entry.id, offset: 1)
        Button(copy.text("Move left", "왼쪽으로 이동")) { if let left { move(entry.id, relativeTo: left, after: false) } }.disabled(left == nil)
        Button(copy.text("Move right", "오른쪽으로 이동")) { if let right { move(entry.id, relativeTo: right, after: true) } }.disabled(right == nil)
        Divider()
        Button(copy.delete, role: .destructive) { deleting = entry }
    }

    private func targetCell(_ entry: WorkspaceComposerEntry, displayID id: String) -> some View {
        let reference = entry.members[id]
        let index = reference?.key.flatMap { composerKeys(id)?.firstIndex(of: $0) }
        let missing = sourceIDs.contains(id) && reference != nil && index == nil
        let name = reference == nil ? copy.keep : missing ? copy.text("Check desktop", "데스크탑 확인 필요")
            : index.flatMap { model.workspaceComposerDesktopName(displayID: id, spaceIndex: $0) } ?? reference.map { copy.desktop(index ?? $0.index) } ?? copy.keep
        let changed = reference != model.workspaceComposerDraft?.baseline.entries.first(where: { $0.id == entry.id })?.members[id]
        let highlighted = activeDesktop?.displayID == id
        let hovered = dropContext == entry.id && (dropDisplay == id || dropDisplay == nil) && highlighted
        return Button {
            if let selectedDesktop { assign(selectedDesktop, to: entry.id, displayID: id) }
            else { picking = entry.id + "|" + id }
        } label: {
            cellLabel(name, member: reference, index: index, changed: changed,
                      offline: !sourceIDs.contains(id), available: highlighted, hovered: hovered)
        }
            .buttonStyle(.plain)
            .disabled(!model.canEditWorkspaceComposer || (activeDesktop != nil && !highlighted))
            .popover(isPresented: Binding(get: { picking == entry.id + "|" + id }, set: { if !$0 { picking = nil } })) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name + " · " + model.displayName(for: id)).font(.system(size: 12, weight: .semibold)).padding(.bottom, 5)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if let keys = composerKeys(id) {
                                ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                                    Button {
                                        assign(.init(displayID: id, key: key), to: entry.id, displayID: id); picking = nil
                                    } label: {
                                        HStack {
                                            Text(model.workspaceComposerDesktopName(displayID: id, spaceIndex: index) ?? copy.desktop(index))
                                            Spacer()
                                            Text(copy.desktop(index)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                                            if reference?.key == key { Image(systemName: "checkmark") }
                                        }.frame(maxWidth: .infinity).padding(8).contentShape(Rectangle())
                                    }.buttonStyle(.plain).pointingHandCursor()
                                }
                            } else { Text(sourceIDs.contains(id) ? copy.readUnavailable : copy.remembered).font(.system(size: 11)).padding(8) }
                        }
                    }.frame(maxHeight: 260)
                    if reference != nil {
                        Divider()
                        Button(copy.keep) {
                            model.editWorkspaceComposer { state in
                                if let i = state.entries.firstIndex(where: { $0.id == entry.id }) { state.entries[i].members.removeValue(forKey: id) }
                            }
                            picking = nil
                        }.pointingHandCursor()
                    }
                }.padding(14).frame(width: 300)
            }
            .pointingHandCursor()
            .padding(9).frame(width: columnWidth, height: rowHeight)
            .background(highlighted ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.tableBackground)
            .rowDivider()
            .onDrop(of: [UTType.plainText], delegate: dropDelegate(contextID: entry.id, displayID: id))
            .help(entry.name + " · " + model.displayName(for: id) + " · " + name)
            .accessibilityLabel(entry.name + " · " + model.displayName(for: id) + " · " + name)
            .accessibilityValue(hovered ? copy.text("Release to connect", "놓으면 연결")
                : highlighted ? copy.text("Connection available", "연결 가능") : "")
            .accessibilityIdentifier("composer-cell-\(entry.id)-\(id)")
    }

    private func cellLabel(_ name: String, member: WorkspaceComposerMember?, index: Int?, changed: Bool,
                           offline: Bool, available: Bool, hovered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if changed { Circle().fill(NativeSurfaceStyle.accent).frame(width: 4, height: 4) }
                Image(systemName: hovered ? "arrow.down.circle.fill" : available ? "plus.circle" : "chevron.down")
                    .font(.system(size: available ? 12 : 8))
                    .foregroundStyle(available ? NativeSurfaceStyle.accent : NativeSurfaceStyle.secondaryText)
            }
            Text(hovered ? copy.text("Release to connect", "놓으면 연결")
                 : available ? (index.map { copy.desktop($0) + " · " } ?? "") + copy.text("Connection available", "연결 가능")
                 : member == nil ? copy.text("This display won't move", "이 화면은 이동하지 않음")
                 : offline ? copy.remembered : index.map(copy.desktop) ?? copy.text("Reconnect in this menu", "메뉴에서 다시 연결"))
                .font(.system(size: 10, weight: hovered ? .semibold : .regular))
                .foregroundStyle(available ? NativeSurfaceStyle.accent : NativeSurfaceStyle.secondaryText).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            .background(available || changed ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.windowBackground, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(available || changed ? NativeSurfaceStyle.accent : NativeSurfaceStyle.itemBorder,
                style: StrokeStyle(lineWidth: hovered ? 2 : available ? 1.2 : 0.7,
                                   dash: hovered ? [] : available || member == nil ? [4, 3] : [])))
            .contentShape(Rectangle())
    }

    private func displayLabel(_ id: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(model.displayName(for: id), systemImage: model.displayLayout.displays.first { $0.id == id }?.isBuiltin == true ? "laptopcomputer" : "display")
                .font(.system(size: 11, weight: .medium)).lineLimit(2)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText).lineLimit(1)
        }.padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(activeDesktop?.displayID == id ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.headerBackground)
            .help(model.displayName(for: id))
    }

    private var nextName: String { var n = 1; while entries.contains(where: { $0.name == copy.defaultName(n) }) { n += 1 }; return copy.defaultName(n) }
    private func composerKeys(_ id: String) -> [String]? { model.composerKeys(id, observation: observation) }
    private var hint: String {
        guard let reference = activeDesktop else { return copy.text("Drag a desktop down, or click it and choose a cell. Drag title handles to reorder setups.", "데스크탑을 아래로 끌거나 선택한 뒤 칸을 누르세요. 제목 옆 손잡이로 구성 순서를 바꿀 수 있어요.") }
        let index = composerKeys(reference.displayID)?.firstIndex(of: reference.key)
        let source = index.flatMap { model.workspaceComposerDesktopName(displayID: reference.displayID, spaceIndex: $0) } ?? index.map(copy.desktop) ?? copy.text("Desktop", "데스크탑")
        if let target = entries.first(where: { $0.id == dropContext }) {
            return target.name + " · " + model.displayName(for: reference.displayID) + ": " + source + " " + copy.text("will be connected", "연결")
        }
        return model.displayName(for: reference.displayID) + " · " + source + " — " + copy.text("Choose a highlighted cell or setup title.", "강조된 칸이나 구성 제목에 놓으세요.")
    }
    private func assign(_ reference: WorkspaceDesktopReference, to id: String, displayID: String? = nil) {
        if !model.assignWorkspaceComposer(reference, to: id, displayID: displayID) { model.workspaceComposerDraft?.error = copy.changed }
        selectedDesktop = nil; drag = nil; dropContext = nil
    }
    private func neighbor(_ id: String, offset: Int) -> String? {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries.indices.contains(i + offset) else { return nil }
        return entries[i + offset].id
    }
    private func move(_ id: String, relativeTo target: String, after: Bool) { model.editWorkspaceComposer { $0.move(id, relativeTo: target, after: after) } }
    private func dropDelegate(contextID: String, displayID: String?, reveal: @escaping (String) -> Void = { _ in }) -> WorkspaceComposerDropDelegate {
        .init(session: session, active: drag, contextID: contextID, displayID: displayID, enabled: model.canEditWorkspaceComposer,
            hover: { entered, after in
                if entered { dropContext = contextID; dropDisplay = displayID; dropAfter = after }
                else if dropContext == contextID { dropContext = nil }
                if entered, let id = drag?.desktop?.displayID { reveal(id) }
            },
            receive: { payload, after in
                if let reference = payload.desktop { assign(reference, to: contextID, displayID: displayID) }
                else if let id = payload.contextID { move(id, relativeTo: contextID, after: after) }
                drag = nil; dropContext = nil
            })
    }
    private func revealRoute(_ route: ProductSettingsRoute) {
        focusID = route.contextID
        if let id = route.displayID, !sourceIDs.contains(id) { showsDisconnected = true }
        selection.reconcile(contextIDs: entries.map(\.id), preferredID: route.contextID)
    }
}

struct WorkspaceComposerDropDelegate: DropDelegate {
    let session: UUID
    let active: WorkspaceComposerDrag?
    let contextID: String
    let displayID: String?
    let enabled: Bool
    var midpoint: CGFloat = 87
    let hover: (Bool, Bool) -> Void
    let receive: (WorkspaceComposerDrag, Bool) -> Void
    func validateDrop(info: DropInfo) -> Bool {
        guard enabled, let active, active.session == session, info.hasItemsConforming(to: [UTType.plainText]) else { return false }
        if let reference = active.desktop { return displayID == nil || reference.displayID == displayID }
        return displayID == nil && active.contextID != nil && active.contextID != contextID
    }
    func dropEntered(info: DropInfo) { if validateDrop(info: info) { hover(true, info.location.x > midpoint) } }
    func dropExited(info: DropInfo) { hover(false, false) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        hover(true, info.location.x > midpoint)
        return DropProposal(operation: active?.desktop == nil ? .move : .copy)
    }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        let after = info.location.x > midpoint
        provider.loadObject(ofClass: NSString.self) { object, _ in
            let raw = object as? String
            Task { @MainActor in
                guard let raw, let payload = WorkspaceComposerDrag(rawValue: raw), payload == active, payload.session == session else { hover(false, false); return }
                receive(payload, after)
            }
        }
        return true
    }
}

private struct ComposerNameRequest: Identifiable {
    let id = UUID()
    let contextID: String?
    let name: String
    let useCurrent: Bool
}

private struct ComposerNameSheet: View {
    let copy: WorkspaceSaveStrings
    let request: ComposerNameRequest
    let save: (String) -> Void
    let cancel: () -> Void
    @State private var name = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.contextID == nil ? copy.text("New setup", "새 구성") : copy.text("Rename setup", "구성 이름 변경")).font(.headline)
            TextField(copy.name, text: $name).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { if valid { save(name.trimmingCharacters(in: .whitespacesAndNewlines)) } }
            HStack { Spacer(); Button(copy.cancel, action: cancel).keyboardShortcut(.cancelAction).pointingHandCursor()
                Button(copy.text("Done", "확인")) { save(name.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .keyboardShortcut(.defaultAction).disabled(!valid).pointingHandCursor() }
        }.padding(24).frame(width: 360).onAppear { name = request.name; focused = true }
    }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 60 }
}

private extension View {
    func composerBorder() -> some View { clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(NativeSurfaceStyle.frameBorder)) }
    func rowDivider() -> some View { overlay(alignment: .bottom) { Rectangle().fill(NativeSurfaceStyle.frameBorder).frame(height: 0.5) } }
}

struct WorkspaceAssignmentReviewFooter: View {
    @ObservedObject var model: SidebyAppModel
    @ObservedObject var navigation: ProductUINavigation
    let finishAssignmentReview: () -> Void
    @State private var confirmsDiscard = false
    private var copy: WorkspaceSaveStrings { model.saveCopy }
    var body: some View {
        let draft = model.workspaceComposerDraft
        let error = draft?.error ?? draft.flatMap(model.workspaceComposerValidation)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(error != nil ? copy.text("Review before saving", "저장 전에 확인해 주세요") : model.hasWorkspaceComposerChanges
                    ? copy.text("Unsaved changes", "저장 전 변경사항이 있습니다") : copy.text("No unsaved changes", "저장한 구성과 같습니다"))
                    .font(.system(size: 12, weight: .medium))
                Text(error ?? model.workspaceSaveMessage ?? copy.text("Connections and order are saved together.", "연결과 순서 변경을 한 번에 저장합니다."))
                    .font(.system(size: 11)).foregroundStyle(error == nil ? NativeSurfaceStyle.secondaryText : .orange)
                    .lineLimit(2).help(error ?? "")
            }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("composer-status")
            Button { model.undoWorkspaceComposer() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canEditWorkspaceComposer || (draft?.history.isEmpty != false && (model.hasWorkspaceComposerChanges || model.settings.savedWorkspaces.undo == nil)))
                .help(draft?.history.isEmpty == false ? copy.text("Undo edit", "편집 되돌리기") : copy.undo).pointingHandCursor().accessibilityIdentifier("composer-undo")
            Button(copy.cancel) { confirmsDiscard = true }.disabled(!model.hasWorkspaceComposerChanges).pointingHandCursor()
            Button(copy.saveChanges) { _ = model.commitWorkspaceComposer() }.buttonStyle(.borderedProminent)
                .disabled(!model.canEditWorkspaceComposer || !model.hasWorkspaceComposerChanges || draft.flatMap(model.workspaceComposerValidation) != nil)
                .pointingHandCursor().accessibilityIdentifier("composer-save")
            if navigation.settingsRoute.returnTo != nil {
                Button(copy.text("Done", "완료"), action: finishAssignmentReview).pointingHandCursor()
            }
        }
        .confirmationDialog(copy.text("Discard unsaved changes?", "편집한 내용을 취소할까요?"), isPresented: $confirmsDiscard) {
            Button(copy.text("Discard changes", "편집 취소"), role: .destructive) { model.discardWorkspaceComposer() }
            Button(copy.text("Keep editing", "계속 편집"), role: .cancel) {}
        }
    }
}

/// The same handle supports dragging and a keyboard-accessible move menu.
struct WorkspaceReorderHandle: View {
    let name: String
    let copy: WorkspaceSaveStrings
    let enabled: Bool
    let moveLeft: (() -> Void)?
    let moveRight: (() -> Void)?
    let startDrag: () -> NSItemProvider
    @State private var showsMoves = false
    var body: some View {
        Button { showsMoves = true } label: {
            Image(systemName: "line.3.horizontal").font(.system(size: 11)).frame(width: 22, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).interactionCursor(.openHand)
            .help(copy.text("Drag to reorder, or click for move options", "끌어서 순서 변경 · 클릭하여 이동 메뉴 열기"))
            .accessibilityLabel(name + " · " + copy.text("Reorder", "순서 변경"))
            .popover(isPresented: $showsMoves) {
                VStack(alignment: .leading, spacing: 10) {
                    Button(copy.text("Move left", "왼쪽으로 이동")) { moveLeft?(); showsMoves = false }.disabled(moveLeft == nil).pointingHandCursor()
                    Button(copy.text("Move right", "오른쪽으로 이동")) { moveRight?(); showsMoves = false }.disabled(moveRight == nil).pointingHandCursor()
                }.padding(14)
            }
            .onDrag { startDrag() }
    }
}
