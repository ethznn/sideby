import XCTest
@testable import SidebyCore
@testable import SidebySystem

final class LoginItemTests: XCTestCase {
    func testToggleControllerDelegatesEnabledState() throws {
        let service = RecordingLoginItemService()
        let controller = LoginItemToggleController(service: service)

        try controller.setEnabled(true)

        XCTAssertEqual(service.enabledValues, [true])
    }
}

private final class RecordingLoginItemService: LoginItemServicing, @unchecked Sendable {
    var isEnabled: Bool { enabledValues.last ?? false }
    private(set) var enabledValues: [Bool] = []

    func setEnabled(_ isEnabled: Bool) throws {
        enabledValues.append(isEnabled)
    }
}
