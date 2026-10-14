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
    private var panelIsEditing = false
    private var measuredContentSize: CGSize?
    private var copyModifiers = HeldMatrixCopyModifiers()
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
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .flagsChanged]) { [weak self] event in
                MainActor.assumeIsolated {
                    if event.type == .flagsChanged { _ = self?.copyModifiers.update(optionDown: event.modifierFlags.contains(.option)) }
                    else if self?.persistent == true { self?.dismiss() }
                }
            }
        }
        if localOutsideMonitor == nil {
            localOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .flagsChanged]) { [weak self] event in
                MainActor.assumeIsolated {
                    if event.type == .flagsChanged {
                        _ = self?.copyModifiers.update(optionDown: event.modifierFlags.contains(.option))
                        return
                    }
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

    private func hide() {
        panel?.orderOut(nil)
        // Retain the hidden window until a pending mouse-up is delivered to its
        // original recipient. Every action also validates the press generation.
    }

    private func show(model: SidebyAppModel, generation: Int, anchor: NSRect? = nil) {
        let pointer = anchor.map { NSPoint(x: $0.midX, y: $0.maxY - 62) } ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { dismiss(); return }
        copyModifiers = HeldMatrixCopyModifiers(ignoresOpeningOption: source?.chordIsDown == true && NSEvent.modifierFlags.contains(.option))
        let snapshot = HeldWorkspaceSnapshot(model: model, previousColumnID: previousColumnID)
        let size = panelSize(model: model, screen: screen, editing: false)
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
        panel.title = "Sideby — " + model.connectionCopy.title
        panel.identifier = NSUserInterfaceItemIdentifier("sideby-held-workspace-matrix")
        self.panel?.orderOut(nil)
        self.panel = panel
        panelIsEditing = false
        measuredContentSize = nil
        let view = HeldWorkspaceMatrixView(model: model, snapshot: snapshot, select: { [weak self] column in
            self?.activate(column, generation: generation)
        }, rememberColumn: { [weak self] id in self?.previousColumnID = id },
            persistent: persistent, close: { [weak self] in self?.dismiss() },
            keepOpen: { [weak self] in self?.pinVisiblePanel() },
            editingChanged: { [weak self] editing in self?.resizeForEditing(editing) },
            copyRequested: { [weak self] in self?.copyModifiers.update(optionDown: NSEvent.modifierFlags.contains(.option)) ?? false },
            availableHeight: max(1, screen.visibleFrame.height - 48),
            contentMeasured: { [weak self, weak panel] size, editing in
                guard let self, let panel, self.panel === panel, self.panelIsEditing == editing,
                      size.height > 0, abs(size.width - panel.frame.width) < 1 else { return }
                self.measuredContentSize = size
                // Avoid changing the window frame during a SwiftUI layout pass.
                DispatchQueue.main.async { [weak self, weak panel] in
                    guard let self, let panel, self.panel === panel, panel.isVisible else { return }
                    self.resizeToMeasuredContent()
                }
            })
        panel.contentView = HeldMatrixHostingView(rootView: view)
        panel.setContentSize(size)
        panel.contentView?.layoutSubtreeIfNeeded()
        let measuredSize = panelSize(model: model, screen: screen, editing: false,
                                     contentHeight: measuredContentSize?.height)
        panel.setContentSize(measuredSize)
        panel.setFrameOrigin(HeldMatrixPanelLayout.origin(size: measuredSize, pointer: pointer, visibleFrame: screen.visibleFrame))
        screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        panel.orderFrontRegardless()
    }

    private func panelSize(model: SidebyAppModel, screen: NSScreen, editing: Bool, contentHeight: CGFloat? = nil) -> NSSize {
        let snapshot = HeldWorkspaceSnapshot(model: model)
        let hasStatus = !model.isEnabled || !model.hasSwitchingAccess || model.workspaceRecoveryTargetID != nil
            || model.settingsStore.hasUnreadableSettings
        return HeldMatrixPanelLayout.size(columns: snapshot.columns.count, displays: snapshot.displayIDs.count,
            visibleFrame: screen.visibleFrame, accessoryHeight: hasStatus ? 42 : 0, editing: editing,
            contentHeight: contentHeight)
    }

    private func resizeForEditing(_ editing: Bool) {
        guard let model, let panel, let screen = panel.screen ?? NSScreen.main else { return }
        panelIsEditing = editing
        measuredContentSize = nil
        let top = NSPoint(x: panel.frame.midX, y: panel.frame.maxY - 62)
        // Change width first so text is measured at its final wrapping width.
        let size = panelSize(model: model, screen: screen, editing: editing, contentHeight: panel.frame.height)
        panel.setFrame(NSRect(origin: HeldMatrixPanelLayout.origin(size: size, pointer: top, visibleFrame: screen.visibleFrame),
                             size: size), display: true)
    }

    private func resizeToMeasuredContent() {
        guard let panel, let measuredContentSize, let screen = panel.screen ?? NSScreen.main,
              abs(measuredContentSize.width - panel.frame.width) < 1 else { return }
        let height = min(ceil(measuredContentSize.height), max(1, screen.visibleFrame.height - 48))
        guard abs(panel.frame.height - height) >= 1 else { return }
        let size = NSSize(width: panel.frame.width, height: height)
        let top = NSPoint(x: panel.frame.midX, y: panel.frame.maxY - 62)
        panel.setFrame(NSRect(origin: HeldMatrixPanelLayout.origin(size: size, pointer: top, visibleFrame: screen.visibleFrame),
                              size: size), display: true)
    }

    private func activate(_ column: HeldWorkspaceColumn, generation: Int) {
        guard let model, persistent || (session.isVisible && session.generation == generation && source?.chordIsDown == true) else { return }
        model.refreshWorkspaceStatus()
        let snapshot = HeldWorkspaceSnapshot(model: model)
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
