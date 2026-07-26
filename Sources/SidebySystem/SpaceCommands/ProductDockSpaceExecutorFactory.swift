import Foundation
import SidebyCore

public struct ProductSpaceExecutorRecipe: Equatable, Sendable {
    public enum Backend: Equatable, Sendable {
        case dockSwipe
    }

    public enum CursorVisibility: Equatable, Sendable {
        case coreGraphicsOnly
    }

    public enum CursorShield: Equatable, Sendable {
        case none
    }

    public let backend: Backend
    public let cursorVisibility: CursorVisibility
    public let cursorShield: CursorShield

    public init(
        backend: Backend,
        cursorVisibility: CursorVisibility,
        cursorShield: CursorShield
    ) {
        self.backend = backend
        self.cursorVisibility = cursorVisibility
        self.cursorShield = cursorShield
    }
}

struct ProductDockSpaceExecutorDependencies: Sendable {
    let poster: any DockSwipeEventPosting
    let targetProvider: any DisplaySwitchTargetProviding
    let cursor: any CursorPositioning
    let visibilityController: any CursorVisibilityControlling
    let cursorShield: any CursorShielding
    let cursorAssociationController: any MouseCursorAssociationControlling
    let postEventAccessChecker: any PostEventAccessChecking
    let hideSettleDelay: TimeInterval
    let focusDelay: TimeInterval
    let switchDelay: TimeInterval
    let transitionSettleDelay: TimeInterval
    let restoreDelay: TimeInterval

    init(
        poster: any DockSwipeEventPosting,
        targetProvider: any DisplaySwitchTargetProviding,
        cursor: any CursorPositioning,
        visibilityController: any CursorVisibilityControlling,
        cursorShield: any CursorShielding,
        cursorAssociationController: any MouseCursorAssociationControlling,
        postEventAccessChecker: any PostEventAccessChecking,
        hideSettleDelay: TimeInterval = HiddenCursorDisplaySpaceCommandExecutor.defaultHideSettleDelay,
        focusDelay: TimeInterval = HiddenCursorDisplaySpaceCommandExecutor.defaultFocusDelay,
        switchDelay: TimeInterval = HiddenCursorDisplaySpaceCommandExecutor.defaultSwitchDelay,
        transitionSettleDelay: TimeInterval = HiddenCursorDisplaySpaceCommandExecutor.defaultTransitionSettleDelay,
        restoreDelay: TimeInterval = HiddenCursorDisplaySpaceCommandExecutor.defaultRestoreDelay
    ) {
        self.poster = poster
        self.targetProvider = targetProvider
        self.cursor = cursor
        self.visibilityController = visibilityController
        self.cursorShield = cursorShield
        self.cursorAssociationController = cursorAssociationController
        self.postEventAccessChecker = postEventAccessChecker
        self.hideSettleDelay = hideSettleDelay
        self.focusDelay = focusDelay
        self.switchDelay = switchDelay
        self.transitionSettleDelay = transitionSettleDelay
        self.restoreDelay = restoreDelay
    }

    static func live(includedStableIDs: Set<String>) -> Self {
        Self(
            poster: CGDockSwipeEventPoster(),
            targetProvider: CGDisplaySwitchTargetProvider(
                includedStableIDs: includedStableIDs
            ),
            cursor: CGCursorPositioner(),
            visibilityController: CGDisplayOnlyCursorVisibilityController(),
            cursorShield: NoopCursorShield(),
            cursorAssociationController: CGMouseCursorAssociationController(),
            postEventAccessChecker: CGPostEventAccessChecker()
        )
    }
}

public enum ProductDockSpaceExecutorFactory {
    public static let recipe = ProductSpaceExecutorRecipe(
        backend: .dockSwipe,
        cursorVisibility: .coreGraphicsOnly,
        cursorShield: .none
    )

    public static func make(
        includedStableIDs: Set<String>
    ) -> any SpaceCommandExecuting {
        make(
            includedStableIDs: includedStableIDs,
            dependencies: .live(includedStableIDs: includedStableIDs)
        )
    }

    static func make(
        includedStableIDs: Set<String>,
        dependencies: ProductDockSpaceExecutorDependencies
    ) -> any SpaceCommandExecuting {
        _ = includedStableIDs
        return HiddenCursorDisplaySpaceCommandExecutor(
            baseExecutor: DockSwipeSpaceCommandExecutor(
                poster: AnyDockSwipeEventPoster(dependencies.poster)
            ),
            targetProvider: dependencies.targetProvider,
            cursor: dependencies.cursor,
            visibilityController: dependencies.visibilityController,
            cursorShield: dependencies.cursorShield,
            cursorAssociationController: dependencies.cursorAssociationController,
            postEventAccessChecker: dependencies.postEventAccessChecker,
            hideSettleDelay: dependencies.hideSettleDelay,
            focusDelay: dependencies.focusDelay,
            switchDelay: dependencies.switchDelay,
            transitionSettleDelay: dependencies.transitionSettleDelay,
            restoreDelay: dependencies.restoreDelay
        )
    }
}
