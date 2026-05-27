import AppKit
import SidebyCore
import SwiftUI

public enum KeyboardShortcutFormatter {
    public static func modifierCaps(_ modifiers: ModifierFlags) -> [String] {
        var caps: [String] = []
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) { caps.append("⇧") }
        if modifiers.contains(.command) { caps.append("⌘") }
        return caps
    }

    public static func keyCaps(_ shortcut: SBSKeyboardShortcut) -> [String] {
        modifierCaps(shortcut.modifiers) + [keyCap(for: shortcut.keyCode)]
    }

    public static func shortcutText(_ shortcut: SBSKeyboardShortcut) -> String {
        keyCaps(shortcut).joined()
    }

    public static func modifierText(_ modifiers: ModifierFlags) -> String {
        let caps = modifierCaps(modifiers)
        return caps.isEmpty ? "None" : caps.joined()
    }

    public static func keyCap(for keyCode: UInt16) -> String {
        if let symbol = symbolicKeyCaps[keyCode] {
            return symbol
        }

        if let character = qwertyKeyCaps[keyCode] {
            return character
        }

        return "#\(keyCode)"
    }

    private static let symbolicKeyCaps: [UInt16: String] = [
        36: "↩",
        48: "⇥",
        49: "Space",
        51: "⌫",
        53: "Esc",
        71: "Clear",
        76: "⌤",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        109: "F10",
        111: "F12",
        115: "Home",
        116: "PgUp",
        117: "⌦",
        118: "F4",
        119: "End",
        120: "F2",
        121: "PgDn",
        122: "F1",
        123: "←",
        124: "→",
        125: "↓",
        126: "↑"
    ]

    private static let qwertyKeyCaps: [UInt16: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "O",
        32: "U",
        33: "[",
        34: "I",
        35: "P",
        37: "L",
        38: "J",
        39: "'",
        40: "K",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "N",
        46: "M",
        47: ".",
        50: "`"
    ]
}

public struct ShortcutSettingsView: View {
    @Binding private var settings: AppSettings
    @State private var recordingRole: KeyboardShortcutRole?
    @State private var statusMessage: String?
    @State private var isErrorStatus = false

    public init(settings: Binding<AppSettings>, showsInputExperiment: Bool = false) {
        self._settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            gestureSection

            Divider()

            keyboardSection

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(isErrorStatus ? .red : .secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gestureSection: some View {
        let strings = SBSStrings(language: settings.language)

        return VStack(alignment: .leading, spacing: 8) {
            Text(strings.gestureModifier)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                ForEach(GestureModifierChoice.allCases) { choice in
                    Button {
                        toggleGestureModifier(choice.flag)
                    } label: {
                        HStack(spacing: 5) {
                            Text(choice.symbol)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                            Text(strings.modifierChoiceTitle(choice.flag))
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.requiredModifiers.contains(choice.flag) ? .accentColor : .secondary)
                }
            }

            Text(strings.horizontalScrollGesture(settings.requiredModifiers))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var keyboardSection: some View {
        let strings = SBSStrings(language: settings.language)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(strings.keyboardShortcuts)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(strings.resetDefaults) {
                    resetDefaults()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .disabled(!settings.keyboardShortcutsEnabled)
            }

            Toggle(strings.enableKeyboardShortcuts, isOn: Binding(
                get: { settings.keyboardShortcutsEnabled },
                set: { setKeyboardShortcutsEnabled($0) }
            ))
            .toggleStyle(.switch)

            Text(strings.keyboardShortcutsOptionalHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                shortcutRow(
                    role: .previous,
                    title: strings.roleTitle(.previous),
                    shortcut: settings.shortcutPrevious
                )
                shortcutRow(
                    role: .next,
                    title: strings.roleTitle(.next),
                    shortcut: settings.shortcutNext
                )
            }
            .disabled(!settings.keyboardShortcutsEnabled)
            .opacity(settings.keyboardShortcutsEnabled ? 1 : 0.45)
        }
    }

    private func shortcutRow(
        role: KeyboardShortcutRole,
        title: String,
        shortcut: SBSKeyboardShortcut
    ) -> some View {
        let strings = SBSStrings(language: settings.language)

        return HStack(spacing: 10) {
            Text(title)
                .frame(width: 78, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(KeyboardShortcutFormatter.keyCaps(shortcut), id: \.self) { cap in
                    Kbd(text: cap)
                }
            }

            Spacer()

            Button(recordingRole == role ? strings.pressKeys : strings.change) {
                recordingRole = role
                statusMessage = strings.pressNewShortcut(title)
                isErrorStatus = false
            }
            .buttonStyle(.bordered)

            KeyboardShortcutCaptureView(
                isRecording: recordingRole == role,
                onCapture: { shortcut in
                    commit(shortcut: shortcut, role: role)
                },
                onCancel: {
                    recordingRole = nil
                    statusMessage = nil
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
        }
    }

    private func toggleGestureModifier(_ modifier: ModifierFlags) {
        var candidate = settings
        if candidate.requiredModifiers.contains(modifier) {
            candidate.requiredModifiers.remove(modifier)
        } else {
            candidate.requiredModifiers.insert(modifier)
        }

        let issues = KeyboardShortcutValidator.issues(
            previous: candidate.shortcutPrevious,
            next: candidate.shortcutNext,
            gestureModifiers: candidate.requiredModifiers
        )
        guard issues.isEmpty else {
            showIssues(issues)
            return
        }

        settings = candidate
        statusMessage = SBSStrings(language: settings.language)
            .gestureModifierSaved(SBSStrings(language: settings.language).modifierText(candidate.requiredModifiers))
        isErrorStatus = false
    }

    private func commit(shortcut: SBSKeyboardShortcut, role: KeyboardShortcutRole) {
        var candidate = settings
        switch role {
        case .previous:
            candidate.shortcutPrevious = shortcut
        case .next:
            candidate.shortcutNext = shortcut
        }

        let issues = KeyboardShortcutValidator.issues(
            previous: candidate.shortcutPrevious,
            next: candidate.shortcutNext,
            gestureModifiers: candidate.requiredModifiers
        )
        guard issues.isEmpty else {
            recordingRole = nil
            showIssues(issues)
            return
        }

        settings = candidate
        recordingRole = nil
        statusMessage = SBSStrings(language: settings.language)
            .shortcutSaved(role: role, shortcut: KeyboardShortcutFormatter.shortcutText(shortcut))
        isErrorStatus = false
    }

    private func resetDefaults() {
        var candidate = settings
        candidate.requiredModifiers = AppSettings.default.requiredModifiers
        candidate.keyboardShortcutsEnabled = AppSettings.default.keyboardShortcutsEnabled
        candidate.shortcutPrevious = AppSettings.default.shortcutPrevious
        candidate.shortcutNext = AppSettings.default.shortcutNext
        candidate.inputExecutionStrategy = AppSettings.default.inputExecutionStrategy
        settings = candidate
        recordingRole = nil
        statusMessage = SBSStrings(language: settings.language).shortcutSettingsReset
        isErrorStatus = false
    }

    private func setKeyboardShortcutsEnabled(_ isEnabled: Bool) {
        var candidate = settings
        candidate.keyboardShortcutsEnabled = isEnabled
        settings = candidate
        statusMessage = isEnabled
            ? SBSStrings(language: settings.language).keyboardShortcutsOn
            : SBSStrings(language: settings.language).keyboardShortcutsOff
        isErrorStatus = false
    }

    private func showIssues(_ issues: [KeyboardShortcutValidationIssue]) {
        statusMessage = issues.map(issueMessage).joined(separator: " ")
        isErrorStatus = true
    }

    private func issueMessage(_ issue: KeyboardShortcutValidationIssue) -> String {
        SBSStrings(language: settings.language).issueMessage(issue)
    }

    private func title(for role: KeyboardShortcutRole) -> String {
        SBSStrings(language: settings.language).roleTitle(role)
    }
}

public struct InputExperimentSettingsView: View {
    @Binding private var settings: AppSettings

    public init(settings: Binding<AppSettings>) {
        self._settings = settings
    }

    public var body: some View {
        let strings = SBSStrings(language: settings.language)

        VStack(alignment: .leading, spacing: 8) {
            Text(strings.inputExperiment)
                .font(.subheadline.weight(.semibold))

            Text(strings.strategySummary(settings.inputExecutionStrategy))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum GestureModifierChoice: CaseIterable, Identifiable {
    case option
    case control
    case command
    case shift

    var id: Self { self }

    var flag: ModifierFlags {
        switch self {
        case .option:
            return .option
        case .control:
            return .control
        case .command:
            return .command
        case .shift:
            return .shift
        }
    }

    var symbol: String {
        switch self {
        case .option:
            return "⌥"
        case .control:
            return "⌃"
        case .command:
            return "⌘"
        case .shift:
            return "⇧"
        }
    }

    var title: String {
        switch self {
        case .option:
            return "Option"
        case .control:
            return "Control"
        case .command:
            return "Command"
        case .shift:
            return "Shift"
        }
    }
}

private struct KeyboardShortcutCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let onCapture: (SBSKeyboardShortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(
            isRecording: isRecording,
            onCapture: onCapture,
            onCancel: onCancel
        )
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel

        guard isRecording else {
            return
        }

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class RecorderView: NSView {
        var isRecording: Bool
        var onCapture: (SBSKeyboardShortcut) -> Void
        var onCancel: () -> Void

        init(
            isRecording: Bool,
            onCapture: @escaping (SBSKeyboardShortcut) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.isRecording = isRecording
            self.onCapture = onCapture
            self.onCancel = onCancel
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            if event.keyCode == 53 {
                onCancel()
                return
            }

            onCapture(
                SBSKeyboardShortcut(
                    keyCode: UInt16(event.keyCode),
                    modifiers: Self.modifierFlags(from: event.modifierFlags)
                )
            )
        }

        override func flagsChanged(with event: NSEvent) {
            guard isRecording else {
                super.flagsChanged(with: event)
                return
            }
        }

        private static func modifierFlags(from flags: NSEvent.ModifierFlags) -> ModifierFlags {
            var modifiers: ModifierFlags = []
            if flags.contains(.shift) {
                modifiers.insert(.shift)
            }
            if flags.contains(.control) {
                modifiers.insert(.control)
            }
            if flags.contains(.option) {
                modifiers.insert(.option)
            }
            if flags.contains(.command) {
                modifiers.insert(.command)
            }
            if flags.contains(.function) {
                modifiers.insert(.function)
            }
            return modifiers
        }
    }
}

#Preview {
    ShortcutSettingsPreview()
        .padding()
        .frame(width: 460)
}

private struct ShortcutSettingsPreview: View {
    @State private var settings = AppSettings.default

    var body: some View {
        ShortcutSettingsView(settings: $settings)
    }
}
