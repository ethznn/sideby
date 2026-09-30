import AppKit
import SidebyCore
import SidebyUI
import SwiftUI

struct DesktopNameStrings {
    let language: AppLanguage
    private func text(_ en: String, _ ko: String) -> String { language == .korean ? ko : en }
    var rename: String { text("Rename desktop…", "데스크탑 이름 변경…") }
    var title: String { text("Rename desktop", "데스크탑 이름 변경") }
    var automatic: String { text("Use automatic name", "자동 이름 사용") }
    var name: String { text("Desktop name", "데스크탑 이름") }
    var hint: String { text("This name appears in Sideby. The Mission Control name stays the same.", "Sideby에 표시할 이름입니다. Mission Control의 이름은 그대로 유지됩니다.") }
    var save: String { text("Save", "저장") }
    var cancel: String { text("Cancel", "취소") }
    var unavailable: String { text("This desktop could not be identified. Check that its display is connected, then reopen the name editor.", "이 데스크탑을 확인할 수 없습니다. 화면이 연결되어 있는지 확인한 뒤 이름 변경을 다시 열어 주세요.") }
    var conflict: String { text("The name was changed in another window. Reopen the editor to see the latest name.", "다른 창에서 이름을 변경했습니다. 다시 열어 최신 이름을 확인해 주세요.") }
    var actions: String { text("Desktop actions", "데스크탑 메뉴") }
    func shared(_ count: Int) -> String {
        text("Applies to all \(count) setups using this desktop.", "이 데스크탑을 사용하는 구성 \(count)개에 함께 적용됩니다.")
    }
    func automaticPreview(_ name: String) -> String { text("Automatic: \(name)", "자동 이름: \(name)") }
    func validation(_ result: DesktopNameValidation) -> String? {
        switch result {
        case .valid: nil
        case .empty: text("Enter a name.", "이름을 입력해 주세요.")
        case .tooLong: text("Use 60 characters or fewer.", "60자 이내로 입력해 주세요.")
        case .multipleLines: text("Use a single line without control characters.", "줄바꿈 없이 한 줄로 입력해 주세요.")
        }
    }
    func failure(_ result: DesktopNameSaveResult) -> String? {
        switch result {
        case .saved: nil
        case let .invalid(value): validation(value)
        case .unavailable: unavailable
        case .conflict: conflict
        }
    }
}

struct DesktopNameEditor: View {
    @ObservedObject var model: SidebyAppModel
    let target: DesktopNameEditTarget
    let dismiss: () -> Void
    @State private var draft: String
    @State private var saveError: String?
    private var copy: DesktopNameStrings { .init(language: model.settings.language) }
    private var desktop: String { SettingsRefreshStrings(language: model.settings.language).desktop(target.spaceIndex) }

    init(model: SidebyAppModel, target: DesktopNameEditTarget, dismiss: @escaping () -> Void) {
        self.model = model
        self.target = target
        self.dismiss = dismiss
        _draft = State(initialValue: target.originalAlias ?? target.automaticName
            ?? SettingsRefreshStrings(language: model.settings.language).desktop(target.spaceIndex))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(model.displayName(for: target.displayID) + " · " + desktop)
                    .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DesktopNameTextField(text: $draft, label: copy.name, submit: save, cancel: dismiss)
                .frame(height: 26)
                .accessibilityIdentifier("desktop-name-field")
            if let error = saveError ?? copy.validation(DesktopNameValidation.validate(draft)) {
                Text(error).font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("desktop-name-error")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(copy.hint)
                if target.sharedCount > 1 { Text(copy.shared(target.sharedCount)) }
                Text(copy.automaticPreview(target.automaticName ?? desktop))
                    .lineLimit(2).help(target.automaticName ?? desktop)
            }
            .font(.system(size: 12)).foregroundStyle(NativeSurfaceStyle.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button(copy.cancel, action: dismiss).pointingHandCursor()
                Button(copy.save, action: save).buttonStyle(.borderedProminent).pointingHandCursor()
                    .disabled(copy.validation(DesktopNameValidation.validate(draft)) != nil)
                    .accessibilityIdentifier("save-desktop-name")
            }
        }
        .padding(16).frame(width: 340)
        .foregroundStyle(NativeSurfaceStyle.primaryText)
        .onChange(of: draft) { _, _ in saveError = nil }
        .onExitCommand(perform: dismiss)
    }

    private func save() {
        // Return while composing Hangul (or another IME) only commits that composition.
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return }
        let result = model.saveDesktopName(draft, target: target)
        if result == .saved { dismiss() } else { saveError = copy.failure(result) }
    }
}

/// Native field editor supplies selection, undo, accessibility and IME behavior.
struct DesktopNameTextField: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.font = .systemFont(ofSize: 13)
        field.setAccessibilityLabel(label)
        field.setAccessibilityIdentifier("desktop-name-field")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
            field.selectText(nil)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.setAccessibilityLabel(label)
        // Never replace marked text while the native editor owns the draft.
        if field.currentEditor() == nil, field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DesktopNameTextField
        init(_ parent: DesktopNameTextField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.text = control.stringValue
                parent.submit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.cancel()
                return true
            }
            return false
        }
    }
}
