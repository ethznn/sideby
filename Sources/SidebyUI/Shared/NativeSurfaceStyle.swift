import AppKit
import SwiftUI

/// Additive styles for the product's native surfaces; legacy views keep Tokens.
public enum NativeSurfaceStyle {
    public static let bodySize: CGFloat = 13
    public static let descriptionSize: CGFloat = 12
    public static let metadataSize: CGFloat = 11
    public static let rowMinimumHeight: CGFloat = 60
    public static let primaryControlMinimumHeight: CGFloat = 32
    public static let groupCornerRadius: CGFloat = 12
    public static let rowCornerRadius: CGFloat = 9
    // Opaque, distinct semantic surfaces also work in inactive windows and Reduce Transparency.
    public static let windowBackground = adaptiveHex(light: 0xFCFCFD, dark: 0x24272F)
    public static let sidebarBackground = adaptiveHex(light: 0xF2F4F8, dark: 0x20232B)
    public static let tableBackground = adaptiveHex(light: 0xFFFFFF, dark: 0x2C3039)
    public static let headerBackground = adaptiveHex(light: 0xF2F4F8, dark: 0x20232B)
    public static let inputBackground = tableBackground
    public static let controlBackground = tableBackground
    public static let itemBackground = adaptiveHex(light: 0xFCFCFD, dark: 0x2C3039)
    // Decorative frames should not compete with editable controls or focus rings.
    public static let frameBorder = adaptive(light: 0.80, dark: 0.40, highLight: 0.30, highDark: 0.86)
    public static let itemBorder = adaptive(light: 0.68, dark: 0.49, highLight: 0.30, highDark: 0.86)
    public static let controlBorder = adaptive(light: 0.52, dark: 0.60, highLight: 0.30, highDark: 0.86)
    public static let hoverBackground = adaptiveHex(light: 0xEDF0F7, dark: 0x333845)
    public static let selectionBackground = adaptiveHex(light: 0xEDF0FF, dark: 0x343C61)
    public static let accent = adaptiveHex(light: 0x354ECC, dark: 0xB4BFFF)

    private static func adaptiveHex(light: UInt32, dark: UInt32, highLight: UInt32? = nil, highDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                || [NSAppearance.Name.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua].contains(appearance.name)
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? (increased ? highDark ?? dark : dark) : (increased ? highLight ?? light : light)
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }

    private static func adaptive(light: CGFloat, dark: CGFloat, highLight: CGFloat? = nil, highDark: CGFloat? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            // macOS 27 can resolve accessibility appearance names to ordinary
            // Aqua; also honor the user's actual Increase Contrast setting.
            let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                || [NSAppearance.Name.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua].contains(appearance.name)
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let value = isDark ? (increased ? highDark ?? dark : dark) : (increased ? highLight ?? light : light)
            return NSColor(white: value, alpha: 1)
        })
    }
    public static let primaryText = adaptiveHex(light: 0x202534, dark: 0xF0F2F8)
    public static let secondaryText = adaptiveHex(light: 0x616B80, dark: 0xADB6C9, highLight: 0x30384A, highDark: 0xF0F2F8)
    public static let separator = Color(nsColor: .separatorColor)
}
