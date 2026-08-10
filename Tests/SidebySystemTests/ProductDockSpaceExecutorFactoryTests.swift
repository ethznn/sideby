import XCTest
import CoreGraphics
@testable import SidebyCore
@testable import SidebySystem

final class ProductDockSpaceExecutorFactoryTests: XCTestCase {
    func testProductFactoryRecipeUsesEventLocationWithoutCursorLifecycle() {
        XCTAssertEqual(
            ProductDockSpaceExecutorFactory.recipe,
            ProductSpaceExecutorRecipe(
                backend: .dockSwipe,
                cursorVisibility: .none,
                cursorShield: .none
            )
        )
    }

    func testFactoryPostsDockGestureAtInjectedTargetPoint() {
        let poster = RecordingFactoryLocatedDockPoster()
        let point = CGPoint(x: 900, y: 100)
        let executor = ProductDockSpaceExecutorFactory.make(
            includedStableIDs: ["main"],
            dependencies: .init(
                poster: poster,
                targetProvider: StaticFactoryTargetProvider(points: [point])
            )
        )

        XCTAssertTrue(executor.execute(.previous))
        XCTAssertEqual(poster.descriptors, [.make(for: .previous)])
        XCTAssertEqual(poster.locations, [point])
    }
}

private final class RecordingFactoryLocatedDockPoster: LocatedDockSwipeEventPosting, @unchecked Sendable {
    private(set) var descriptors: [DockSwipeGestureDescriptor] = []
    private(set) var locations: [CGPoint] = []

    func post(_ descriptor: DockSwipeGestureDescriptor, at location: CGPoint) -> Bool {
        descriptors.append(descriptor)
        locations.append(location)
        return true
    }
}

private struct StaticFactoryTargetProvider: DisplaySwitchTargetProviding {
    let points: [CGPoint]

    func targetPoints() -> [CGPoint] {
        points
    }
}
