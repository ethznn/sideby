import AppKit
import SidebyCore
import SidebySystem
import SwiftUI

@MainActor final class HeldWorkspaceMatrixController {
    private weak var model: SidebyAppModel?
    private var source: HeldMatrixShortcutInputSource?
    private var configuration: HeldMatrixConfiguration?
    private var panel: HeldMatrixPanel?
    private var session = HeldMatrixSession()
    private var screenID: NSNumber?
    private var previousColumnID: String?
    private var persistent = false
    private var outsideMonitor: Any?
    private var localOutsideMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    init(model: SidebyAppModel) {
        self.model = model
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.model?.isSwitching != true else { return }
                    self.refreshVisiblePanelInput()
                }
            })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if !NSScreen.screens.contains(where: { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == self.screenID }) {
                        self.dismiss()
                    }
                }
            })
    }

    isolated deinit {
        source?.stop()
        panel?.orderOut(nil)
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localOutsideMonitor { NSEvent.removeMonitor(localOutsideMonitor) }
        for token in observers {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    func configure(_ configuration: HeldMatrixConfiguration) -> Bool {
        guard !configuration.isEnabled || HeldMatrixConfiguration.isValid(configuration.shortcut) else { return false }
        if self.configuration == configuration, source != nil || !configuration.isEnabled { return true }
        if !configuration.isEnabled {
            suspend()
            self.configuration = configuration
            return true
        }
        let candidate = HeldMatrixShortcutInputSource { [weak self] event in self?.receive(event) }
        guard candidate.start(shortcut: configuration.shortcut) else { return false }
        source?.stop()
        dismiss()
        source = candidate
        self.configuration = configuration
        return true
    }

    func suspend() {
        source?.stop()
        source = nil
        dismiss()
        session.release()
        model?.setHeldMatrixInputActive(false)
    }

    private func receive(_ event: HeldMatrixShortcutInputSource.Event) {
        switch event {
        case .pressed:
            if model?.workspaceSaveDraft != nil { model?.showWorkspaceSave(); return }
            if persistent { dismiss(); return }
            guard let generation = session.press(), let model else { return }
            model.setHeldMatrixInputActive(true)
            model.refreshWorkspaceStatus()
            guard source?.chordIsDown == true else { source?.checkHeldKeys(); return }
            show(model: model, generation: generation)
        case .released:
            session.release()
            model?.setHeldMatrixInputActive(false)
            if !persistent { hide() }
        case .cancelled: dismiss()
        }
    }

    func dismiss() {
        persistent = false
        session.dismiss()
        hide()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor); self.outsideMonitor = nil }
        if let localOutsideMonitor { NSEvent.removeMonitor(localOutsideMonitor); self.localOutsideMonitor = nil }
    }

    func showPersistent(anchor: NSRect? = nil) {
        guard let model, model.workspaceSaveDraft == nil else { return }
        persistent = true
        model.refreshWorkspaceStatus()
        show(model: model, generation: session.generation, anchor: anchor)
        pinVisiblePanel()
    }

    // Confirmations and their undo result remain usable after the opening chord is released.
    func pinVisiblePanel() {
        guard let panel, panel.isVisible else { return }
        persistent = true
        panel.acceptsKeyboard = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { if self?.persistent == true { self?.dismiss() } }
            }
        }
        if localOutsideMonitor == nil {
            localOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.persistent, let panel = self.panel,
                          let clicked = event.window, clicked !== panel,
                          clicked.parent !== panel, panel.attachedSheet == nil,
                          NSApp.modalWindow == nil, clicked.level < panel.level else { return }
                    self.dismiss()
                }
                return event
            }
        }
    }

    private func beginSave(editingID: String? = nil) {
        guard let model else { return }
        let anchor = panel?.frame
        dismiss()
        model.showWorkspaceSave(editingID: editingID, anchor: anchor) { [weak self] in self?.showPersistent(anchor: anchor) }
    }

    private func hide() {
        panel?.orderOut(nil)
        // Retain the hidden window until a pending mouse-up is delivered to its
        // original recipient. Every action also validates the press generation.
    }

    private func show(model: SidebyAppModel, generation: Int, anchor: NSRect? = nil) {
        let pointer = anchor.map { NSPoint(x: $0.midX, y: $0.maxY - 62) } ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { dismiss(); return }
        let snapshot = HeldWorkspaceSnapshot(model: model, previousColumnID: previousColumnID)
        var accessoryHeight: CGFloat = model.workspaceSaveMessage == nil ? 0 : 52
        if let previous = model.workspaceHistory.previousContextID,
           previous != model.verifiedCurrentWorkspaceID,
           model.settings.contextPlan.contexts.contains(where: { $0.id == previous }) { accessoryHeight += 30 }
        if !model.isEnabled || !model.hasSwitchingAccess { accessoryHeight += 36 }
        let size = HeldMatrixPanelLayout.size(columns: snapshot.columns.count,
            displays: model.connectedWorkspaceDisplayIDs.count,
            visibleFrame: screen.visibleFrame, accessoryHeight: accessoryHeight)
        let panel = HeldMatrixPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.acceptsKeyboard = persistent
        panel.onCancel = { [weak self] in self?.dismiss() }
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.title = "Sideby — Quick setup matrix"
        panel.identifier = NSUserInterfaceItemIdentifier("sideby-held-workspace-matrix")
        let view = HeldWorkspaceMatrixView(model: model, snapshot: snapshot, select: { [weak self] column in
            self?.activate(column, snapshot: snapshot, generation: generation)
        }, rememberColumn: { [weak self] id in self?.previousColumnID = id },
            save: { [weak self] in self?.beginSave() }, edit: { [weak self] id in self?.beginSave(editingID: id) },
            persistent: persistent, close: { [weak self] in self?.dismiss() },
            keepOpen: { [weak self] in self?.pinVisiblePanel() })
        panel.contentView = HeldMatrixHostingView(rootView: view.frame(width: size.width, height: size.height))
        panel.setFrameOrigin(HeldMatrixPanelLayout.origin(size: size, pointer: pointer, visibleFrame: screen.visibleFrame))
        self.panel?.orderOut(nil)
        self.panel = panel
        screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        panel.orderFrontRegardless()
    }

    private func activate(_ column: HeldWorkspaceColumn, snapshot: HeldWorkspaceSnapshot, generation: Int) {
        guard let model, persistent || (session.isVisible && session.generation == generation && source?.chordIsDown == true) else { return }
        model.refreshWorkspaceStatus()
        guard model.verifiedCurrentWorkspaceID != column.id,
              model.heldMatrixCanActivate(column, displayIDs: snapshot.displayIDs),
              persistent || session.beginTransition(session: generation) else { return }
        model.heldMatrixSwitchInFlight = true
        model.activateContext(contextID: column.id, requestsPermissions: false) { [weak self, weak model] success in
            self?.session.finishTransition()
            model?.heldMatrixSwitchInFlight = false
            if success && self?.persistent == true { self?.dismiss() }
            else { self?.refreshVisiblePanelInput() }
        }
    }

    private func refreshVisiblePanelInput() {
        guard #available(macOS 27, *) else { return }
        panel?.refreshOrderIfVisible(session: session, chordIsDown: source?.chordIsDown == true)
    }
}

final class HeldMatrixPanel: NSPanel {
    var acceptsKeyboard = false
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKeyboard }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override var canBecomeMain: Bool { false }

    /// On macOS 27 a nonactivating panel can remain visible after a Space
    /// transition but stop receiving mouse events. Refresh WindowServer's
    /// ordering in one animation-free turn, retaining the content and geometry.
    /// A completion or Space notification must never resurrect a hidden panel.
    @discardableResult func refreshOrderIfVisible(session: HeldMatrixSession, chordIsDown: Bool) -> Bool {
        guard isVisible, session.isHeld, session.isVisible, chordIsDown else { return false }
        orderOut(nil)
        orderFrontRegardless()
        return true
    }
}

final class HeldMatrixHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
