import SidebyCore
import SwiftUI

public struct NativeWorkspaceRow: View {
    private let name: String
    private let metadata: String
    private let shortcut: String?
    private let isCurrent: Bool
    private let isEnabled: Bool
    private let action: () -> Void
    private let language: AppLanguage
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @ScaledMetric(relativeTo: .body) private var bodySize = NativeSurfaceStyle.bodySize
    @ScaledMetric(relativeTo: .caption) private var metadataSize = NativeSurfaceStyle.metadataSize

    public init(name: String, metadata: String, shortcut: String?,
                isCurrent: Bool, isEnabled: Bool, action: @escaping () -> Void,
                language: AppLanguage = .english) {
        self.name = name
        self.metadata = metadata
        self.shortcut = shortcut
        self.isCurrent = isCurrent
        self.isEnabled = isEnabled
        self.action = action
        self.language = language
    }

    public var body: some View {
        let strings = SBSStrings(language: language)
        Group {
            if isCurrent {
                rowContent
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: NativeSurfaceStyle.rowCornerRadius))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(name)
                    .accessibilityValue(([strings.workspaceCurrent, metadata] + [shortcut].compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: ", "))
                    .accessibilityAddTraits(.isSelected)
            } else {
                Button(action: action) { rowContent }
                    .buttonStyle(NativeWorkspaceButtonStyle(isHovered: isHovered, isFocused: isFocused))
                    .focused($isFocused)
                    .disabled(!isEnabled)
                    .onHover { isHovered = $0 && isEnabled }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(strings.workspaceGoTo(name))
                    .accessibilityValue(([metadata] + [shortcut].compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: ", "))
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isCurrent ? "checkmark.circle.fill" : "rectangle.on.rectangle")
                .font(.system(size: 18))
                .foregroundStyle(isCurrent ? Color.accentColor : NativeSurfaceStyle.secondaryText)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: bodySize, weight: .medium))
                    .foregroundStyle(NativeSurfaceStyle.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if isCurrent || !metadata.isEmpty {
                    Text(visibleMetadata)
                        .font(.system(size: metadataSize))
                        .foregroundStyle(NativeSurfaceStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let shortcut, !shortcut.isEmpty {
                Text(shortcut)
                    .font(.system(size: metadataSize).monospacedDigit())
                    .foregroundStyle(NativeSurfaceStyle.secondaryText)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: NativeSurfaceStyle.rowMinimumHeight)
        .contentShape(Rectangle())
    }

    private var visibleMetadata: String {
        let current = language == .korean ? "현재" : "Current"
        return ([isCurrent ? current : nil, metadata.isEmpty ? nil : metadata])
            .compactMap { $0 }.joined(separator: " · ")
    }
}

private struct NativeWorkspaceButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: NativeSurfaceStyle.rowCornerRadius)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(isEnabled && (configuration.isPressed || isHovered) ? 1 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: NativeSurfaceStyle.rowCornerRadius)
                    .strokeBorder(Color.accentColor, lineWidth: isFocused ? 3 : 0)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

public enum NativeStatusTone { case neutral, warning, error }

public struct NativeStatusSection<Actions: View>: View {
    private let tone: NativeStatusTone
    private let title: String
    private let message: String
    private let actions: Actions
    @ScaledMetric(relativeTo: .body) private var bodySize = NativeSurfaceStyle.bodySize
    @ScaledMetric(relativeTo: .subheadline) private var descriptionSize = NativeSurfaceStyle.descriptionSize

    public init(tone: NativeStatusTone, title: String, message: String,
                @ViewBuilder actions: () -> Actions) {
        self.tone = tone
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(symbolColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: bodySize, weight: .semibold))
                    .foregroundStyle(NativeSurfaceStyle.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.system(size: descriptionSize))
                    .foregroundStyle(NativeSurfaceStyle.secondaryText)
                if Actions.self != EmptyView.self {
                    actions
                        .controlSize(.large)
                        .frame(minHeight: NativeSurfaceStyle.primaryControlMinimumHeight, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(NativeSurfaceStyle.controlBackground, in: RoundedRectangle(cornerRadius: NativeSurfaceStyle.groupCornerRadius))
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch tone {
        case .neutral: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "exclamationmark.circle"
        }
    }

    private var symbolColor: Color {
        switch tone {
        case .neutral: NativeSurfaceStyle.secondaryText
        case .warning: Color(nsColor: .systemOrange)
        case .error: Color(nsColor: .systemRed)
        }
    }
}

public struct NativePermissionRow<Actions: View>: View {
    private let name: String
    private let reason: String
    private let status: String
    private let actions: Actions
    @ScaledMetric(relativeTo: .body) private var bodySize = NativeSurfaceStyle.bodySize
    @ScaledMetric(relativeTo: .subheadline) private var descriptionSize = NativeSurfaceStyle.descriptionSize
    @ScaledMetric(relativeTo: .caption) private var metadataSize = NativeSurfaceStyle.metadataSize

    public init(name: String, reason: String, status: String,
                @ViewBuilder actions: () -> Actions) {
        self.name = name
        self.reason = reason
        self.status = status
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(name).font(.system(size: bodySize, weight: .medium))
                    .foregroundStyle(NativeSurfaceStyle.primaryText)
                Text(reason).font(.system(size: descriptionSize))
                    .foregroundStyle(NativeSurfaceStyle.secondaryText)
                Text(status).font(.system(size: metadataSize, weight: .medium))
                    .foregroundStyle(NativeSurfaceStyle.primaryText)
            }
            .accessibilityElement(children: .combine)
            if Actions.self != EmptyView.self {
                actions.controlSize(.large)
                    .frame(minHeight: NativeSurfaceStyle.primaryControlMinimumHeight, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(16)
        .accessibilityElement(children: .contain)
    }
}

public struct NativeInlineNameField: View {
    private let identity: String
    private let value: String
    private let label: String
    private let onChange: (String) -> Void
    private let compact: Bool

    public init(identity: String, value: String, label: String, compact: Bool = false,
                onChange: @escaping (String) -> Void) {
        self.identity = identity
        self.compact = compact
        self.value = value
        self.label = label
        self.onChange = onChange
    }

    public var body: some View {
        NativeNameFieldEditor(value: value, label: label, compact: compact, onChange: onChange)
            .id(identity)
    }
}

private struct NativeNameFieldEditor: View {
    let value: String
    let label: String
    let onChange: (String) -> Void
    let compact: Bool
    @State private var editing: NativeNameEditingState
    @FocusState private var isFocused: Bool
    @ScaledMetric(relativeTo: .body) private var bodySize = NativeSurfaceStyle.bodySize

    init(value: String, label: String, compact: Bool, onChange: @escaping (String) -> Void) {
        self.value = value
        self.label = label
        self.compact = compact
        self.onChange = onChange
        _editing = State(initialValue: NativeNameEditingState(value: value))
    }

    var body: some View {
        TextField(label, text: Binding(
            get: { editing.draft },
            set: { draft in
                editing.edit(draft)
                onChange(draft)
            }
        ), axis: .vertical)
        .font(.system(size: bodySize))
        .textFieldStyle(.plain)
        .padding(.horizontal, 5).padding(.vertical, compact ? 3 : 6)
        .background(NativeSurfaceStyle.inputBackground, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isFocused ? Color.accentColor : NativeSurfaceStyle.controlBorder, lineWidth: isFocused ? 2 : 1))
        .frame(minHeight: compact ? 26 : NativeSurfaceStyle.primaryControlMinimumHeight)
        .focused($isFocused)
        .accessibilityLabel(label)
        .onChange(of: value) { _, newValue in editing.receiveExternalValue(newValue) }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                onChange(editing.draft)
                // A normalized echo may equal the old model value, so SwiftUI
                // need not emit onChange(value). Reconcile explicitly on blur.
                editing.receiveExternalValue(value)
            }
            editing.isFocused = focused
        }
        .onSubmit {
            onChange(editing.draft)
            isFocused = false
        }
        .onDisappear {
            if editing.isFocused { onChange(editing.draft) }
        }
    }
}
