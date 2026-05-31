import Foundation

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

public enum FloatingMenuContextCaptureAvailability: Sendable {
    public static func canStart(
        displayCount: Int,
        isSwitching: Bool,
        isCapturing: Bool
    ) -> Bool {
        displayCount > 0 && !isSwitching && !isCapturing
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
        isCompact ? 132 : 170
    }

    public static func contextColumnWidth(isCompact: Bool) -> CGFloat {
        isCompact ? 170 * 2 / 3 : 220
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

public enum FloatingMenuCollapsibleSection: Equatable, Sendable {
    case input
    case permissions
    case general
    case diagnostics
}

public struct FloatingMenuSectionExpansion: Equatable, Sendable {
    public var showsInput: Bool
    public var showsPermissions: Bool
    public var showsGeneral: Bool
    public var showsDiagnostics: Bool

    public init(
        showsInput: Bool,
        showsPermissions: Bool,
        showsGeneral: Bool,
        showsDiagnostics: Bool
    ) {
        self.showsInput = showsInput
        self.showsPermissions = showsPermissions
        self.showsGeneral = showsGeneral
        self.showsDiagnostics = showsDiagnostics
    }

    public static let `default` = FloatingMenuSectionExpansion(
        showsInput: false,
        showsPermissions: false,
        showsGeneral: false,
        showsDiagnostics: false
    )

    public func isExpanded(_ section: FloatingMenuCollapsibleSection) -> Bool {
        switch section {
        case .input:
            showsInput
        case .permissions:
            showsPermissions
        case .general:
            showsGeneral
        case .diagnostics:
            showsDiagnostics
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
        case .diagnostics:
            showsDiagnostics = isExpanded
        }
    }

    public mutating func toggle(_ section: FloatingMenuCollapsibleSection) {
        set(section, isExpanded: !isExpanded(section))
    }
}

public enum FloatingMenuPanelLayout {
    public static let defaultSize = NSSize(width: 720, height: 640)
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
