import XCTest
@testable import SidebyCore

final class DesktopNameIdentityTests: XCTestCase {
    func testUUIDIsCanonicalAndFollowsDesktopAcrossDisplays() {
        let uuid = "12345678-abcd-abcd-abcd-123456789abc"
        let first = DesktopNameIdentity(spaceKey: "uuid:" + uuid, displayID: "first")
        XCTAssertEqual(first, DesktopNameIdentity(spaceKey: "uuid:" + uuid.uppercased(), displayID: "second"))
        XCTAssertEqual(first?.storageKey, "uuid:" + uuid.uppercased())
    }

    func testDefaultDesktopRequiresDurableDisplayIdentity() {
        let first = DesktopNameIdentity(spaceKey: "default-desktop", displayID: "uuid:11111111-1111-1111-1111-111111111111")
        let second = DesktopNameIdentity(spaceKey: "default-desktop", displayID: "uuid:22222222-2222-2222-2222-222222222222")
        XCTAssertNotNil(first)
        XCTAssertNotEqual(first, second)
        for displayID in ["", "1552-123-0-1", "uuid:invalid"] {
            XCTAssertNil(DesktopNameIdentity(spaceKey: "default-desktop", displayID: displayID))
        }
        for key in ["", "123", "Desktop 1", "uuid:broken"] {
            XCTAssertNil(DesktopNameIdentity(spaceKey: key, displayID: "first"))
        }
    }

    func testValidationPreservesGraphemesAndDoesNotSilentlyTruncate() {
        XCTAssertEqual(DesktopNameValidation.validate(" \n개발 자료 📚 \t"), .valid("개발 자료 📚"))
        XCTAssertEqual(DesktopNameValidation.validate(" \n\t"), .empty)
        XCTAssertEqual(DesktopNameValidation.validate("첫째\n둘째"), .multipleLines)
        XCTAssertEqual(DesktopNameValidation.validate("코드\t리뷰"), .multipleLines)
        let name = String(repeating: "👨‍👩‍👧‍👦", count: 60)
        XCTAssertEqual(DesktopNameValidation.validate(name), .valid(name))
        XCTAssertEqual(DesktopNameValidation.validate(name + "가"), .tooLong)
        XCTAssertEqual(DesktopNameValidation.validate(String(repeating: "한", count: 60)),
                       .valid(String(repeating: "한", count: 60)))
    }
}
