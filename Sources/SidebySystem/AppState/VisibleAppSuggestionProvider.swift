import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import SidebyCore

public struct VisibleWindowCandidate: Equatable, Sendable {
    public let ownerName: String
    public let windowTitle: String?
    public let bounds: CGRect
    public let processIdentifier: pid_t?
    public let layer: Int

    public init(
        ownerName: String,
        windowTitle: String?,
        bounds: CGRect,
        processIdentifier: pid_t?,
        layer: Int
    ) {
        self.ownerName = ownerName
        self.windowTitle = windowTitle
        self.bounds = bounds
        self.processIdentifier = processIdentifier
        self.layer = layer
    }
}

public enum VisibleAppSuggestionResolver {
    public static func suggestion(
        for display: DisplayInfo,
        accessibilitySuggestion: VisibleAppSuggestion?,
        windows: [VisibleWindowCandidate]
    ) -> VisibleAppSuggestion? {
        if let accessibilitySuggestion {
            return accessibilitySuggestion
        }

        guard let displayFrame = display.frame?.cgRect else {
            return nil
        }

        return windows
            .filter { $0.layer == 0 }
            .compactMap { window -> (window: VisibleWindowCandidate, area: CGFloat)? in
                let ownerName = window.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !ownerName.isEmpty else {
                    return nil
                }

                let intersection = window.bounds.intersection(displayFrame)
                guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
                    return nil
                }

                return (window, intersection.width * intersection.height)
            }
            .max { lhs, rhs in
                if lhs.area == rhs.area {
                    return lhs.window.ownerName < rhs.window.ownerName
                }

                return lhs.area < rhs.area
            }
            .map { winner in
                VisibleAppSuggestion(
                    displayID: display.id,
                    appName: winner.window.ownerName,
                    windowTitle: winner.window.windowTitle,
                    source: .windowList
                )
            }
    }
}

public protocol VisibleWindowProviding: Sendable {
    func visibleWindows() -> [VisibleWindowCandidate]
}

public protocol AccessibilityVisibleAppProbing: Sendable {
    func suggestion(at point: CGPoint, displayID: String) -> VisibleAppSuggestion?
}

public struct MacVisibleAppSuggestionProvider: VisibleAppSuggestionProviding {
    private let accessibilityProbe: any AccessibilityVisibleAppProbing
    private let windowProvider: any VisibleWindowProviding

    public init(
        accessibilityProbe: any AccessibilityVisibleAppProbing = AXVisibleAppSuggestionProbe(),
        windowProvider: any VisibleWindowProviding = CGVisibleWindowProvider()
    ) {
        self.accessibilityProbe = accessibilityProbe
        self.windowProvider = windowProvider
    }

    public func suggestions(for displayLayout: DisplayLayout) -> [VisibleAppSuggestion] {
        let windows = windowProvider.visibleWindows()

        return displayLayout.displays.compactMap { display in
            let accessibilitySuggestion = samplePoints(for: display)
                .lazy
                .compactMap { point in
                    accessibilityProbe.suggestion(at: point, displayID: display.id)
                }
                .first

            return VisibleAppSuggestionResolver.suggestion(
                for: display,
                accessibilitySuggestion: accessibilitySuggestion,
                windows: windows
            )
        }
    }

    private func samplePoints(for display: DisplayInfo) -> [CGPoint] {
        guard let frame = display.frame?.cgRect else {
            return []
        }

        return [
            CGPoint(x: frame.midX, y: frame.midY),
            CGPoint(x: frame.minX + frame.width * 0.33, y: frame.midY),
            CGPoint(x: frame.minX + frame.width * 0.67, y: frame.midY),
            CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.33),
            CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.67)
        ]
    }
}

public struct AXVisibleAppSuggestionProbe: AccessibilityVisibleAppProbing {
    private let currentProcessIdentifier: pid_t

    public init(currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.currentProcessIdentifier = currentProcessIdentifier
    }

    public func suggestion(at point: CGPoint, displayID: String) -> VisibleAppSuggestion? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(),
            Float(point.x),
            Float(point.y),
            &element
        ) == .success,
            let element
        else {
            return nil
        }

        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &processIdentifier) == .success,
              processIdentifier != currentProcessIdentifier,
              let appName = NSRunningApplication(processIdentifier: processIdentifier)?.localizedName?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !appName.isEmpty
        else {
            return nil
        }

        let title = title(from: windowElement(for: element) ?? element)
        return VisibleAppSuggestion(
            displayID: displayID,
            appName: appName,
            windowTitle: title,
            source: .accessibility
        )
    }

    private func windowElement(for element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func title(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
              let title = value as? String
        else {
            return nil
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct CGVisibleWindowProvider: VisibleWindowProviding {
    private let currentProcessIdentifier: pid_t

    public init(currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.currentProcessIdentifier = currentProcessIdentifier
    }

    public func visibleWindows() -> [VisibleWindowCandidate] {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return windows.compactMap { dictionary in
            guard let ownerName = stringValue(dictionary[kCGWindowOwnerName as String]),
                  !ownerName.isEmpty,
                  let bounds = bounds(from: dictionary[kCGWindowBounds as String]),
                  bounds.width > 0,
                  bounds.height > 0
            else {
                return nil
            }

            let processIdentifier = intValue(dictionary[kCGWindowOwnerPID as String]).map(pid_t.init)
            guard processIdentifier != currentProcessIdentifier else {
                return nil
            }

            return VisibleWindowCandidate(
                ownerName: ownerName,
                windowTitle: stringValue(dictionary[kCGWindowName as String]),
                bounds: bounds,
                processIdentifier: processIdentifier,
                layer: intValue(dictionary[kCGWindowLayer as String]) ?? 0
            )
        }
    }

    private func bounds(from value: Any?) -> CGRect? {
        guard let dictionary = value as? [String: Any],
              let x = doubleValue(dictionary["X"]),
              let y = doubleValue(dictionary["Y"]),
              let width = doubleValue(dictionary["Width"]),
              let height = doubleValue(dictionary["Height"])
        else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }

        if let value = value as? CGFloat {
            return Double(value)
        }

        if let value = value as? Int {
            return Double(value)
        }

        if let value = value as? NSNumber {
            return value.doubleValue
        }

        return nil
    }
}

private extension DisplayFrame {
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
