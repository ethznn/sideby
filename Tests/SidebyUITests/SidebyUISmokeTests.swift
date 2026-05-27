import XCTest
@testable import SidebyUI

final class SidebyUISmokeTests: XCTestCase {
    func testUIModuleLoads() {
        XCTAssertEqual(SidebyUI.moduleName, "SidebyUI")
    }
}
