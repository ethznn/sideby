import XCTest
@testable import SidebyCore

final class FoundationSmokeTests: XCTestCase {
    func testPackageExposesProductName() {
        XCTAssertEqual(SidebyCore.productName, "Sideby")
        XCTAssertEqual(SidebyCore.slogan, "Side by Side")
    }
}
