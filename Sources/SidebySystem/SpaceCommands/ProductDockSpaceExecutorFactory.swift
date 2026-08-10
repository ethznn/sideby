import SidebyCore

public struct ProductSpaceExecutorRecipe: Equatable, Sendable {
    public enum Backend: Equatable, Sendable {
        case dockSwipe
    }

    public enum CursorVisibility: Equatable, Sendable {
        case coreGraphicsOnly
        case none
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
    let poster: any LocatedDockSwipeEventPosting
    let targetProvider: any DisplaySwitchTargetProviding

    init(
        poster: any LocatedDockSwipeEventPosting,
        targetProvider: any DisplaySwitchTargetProviding
    ) {
        self.poster = poster
        self.targetProvider = targetProvider
    }

    static func live(includedStableIDs: Set<String>) -> Self {
        Self(
            poster: CGDockSwipeEventPoster(),
            targetProvider: CGDisplaySwitchTargetProvider(
                includedStableIDs: includedStableIDs
            )
        )
    }
}

public enum ProductDockSpaceExecutorFactory {
    public static let recipe = ProductSpaceExecutorRecipe(
        backend: .dockSwipe,
        cursorVisibility: .none,
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
        return TargetedDockSwipeSpaceCommandExecutor(
            poster: AnyLocatedDockSwipeEventPoster(dependencies.poster),
            targetProvider: dependencies.targetProvider
        )
    }
}
