import SidebyCore
import SwiftUI

struct ConnectionNameEditor: View {
    @ObservedObject var model: SidebyAppModel
    let target: ContextDefinition
    let close: () -> Void
    @State private var name: String
    @State private var error: String?

    init(model: SidebyAppModel, target: ContextDefinition, close: @escaping () -> Void) {
        self.model = model; self.target = target; self.close = close
        _name = State(initialValue: target.name)
    }

    private var valid: Bool { if case .valid = DesktopNameValidation.validate(name) { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.connectionCopy.rename).font(.headline)
            DesktopNameTextField(text: $name, label: model.saveCopy.name, submit: save, cancel: close)
                .frame(height: 26).accessibilityIdentifier("connection-name-field")
            if let message = error ?? (valid ? nil : model.connectionCopy.invalidName) {
                Text(message).font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("connection-name-error")
            }
            HStack {
                Spacer()
                Button(model.saveCopy.cancel, action: close).pointingHandCursor()
                    .accessibilityIdentifier("connection-name-cancel")
                Button(model.connectionCopy.text("Apply", "적용"), action: save)
                    .buttonStyle(.borderedProminent).pointingHandCursor()
                    .disabled(!valid || !model.canChangeSavedWorkspaces)
                    .accessibilityIdentifier("connection-name-apply")
            }
        }.padding(18).frame(width: 330)
            .onChange(of: name) { _, _ in error = nil }
    }

    private func save() {
        guard valid, model.canChangeSavedWorkspaces else { return }
        if model.renameCurrentConnection(target.id, originalName: target.name, name: name) { close() }
        else { error = model.workspaceSaveMessage }
    }
}
