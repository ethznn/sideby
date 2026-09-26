import AppKit
import SidebyCore
import SidebySystem
import SidebyUI
import SwiftUI

struct HeldMatrixShortcutSettingsView: View {
    @ObservedObject var model: SidebyAppModel
    @State private var isRecording = false
    private var copy: HeldMatrixStrings { .init(language: model.settings.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(copy.setting, isOn: Binding(get: { model.heldMatrixConfiguration.isEnabled }, set: { value in
                endRecording()
                var configuration = model.heldMatrixConfiguration
                configuration.isEnabled = value
                model.updateHeldMatrixConfiguration(configuration)
            })).pointingHandCursor()
            HStack(spacing: 12) {
                Text(KeyboardShortcutFormatter.shortcutText(model.heldMatrixConfiguration.shortcut)).font(.system(size: 13, weight: .medium))
                HeldShortcutRecorder(title: isRecording ? copy.recording : copy.record, isRecording: $isRecording,
                    begin: { model.beginHeldMatrixShortcutRecording() }, cancel: endRecording,
                    capture: { shortcut in
                        var configuration = model.heldMatrixConfiguration
                        configuration.shortcut = shortcut
                        let saved = model.updateHeldMatrixConfiguration(configuration)
                        if saved { endRecording() }
                    }).frame(width: isRecording ? 270 : 150, height: 28).pointingHandCursor()
            }
            Text(copy.hint).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            if let error = model.heldMatrixShortcutError {
                Text(error).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.primaryText).fixedSize(horizontal: false, vertical: true)
            }
        }.onDisappear(perform: endRecording)
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        model.endHeldMatrixShortcutRecording()
    }
}

private struct HeldShortcutRecorder: NSViewRepresentable {
    let title: String
    @Binding var isRecording: Bool
    let begin: () -> Void
    let cancel: () -> Void
    let capture: (SBSKeyboardShortcut) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(RecorderButton.startRecording)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.title = title
        button.recording = isRecording
        if !isRecording { button.removeMonitor() }
        button.start = { isRecording = true; begin() }
        button.cancel = cancel
        button.capture = capture
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier("held-matrix-shortcut-recorder")
    }

    final class RecorderButton: NSButton {
        var recording = false
        var start: (() -> Void)?
        var cancel: (() -> Void)?
        var capture: ((SBSKeyboardShortcut) -> Void)?
        private var monitor: Any?
        isolated deinit { removeMonitor() }
        override var acceptsFirstResponder: Bool { true }
        @objc func startRecording() {
            recording = true
            start?()
            window?.makeFirstResponder(self)
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.recording else { return event }
                self.keyDown(with: event)
                return nil
            }
        }
        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { cancel?(); return }
            guard !event.isARepeat else { return }
            let modifiers = EventTapInputNormalizer.modifierFlags(from: event.cgEvent?.flags ?? [])
            capture?(.init(keyCode: event.keyCode, modifiers: modifiers))
        }
        override func resignFirstResponder() -> Bool {
            if recording { removeMonitor(); cancel?() }
            return super.resignFirstResponder()
        }
    }
}
