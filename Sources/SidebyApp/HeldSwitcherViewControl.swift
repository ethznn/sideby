import AppKit
import SidebyCore
import SidebyUI
import SwiftUI

enum HeldSwitcherViewMode: String { case wheel, table
    var presentation: HeldSwitcherPresentation { self == .wheel ? .wheel : .table }
}

@MainActor final class HeldSwitcherPlacement: ObservableObject {
    @Published var toolbarOffsetX: CGFloat = 0
}

/// A shared, non-scrolling toolbar. Window resizing preserves its screen anchor.
struct HeldSwitcherViewControl: View {
    static let height: CGFloat = 40
    let mode: HeldSwitcherViewMode
    let language: AppLanguage
    var wheelAvailable = true
    let select: (HeldSwitcherViewMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            choice(.wheel, title: language == .korean ? "원형" : "Circle", icon: "circle.hexagongrid")
            choice(.table, title: language == .korean ? "표" : "Table", icon: "rectangle.split.3x3")
        }.padding(3)
            .background(NativeSurfaceStyle.windowBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(NativeSurfaceStyle.frameBorder))
            .frame(maxWidth: .infinity).frame(height: Self.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(language == .korean ? "보기 방식" : "View mode")
            .accessibilityIdentifier("held-view-control")
    }

    private func choice(_ value: HeldSwitcherViewMode, title: String, icon: String) -> some View {
        Button { select(value) } label: {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .medium))
                .frame(width: 78, height: 26)
                .contentShape(Rectangle())
                .background(mode == value ? NativeSurfaceStyle.selectionBackground : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(mode == value ? NativeSurfaceStyle.accent.opacity(0.7) : .clear))
        }.buttonStyle(.plain).pointingHandCursor()
            .disabled(value == .wheel && !wheelAvailable)
            .accessibilityAddTraits(mode == value ? .isSelected : [])
            .accessibilityIdentifier(value == .wheel ? "held-show-wheel" : "wheel-show-table")
            .help(value == .wheel && !wheelAvailable
                ? (language == .korean ? "이 화면은 원형 보기를 표시하기에 너무 작습니다." : "This screen is too small for the circle view.") : title)
    }
}

enum HeldSwitcherPanelAnchor {
    static func origin(size: NSSize, topCenter: NSPoint, visibleFrame: NSRect) -> NSPoint {
        let bounds = visibleFrame.insetBy(dx: 16, dy: 16)
        return NSPoint(x: max(bounds.minX, min(topCenter.x - size.width / 2, bounds.maxX - size.width)),
                       y: max(bounds.minY, min(topCenter.y - size.height, bounds.maxY - size.height)))
    }
}
