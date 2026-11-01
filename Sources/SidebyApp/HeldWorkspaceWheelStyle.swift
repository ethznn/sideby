import AppKit
import SidebyUI
import SwiftUI

/// Opaque, inexpensive surfaces: readable over any desktop, including with
/// Reduce Transparency. High Contrast retains explicit control boundaries.
enum HeldWorkspaceWheelStyle {
    static let border = color(light: 0xCDD1DC, dark: 0x555B69, highLight: 0x525968, highDark: 0xBCC4D5)
    static let activeBorder = color(light: 0x929FDD, dark: 0x8D9BD7, highLight: 0x354ECC, highDark: 0xCED6FF)
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
