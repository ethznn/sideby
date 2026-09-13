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
    public static let controlBorder = adaptive(light: 0.48, dark: 0.67, highLight: 0.30, highDark: 0.86)
    public static let selectionBackground = Color(nsColor: .controlAccentColor).opacity(0.18)

    private static func adaptive(light: CGFloat, dark: CGFloat, highLight: CGFloat? = nil, highDark: CGFloat? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            let value: CGFloat
            switch match {
            case .darkAqua: value = dark
            case .accessibilityHighContrastDarkAqua: value = highDark ?? dark
            case .accessibilityHighContrastAqua: value = highLight ?? light
            default: value = light
            }
            return NSColor(white: value, alpha: 1)
        })
    }
    public static let primaryText = Color(nsColor: .labelColor)
    public static let secondaryText = Color(nsColor: .labelColor).opacity(0.85)
    public static let separator = Color(nsColor: .separatorColor)
}
