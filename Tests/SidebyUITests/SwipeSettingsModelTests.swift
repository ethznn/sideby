import XCTest
@testable import SidebyCore
@testable import SidebyUI

final class SwipeSettingsModelTests: XCTestCase {
    func testConvertsBetweenGestureSettingsAndEditableModel() {
        var model = SwipeSettingsModel(settings: .default)

        model.threshold = 120
        model.naturalScrollingEnabled = false

        let settings = model.gestureSettings

        XCTAssertEqual(settings.horizontalThreshold, 120)
        XCTAssertFalse(settings.naturalScrollingEnabled)
        XCTAssertEqual(settings.requiredModifiers, [.option, .shift])
    }
}
