import AppKit
import SwiftUI
import SidebyCore
import SidebyUI

struct WorkspaceSaveView: View {
    @ObservedObject var model: SidebyAppModel
    let finish: (Bool) -> Void
    @State private var isReadyForTyping = false
    private var copy: WorkspaceSaveStrings { model.saveCopy }
    private var displayIDs: [String] {
        let live = model.displayLayout.displays.map(\.id)
        let remembered = Set(model.workspaceSaveDraft?.original?.displayIDs ?? [])
            .union(model.workspaceSaveDraft?.members.keys.map { $0 } ?? [])
        return live + remembered.sorted().filter { !live.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let draft = model.workspaceSaveDraft {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "rectangle.on.rectangle").font(.system(size: 23, weight: .medium))
                                .foregroundStyle(NativeSurfaceStyle.accent).padding(10)
                                .background(NativeSurfaceStyle.selectionBackground, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(draft.editingID == nil ? copy.saveConfiguration : copy.edit)
                                    .font(.system(size: 23, weight: .semibold)).accessibilityAddTraits(.isHeader)
                                Text(draft.editingID == nil ? copy.preserve : copy.preserveEdit)
                                    .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                            }
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(copy.name).font(.system(size: 12, weight: .medium))
                            WorkspaceNameInput(text: Binding(get: { model.workspaceSaveDraft?.name ?? "" }, set: {
                                model.workspaceSaveDraft?.name = $0
                                if model.workspaceSaveDraft?.error == copy.invalidNameOrSelection { model.workspaceSaveDraft?.error = nil }
                            }), label: copy.name, enabled: isReadyForTyping, submit: {
                                if model.commitWorkspaceSave() { finish(true) }
                            }).frame(height: 36).accessibilityIdentifier("workspace-save-name")
                            if !isReadyForTyping { Text(copy.releaseHint).font(.system(size: 11)).foregroundStyle(NativeSurfaceStyle.secondaryText) }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(copy.included).font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text("\(draft.members.count)").font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                            }
                            VStack(spacing: 0) {
                                ForEach(displayIDs, id: \.self) { id in
                                    displayRow(id, draft: draft)
                                    if id != displayIDs.last { Divider().padding(.leading, 44) }
                                }
                            }
                            .background(NativeSurfaceStyle.tableBackground, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(NativeSurfaceStyle.frameBorder))
                            Label(copy.scope, systemImage: "info.circle").font(.system(size: 11))
                                .foregroundStyle(NativeSurfaceStyle.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }
                        if draft.editingID != nil {
                            Button(copy.useCurrent) { model.refreshWorkspaceSaveDraft() }
                                .buttonStyle(.link).pointingHandCursor()
                            if !changeLines(draft).isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(copy.changes).fontWeight(.semibold)
                                    ForEach(changeLines(draft), id: \.self) { Text($0) }
                                }.font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.accent)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(NativeSurfaceStyle.selectionBackground, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }.padding(26)
                }
                Group {
                    if let error = draft.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).foregroundStyle(.red).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            if let duplicateID = draft.duplicateID {
                                Button(copy.showExisting) { model.workspaceSavedFocusID = duplicateID; finish(false) }.pointingHandCursor()
                            } else if error == copy.readUnavailable || error == copy.changed {
                                Button(copy.readAgain) { model.refreshWorkspaceSaveDraft() }.pointingHandCursor()
                            }
                        }.accessibilityIdentifier("workspace-save-error")
                    }
                }
                .padding(.horizontal, 26).padding(.bottom, draft.error == nil ? 0 : 12)
                Divider()
                HStack(spacing: 10) {
                    Spacer()
                    Button(copy.cancel) { finish(false) }.keyboardShortcut(.cancelAction)
                    Button(draft.editingID == nil ? copy.save : copy.saveChanges) {
                        if model.commitWorkspaceSave() { finish(true) }
                    }.buttonStyle(.borderedProminent).tint(NativeSurfaceStyle.accent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isReadyForTyping || draft.members.isEmpty || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).count > 60 || !model.canSaveWorkspace)
                        .accessibilityIdentifier("workspace-save-commit")
                }.controlSize(.large).padding(18).background(NativeSurfaceStyle.sidebarBackground)
            }
        }
        .foregroundStyle(NativeSurfaceStyle.primaryText).background(NativeSurfaceStyle.windowBackground)
        .task {
            // Do not let the chord that opened the chooser type into the name field.
            while !Task.isCancelled && (!NSEvent.modifierFlags.intersection([.option, .shift, .control, .command]).isEmpty || CGEventSource.keyState(.combinedSessionState, key: 49)) {
                try? await Task.sleep(for: .milliseconds(30))
            }
            guard !Task.isCancelled else { return }
            isReadyForTyping = true
        }
    }

    private func displayRow(_ id: String, draft: WorkspaceSaveDraft) -> some View {
        let live = draft.observation?.displays.first { $0.displayID == id }
        let selected = draft.members[id] != nil
        let allowed = model.selectedDisplayIDs.contains(id)
        return HStack(alignment: .top, spacing: 12) {
            Toggle(model.displayName(for: id), isOn: Binding(get: { model.workspaceSaveDraft?.members[id] != nil }, set: {
                model.setWorkspaceDraftDisplay(id, included: $0)
            })).labelsHidden().toggleStyle(.checkbox).padding(.top, 3)
                .disabled(live == nil && draft.original?.spaceIndex(for: id) == nil || live != nil && !selected && (!allowed || model.durableCurrentKey(id, observation: draft.observation) == nil))
                .accessibilityLabel(model.displayName(for: id))
                .accessibilityIdentifier("workspace-include-" + id)
            Image(systemName: model.displayLayout.displays.first(where: { $0.id == id })?.isBuiltin == true ? "laptopcomputer" : "display")
                .foregroundStyle(selected ? NativeSurfaceStyle.accent : NativeSurfaceStyle.secondaryText).frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(model.displayName(for: id)).font(.system(size: 13, weight: .medium))
                    Spacer()
                    if live == nil { Text(copy.offline).font(.system(size: 10)).foregroundStyle(NativeSurfaceStyle.secondaryText) }
                }
                if draft.editingID != nil, selected, let live, let keys = draft.observation?.spaceKeysByDisplayID[id], keys.count == live.spaceCount {
                    Picker(copy.included, selection: Binding(get: {
                        guard let key = model.workspaceSaveDraft?.bookmarks[id] else { return -1 }
                        return keys.firstIndex(of: key) ?? -1
                    }, set: {
                        model.setWorkspaceDraftDesktop(id, index: $0)
                    })) {
                        if !keys.contains(draft.bookmarks[id] ?? "") { Text(copy.text("Choose a replacement desktop", "연결할 데스크탑 선택")).tag(-1) }
                        ForEach(0..<keys.count, id: \.self) { index in Text(desktopLabel(id, index)).tag(index) }
                    }.labelsHidden().font(.system(size: 12))
                } else {
                    Text(live == nil ? (selected ? copy.remembered : copy.text("Excluded from this setup", "이 구성에서 제외")) : selected ? desktopLabel(id, draft.members[id] ?? 0) : allowed ? copy.keep : copy.excluded)
                        .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                }
            }
        }.padding(14)
    }

    private func desktopLabel(_ id: String, _ index: Int) -> String {
        let label = copy.desktop(index)
        if let name = model.workspaceDesktopName(displayID: id, spaceIndex: index), name != label { return label + " · " + name }
        return label
    }

    private func changeLines(_ draft: WorkspaceSaveDraft) -> [String] {
        guard let original = draft.original else { return [] }
        var lines: [String] = []
        if original.name != draft.name { lines.append(original.name + " → " + draft.name) }
        for id in Set(original.displayIDs).union(draft.members.keys).sorted() {
            if original.spaceIndex(for: id) != draft.members[id] || draft.originalBookmarks[id] != draft.bookmarks[id] {
                lines.append(model.displayName(for: id) + ": " + (original.spaceIndex(for: id).map(copy.desktop) ?? copy.notIncluded) + " → " + (draft.members[id].map(copy.desktop) ?? copy.notIncluded))
            }
        }
        return lines
    }
}

@MainActor final class WorkspaceSaveWindowController: NSObject, NSWindowDelegate {
    private weak var model: SidebyAppModel?
    private(set) var panel: NSPanel?
    private var completion: (() -> Void)?
    init(model: SidebyAppModel) { self.model = model }

    func show(anchor: NSRect?, completion: (() -> Void)?) {
        guard let model else { return }
        if let panel, panel.isVisible { panel.makeKeyAndOrderFront(nil); return }
        if let completion { self.completion = completion }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.map { NSPoint(x: $0.midX, y: $0.midY) } ?? pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let rowCount = Set(model.displayLayout.displays.map(\.id) + Array(model.workspaceSaveDraft?.members.keys ?? [:].keys)).count
        let preferredHeight = max(440, 330 + CGFloat(rowCount) * 66 + (model.workspaceSaveDraft?.editingID == nil ? 0 : 80))
        let size = NSSize(width: min(530, visible.width - 32), height: min(preferredHeight, 640, visible.height - 40))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = model.saveCopy.saveConfiguration
        panel.identifier = .init("sideby-save-workspace")
        panel.delegate = self
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WorkspaceSaveView(model: model, finish: { [weak self] saved in self?.finish(saved: saved) }))
        let origin = anchor.map { NSPoint(x: $0.minX, y: $0.maxY - panel.frame.height) }
            ?? HeldMatrixPanelLayout.origin(size: panel.frame.size, pointer: pointer, visibleFrame: visible)
        panel.setFrameOrigin(NSPoint(x: max(visible.minX + 16, min(origin.x, visible.maxX - panel.frame.width - 16)),
                                     y: max(visible.minY + 16, min(origin.y, visible.maxY - panel.frame.height - 16))))
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { finish(saved: false); return false }

    func finish(saved: Bool) {
        model?.workspaceSaveDraft = nil
        panel?.orderOut(nil)
        panel = nil
        let callback = completion
        completion = nil
        callback?()
    }
}

/// AppKit owns composition. Return commits an IME candidate before it can submit the draft.
private struct WorkspaceNameInput: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let enabled: Bool
    let submit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.font = .systemFont(ofSize: 15)
        field.bezelStyle = .roundedBezel
        field.isBezeled = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(label)
        field.setAccessibilityIdentifier("workspace-save-name")
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = enabled
        if field.stringValue != text, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true { field.stringValue = text }
        if enabled && !context.coordinator.didFocus {
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard let field, let coordinator, !coordinator.didFocus, field.window != nil else { return }
                coordinator.didFocus = true
                field.window?.makeFirstResponder(field)
                field.selectText(nil)
            }
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: WorkspaceNameInput
        var didFocus = false
        init(_ parent: WorkspaceNameInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() {
                parent.submit()
                return true
            }
            return false
        }
    }
}
