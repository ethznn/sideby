import XCTest
import CoreGraphics
@testable import SidebyCore
@testable import SidebySystem

final class ProductDockSpaceExecutorFactoryTests: XCTestCase {
    func testProductFactoryRecipeIsDockAndAppKitFree() {
        XCTAssertEqual(
            ProductDockSpaceExecutorFactory.recipe,
            ProductSpaceExecutorRecipe(
                backend: .dockSwipe,
                cursorVisibility: .coreGraphicsOnly,
                cursorShield: .none
            )
        )
    }

    func testFactoryAssemblesInjectedDockPosterInsideCoreGraphicsCursorLifecycle() {
        let poster = RecordingFactoryDockPoster()
        let executor = ProductDockSpaceExecutorFactory.make(
            includedStableIDs: ["main"],
            dependencies: .init(
                poster: poster,
                targetProvider: StaticFactoryTargetProvider(points: [CGPoint(x: 100, y: 100)]),
                cursor: FactoryCursor(),
                visibilityController: FactoryVisibilityController(),
                cursorShield: NoopCursorShield(),
                cursorAssociationController: FactoryCursorAssociationController(),
                postEventAccessChecker: FactoryPostEventAccessChecker(),
                hideSettleDelay: 0,
                focusDelay: 0,
                switchDelay: 0,
                transitionSettleDelay: 0,
                restoreDelay: 0
            )
        )

        XCTAssertTrue(executor.execute(.previous))
        XCTAssertEqual(poster.descriptors, [.make(for: .previous)])
    }
}

private final class RecordingFactoryDockPoster: DockSwipeEventPosting, @unchecked Sendable {
    private(set) var descriptors: [DockSwipeGestureDescriptor] = []

    func post(_ descriptor: DockSwipeGestureDescriptor) -> Bool {
        descriptors.append(descriptor)
        return true
    }
}

private struct StaticFactoryTargetProvider: DisplaySwitchTargetProviding {
    let points: [CGPoint]

    func targetPoints() -> [CGPoint] {
        points
    }
}

private struct FactoryCursor: CursorPositioning {
    func currentLocation() -> CGPoint? {
        CGPoint(x: 10, y: 10)
    }

    func move(to point: CGPoint) -> Bool {
        true
    }
}

private struct FactoryVisibilityController: CursorVisibilityControlling {
    func hide() -> Bool { true }
    func show() -> Bool { true }
}

private struct FactoryCursorAssociationController: MouseCursorAssociationControlling {
    func disconnect() -> Bool { true }
    func connect() -> Bool { true }
}

private struct FactoryPostEventAccessChecker: PostEventAccessChecking {
    func hasOrRequestAccess() -> Bool { true }
}
