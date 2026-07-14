import Foundation
import SidebyCore
import SwiftUI

public enum FloatingMenuContextSectionItem: Equatable, Sendable {
    case captureControls
    case matrix
}

public enum FloatingMenuContextSectionContent: Sendable {
    public static let defaultItems: [FloatingMenuContextSectionItem] = [
        .captureControls,
        .matrix
    ]
}

public enum FloatingMenuPinnedHeaderItem: Equatable, Hashable, Sendable {
    case masterControl
    case navigationControls
}

public enum FloatingMenuPinnedHeaderContent: Sendable {
    public static let defaultItems: [FloatingMenuPinnedHeaderItem] = [
        .masterControl,
        .navigationControls
    ]
}

public enum FloatingMenuSwitchSectionItem: Equatable, Hashable, Sendable {
    case navigationControls
    case targetSummary
    case hint
}

public enum FloatingMenuSwitchSectionContent: Sendable {
    public static let defaultItems: [FloatingMenuSwitchSectionItem] = [
        .navigationControls,
        .targetSummary,
        .hint
    ]

    public static let pinnedItems: [FloatingMenuSwitchSectionItem] = [
        .navigationControls
    ]
}

public enum FloatingMenuContextCaptureAvailability: Sendable {
    public static func canStart(
        displayCount: Int,
        isSwitching: Bool,
        isCapturing: Bool
    ) -> Bool {
        displayCount > 0 && !isSwitching && !isCapturing
    }
}

public enum FloatingMenuContextMatrixAxis: Equatable, Sendable {
    case contexts
    case displays
}

public enum FloatingMenuContextMatrixAxisHeaderContent: Sendable {
    public static let topTrailing: FloatingMenuContextMatrixAxis = .contexts
    public static let bottomLeading: FloatingMenuContextMatrixAxis = .displays
}

public struct FloatingMenuContextMatrixHeaderHeightPreferenceKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public enum FloatingMenuPanelPresentationTrigger: Equatable, Sendable {
    case menuBarIcon
    case onboardingCompletion
    case settingsRedirect
}

public enum FloatingMenuPanelPresentationAnchor: Equatable, Sendable {
    case sourceWindow
    case menuBarFallback
}

public enum FloatingMenuPanelPresentationPolicy: Sendable {
    public static func anchor(
        for trigger: FloatingMenuPanelPresentationTrigger
    ) -> FloatingMenuPanelPresentationAnchor {
        switch trigger {
        case .menuBarIcon:
            return .sourceWindow
        case .onboardingCompletion, .settingsRedirect:
            return .menuBarFallback
        }
    }
}

public enum FloatingMenuContextMatrixLayout: Sendable {
    public static let headerLineLimit = 1

    public static func displayColumnWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 72 : 170
    }

    public static func contextColumnWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 72 : 220
    }

    public static func displayColumnMaximumWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 180 : 260
    }

    public static func clampedDisplayColumnWidth(
        _ width: CGFloat,
        isCompact: Bool
    ) -> CGFloat {
        min(
            max(width, displayColumnWidth(isCompact: isCompact)),
            displayColumnMaximumWidth(isCompact: isCompact)
        )
    }

    public static func nameLineLimit(isCompact: Bool) -> Int {
        2
    }

    public static func statusTitle(
        for state: ContextRowState,
        isCompact: Bool,
        strings: SBSStrings
    ) -> String? {
        switch state {
        case .current:
            return isCompact ? strings.currentContextCompact : strings.currentContext
        case .needsSync:
            return isCompact ? strings.contextNeedsSyncCompact : strings.contextNeedsSync
        case .paused:
            return isCompact ? strings.contextMatchingPausedCompact : strings.contextMatchingPaused
        case .normal:
            return nil
        }
    }
}

public enum FloatingMenuInteractiveControlKind: Equatable, Sendable {
    case button
    case toggle
    case picker
}

public enum FloatingMenuInteractiveCursorPolicy: Sendable {
    public static func usesPointingHand(for kind: FloatingMenuInteractiveControlKind) -> Bool {
        switch kind {
        case .button, .toggle, .picker:
            return true
        }
    }
}

public enum FloatingMenuCollapsibleSection: Equatable, Hashable, Sendable {
    case input
    case permissions
    case general
}

public enum FloatingMenuCollapsibleSectionContent: Sendable {
    public static let defaultItems: [FloatingMenuCollapsibleSection] = [
        .input,
        .permissions,
        .general
    ]
}

public enum FloatingMenuGeneralActionItem: Equatable, Hashable, Sendable {
    case replayOnboarding
    case refresh
    case checkForUpdates
}

public enum FloatingMenuGeneralActionContent: Sendable {
    public static let defaultItems: [FloatingMenuGeneralActionItem] = [
        .replayOnboarding,
        .refresh,
        .checkForUpdates
    ]
}

public struct FloatingMenuSectionExpansion: Equatable, Sendable {
    public var showsInput: Bool
    public var showsPermissions: Bool
    public var showsGeneral: Bool

    public init(
        showsInput: Bool,
        showsPermissions: Bool,
        showsGeneral: Bool
    ) {
        self.showsInput = showsInput
        self.showsPermissions = showsPermissions
        self.showsGeneral = showsGeneral
    }

    public static let `default` = FloatingMenuSectionExpansion(
        showsInput: false,
        showsPermissions: false,
        showsGeneral: false
    )

    public func isExpanded(_ section: FloatingMenuCollapsibleSection) -> Bool {
        switch section {
        case .input:
            showsInput
        case .permissions:
            showsPermissions
        case .general:
            showsGeneral
        }
    }

    public mutating func set(
        _ section: FloatingMenuCollapsibleSection,
        isExpanded: Bool
    ) {
        switch section {
        case .input:
            showsInput = isExpanded
        case .permissions:
            showsPermissions = isExpanded
        case .general:
            showsGeneral = isExpanded
        }
    }

    public mutating func toggle(_ section: FloatingMenuCollapsibleSection) {
        set(section, isExpanded: !isExpanded(section))
    }
}

public struct FloatingMenuDisplayLayoutInput: Equatable, Sendable {
    public let displayID: String
    public let frame: DisplayFrame

    public init(displayID: String, frame: DisplayFrame) {
        self.displayID = displayID
        self.frame = frame
    }
}

public struct FloatingMenuDisplayPlacement: Equatable, Sendable {
    public let displayID: String
    public let frame: CGRect

    public init(displayID: String, frame: CGRect) {
        self.displayID = displayID
        self.frame = frame
    }
}

public enum FloatingMenuDisplayArrangementLayout: Sendable {
    public static let stageHeight: CGFloat = 220
    public static let padding: CGFloat = 24
    public static let minimumDisplaySize = CGSize(width: 72, height: 46)

    public static func placements(
        for displays: [FloatingMenuDisplayLayoutInput],
        in size: CGSize,
        padding: CGFloat = Self.padding,
        minimumDisplaySize: CGSize = Self.minimumDisplaySize
    ) -> [FloatingMenuDisplayPlacement] {
        guard !displays.isEmpty else {
            return []
        }

        let minX = displays.map(\.frame.x).min() ?? 0
        let minY = displays.map(\.frame.y).min() ?? 0
        let maxX = displays.map { $0.frame.x + $0.frame.width }.max() ?? 1
        let maxY = displays.map { $0.frame.y + $0.frame.height }.max() ?? 1
        let unionWidth = max(maxX - minX, 1)
        let unionHeight = max(maxY - minY, 1)
        let availableWidth = max(size.width - padding * 2, 1)
        let availableHeight = max(size.height - padding * 2, 1)
        let arrangementScale = min(
            availableWidth / CGFloat(unionWidth),
            availableHeight / CGFloat(unionHeight)
        )

        let rawPlacements = displays.map { display in
            let frame = display.frame
            let scaledFrame = CGRect(
                x: CGFloat(frame.x - minX) * arrangementScale,
                y: CGFloat(frame.y - minY) * arrangementScale,
                width: CGFloat(frame.width) * arrangementScale,
                height: CGFloat(frame.height) * arrangementScale
            )
            let fittedFrame = frameWithReadableMinimum(
                scaledFrame,
                minimumSize: minimumDisplaySize
            )
            return FloatingMenuDisplayPlacement(displayID: display.displayID, frame: fittedFrame)
        }

        let scaledPlacements = compressSpacing(
            rawPlacements,
            maxSize: CGSize(width: availableWidth, height: availableHeight)
        )
        let scaledUnion = scaledPlacements.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let offset = CGPoint(
            x: (size.width - scaledUnion.width) / 2 - scaledUnion.minX,
            y: (size.height - scaledUnion.height) / 2 - scaledUnion.minY
        )

        return scaledPlacements.map { placement in
            FloatingMenuDisplayPlacement(
                displayID: placement.displayID,
                frame: placement.frame.offsetBy(dx: offset.x, dy: offset.y)
            )
        }
    }

    private static func frameWithReadableMinimum(
        _ frame: CGRect,
        minimumSize: CGSize
    ) -> CGRect {
        let width = max(frame.width, minimumSize.width)
        let height = max(frame.height, minimumSize.height)
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func compressSpacing(
        _ placements: [FloatingMenuDisplayPlacement],
        maxSize: CGSize
    ) -> [FloatingMenuDisplayPlacement] {
        let union = placements.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let widestDisplay = placements.map(\.frame.width).max() ?? 0
        let tallestDisplay = placements.map(\.frame.height).max() ?? 0
        let xScale = spacingScale(
            currentSpan: union.width,
            largestItemSpan: widestDisplay,
            maxSpan: maxSize.width
        )
        let yScale = spacingScale(
            currentSpan: union.height,
            largestItemSpan: tallestDisplay,
            maxSpan: maxSize.height
        )

        return placements.map { placement in
            let frame = placement.frame
            let center = CGPoint(
                x: union.center.x + (frame.midX - union.center.x) * xScale,
                y: union.center.y + (frame.midY - union.center.y) * yScale
            )
            return FloatingMenuDisplayPlacement(
                displayID: placement.displayID,
                frame: CGRect(
                    x: center.x - frame.width / 2,
                    y: center.y - frame.height / 2,
                    width: frame.width,
                    height: frame.height
                )
            )
        }
    }

    private static func spacingScale(
        currentSpan: CGFloat,
        largestItemSpan: CGFloat,
        maxSpan: CGFloat
    ) -> CGFloat {
        guard currentSpan > maxSpan else {
            return 1
        }

        let movableSpan = max(currentSpan - largestItemSpan, 1)
        return max(0, min(1, (maxSpan - largestItemSpan) / movableSpan))
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

public enum FloatingMenuPanelLayout {
    public static let defaultSize = NSSize(width: 520, height: 640)
    public static let minimumSize = NSSize(width: 520, height: 420)
    public static let screenPadding: CGFloat = 24

    public static func contentSize(
        currentContentSize: NSSize?,
        isNewPanel: Bool,
        visibleFrame: NSRect?
    ) -> NSSize {
        let preferredSize = isNewPanel
            ? defaultSize
            : currentContentSize ?? defaultSize
        return clampedContentSize(preferredSize, visibleFrame: visibleFrame)
    }

    public static func presentationContentSize(
        capturedExistingContentSize: NSSize?,
        currentContentSize: NSSize?,
        isNewPanel: Bool,
        visibleFrame: NSRect?
    ) -> NSSize {
        let currentContentSize = isNewPanel
            ? currentContentSize
            : capturedExistingContentSize ?? currentContentSize
        return contentSize(
            currentContentSize: currentContentSize,
            isNewPanel: isNewPanel,
            visibleFrame: visibleFrame
        )
    }

    public static func clampedContentSize(
        _ size: NSSize,
        visibleFrame: NSRect?
    ) -> NSSize {
        let maxWidth: CGFloat
        let maxHeight: CGFloat
        if let visibleFrame {
            maxWidth = max(minimumSize.width, visibleFrame.width - screenPadding)
            maxHeight = max(minimumSize.height, visibleFrame.height - screenPadding)
        } else {
            maxWidth = max(size.width, minimumSize.width)
            maxHeight = max(size.height, minimumSize.height)
        }

        return NSSize(
            width: min(max(size.width, minimumSize.width), maxWidth),
            height: min(max(size.height, minimumSize.height), maxHeight)
        )
    }
}
