import AppKit
import SwiftUI
import XCTest
import SidebyUI

@MainActor final class NativeSurfaceContrastTests: XCTestCase {
    func testSupportingTextRemainsReadableOnEveryNeutralSurface() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            try withAppearance(name) {
                let text = try luminance(NativeSurfaceStyle.secondaryText)
                for surface in [NativeSurfaceStyle.windowBackground, NativeSurfaceStyle.sidebarBackground,
                                NativeSurfaceStyle.tableBackground, NativeSurfaceStyle.headerBackground,
                                NativeSurfaceStyle.inputBackground, NativeSurfaceStyle.itemBackground,
                                NativeSurfaceStyle.hoverBackground] {
                    XCTAssertGreaterThanOrEqual(contrast(text, try luminance(surface)), 4.5, name.rawValue)
                }
            }
        }
    }

    private func withAppearance<T>(_ name: NSAppearance.Name, body: () throws -> T) throws -> T {
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        var result: Result<T, Error>?
        appearance.performAsCurrentDrawingAppearance { result = Result(catching: body) }
        return try XCTUnwrap(result).get()
    }

    private func luminance(_ color: Color) throws -> Double {
        let rgb = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
        func linear(_ value: CGFloat) -> Double {
            let c = Double(value)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }

    private func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
