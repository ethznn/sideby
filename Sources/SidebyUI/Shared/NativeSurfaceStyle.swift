import AppKit
import SwiftUI

/// Additive styles for the product's native surfaces; legacy views keep Tokens.
public enum NativeSurfaceStyle {
    public static let bodySize: CGFloat = 13
    public static let descriptionSize: CGFloat = 12
    public static let metadataSize: CGFloat = 11
    public static let rowMinimumHeight: CGFloat = 60
    public static let primaryControlMinimumHeight: CGFloat = 32
    public static let groupCornerRadius: CGFloat = 8
    public static let rowCornerRadius: CGFloat = 7
    // Opaque, distinct semantic surfaces also work in inactive windows and Reduce Transparency.
    public static let windowBackground = adaptive(light: 0.96, dark: 0.20)
    public static let sidebarBackground = adaptive(light: 0.91, dark: 0.16)
    public static let tableBackground = adaptive(light: 1.0, dark: 0.25)
    public static let headerBackground = adaptive(light: 0.90, dark: 0.31)
    public static let inputBackground = adaptive(light: 1.0, dark: 0.20)
    public static let controlBackground = tableBackground
    public static let itemBackground = adaptive(light: 0.97, dark: 0.27)
    // Decorative frames should not compete with editable controls or focus rings.
    public static let frameBorder = adaptive(light: 0.80, dark: 0.40, highLight: 0.30, highDark: 0.86)
    public static let itemBorder = adaptive(light: 0.68, dark: 0.49, highLight: 0.30, highDark: 0.86)
    public static let controlBorder = adaptive(light: 0.52, dark: 0.60, highLight: 0.30, highDark: 0.86)
    public static let hoverBackground = adaptive(light: 0.93, dark: 0.32)
    public static let selectionBackground = Color(nsColor: .controlAccentColor).opacity(0.18)

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
    public static let primaryText = Color(nsColor: .labelColor)
    public static let secondaryText = adaptive(light: 0.34, dark: 0.78, highLight: 0.20, highDark: 0.94)
    public static let separator = Color(nsColor: .separatorColor)
}
