import AppKit
import SidebyUI
import SwiftUI

/// Opaque, inexpensive surfaces: readable over any desktop, including with
/// Reduce Transparency. High Contrast retains explicit control boundaries.
enum HeldWorkspaceWheelStyle {
    static let border = color(light: 0xCDD1DC, dark: 0x555B69, highLight: 0x525968, highDark: 0xBCC4D5)
    static let activeBorder = color(light: 0x929FDD, dark: 0x8D9BD7, highLight: 0x354ECC, highDark: 0xCED6FF)
    static let outline = color(light: 0x727DB8, dark: 0xADB8F0, highLight: 0x354280, highDark: 0xE0E6FF)
    static let outlineHighlight = color(light: 0x4E5AD2, dark: 0xEEF0FF, highLight: 0x2638A0, highDark: 0xFFFFFF)
    static let controlBorder = color(light: 0x858DB5, dark: 0x939DC9, highLight: 0x354280, highDark: 0xE0E6FF)
    static let controlShadow = Color.black.opacity(0.24)
    static let chrome = color(light: 0xF8F9FC, dark: 0x252831)
    private static let top = color(light: 0xFFFFFF, dark: 0x30343E)
    private static let bottom = color(light: 0xF2F4F9, dark: 0x272A33)
    private static let activeTop = color(light: 0xF0F3FF, dark: 0x3A425C)
    private static let activeBottom = color(light: 0xE8EDFE, dark: 0x30374E)
    private static let centerTop = color(light: 0xFFFFFF, dark: 0x2B2F38)
    private static let centerBottom = color(light: 0xF8F9FC, dark: 0x22252D)

    static func surface(active: Bool) -> LinearGradient {
        LinearGradient(colors: active ? [activeTop, activeBottom] : [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    static func center(active: Bool) -> LinearGradient {
        LinearGradient(colors: active ? [activeTop, activeBottom] : [centerTop, centerBottom], startPoint: .top, endPoint: .bottom)
    }

    private static func color(light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                || [.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua].contains(appearance.name)
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? (highContrast ? highDark ?? dark : dark) : (highContrast ? highLight ?? light : light)
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

/// Detached controls need their own opaque surface and boundary, including when
/// the label is disabled. The shadow belongs to the simple shape, not its text.
private struct HeldFloatingSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(HeldWorkspaceWheelStyle.chrome)
                    .shadow(color: HeldWorkspaceWheelStyle.controlShadow, radius: 4, x: 0, y: 2)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(HeldWorkspaceWheelStyle.controlBorder, lineWidth: 1.25)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func heldFloatingSurface<S: InsettableShape>(in shape: S) -> some View {
        modifier(HeldFloatingSurface(shape: shape))
    }
}
