import SidebyCore
import SidebyUI
import SwiftUI

/// The diagram is a pointer proxy; each UUID has exactly one native checkbox in the legend.
struct NativeDisplaySelector: View {
    let displays: [DisplayInfo]
    let selectedIDs: Set<String>
    let language: AppLanguage
    var showsArrangement = true
    let isEnabled: Bool
    let setSelected: (DisplayInfo, Bool) -> Void
    private var strings: SettingsRefreshStrings { .init(language: language) }

    static func placements(_ displays: [DisplayInfo], size: CGSize) -> [FloatingMenuDisplayPlacement] {
        FloatingMenuDisplayArrangementLayout.placements(
            for: displays.compactMap { display in display.frame.map { FloatingMenuDisplayLayoutInput(displayID: display.id, frame: $0) } },
            in: size, padding: 8, minimumDisplaySize: .zero)
    }

    var body: some View {
        Group {
            if displays.count > 2 {
                VStack(alignment: .leading, spacing: 8) {
                    if showsArrangement && WorkspaceTablePresentation.hasGeometry(displays) { diagram.frame(height: 92) }
                    legend
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    if showsArrangement && WorkspaceTablePresentation.hasGeometry(displays) { diagram.frame(width: 180, height: 92) }
                    legend
                }
            }
        }
    }

    @ViewBuilder private var diagram: some View {
        if WorkspaceTablePresentation.hasGeometry(displays) {
            GeometryReader { geometry in
                let placements = Self.placements(displays, size: geometry.size)
                    ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                        if let placement = placements.first(where: { $0.displayID == display.id }) {
                            let selected = selectedIDs.contains(display.id)
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(selected ? NativeSurfaceStyle.selectionBackground : NativeSurfaceStyle.inputBackground)
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(selected ? Color.accentColor : NativeSurfaceStyle.controlBorder, lineWidth: selected ? 2 : 1)
                                HStack(spacing: 3) {
                                    Text(strings.screenNumber(index)).monospacedDigit()
                                    if selected { Image(systemName: "checkmark").fontWeight(.bold) }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NativeSurfaceStyle.primaryText)
                            }
                            .frame(width: placement.frame.width, height: placement.frame.height)
                            .contentShape(Rectangle())
                            .onTapGesture { if isEnabled { setSelected(display, !selected) } }
                            .pointingHandCursor(isEnabled)
                            .position(x: placement.frame.midX, y: placement.frame.midY)
                            .help(display.name)
                            .accessibilityHidden(true)
                        }
                    }
                }
                .background(NativeSurfaceStyle.tableBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(NativeSurfaceStyle.frameBorder))
        }
    }

    private var legend: some View {
            VStack(alignment: .leading, spacing: 6) {
                if !displays.isEmpty && !WorkspaceTablePresentation.hasGeometry(displays) {
                    Text(strings.geometryUnavailable).font(.system(size: 12))
                        .foregroundStyle(NativeSurfaceStyle.secondaryText)
                }
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    Toggle(isOn: Binding(get: { selectedIDs.contains(display.id) }, set: { setSelected(display, $0) })) {
                        Text("\(strings.screenNumber(index)) · \(display.name) · \(display.isBuiltin ? strings.compactBuiltin : strings.compactExternal)\(display.isPrimary ? strings.primaryDisplaySuffix : "")")
                            .foregroundStyle(NativeSurfaceStyle.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox).pointingHandCursor()
                    .disabled(!isEnabled)
                    .accessibilityIdentifier("display-selection-" + display.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
